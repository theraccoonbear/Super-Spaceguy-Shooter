# Command-line options

`sss --help` prints the flags the binary you built accepts and is the authoritative list; the block below is a reference copy. For the input-script syntax the header of `src/sys/inputscript.bas` is authoritative; the Scripted playtests paragraph below is a summary.

```
sss [options]

  -v, --version          Print version and exit
  -h, --help             Show this help and exit
  --scene <name>         Jump to a named scene, skipping normal startup (see ../src/sys/README-sequence.md)
  --crawls               Crawl browser: list every named crawl with its scroll speed, play any of them
  --god                  God mode: shields, health, and laser never deplete
  --nerf                 Nerf mode: shorter stages, weaker bosses (for testing/streaming)
  --difficulty <level>   Play every run at this level (easy, normal or hard; assets/config/difficulty.ini), whatever Settings says
  --debug                Enable the debug HUD overlay and diagnostic console output
  --no-telem             Disable gameplay telemetry for this session (on by default; see [Telemetry and leaderboards](../server/README.md))
  --input-script <file>  Play from a script instead of the keyboard/gamepad (see Scripted playtests below)
  --script-override      Let flags differ from the input script's `#!` header (the command line wins)
  --leaderboard-file <file>  Show a saved top_scores JSON response on the leaderboard instead of polling (offline testing)
  --frames N             Quit after N frames (60 per second)
  --realtime             Keep 60 frames per second in --input-script runs (for recordings, see tools/dev record)
  --seed N               Fixed random seed, so a scripted run repeats exactly
  --credits N            Start every run with N credits (whole number, 0 or more; for trying the upgrade dock)
  --ships N              Start every run with N ships (testing)
  --shields N            Start every run with N shield points (testing, e.g. damaged shields at the dock)
  --fuel N               Start every run with N fuel (testing, e.g. a nearly empty tank at the dock)
  --pup K,K,K            Place power-ups (shield, fuel, points) when play starts: in your path, beside it, off-screen
  --screenshot-at N,N    Save frames N,... as shot-N.png in the launch folder
  --settings-dir <path>  Keep sss_settings.ini in this folder instead of the per-user one (--input-script runs use the launch folder)
```

**Crawls:** `--scene crawl:<key>` jumps to any named crawl. That covers every `CRAWL` task in `assets/sequence.txt` plus crawls the code starts directly (today, `death_final` on game over). `sss --help` prints the full list. A sequence crawl carries on from its place in the sequence; `crawl:death_final` plays and then goes to the title. `crawlN` still works for the sequence crawls. `sss --crawls` opens a browser of the same list: ↑/↓ select, ENTER plays and returns to the list, ←/→ picks the narration setting for the session (your saved setting isn't changed), ESC quits.

**Tutorial:** `--scene tutorial` starts the isolated tutorial run: nothing is recorded and it cannot be failed (see [the tutorial run](../src/sys/README-sequence.md)).

**Scripted playtests:** `--input-script <file>` replaces the keyboard and gamepad with a per-frame script. Each line is `<from> <to> KEY [KEY ...]`: hold those keys on frames from..to (inclusive, 60 per second). The keys are `LEFT RIGHT UP DOWN FIRE` (or `SPACE`) `ESC TAB ENTER BACKSPACE BACKTICK F1`-`F12`, any letter `A`-`Z` (either case counts), any digit `0`-`9`, and `#<code>` for any other `_KEYDOWN` code (e.g. `#21248` for Delete). The gamepad is `PAD_A PAD_B PAD_X PAD_Y PAD_START PAD_SELECT`, the left stick `PAD_LEFT PAD_RIGHT PAD_UP PAD_DOWN` and the d-pad `PAD_DPAD_UP PAD_DPAD_DOWN PAD_DPAD_LEFT PAD_DPAD_RIGHT` (an Xbox 360 layout), or raw: `PADBTN<n>` holds button n and `PADAXIS<n>-` / `PADAXIS<n>+` push axis n fully. These set the pad's raw state and go through the same mapping as a real controller (so `PAD_A` and `PAD_B` fire but are not the SPACE key to a menu that reads the keyboard). Every screen and dialog sees them, so menus can be scripted too: a key press registers once, on the first frame of its range. A line starting with `#` is a comment. A script can say how it must be launched in a `#!` header: `#! seed 1`, `#! args --god --nerf` (launch flags; repeatable) and `#! frames 20000` act as `--seed 1 --god --nerf --frames 20000` (`tests/playthrough/playthrough.txt` has one). Giving the same flag on the command line is fine when the values match; a different value (`--seed 7` against `#! seed 1`) is an error, unless `--script-override` lets the command line win. Scripts without a header run as before. A line can also react to the game instead of the clock: `@<trigger> +<offset> [<len> | *] [every <n>] KEY ...` holds the keys `<offset>` frames after each entry into a game state (`@GS_CRAWL +60 FIRE ESC` skips every crawl) or a sequence label (`@label:level3 ...`), for `<len>` frames (default 1), for as long as the trigger lasts (`*`), or repeating `every <n>` frames; `@GS_TITLE#1` fires on the first entry only. A held key lets go when its trigger ends. `tests/playthrough/playthrough.txt` is written this way; the full syntax is in the header of `src/sys/inputscript.bas`. Scripted runs skip the 60 fps throttle and go as fast as the machine allows (unless `--realtime` is given). Gameplay steps per frame, so the result doesn't change. With `--seed`, the same script plays the same fight every time. Example (`tests/input/boss-hold-left.txt` holds left and fires for 25 s):

```bash
tools/dev headless --scene boss3 --god --no-telem --seed 1 --frames 1500 --input-script tests/input/boss-hold-left.txt
```

Add `--screenshot-at 200,700,1250` to save those frames as `shot-<frame>.png` (gitignored) to look at afterwards. A relative script path is resolved from the directory you launch from.

`--leaderboard-file <file>` fills the leaderboard from a saved `top_scores` response, so it can be checked without the network: `tools/dev headless --scene title --no-telem --seed 1 --frames 130 --leaderboard-file tests/input/leaderboard.json --input-script tests/input/open-leaderboard.txt --screenshot-at 120`.

**Where settings live (#284):** `sss_settings.ini` (volumes, fullscreen, difficulty, telemetry consent, callsign, key and gamepad bindings, high score) is kept in a per-user folder, so it doesn't matter where the game is launched from: `$XDG_CONFIG_HOME/sss` (default `~/.config/sss`) on Linux, `%APPDATA%\sss` on Windows, `~/Library/Application Support/sss` on macOS. The game creates the folder if it's missing. On the first run with the new location it copies an existing `sss_settings.ini` from the launch folder, so current players keep their settings; the old file is left where it was and is no longer read. If the per-user folder can't be created or written, the game uses the launch folder, and if that isn't writable either it plays without saving settings (no error dialog). The local telemetry CSV (`sss_telemetry.csv`) stays in the launch folder (skipped if it isn't writable) and is written once, when the session ends or the window is closed, not on every event.

Dev builds only: `--settings-dir <path>` keeps `sss_settings.ini` in that folder (a relative path is from the launch folder; `.` is the launch folder itself), and any `--input-script` run uses the launch folder. So `tools/dev test`, `render`, `record` and the playthrough and determinism runs start from the settings in their own fresh launch folder and never read or write your own. `tools/dev run` mounts your host settings folder (`$XDG_CONFIG_HOME/sss` or `~/.config/sss`, created if missing) into the container, so a containerized run and a native run share settings. A `sss_settings.ini` in the repo root from before is copied into it on the first run.
