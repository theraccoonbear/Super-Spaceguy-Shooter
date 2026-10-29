import { env, exports } from "cloudflare:workers";
import worker from "../src/index";
import wranglerToml from "../wrangler.toml?raw";

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

// The configured `limit` of a [[ratelimits]] binding in wrangler.toml.
export function configuredLimit(name: string): number {
  const block = wranglerToml.split("[[ratelimits]]").find((b) => b.includes(`name = "${name}"`));
  const limit = block?.match(/limit\s*=\s*(\d+)/)?.[1];
  if (!limit) throw new Error(`no [[ratelimits]] limit for ${name} in wrangler.toml`);
  return Number(limit);
}

// Stand-in for a RateLimit binding: a per-key counter with no time window, so the rate-limit
// tests never depend on where the wall-clock minute falls (#307).
export function fakeLimiter(limit: number): RateLimit & { keys: string[] } {
  const counts = new Map<string, number>();
  const keys: string[] = [];
  return {
    keys,
    async limit({ key }: RateLimitOptions): Promise<RateLimitOutcome> {
      keys.push(key);
      const n = (counts.get(key) ?? 0) + 1;
      counts.set(key, n);
      return { success: n <= limit };
    },
  };
}

// Like `post`, but straight into the Worker with `overrides` layered over the test env.
export function postWith(
  overrides: Partial<Cloudflare.Env>,
  path: string,
  body: string,
  ip: string,
  headers = gameHeaders(),
): Promise<Response> {
  const req = new Request(ORIGIN + path, { method: "POST", headers: { ...headers, "CF-Connecting-IP": ip }, body });
  return worker.fetch(req, { ...env, ...overrides });
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
