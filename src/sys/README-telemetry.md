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
- Buffers a CSV row in memory (`telemCsvBuf`); `TELEM_FlushCsv` writes the buffer to `sss_telemetry.csv` in the launch folder (`telemCsvDir`; no CSV when it is not writable or under `--no-telem`) once, from `TELEM_SessionEnd` (the same moment the network batch goes out, so also on window close or title QUIT via `GAME_Quit`) and on a `--frames` exit, so a kill never touches the disk and a crash loses the unwritten rows. Row format: `time,session,event,data` (`time` = seconds since midnight (local file only), `session` = `YYYYMMDDHHMMSS` boot timestamp, `data` = pipe-separated `key=value` pairs).
- If `DB_URL` is set, also appends a JSON object to an in-memory batch (`telemBatch`) via [`json.bas`](../sys/json.bas)'s minimal encoder, sent as POSTs of at most 1000 rows (and about 100 KB) each: a full chunk goes out as soon as it fills, the rest when the session ends. In the JSON, `ev_time` is whole seconds since the session started, counted in frames at 60 a second so a scripted run agrees at any speed (`session_start` is 0, never the time of day), which is the integer the Worker requires.

Where it happened: `enemy_killed`, `powerup_collected`, `powerup_missed`, `enemy_escaped`, `fuel_exhausted`, `player_damaged`, `player_death`, `boss_reached`, `boss_phase`, `boss_defeated` and `session_end` end with `chapter=N|stage_kills=K|stage_target=T` (`TELEM_At$`: `levelNum`, and the kills made of the kills the stage needs); `upgrade_bought` carries `chapter`, and the dock purchases and `stage_clear` already had their own.

Events fired today (see call sites in `gameplay/`, `state/`, `sys/sequence.bas`): `session_start` (player_id, version, build, nerf, difficulty: the run's difficulty level from `assets/config/difficulty.ini`, e.g. `easy`, `normal`, `hard`; flags: the dev flags in use, comma-separated from `god`, `nerf`, `scene`, `credits`, `ships`, `shields`, `fuel`, `pup`, `seed`, `script` for `--input-script`, so test and cheat sessions can be told apart; empty in a normal session, and always empty in a release build, where those flags are compiled out), `enemy_killed`, `powerup_collected` (kind: points, shield or fuel; amount applied, 0 when the gauge was full and it paid score instead; score, shield, fuel, wave), `powerup_missed` (kind, wave: a power-up drifted past uncaught), `enemy_escaped`, `fuel_exhausted`, `player_damaged`, `player_death`, `boss_reached`, `boss_phase`, `boss_defeated`, `upgrade_bought` (item, level, price, credits_left; one per dock purchase), `fuel_bought` (amount, price, unit, mult, chapter, credits_left: fuel bought by the amount at a dock, `unit` the price per unit after the chapter's surcharge `mult`), `shield_bought` (amount, price, chapter, credits_left), `stage_clear` (chapter, fuel_used, seconds, fuel_left, credits: once per planet arrival; `fuel_used` and `seconds` cover the leg since the last dock or the start, and `fuel_used` counts what the leg burned even after the tank ran dry, for fitting the fuel need in `assets/config/economy.ini`), `credits_earned` (earned, spent, left; logged just before `session_end`), `credit_bonus` (credits, rate, points, score; once per run that ends in a win, a death or stranded, when leftover credits become score), `run_stranded` (chapter, fuel, need, credits, fuel_price: the run ended at a dock where the tank plus every unit the credits buy falls short of the next jump; logged before the cash-out, and `session_end` then has `exit=stranded`), `session_end` (exit, score, kills, wave, boss, shots, hits, misses, escapes; secs: seconds since the session started, counted the same way as `ev_time`, pauses included; the chapter and stage progress, and for `exit=quit` also `state`, the `GS_*` screen it happened in). `TELEM_SessionEnd` is idempotent (guarded on `telemSession` being non-empty) since it can be reached from more than one exit path.

### Backend schema

The tables are defined in [`server/migrations/`](../../server/migrations/) and the routes and validation in [`server/src/index.ts`](../../server/src/index.ts), with tests in `server/test/`:

- **`sss_telemetry`** (POST target for the batched event array): `session` (text, max 64 chars), `ev_time` (non-negative integer), `event` (text, max 64), `player_id` (text, max 64), `data` (text, max 1024), one row per event.
- **`scores`** (POST target for score submission, only sent if `DB_URL`/`DB_KEY` are set, consent was given, and `score > 0`): `player_id` (max 64), `player_name` (max 32), `score`, `wave` (non-negative integers), `session` (max 64), and optionally `difficulty` (lowercase slug, max 16, stored as `normal` when absent). The game sends the run's level (`runDifficulty`, a `levels` name from `assets/config/difficulty.ini`).
- **`top_scores`** (GET target for the leaderboard poll, `?order=score.desc&limit=N&select=player_name,score,difficulty`): a read-only route over `scores`, highest score first, ties broken by earlier submission. `select` may also name `wave`, and `difficulty=eq.<slug>` limits it to one difficulty. It's public; the two POSTs need `DB_KEY`.

The Worker rejects anything outside these shapes with a 400, so a payload change in `telemetry.bas` needs a matching change (and test) in `server/`.

## Leaderboard (`lbrd.bas`)

```basic
LBRD_Poll               ' enqueue a GET for the top N scores; call once per title-screen entry
LBRD_Parse body$         ' parse the backend's JSON array response into lbrdName$()/lbrdScore()/lbrdDiff$()
LBRD_DisplayName$(rank, name$, level$)  ' the board's name text: rank color, name, the level's tag
LBRD_Rank%(score)        ' 1-based rank a given score would have on the current board, or 0
```

The board ranks every difficulty together and marks each row with its level's `<level>_tag` from `difficulty.ini` (`DLV_Tag$`), in gray after the name; a level with an empty tag (Normal) shows none. A row without a `difficulty` counts as the default level; a level this build doesn't know shows no tag.

`LBRD_Parse` is a linear string scan tailored to the exact flat-object array shape the backend returns for this query (`server/test/top_scores.test.ts` checks the Worker returns `tests/input/leaderboard.json`, the saved response `--leaderboard-file` loads, byte for byte), not a general JSON parser. If the query's `select=` list ever changes, this parser needs to change with it.

## How to query the data locally

Without a configured backend, `sss_telemetry.csv` in the launch folder is the only telemetry output. It's plain CSV, so any spreadsheet tool or `awk`/`csvkit`/pandas works directly. With a backend configured, the same events also land in the D1 database, queryable with `npx wrangler d1 execute sss --remote --command "SELECT ..."` from `server/` or in the Cloudflare dashboard.

## Known limitations and gotchas

- **No delivery guarantee.** Each chunk is queued with `HTTP_Post` and sent in the background. If one fails, the batch is just dropped (see [`http.bas`](README-http.md)'s "no retry logic" note); the local CSV is the only durable record.
- **Quitting.** `GAME_Quit` (title QUIT, and the window close button via `_EXIT` in the main loop) ends a run in progress as `exit=quit` through `SEQ_QuitProcess` (once, and only while `seqRunActive` is set), then `HTTP_Flush`es for at most 1.5 seconds so the last chunks leave before the process does. Anything still unsent after that is dropped. Telemetry never gates game state: nothing in the frame loop waits on it.
- **`LBRD_Parse`'s hand-rolled scan breaks silently on unexpected response shapes.** A backend or query change that alters the JSON structure won't raise an error, it'll just parse zero or garbled entries.

## Testing in isolation

`tests/telem_creds_test.bas` covers `.env` parsing (`TELEM_LoadCredentials`): normal values, comments/blank lines, rejecting stale key names, missing keys, empty content, and values containing `=`. It doesn't exercise the network path; that's covered indirectly by [`http_queue_test`](README-http.md#testing-in-isolation), which tests the underlying HTTP layer telemetry POSTs through.

```bash
tools/buildqb tests/telem_creds_test.bas && builds/telem_creds_test
```

`tests/death_telem_test.bas` covers the batch contents (flags, chapter and progress, quit state, duration, `ev_time`, chunking at 1000 rows) and `tests/run_end_test.bas` the one-session-end rule for window close. `tests/settings_dir_test.bas` checks the CSV file: nothing is written while rows are logged, and one write at session end or on quit. The backend side of the payloads is tested in `server/` (`npm test`) against copies of the JSON the game builds; if you change the event schema, update those tests too.
