import { env, exports } from "cloudflare:workers";

export const KEY = "test-key";
export const ORIGIN = "https://sss-api.example.workers.dev";

export function gameHeaders(key = KEY): Record<string, string> {
  return {
    "Content-Type": "application/json",
    apikey: key,
    Authorization: `Bearer ${key}`,
    Prefer: "return=minimal",
  };
}

let nextIp = 0;

// Each call comes from a fresh client IP so the per-IP rate limits only bite where a test
// pins one with `ip`.
export function post(path: string, body: string, headers = gameHeaders(), ip?: string): Promise<Response> {
  const from = ip ?? `10.0.${(++nextIp >> 8) & 255}.${nextIp & 255}`;
  return exports.default.fetch(
    new Request(ORIGIN + path, { method: "POST", headers: { ...headers, "CF-Connecting-IP": from }, body }),
  );
}

export function get(path: string, headers: Record<string, string> = {}): Promise<Response> {
  return exports.default.fetch(new Request(ORIGIN + path, { headers }));
}

export async function rows<T = Record<string, unknown>>(sql: string): Promise<T[]> {
  return (await env.DB.prepare(sql).all<T>()).results;
}

export async function seedScores(list: [string, number, number][]): Promise<void> {
  for (const [name, score, wave] of list) {
    await env.DB.prepare(
      "INSERT INTO scores (player_id, player_name, score, wave, session) VALUES (?, ?, ?, ?, ?)",
    )
      .bind("pid-" + name, name, score, wave, "20261027120000")
      .run();
  }
}
