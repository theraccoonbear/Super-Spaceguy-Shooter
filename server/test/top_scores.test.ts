import { describe, expect, it } from "vitest";
import fixture from "../../tests/input/leaderboard.json?raw";
import { gameHeaders, get, post, seedScores } from "./helpers";

const GAME_QUERY = "/top_scores?order=score.desc&limit=10&select=player_name,score";

function lbrdParse(body: string): [string, number][] {
  return (JSON.parse(body) as Record<string, unknown>[]).map((row) => {
    expect(Object.keys(row)).toEqual(["player_name", "score"]);
    return [row.player_name as string, row.score as number];
  });
}

describe("GET /top_scores", () => {
  it("answers the game's exact query with flat player_name,score objects, best first", async () => {
    await seedScores([
      ["BOB", 500, 2],
      ["ACE", 1234, 4],
      ["CAT", 900, 3],
    ]);
    const res = await get(GAME_QUERY, gameHeaders());
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/json");
    const body = await res.text();
    expect(body).toBe(
      '[{"player_name":"ACE","score":1234},{"player_name":"CAT","score":900},{"player_name":"BOB","score":500}]',
    );
    expect(lbrdParse(body)).toEqual([
      ["ACE", 1234],
      ["CAT", 900],
      ["BOB", 500],
    ]);
  });

  it("is public: no key or a wrong key still reads", async () => {
    await seedScores([["ACE", 10, 1]]);
    expect((await get(GAME_QUERY)).status).toBe(200);
    expect((await get(GAME_QUERY, gameHeaders("nope"))).status).toBe(200);
  });

  it("returns an empty array when there are no scores", async () => {
    expect(await (await get(GAME_QUERY)).text()).toBe("[]");
  });

  it("accepts the old /rest/v1 prefix", async () => {
    await seedScores([["ACE", 10, 1]]);
    expect(await (await get("/rest/v1" + GAME_QUERY)).json()).toEqual([{ player_name: "ACE", score: 10 }]);
  });

  it("breaks ties by earlier insert", async () => {
    await seedScores([
      ["FIRST", 700, 1],
      ["SECOND", 700, 1],
      ["THIRD", 700, 1],
    ]);
    const body = (await (await get(GAME_QUERY)).json()) as { player_name: string }[];
    expect(body.map((r) => r.player_name)).toEqual(["FIRST", "SECOND", "THIRD"]);
  });

  it("defaults to limit 10 and player_name,score", async () => {
    await seedScores(Array.from({ length: 15 }, (_, i) => [`P${i}`, i * 10, 1] as [string, number, number]));
    const body = (await (await get("/top_scores")).json()) as Record<string, unknown>[];
    expect(body).toHaveLength(10);
    expect(Object.keys(body[0])).toEqual(["player_name", "score"]);
    expect(body[0]).toEqual({ player_name: "P14", score: 140 });
  });

  it("honours limit and caps it at 100", async () => {
    await seedScores(Array.from({ length: 120 }, (_, i) => [`P${i}`, i, 1] as [string, number, number]));
    expect(((await (await get("/top_scores?limit=3")).json()) as unknown[]).length).toBe(3);
    expect(((await (await get("/top_scores?limit=500")).json()) as unknown[]).length).toBe(100);
  });

  it("returns the selected keys in the requested order", async () => {
    await seedScores([["ACE", 1234, 4]]);
    expect(await (await get("/top_scores?select=wave,player_name,score")).text()).toBe(
      '[{"wave":4,"player_name":"ACE","score":1234}]',
    );
    expect(await (await get("/top_scores?select=score")).text()).toBe('[{"score":1234}]');
  });

  it("selects difficulty, defaulting to normal for scores posted without one", async () => {
    await post("/scores", JSON.stringify({ player_id: "p", player_name: "OLD", score: 900, wave: 2, session: "s" }));
    await post(
      "/scores",
      JSON.stringify({ player_id: "p", player_name: "NEW", score: 1200, wave: 3, session: "s", difficulty: "hard" }),
    );
    expect(await (await get("/top_scores?select=player_name,score,difficulty")).text()).toBe(
      '[{"player_name":"NEW","score":1200,"difficulty":"hard"},{"player_name":"OLD","score":900,"difficulty":"normal"}]',
    );
    expect(await (await get(GAME_QUERY)).text()).toBe(
      '[{"player_name":"NEW","score":1200},{"player_name":"OLD","score":900}]',
    );
  });

  it("filters by difficulty=eq.<slug>", async () => {
    for (const [name, score, difficulty] of [
      ["EASY1", 3000, "easy"],
      ["HARD1", 800, "hard"],
      ["NORM1", 1500, undefined],
      ["HARD2", 1100, "hard"],
    ] as const) {
      const body = { player_id: "p", player_name: name, score, wave: 1, session: "s", difficulty };
      expect((await post("/scores", JSON.stringify(body))).status).toBe(201);
    }
    const names = async (q: string) =>
      ((await (await get("/top_scores?select=player_name&" + q)).json()) as { player_name: string }[]).map(
        (r) => r.player_name,
      );
    expect(await names("difficulty=eq.hard")).toEqual(["HARD2", "HARD1"]);
    expect(await names("difficulty=eq.normal")).toEqual(["NORM1"]);
    expect(await names("difficulty=eq.nightmare")).toEqual([]);
    expect(await names("difficulty=eq.hard&limit=1")).toEqual(["HARD2"]);
    expect(await names("limit=10")).toEqual(["EASY1", "NORM1", "HARD2", "HARD1"]);
  });

  it("reads back a score posted the way the game posts it", async () => {
    await post(
      "/scores",
      '{"player_id":"9b8a7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d","player_name":"ACE","score":1450,"wave":3,"session":"20261027143005"}',
    );
    expect(lbrdParse(await (await get(GAME_QUERY)).text())).toEqual([["ACE", 1450]]);
  });

  it.each([
    "/top_scores?order=score.asc",
    "/top_scores?order=wave.desc",
    "/top_scores?limit=0",
    "/top_scores?limit=-1",
    "/top_scores?limit=ten",
    "/top_scores?select=player_id",
    "/top_scores?select=*",
    "/top_scores?select=score,score",
    "/top_scores?select=",
    "/top_scores?offset=5",
    "/top_scores?score=gt.5",
    "/top_scores?difficulty=hard",
    "/top_scores?difficulty=neq.hard",
    "/top_scores?difficulty=eq.",
    "/top_scores?difficulty=eq.Hard",
    "/top_scores?difficulty=eq.hard,easy",
    "/top_scores?difficulty=in.(hard,easy)",
    "/top_scores?difficulty=eq.hard&difficulty=eq.easy",
    "/top_scores?select=player_name,player_id,difficulty",
  ])("rejects %s with 400", async (path) => {
    expect((await get(path)).status).toBe(400);
  });

  it("serves the leaderboard fixture LBRD_Parse is tested against, byte for byte", async () => {
    const expected = fixture.trim();
    for (const row of JSON.parse(expected) as { player_name: string; score: number }[]) {
      const body = JSON.stringify({ player_id: "p", player_name: row.player_name, score: row.score, wave: 1, session: "s" });
      expect((await post("/scores", body)).status).toBe(201);
    }
    expect(await (await get(GAME_QUERY)).text()).toBe(expected);
  });

  it("rejects POST with 405", async () => {
    expect((await post("/top_scores", "{}")).status).toBe(405);
  });
});

describe("routing", () => {
  it.each(["/", "/players", "/rest/v1/", "/rest/v1/nope", "/scores/1", "/rest/v1scores"])(
    "returns 404 for %s",
    async (path) => {
      expect((await get(path)).status).toBe(404);
    },
  );
});
