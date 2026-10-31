export interface Env {
  DB: D1Database;
  API_KEY: string;
  SCORES_LIMITER?: RateLimit;
  TELEMETRY_LIMITER?: RateLimit;
}

type Row = Record<string, string | number>;
type FieldKind = "text" | "count";
type Schema = Record<
  string,
  { kind: FieldKind; max?: number; pattern?: RegExp; patternName?: string; default?: string }
>;

const MAX_BODY_BYTES = 256 * 1024;
const MAX_ROWS = 1000;

// A full winning run tops out near 65,000 (the best real score is 21,882, 2026-10-28):
//   kills       ~150 x SCORE_ENEMY 100       = 15,000  (sequence.txt triggers total 70;
//                                                       a god-mode run measured 71)
//   bosses         3 x 2,000                 =  6,000  (boss.bas)
//   power-ups    ~40 x pup_points 500        = 20,000  (pup_chance 0.25 per combat wave)
//   near misses  <96 x INT(scl*60) <= ~180   = 17,300  (50-frame cooldown over the
//                                                       4,800-frame asteroid field)
//   fuel bonus   fuelMax 160 x 5             =    800
//   credit bonus ~6,000 credits x 1          =  6,000  (economy.ini credit_bonus_rate)
// The ceiling leaves ~4x headroom for balance changes; raise it if the game's scoring grows.
const MAX_SCORE = 250_000;
// The game sends waveType, the formation index (0-5, wave.bas). 100 leaves room for more
// formations or a switch to the level number.
const MAX_WAVE = 100;
// The callsign screen (usernamelogic.bas / textedit.bas) types chars 32-126 only, ~X colour
// tokens included, needs UN_MIN_LEN 3 to confirm and stops at UN_MAX_LEN 32; skipping
// gives UN_AutoName$ "PILOT-1234".
const CALLSIGN = /^[\x20-\x7e]{3,32}$/;
// A slug, not a fixed list, so the game can add difficulty levels without a server change.
const DIFFICULTY = /^[a-z][a-z0-9_-]{0,15}$/;
const DEFAULT_DIFFICULTY = "normal";
const DEFAULT_LIMIT = 10;
const MAX_LIMIT = 100;
const LEADERBOARD_COLUMNS = ["player_name", "score", "wave", "difficulty"];

const TELEMETRY: Schema = {
  session: { kind: "text", max: 64 },
  ev_time: { kind: "count" },
  event: { kind: "text", max: 64 },
  player_id: { kind: "text", max: 64 },
  data: { kind: "text", max: 1024 },
};

const SCORES: Schema = {
  player_id: { kind: "text", max: 64 },
  player_name: { kind: "text", max: 32, pattern: CALLSIGN, patternName: "callsign" },
  score: { kind: "count", max: MAX_SCORE },
  wave: { kind: "count", max: MAX_WAVE },
  session: { kind: "text", max: 64 },
  // Optional: game builds from before #102 don't send it.
  difficulty: { kind: "text", max: 16, pattern: DIFFICULTY, patternName: "difficulty", default: DEFAULT_DIFFICULTY },
};

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (err) {
      if (err instanceof HttpError) return json({ message: err.message }, err.status);
      throw err;
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  let path = url.pathname;
  if (path.startsWith("/rest/v1/")) path = path.slice("/rest/v1".length);

  switch (path) {
    case "/sss_telemetry":
      requireMethod(request, "POST");
      await rateLimit(request, env.TELEMETRY_LIMITER);
      await requireKey(request, env);
      return insert(env, "sss_telemetry", TELEMETRY, await readRows(request, TELEMETRY, MAX_ROWS));
    case "/scores":
      requireMethod(request, "POST");
      await rateLimit(request, env.SCORES_LIMITER);
      await requireKey(request, env);
      return insert(env, "scores", SCORES, await readRows(request, SCORES, 1));
    case "/top_scores":
      requireMethod(request, "GET");
      return topScores(env, url.searchParams);
    default:
      throw new HttpError(404, "not found");
  }
}

function requireMethod(request: Request, method: string): void {
  if (request.method !== method) {
    throw new HttpError(405, `method ${request.method} not allowed`);
  }
}

// Absent in plain local runs that don't simulate the binding: no limit there.
async function rateLimit(request: Request, limiter: RateLimit | undefined): Promise<void> {
  if (!limiter) return;
  const key = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await limiter.limit({ key });
  if (!success) throw new HttpError(429, "too many requests");
}

async function requireKey(request: Request, env: Env): Promise<void> {
  if (!env.API_KEY) throw new HttpError(500, "API_KEY is not configured");
  const bearer = request.headers.get("Authorization")?.match(/^Bearer (.+)$/)?.[1];
  const given = request.headers.get("apikey") ?? bearer;
  if (given === undefined || given === null || !(await sameSecret(given, env.API_KEY))) {
    throw new HttpError(401, "invalid api key");
  }
}

async function sameSecret(given: string, expected: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(given)),
    crypto.subtle.digest("SHA-256", enc.encode(expected)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

async function readRows(request: Request, schema: Schema, maxRows: number): Promise<Row[]> {
  const declared = Number(request.headers.get("Content-Length") ?? 0);
  if (declared > MAX_BODY_BYTES) throw new HttpError(400, "body larger than 256 KB");
  const raw = await request.arrayBuffer();
  if (raw.byteLength > MAX_BODY_BYTES) throw new HttpError(400, "body larger than 256 KB");

  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    throw new HttpError(400, "body is not valid JSON");
  }
  const items = Array.isArray(body) ? body : [body];
  if (items.length === 0) throw new HttpError(400, "no rows");
  if (items.length > maxRows) {
    throw new HttpError(400, maxRows === 1 ? "exactly one row allowed" : `more than ${maxRows} rows`);
  }
  return items.map((item, i) => validateRow(item, schema, i));
}

function validateRow(item: unknown, schema: Schema, index: number): Row {
  if (typeof item !== "object" || item === null || Array.isArray(item)) {
    throw new HttpError(400, `row ${index}: not an object`);
  }
  const obj = item as Record<string, unknown>;
  for (const key of Object.keys(obj)) {
    if (!(key in schema)) throw new HttpError(400, `row ${index}: unknown field ${key}`);
  }
  const row: Row = {};
  for (const [key, rule] of Object.entries(schema)) {
    const value = !(key in obj) && rule.default !== undefined ? rule.default : obj[key];
    if (rule.kind === "text") {
      if (typeof value !== "string") throw new HttpError(400, `row ${index}: ${key} must be a string`);
      if (value.length > rule.max!) {
        throw new HttpError(400, `row ${index}: ${key} longer than ${rule.max}`);
      }
      if (rule.pattern && !rule.pattern.test(value)) {
        throw new HttpError(400, `row ${index}: ${key} is not a valid ${rule.patternName}`);
      }
    } else if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
      throw new HttpError(400, `row ${index}: ${key} must be a non-negative integer`);
    } else if (rule.max !== undefined && value > rule.max) {
      throw new HttpError(400, `row ${index}: ${key} above ${rule.max}`);
    }
    row[key] = value;
  }
  return row;
}

async function insert(env: Env, table: string, schema: Schema, rows: Row[]): Promise<Response> {
  const columns = Object.keys(schema);
  const sql = `INSERT INTO ${table} (${columns.join(", ")}) VALUES (${columns.map(() => "?").join(", ")})`;
  const stmt = env.DB.prepare(sql);
  await env.DB.batch(rows.map((row) => stmt.bind(...columns.map((c) => row[c]))));
  return new Response(null, { status: 201 });
}

async function topScores(env: Env, params: URLSearchParams): Promise<Response> {
  let limit = DEFAULT_LIMIT;
  let columns = ["player_name", "score"];
  let difficulty: string | undefined;
  for (const [key, value] of params) {
    switch (key) {
      case "order":
        if (value !== "score.desc") throw new HttpError(400, "only order=score.desc is supported");
        break;
      case "limit":
        if (!/^[0-9]{1,9}$/.test(value) || Number(value) < 1) {
          throw new HttpError(400, "limit must be a positive integer");
        }
        limit = Math.min(Number(value), MAX_LIMIT);
        break;
      case "select":
        columns = value.split(",");
        if (
          columns.some((c) => !LEADERBOARD_COLUMNS.includes(c)) ||
          new Set(columns).size !== columns.length
        ) {
          throw new HttpError(400, `select must be a subset of ${LEADERBOARD_COLUMNS.join(",")}`);
        }
        break;
      case "difficulty": {
        const slug = value.startsWith("eq.") ? value.slice(3) : "";
        if (difficulty !== undefined || !DIFFICULTY.test(slug)) {
          throw new HttpError(400, "difficulty must be a single eq.<difficulty> filter");
        }
        difficulty = slug;
        break;
      }
      default:
        throw new HttpError(400, `unsupported parameter ${key}`);
    }
  }

  const where = difficulty === undefined ? "" : "WHERE difficulty = ? ";
  const binds = difficulty === undefined ? [limit] : [difficulty, limit];
  const { results } = await env.DB.prepare(
    `SELECT ${columns.join(", ")} FROM scores ${where}ORDER BY score DESC, id ASC LIMIT ?`,
  )
    .bind(...binds)
    .all<Row>();
  const rows = results.map((r) => Object.fromEntries(columns.map((c) => [c, r[c]])));
  return json(rows, 200);
}

function json(value: unknown, status: number): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
