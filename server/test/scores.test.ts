import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { ORIGIN, gameHeaders, post, rows } from "./helpers";

const GAME_SCORE =
  '{"player_id":"9b8a7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d","player_name":"ACE","score":1450,"wave":3,"session":"20261027143005"}';

function score(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { ...JSON.parse(GAME_SCORE), ...overrides };
}

describe("POST /scores", () => {
  it("stores the score exactly as the game sends it and returns 201 with no body", async () => {
    const res = await post("/scores", GAME_SCORE);
    expect(res.status).toBe(201);
    expect(await res.text()).toBe("");
    expect(await rows("SELECT player_id, player_name, score, wave, session FROM scores")).toEqual([
      JSON.parse(GAME_SCORE),
    ]);
  });

  it("accepts a one-row array", async () => {
    expect((await post("/scores", JSON.stringify([score()]))).status).toBe(201);
    expect(await rows("SELECT id FROM scores")).toHaveLength(1);
  });

  it("rejects a 2-row array with 400 and stores nothing", async () => {
    const res = await post("/scores", JSON.stringify([score(), score({ player_name: "BOB" })]));
    expect(res.status).toBe(400);
    expect(await rows("SELECT id FROM scores")).toHaveLength(0);
  });

  it.each([
    ["the auto-generated name", "PILOT-4821"],
    ["a 3-char name", "ACE"],
    ["colour tokens", "~CRED~FWOLF"],
    ["colour tokens filling 32 chars", "~AVERY~BLONG~CCALLSIGN~D12345678"],
    ["lowercase and punctuation", "~9low-case.pilot!"],
    ["spaces", "ACE OF SPACE"],
    ["JSON-escaped characters", 'QUOTE"BACK\\SLASH'],
  ])("accepts %s as a callsign", async (_name, name) => {
    expect((await post("/scores", JSON.stringify(score({ player_name: name })))).status).toBe(201);
    expect(await rows("SELECT player_name FROM scores")).toEqual([{ player_name: name }]);
  });

  it("accepts score and wave at their ceilings", async () => {
    expect((await post("/scores", JSON.stringify(score({ score: 250000, wave: 100 })))).status).toBe(201);
  });

  it("returns 429 once a client passes 10 posts a minute, per IP", async () => {
    const ip = "203.0.113.7";
    for (let i = 0; i < 10; i++) {
      expect((await post("/scores", GAME_SCORE, gameHeaders(), ip)).status).toBe(201);
    }
    const res = await post("/scores", GAME_SCORE, gameHeaders(), ip);
    expect(res.status).toBe(429);
    expect(await rows("SELECT id FROM scores")).toHaveLength(10);
    expect((await post("/scores", GAME_SCORE, gameHeaders(), "203.0.113.8")).status).toBe(201);
  });

  it("runs unlimited when the rate limit binding is absent", async () => {
    const bare = { ...env, SCORES_LIMITER: undefined };
    for (let i = 0; i < 12; i++) {
      const req = new Request(ORIGIN + "/scores", { method: "POST", headers: gameHeaders(), body: GAME_SCORE });
      expect((await worker.fetch(req, bare)).status).toBe(201);
    }
  });

  it("accepts the old /rest/v1 prefix", async () => {
    expect((await post("/rest/v1/scores", GAME_SCORE)).status).toBe(201);
  });

  it("accepts a 32-char name", async () => {
    expect((await post("/scores", JSON.stringify(score({ player_name: "N".repeat(32) })))).status).toBe(201);
  });

  it("rejects a bad key with 401", async () => {
    expect((await post("/scores", GAME_SCORE, gameHeaders("nope"))).status).toBe(401);
    expect(await rows("SELECT id FROM scores")).toHaveLength(0);
  });

  it.each([
    ["a name over 32 chars", score({ player_name: "N".repeat(33) })],
    ["a name under 3 chars", score({ player_name: "AB" })],
    ["an empty name", score({ player_name: "" })],
    ["a name with a newline", score({ player_name: "ACE\nBOB" })],
    ["a name with a control char", score({ player_name: "ACE\u0007" })],
    ["a name with non-ASCII", score({ player_name: "ÄCE" })],
    ["a name with an emoji", score({ player_name: "ACE\u{1F680}" })],
    ["a score over the ceiling", score({ score: 250001 })],
    ["a huge score", score({ score: 9_000_000_000_000_000 })],
    ["a wave over the ceiling", score({ wave: 101 })],
    ["a negative score", score({ score: -5 })],
    ["a fractional score", score({ score: 1.5 })],
    ["a string score", score({ score: "1450" })],
    ["a missing wave", score({ wave: undefined })],
    ["a null name", score({ player_name: null })],
    ["an unknown field", score({ rank: 1 })],
  ])("rejects %s with 400", async (_name, body) => {
    expect((await post("/scores", JSON.stringify(body))).status).toBe(400);
    expect(await rows("SELECT id FROM scores")).toHaveLength(0);
  });
});
