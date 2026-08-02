# Telemetry and leaderboard (`src/sys/telemetry.bas`, `src/sys/lbrd.bas`)

## What problem it solves

The author wants aggregate, anonymous gameplay data (where do players die, how far do they get, does the difficulty ramp feel right) without collecting anything personally identifying, and an optional online leaderboard. `telemetry.bas` always logs events locally to CSV, and if a backend is configured and the player has consented, also batches them and POSTs to a [Supabase](https://supabase.com) REST endpoint via [`http.bas`](README-http.md). `lbrd.bas` is the read side: it polls and parses the top-scores leaderboard for display on the title screen.

## Consent and configuration flow

1. **Backend configuration** (developer-side, not player-side): `assets/.env` (gitignored, one `KEY=value` per line) provides `DB_URL` and `DB_KEY`, embedded into the binary at build time via `$EMBED:'assets/.env':'ENVCONFIG'` and loaded by `TELEM_LoadCredentials` at startup. Empty or absent `assets/.env` means `DB_URL`/`DB_KEY` stay empty strings and **all network telemetry is compiled-in but inert**: events still get written to the local CSV, nothing goes over the network. CI writes its own `assets/.env` from repository secrets at build time.
2. **Player consent** (runtime, per-install): on first launch (if telemetry isn't disabled via `--no-telem`), `src/state/consent.bas` shows a one-screen disclosure (`GS_CONSENT`) before anything is sent. SPACE consents for this session only; `S` saves `telem_consent=1` to `sss_settings.ini` so it never asks again; ESC disables telemetry for the session (`telemOn = 0`).
3. **Player identity**: a random UUID (`telemPlayerID`, `TELEM_NewUUID$` in `telemetry.bas`) is generated once and persisted in `sss_settings.ini`. This is the only per-player identifier, and it isn't tied to anything outside the local settings file. A player-chosen callsign (`telemPlayerName`, `src/state/username.bas`) is also collected, but only for on-screen leaderboard display, not as an analytics ID.
4. **CLI override**: `--no-telem` disables telemetry (and skips the consent prompt) for a single session regardless of saved consent.

## Event schema

Every event goes through `TELEM_Row(event$, data$)`, which:
- Appends a CSV row to `sss_telemetry.csv` in the working directory: `time,session,event,data` (`time` = seconds since midnight, `session` = `YYYYMMDDHHMMSS` boot timestamp, `data` = pipe-separated `key=value` pairs).
- If `DB_URL` is set, also appends a JSON object to an in-memory batch (`telemBatch`) via [`json.bas`](../sys/json.bas)'s minimal encoder, sent as one array in a single POST when the session ends.

Events fired today (see call sites in `gameplay/`, `state/`, `sys/sequence.bas`): `session_start`, `enemy_killed`, `powerup_collected`, `enemy_escaped`, `fuel_exhausted`, `player_damaged`, `player_death`, `boss_reached`, `boss_phase`, `boss_defeated`, `session_end`. `TELEM_SessionEnd` is idempotent (guarded on `telemSession` being non-empty) since it can be reached from more than one exit path.

### Inferred Supabase schema

This is inferred from the JSON shapes the code sends. It's worth confirming against the actual Supabase project rather than treating as authoritative:

- **`sss_telemetry`** (POST target for the batched event array): `session` (text), `ev_time` (number), `event` (text), `player_id` (text), `data` (text), one row per event.
- **`scores`** (POST target for score submission, only sent if `DB_URL`/`DB_KEY` are set, consent was given, and `score > 0`): `player_id`, `player_name`, `score`, `wave`, `session`.
- **`top_scores`** (GET target for the leaderboard poll, `?order=score.desc&limit=N&select=player_name,score`): a view or table exposing at least `player_name` and `score`, ordered descending. Likely a Supabase *view* over `scores` (name differs from the POST target) rather than a table `lbrd.bas` writes to directly.

## Leaderboard (`lbrd.bas`)

```basic
LBRD_Poll               ' enqueue a GET for the top N scores; call once per title-screen entry
LBRD_Parse body$         ' parse the Supabase JSON array response into lbrdName$()/lbrdScore()
LBRD_Rank%(score)        ' 1-based rank a given score would have on the current board, or 0
```

`LBRD_Parse` is a linear string scan tailored to the exact flat-object array shape Supabase returns for this query, not a general JSON parser. If the query's `select=` list ever changes, this parser needs to change with it.

## How to query the data locally

Without a configured backend, `sss_telemetry.csv` in the game's working directory is the only telemetry output. It's plain CSV, so any spreadsheet tool or `awk`/`csvkit`/pandas works directly. With a backend configured, the same events also land in Supabase, queryable via its REST API or SQL editor.

## Known limitations and gotchas

- **No delivery guarantee.** The batched POST fires once at session end via `HTTP_Post`. If it fails, the batch is just dropped (see [`http.bas`](README-http.md)'s "no retry logic" note); the local CSV is the only durable record.
- **`telemBatch` grows unbounded within a session.** For a normal play session this is fine (dozens of events, well under the 128 KB POST cap in `curl_qb64.h`), but an unusually long session could theoretically exceed it, and there's no chunking.
- **The inferred Supabase schema above is not verified against the actual project.** If it's wrong, fix this doc, don't guess again from the code.
- **`LBRD_Parse`'s hand-rolled scan breaks silently on unexpected response shapes.** A Supabase schema or query change that alters the JSON structure won't raise an error, it'll just parse zero or garbled entries.

## Testing in isolation

`tests/telem_creds_test.bas` covers `.env` parsing (`TELEM_LoadCredentials`): normal values, comments/blank lines, rejecting stale key names, missing keys, empty content, and values containing `=`. It doesn't exercise the network path; that's covered indirectly by [`http_queue_test`](README-http.md#testing-in-isolation), which tests the underlying HTTP layer telemetry POSTs through.

```bash
tools/buildqb tests/telem_creds_test.bas && builds/telem_creds_test
```

There is no test that exercises `TELEM_Row`/`TELEM_SessionEnd`'s CSV writing or the real Supabase POST payloads end-to-end. If you're changing the event schema, verify manually against a real (or mock) backend.
