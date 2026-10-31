# Telemetry and leaderboard (`src/sys/telemetry.bas`, `src/sys/lbrd.bas`)

## What problem it solves

The author wants aggregate, anonymous gameplay data (where do players die, how far do they get, does the difficulty ramp feel right) without collecting anything personally identifying, and an optional online leaderboard. `telemetry.bas` always logs events locally to CSV, and if a backend is configured and the player has consented, also batches them and POSTs them to the project's [Cloudflare Worker backend](../../server/) via [`http.bas`](README-http.md). `lbrd.bas` is the read side: it polls and parses the top-scores leaderboard for display on the title screen.

## Consent and configuration flow

1. **Backend configuration** (developer-side, not player-side): `assets/.env` (gitignored, one `KEY=value` per line) provides `DB_URL` and `DB_KEY`, embedded into the binary at build time via `$EMBED:'assets/.env':'ENVCONFIG'` and loaded by `TELEM_LoadCredentials` at startup. Empty or absent `assets/.env` means `DB_URL`/`DB_KEY` stay empty strings and **all network telemetry is compiled-in but inert**: events still get written to the local CSV, nothing goes over the network. CI writes its own `assets/.env` from repository secrets at build time.
2. **Player consent** (runtime, per-install): on first launch (if telemetry isn't disabled via `--no-telem`), `src/state/consent.bas` shows a one-screen disclosure (`GS_CONSENT`) before anything is sent. SPACE consents for this session only; `S` saves `telem_consent=1` to `sss_settings.ini` so it never asks again; ESC disables telemetry for the session (`telemOn = 0`).
3. **Player identity**: a random UUID (`telemPlayerID`, `TELEM_NewUUID$` in `telemetry.bas`) is generated once and persisted in `sss_settings.ini`. This is the only per-player identifier, and it isn't tied to anything outside the local settings file. A player-chosen callsign (`telemPlayerName`, `src/state/username.bas`) is also collected, but only for on-screen leaderboard display, not as an analytics ID.
4. **CLI override**: `--no-telem` disables telemetry (and skips the consent prompt) for a single session regardless of saved consent.

## Event schema

Every event goes through `TELEM_Row(event$, data$)`, which:
- Appends a CSV row to `sss_telemetry.csv` in the working directory: `time,session,event,data` (`time` = seconds since midnight, `session` = `YYYYMMDDHHMMSS` boot timestamp, `data` = pipe-separated `key=value` pairs).
- If `DB_URL` is set, also appends a JSON object to an in-memory batch (`telemBatch`) via [`json.bas`](../sys/json.bas)'s minimal encoder, sent as one array in a single POST when the session ends.

Events fired today (see call sites in `gameplay/`, `state/`, `sys/sequence.bas`): `session_start`, `enemy_killed`, `powerup_collected` (kind: points, shield or fuel; amount applied, 0 when the gauge was full and it paid score instead; score, shield, fuel, wave), `powerup_missed` (kind, wave: a power-up drifted past uncaught), `enemy_escaped`, `fuel_exhausted`, `player_damaged`, `player_death`, `boss_reached`, `boss_phase`, `boss_defeated`, `upgrade_bought` (item, level, price, credits_left; one per dock purchase), `fuel_bought` (amount, price, unit, mult, chapter, credits_left: fuel bought by the amount at a dock, `unit` the price per unit after the chapter's surcharge `mult`), `shield_bought` (amount, price, chapter, credits_left), `stage_clear` (chapter, fuel_used, seconds, fuel_left, credits: once per planet arrival; `fuel_used` and `seconds` cover the leg since the last dock or the start, and `fuel_used` counts what the leg burned even after the tank ran dry, for fitting the fuel need in `assets/config/economy.ini`), `credits_earned` (earned, spent, left; logged just before `session_end`), `credit_bonus` (credits, rate, points, score; once per run that ends in a win, a death or stranded, when leftover credits become score), `run_stranded` (chapter, fuel, need, credits, fuel_price: the run ended at a dock where the tank plus every unit the credits buy falls short of the next jump; logged before the cash-out, and `session_end` then has `exit=stranded`), `session_end`. `TELEM_SessionEnd` is idempotent (guarded on `telemSession` being non-empty) since it can be reached from more than one exit path.

### Backend schema

The tables are defined in [`server/migrations/`](../../server/migrations/) and the routes and validation in [`server/src/index.ts`](../../server/src/index.ts), with tests in `server/test/`:

- **`sss_telemetry`** (POST target for the batched event array): `session` (text, max 64 chars), `ev_time` (non-negative integer), `event` (text, max 64), `player_id` (text, max 64), `data` (text, max 1024), one row per event.
- **`scores`** (POST target for score submission, only sent if `DB_URL`/`DB_KEY` are set, consent was given, and `score > 0`): `player_id` (max 64), `player_name` (max 32), `score`, `wave` (non-negative integers), `session` (max 64), and optionally `difficulty` (lowercase slug, max 16, stored as `normal` when absent).
- **`top_scores`** (GET target for the leaderboard poll, `?order=score.desc&limit=N&select=player_name,score`): a read-only route over `scores`, highest score first, ties broken by earlier submission. `select` may also name `wave` and `difficulty`, and `difficulty=eq.<slug>` limits it to one difficulty. It's public; the two POSTs need `DB_KEY`.

The Worker rejects anything outside these shapes with a 400, so a payload change in `telemetry.bas` needs a matching change (and test) in `server/`.

## Leaderboard (`lbrd.bas`)

```basic
LBRD_Poll               ' enqueue a GET for the top N scores; call once per title-screen entry
LBRD_Parse body$         ' parse the backend's JSON array response into lbrdName$()/lbrdScore()
LBRD_Rank%(score)        ' 1-based rank a given score would have on the current board, or 0
```

`LBRD_Parse` is a linear string scan tailored to the exact flat-object array shape the backend returns for this query (`server/test/top_scores.test.ts` checks the Worker returns `tests/input/leaderboard.json`, the saved response `--leaderboard-file` loads, byte for byte), not a general JSON parser. If the query's `select=` list ever changes, this parser needs to change with it.

## How to query the data locally

Without a configured backend, `sss_telemetry.csv` in the game's working directory is the only telemetry output. It's plain CSV, so any spreadsheet tool or `awk`/`csvkit`/pandas works directly. With a backend configured, the same events also land in the D1 database, queryable with `npx wrangler d1 execute sss --remote --command "SELECT ..."` from `server/` or in the Cloudflare dashboard.

## Known limitations and gotchas

- **No delivery guarantee.** The batched POST fires once at session end via `HTTP_Post`. If it fails, the batch is just dropped (see [`http.bas`](README-http.md)'s "no retry logic" note); the local CSV is the only durable record.
- **`telemBatch` grows unbounded within a session.** For a normal play session this is fine (dozens of events, well under the 128 KB POST cap in `curl_qb64.h`), but an unusually long session could theoretically exceed it, and there's no chunking.
- **`LBRD_Parse`'s hand-rolled scan breaks silently on unexpected response shapes.** A backend or query change that alters the JSON structure won't raise an error, it'll just parse zero or garbled entries.

## Testing in isolation

`tests/telem_creds_test.bas` covers `.env` parsing (`TELEM_LoadCredentials`): normal values, comments/blank lines, rejecting stale key names, missing keys, empty content, and values containing `=`. It doesn't exercise the network path; that's covered indirectly by [`http_queue_test`](README-http.md#testing-in-isolation), which tests the underlying HTTP layer telemetry POSTs through.

```bash
tools/buildqb tests/telem_creds_test.bas && builds/telem_creds_test
```

There is no test that exercises `TELEM_Row`/`TELEM_SessionEnd`'s CSV writing end-to-end. The backend side of the payloads is tested in `server/` (`npm test`) against copies of the JSON the game builds; if you change the event schema, update those tests too.
