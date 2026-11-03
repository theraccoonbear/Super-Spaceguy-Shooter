# Telemetry and leaderboard (`src/sys/telemetry.bas`, `src/sys/lbrd.bas`)

## What problem it solves

The author wants aggregate, anonymous gameplay data (where do players die, how far do they get, does the difficulty ramp feel right) without collecting anything personally identifying, and an optional online leaderboard. `telemetry.bas` always logs events locally to CSV, and if a backend is configured and the player has consented, also batches them and POSTs them to the project's [Cloudflare Worker backend](../../server/) via [`http.bas`](README-http.md). `lbrd.bas` is the read side: it polls and parses the top-scores leaderboard for display on the title screen.

## Consent and configuration flow

1. **Backend configuration** (developer-side, not player-side): `assets/.env` (gitignored, one `KEY=value` per line) provides `DB_URL` and `DB_KEY`, embedded into the binary at build time via `$EMBED:'assets/.env':'ENVCONFIG'` and loaded by `TELEM_LoadCredentials` at startup. Empty or absent `assets/.env` means `DB_URL`/`DB_KEY` stay empty strings and **all network telemetry is compiled-in but inert**: events still get written to the local CSV, nothing goes over the network. CI writes its own `assets/.env` from repository secrets at build time.
2. **Player consent** (runtime, per-install): on first launch (if telemetry isn't disabled via `--no-telem`), `src/state/consent.bas` shows a one-screen disclosure (`GS_CONSENT`) before anything is sent. SPACE consents for this session only; `S` saves `telem_consent=1` to `sss_settings.ini` so it never asks again; ESC disables telemetry for the session (`telemOn = 0`).
3. **Player identity**: a random UUID (`telemPlayerID`, `TELEM_NewUUID$` in `telemetry.bas`) is generated once and persisted in `sss_settings.ini`. This is the only per-player identifier, and it isn't tied to anything outside the local settings file. A player-chosen callsign (`telemPlayerName`, `src/state/username.bas`) is also collected, but only for on-screen leaderboard display, not as an analytics ID.
4. **CLI override**: `--no-telem` disables telemetry (and skips the consent prompt) for a single session regardless of saved consent. Dev, cheat and test flags imply it (every `--...-dev` flag, `--god`, `--nerf`, `--scene`, `--bench`, `--input-script`, `--explode`, `--seed`, `--frames`, `--credits`, `--ships`, `--shields`, `--fuel`, `--pup`, `--screenshot-at`, `--leaderboard-file`; decided by `CLI_ImpliesNoTelem%` in `src/sys/cliflags.bas`, listed in [docs/cli.md](../../docs/cli.md)), so their sessions log nothing and post nothing. With `--debug` a line says which flag did it.

## Event schema

Every event goes through `TELEM_Row(event$, data$)`, which:
- Buffers a CSV row in memory (`telemCsvBuf`); `TELEM_FlushCsv` writes the buffer to `sss_telemetry.csv` in the launch folder (`telemCsvDir`; no CSV when it is not writable or under `--no-telem`) once, from `TELEM_SessionEnd` (the same moment the network batch goes out, so also on window close or title QUIT via `GAME_Quit`) and on a `--frames` exit, so a kill never touches the disk and a crash loses the unwritten rows. Row format: `time,session,event,data` (`time` = seconds since midnight (local file only), `session` = `YYYYMMDDHHMMSS` boot timestamp, `data` = pipe-separated `key=value` pairs).
- If `DB_URL` is set, also appends a JSON object to an in-memory batch (`telemBatch`) via [`json.bas`](../sys/json.bas)'s minimal encoder, sent as POSTs of at most 1000 rows (and about 100 KB) each: a full chunk goes out as soon as it fills, the rest when the session ends. In the JSON, `ev_time` is whole seconds since the session started, counted in frames at 60 a second so a scripted run agrees at any speed (`session_start` is 0, never the time of day), which is the integer the Worker requires.

Where it happened: `enemy_killed`, `powerup_collected`, `powerup_missed`, `enemy_escaped`, `fuel_exhausted`, `player_damaged`, `player_death`, `boss_reached`, `boss_phase`, `boss_defeated` and `session_end` end with `chapter=N|stage_kills=K|stage_target=T` (`TELEM_At$`: `levelNum`, and the kills made of the kills the stage needs); `upgrade_bought` carries `chapter`, and the dock purchases and `stage_clear` already had their own.

Events fired today (see call sites in `gameplay/`, `state/`, `sys/sequence.bas`): `session_start` (player_id, version, build, nerf, difficulty: the run's difficulty level from `assets/config/difficulty.ini`, e.g. `easy`, `normal`, `hard`; flags: the dev flags in use, comma-separated from `god`, `nerf`, `scene`, `credits`, `ships`, `shields`, `fuel`, `pup`, `seed`, `script` for `--input-script`, so test and cheat sessions can be told apart; empty in a normal session, and always empty in a release build, where those flags are compiled out), `enemy_killed`, `powerup_collected` (kind: points, shield or fuel; amount applied, 0 when the gauge was full and it paid score instead; score, shield, fuel, wave), `powerup_missed` (kind, wave: a power-up drifted past uncaught), `enemy_escaped`, `fuel_exhausted`, `player_damaged`, `player_death`, `boss_reached`, `boss_phase`, `boss_defeated`, `upgrade_bought` (item, level, price, credits_left; one per dock purchase), `fuel_bought` (amount, price, unit, mult, chapter, credits_left: fuel bought by the amount at a dock, `unit` the price per unit after the chapter's surcharge `mult`), `shield_bought` (amount, price, chapter, credits_left), `stage_clear` (chapter, fuel_used, seconds, fuel_left, credits: once per planet arrival; `fuel_used` and `seconds` cover the leg since the last dock or the start, and `fuel_used` counts what the leg burned even after the tank ran dry, for fitting the fuel need in `assets/config/economy.ini`), `credits_earned` (earned, spent, left: the credits unspent at the end, before any cash-out; logged just before `session_end`), `dock_visit` (see below), `credit_bonus` (credits, rate, points, score; once per run that ends in a win, a death or stranded, when leftover credits become score), `run_stranded` (chapter, fuel, need, credits, fuel_price: the run ended at a dock where the tank plus every unit the credits buy falls short of the next jump; logged before the cash-out, and `session_end` then has `exit=stranded`), `session_end` (exit, score, kills, wave, boss, shots, hits, misses, escapes; secs: seconds since the session started, counted the same way as `ev_time`, pauses included; the chapter and stage progress, and for `exit=quit` also `state`, the `GS_*` screen it happened in). `TELEM_SessionEnd` is idempotent (guarded on `telemSession` being non-empty) since it can be reached from more than one exit path.

### Per-leg counters and schema version (#387)

`session_start` ends with `tv=2` (the telemetry schema version). A leg runs from the run start or a dock to the next planet arrival; its counters are appended to `stage_clear` and, for the unfinished last leg, to `session_end`, then reset. Everything is counted in frames and events, never wall time, so the determinism check can diff the CSV. The counters live in `telemetry.bas` and the game reaches them through `TELEM_NoteFire`, `TELEM_NoteRoll`, `TELEM_NoteNova`, `TELEM_NoteDodge`, `TELEM_NoteRegen`, `TELEM_NoteArmour` and `TELEM_NovaKill`.

| Field | Meaning |
|---|---|
| `fire_f` | frames with fire held in play |
| `starve_f` | of those, frames with the gun ready but the laser below its shot cost |
| `starve_n` | starved episodes (consecutive starved frames; ends on release or a shot) |
| `lshots`, `lhits` | shots fired and hit this leg |
| `roll_have` | 1 when the evasive roll is owned |
| `roll_n` | rolls started |
| `roll_lock` | roll presses with the upgrade not owned |
| `roll_cool` | roll presses refused while rolling or cooling |
| `dodge` | hits the roll avoided; frames in a row from a per-frame source (spore, cut) count once |
| `nova_max` | nova charges the upgrade holds (0 = not owned) |
| `nova_n` | novas fired |
| `nova_dry` | presses with the upgrade owned and no charge left |
| `nova_kills` | ships downed by a nova; their `enemy_killed` rows end with `src=nova` |
| `regen` | shield points restored by shield regen |
| `armour_saved` | collision damage absorbed by hull armour |

`player_death` also carries `nova_left` (charges left) and `roll_ready` (1 when the roll is owned and cooled down). The longest payloads (every counter at its maximum) are about 475 characters for the leg-summary rows and 600 for `dock_visit`, checked by `death_telem_test` against the Worker's 1024-character cap. The expected key lists of the payloads are in `tests/input/telemetry_rows.txt`, which `death_telem_test` checks the builders against.

### Dock visits and the unspent-credit fix (#387)

`dock_visit` is logged once per dock as the visit ends: `exit=launch` when the player leaves, `exit=stranded` when the stranded dialog is answered (credits_out is then the credits before the cash-out). A run quit from the pause menu while docked ends with `session_end exit=quit state=GS_DOCK` and no `dock_visit`. The tallies are `Dim Shared` values in `src/state/docklogic.bas` (no TELEM calls there, so `dock_test` checks them); `dock.bas` passes them to `TELEM_DockVisit`.

| Field | Meaning |
|---|---|
| `chapter` | the chapter whose dock it is |
| `credits_in`, `credits_out` | credits on arrival and on leaving |
| `spent_upg`, `spent_fuel`, `spent_shield` | credits actually taken for upgrades, fuel and shield repairs |
| `secs` | seconds in the dock, counted in frames |
| `exit` | `launch` or `stranded` |
| `bought` | `key:count` list of purchases: `refuel`, `repair`, then the upgrade keys (`laser`, `cannon`, ...) |
| `denied` | the same, for purchases refused for lack of credits |
| `afford` | upgrade keys whose next level costs no more than `credits_out` and which were not bought this visit |
| `seen` | rows the cursor visited, in list order |
| `lv` | the upgrade levels leaving the dock, comma-separated in `UPG_*` order (`UPG_LevelsStr$`) |

Counts in `bought` and `denied` top out at 99. `credits_earned.left` is the unspent amount: `CR_CashOut` zeroes `credits` before `session_end`, so `TELEM_CreditBonus` records what was held and `credits_earned` reports that.

### Backend schema

The tables are defined in [`server/migrations/`](../../server/migrations/) and the routes and validation in [`server/src/index.ts`](../../server/src/index.ts), with tests in `server/test/`:

- **`sss_telemetry`** (POST target for the batched event array): `session` (text, max 64 chars), `ev_time` (non-negative integer), `event` (text, max 64), `player_id` (text, max 64), `data` (text, max 1024), one row per event.
- **`scores`** (POST target for score submission, only sent if telemetry is on (`telemOn`, so never under `--no-telem`, an implied one or a declined consent prompt), `DB_URL`/`DB_KEY` are set, consent was given, and `score > 0`): `player_id` (max 64), `player_name` (max 32), `score`, `wave` (non-negative integers), `session` (max 64), and optionally `difficulty` (lowercase slug, max 16, stored as `normal` when absent). The game sends the run's level (`runDifficulty`, a `levels` name from `assets/config/difficulty.ini`).
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
