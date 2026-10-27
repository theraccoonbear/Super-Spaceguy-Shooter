import { describe, expect, it } from "vitest";
import { KEY, gameHeaders, get, post, rows } from "./helpers";

const PLAYER = "3f2a9c1e-7b4d-4e8a-9c2f-1d5e6a7b8c9d";

const GAME_BATCH =
  "[" +
  `{"session":"20261027143005","ev_time":52205,"event":"session_start","player_id":"${PLAYER}","data":"player_id=${PLAYER}|version=0.1.0|nerf=0"},` +
  `{"session":"20261027143005","ev_time":52231,"event":"enemy_killed","player_id":"${PLAYER}","data":"score=100|kills=1|wave=1"},` +
  `{"session":"20261027143005","ev_time":52260,"event":"player_damaged","player_id":"${PLAYER}","data":"cause=asteroid|score=100|shield=2|fuel=87|laser=64"},` +
  `{"session":"20261027143005","ev_time":52390,"event":"session_end","player_id":"${PLAYER}","data":"exit=death|score=1450|kills=12|wave=3|boss=0|shots=88|hits=31|misses=57|escapes=4"}` +
  "]";

function event(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    session: "20261027143005",
    ev_time: 52205,
    event: "session_start",
    player_id: PLAYER,
    data: "x=1",
    ...overrides,
  };
}

describe("POST /sss_telemetry", () => {
  it("stores the batch exactly as the game sends it and returns 201 with no body", async () => {
    const res = await post("/sss_telemetry", GAME_BATCH);
    expect(res.status).toBe(201);
    expect(await res.text()).toBe("");
    const stored = await rows("SELECT session, ev_time, event, player_id, data, created_at FROM sss_telemetry ORDER BY id");
    expect(stored).toHaveLength(4);
    expect(stored[0]).toMatchObject({
      session: "20261027143005",
      ev_time: 52205,
      event: "session_start",
      player_id: PLAYER,
      data: `player_id=${PLAYER}|version=0.1.0|nerf=0`,
    });
    expect(stored[3].event).toBe("session_end");
    expect(stored[0].created_at).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
  });

  it("accepts a single object", async () => {
    const res = await post("/sss_telemetry", JSON.stringify(event()));
    expect(res.status).toBe(201);
    expect(await rows("SELECT id FROM sss_telemetry")).toHaveLength(1);
  });

  it("accepts the old /rest/v1 prefix", async () => {
    const res = await post("/rest/v1/sss_telemetry", GAME_BATCH);
    expect(res.status).toBe(201);
    expect(await rows("SELECT id FROM sss_telemetry")).toHaveLength(4);
  });

  it("accepts the key from apikey alone or Authorization alone", async () => {
    const onlyApikey = { "Content-Type": "application/json", apikey: KEY };
    const onlyBearer = { "Content-Type": "application/json", Authorization: `Bearer ${KEY}` };
    expect((await post("/sss_telemetry", JSON.stringify(event()), onlyApikey)).status).toBe(201);
    expect((await post("/sss_telemetry", JSON.stringify(event()), onlyBearer)).status).toBe(201);
  });

  it.each([
    ["no key", { "Content-Type": "application/json" }],
    ["wrong key", gameHeaders("nope")],
    ["key prefix", gameHeaders(KEY.slice(0, 4))],
    ["wrong apikey with right bearer", { apikey: "nope", Authorization: `Bearer ${KEY}` }],
  ])("rejects %s with 401 and stores nothing", async (_name, headers) => {
    const res = await post("/sss_telemetry", GAME_BATCH, headers as Record<string, string>);
    expect(res.status).toBe(401);
    expect(await rows("SELECT id FROM sss_telemetry")).toHaveLength(0);
  });

  it.each([
    ["invalid JSON", "[{"],
    ["empty array", "[]"],
    ["a non-object row", "[1]"],
    ["a null body", "null"],
    ["a missing field", JSON.stringify([{ ...event(), data: undefined }])],
    ["an unknown field", JSON.stringify([event({ extra: 1 })])],
    ["a numeric session", JSON.stringify([event({ session: 20261027143005 })])],
    ["a string ev_time", JSON.stringify([event({ ev_time: "52205" })])],
    ["a negative ev_time", JSON.stringify([event({ ev_time: -1 })])],
    ["a fractional ev_time", JSON.stringify([event({ ev_time: 1.5 })])],
    ["an event over 64 chars", JSON.stringify([event({ event: "e".repeat(65) })])],
    ["data over 1024 chars", JSON.stringify([event({ data: "d".repeat(1025) })])],
    ["a player_id over 64 chars", JSON.stringify([event({ player_id: "p".repeat(65) })])],
    ["a session over 64 chars", JSON.stringify([event({ session: "s".repeat(65) })])],
    ["more than 1000 rows", JSON.stringify(Array.from({ length: 1001 }, () => event()))],
    ["a body over 256 KB", JSON.stringify([event({ data: "d".repeat(256 * 1024) })])],
  ])("rejects %s with 400 and stores nothing", async (_name, body) => {
    const res = await post("/sss_telemetry", body);
    expect(res.status).toBe(400);
    expect(await rows("SELECT id FROM sss_telemetry")).toHaveLength(0);
  });

  it("accepts limits at their edges", async () => {
    const edge = event({
      session: "s".repeat(64),
      player_id: "p".repeat(64),
      event: "e".repeat(64),
      data: "d".repeat(1024),
      ev_time: 0,
    });
    expect((await post("/sss_telemetry", JSON.stringify(edge))).status).toBe(201);
    const batch = JSON.stringify(Array.from({ length: 1000 }, () => event()));
    expect((await post("/sss_telemetry", batch)).status).toBe(201);
    expect(await rows("SELECT id FROM sss_telemetry")).toHaveLength(1001);
  });

  it("rejects GET with 405", async () => {
    expect((await get("/sss_telemetry", gameHeaders())).status).toBe(405);
  });
});
