import { describe, expect, it } from "vitest";
import { gameHeaders, post, rows } from "./helpers";

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

  it("accepts an array", async () => {
    const res = await post("/scores", JSON.stringify([score(), score({ player_name: "BOB" })]));
    expect(res.status).toBe(201);
    expect(await rows("SELECT id FROM scores")).toHaveLength(2);
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

  it("rejects a whole batch when one row is bad", async () => {
    const res = await post("/scores", JSON.stringify([score(), score({ score: -1 })]));
    expect(res.status).toBe(400);
    expect(await rows("SELECT id FROM scores")).toHaveLength(0);
  });
});
