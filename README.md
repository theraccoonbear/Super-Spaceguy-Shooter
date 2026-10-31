# Super Spaceguy Shooter

> A political allegory wrapped in a love letter to 90s gaming, written entirely in QB64-PE (QBasic)

[![Build Linux](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=Linux)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)
[![Build macOS](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=macOS)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)
[![Build Windows](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=Windows)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)

Built with [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe).

---

## What it is

Super Spaceguy Shooter is a cinematic space shooter with a full narrative arc: intro crawl, cutscenes, six combat/asteroid stages (three with boss fights), and an outro sequence. The player flies a ship on a forward rail with free Y/Z movement; velocity-driven bank and pitch sell the illusion of full 3D maneuvering. Enemy waves are shot down while a story unfolds around them.

It runs natively on Linux, macOS, and Windows as a single compiled binary with no runtime dependencies. Network telemetry and leaderboards are optional and off by default unless configured; see [Telemetry and leaderboards](#telemetry-and-leaderboards) below.

## Current state

- Full intro-to-credits scene sequence: crawl → cutscene → title → six stages → outro, driven by a data-defined [scene sequencer](#architecture)
- Combat with projectiles, collision, hit effects, and wave-based enemy spawning, plus three boss fights
- Parallax starfield backdrop, with true 3D-modeled ships, asteroids, and pickups (planets are 2D sprites)
- Fully procedural audio: music, sound effects, and synthesized speech, with no audio files
- Persistent settings (music/SFX/speech/narration volumes, fullscreen, telemetry consent, player callsign, key and gamepad bindings)
- Optional anonymous gameplay telemetry and an online leaderboard (opt-in, disabled unless a backend is configured)
- Cross-platform CI/CD building, testing, and releasing on all three platforms

## Building

You need:

- [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe) installed and on your `PATH` as `qb64pe`.
- [Node.js](https://nodejs.org/) with `npm` on your `PATH`. `tools/buildqb sss.bas` runs `npm install` in `math/` and then `node tools/emit-spline.js` to generate the spline math (see [Flight path math](#flight-path-math)).
- Network access on the first build, so `npm install` can fetch [exprforge](https://www.npmjs.com/package/exprforge) into `math/node_modules/`. Later builds use the installed copy.

```bash
# recommended -- run from the repo root
tools/buildqb sss.bas
```

This generates the spline math, bakes the speech phoneme dictionary, regenerates `src/sys/version.bas` from the `VERSION` file and the current git commit, links QB64-PE's asset directory to this repo's `assets/` (so `$EMBED:'assets/...'` resolves), and compiles. The binary lands in `builds/sss` (`builds/sss.exe` on Windows).

```bash
# smoke test
builds/sss --version
```

Pre-built binaries for Linux, macOS, and Windows are produced by CI on every merge to `master` and attached to tagged releases.

**Release builds.** A plain build is a dev build. `tools/buildqb --release sss.bas` (or `SSS_RELEASE=1`; `.github/scripts/qb64build.sh --release` in CI; `tools/dev build --release` in the container) makes a release build: `--version` prints the bare version, and the dev-only flags (everything below except `--version`, `--help`, `--no-telem` and `--debug`) are compiled out, so passing one is an `unknown option` error. `--debug` still works, for bug reports, but `--help` doesn't list it. `tools/make-version.sh` switches it with `$LET RELEASEBUILD` in the generated `src/sys/version.bas`. Tagged (`v*`) releases ship release builds; every other CI build is a dev build, plus one Linux release build checked by `tests/release_build_test.sh`. A release build overwrites `builds/sss`, so rebuild without `--release` before using the dev flags again.

### Downloading a release

Each release has three binaries: `sss-linux`, `sss-macos` and `sss-windows.exe`. Release assets don't keep the executable bit, so on Linux and macOS make the file executable after downloading it:

```bash
chmod +x sss-linux    # or sss-macos
```

macOS also quarantines files downloaded from the internet and won't open an unsigned binary. Clear the flag with `xattr -d com.apple.quarantine sss-macos`, or right-click the file in Finder, choose **Open**, and confirm.

### Building in a container

If you'd rather not install QB64-PE natively, `tools/dev` runs everything inside an Ubuntu 24.04 container that mirrors CI's Linux job: the same apt packages, QB64-PE `v4.5.0` (pinned to match `QB64PE_VERSION` in `.github/workflows/build.yml`; bump `QB64PE_VERSION`/`QB64PE_ASSET` in `tools/container/Containerfile` together with it), and Node 22 for ExprForge. You only need Podman or Docker. The script uses Podman if it finds it, otherwise Docker; set `SSS_ENGINE=docker` to override.

```bash
tools/dev image   # build the image (done automatically on first use)
tools/dev build   # tools/buildqb sss.bas + the --version smoke test
tools/dev test    # full test suite (.github/scripts/qb64test.sh, same as CI)
tools/dev bake    # tools/bake_speech_dict
tools/dev emit    # regenerate spline math (npm install in math/ + node tools/emit-spline.js)
tools/dev shell   # interactive shell in the container; `tools/dev shell <cmd>` runs one command
tools/dev run     # play the game in the container on your display; args pass through to sss
tools/dev headless  # run the game on an off-screen display (Xvfb), e.g. for scripted playtests (below)
```

Typical workflow:

```bash
git pull
tools/dev run --scene boss3 --god   # rebuilds first if any source changed, then plays
tools/dev test                      # full suite before you commit (pre-commit checklist in CLAUDE.md)
```

`run` takes any [CLI option](#cli-options). Handy ones: `--scene boss3` / `boss5` / `boss6` jumps to a boss fight (`bossN` is the boss on level N; levels 3, 5 and 6 have one), `--scene playing4` starts a level, `--scene dock2 --credits 2000` opens the upgrade dock after stage 2 (docks follow stages 1-5) with 2000 credits to spend, `--god` stops you dying, `--nerf` gives short stages and weak bosses, `--debug` shows the debug HUD.

The repo is bind-mounted at its host path, not copied, so `builds/` and every generated file land in your checkout. They are owned by you, not root: Podman runs with `--userns=keep-id`, rootful Docker with `--user $(id -u):$(id -g)`, and rootless Docker needs neither. The mounts use `:Z`, so this works under SELinux (Fedora, Bazzite). Git worktrees work too, because the main checkout's git directory is mounted alongside.

`tools/dev run` and `tools/dev headless` rebuild `builds/sss` if it is missing, older than any file in `sss.bas`, `src/`, `assets/` or `VERSION` (so a `git pull` or a branch switch never plays a stale build), or was built natively on a host with a newer glibc than the container, then runs it with your desktop passed through: the X11 socket and `DISPLAY`/`XAUTHORITY` (XWayland on Wayland desktops), the PulseAudio/PipeWire socket from `$XDG_RUNTIME_DIR`, `/dev/dri` for GPU rendering, and `/dev/input` so the game sees your controllers (bind-mounted, so a pad plugged in after launch works too). For that container only, SELinux labeling is turned off (`--security-opt label=disable`) so it can share the sockets, and `--ipc=host` lets X11 shared memory work. If no audio socket is found it warns and runs silently. Every other command stays headless. You can also run a container-built `builds/sss` directly on the host if it has the GL/X11/ALSA runtime libraries.

### CLI options

```
sss [options]

  -v, --version          Print version and exit
  -h, --help             Show this help and exit
  --scene <name>         Jump to a named scene, skipping normal startup (see src/sys/README-sequence.md)
  --crawls               Crawl browser: list every named crawl with its scroll speed, play any of them
  --god                  God mode: shields, health, and laser never deplete
  --nerf                 Nerf mode: shorter stages, weaker bosses (for testing/streaming)
  --difficulty <level>   Play every run at this level (easy, normal or hard; assets/config/difficulty.ini), whatever Settings says
  --debug                Enable the debug HUD overlay and diagnostic console output
  --no-telem             Disable gameplay telemetry for this session (on by default; see below)
  --input-script <file>  Play from a script instead of the keyboard/gamepad (see below)
  --leaderboard-file <file>  Show a saved top_scores JSON response on the leaderboard instead of polling (offline testing)
  --frames N             Quit after N frames (60 per second)
  --seed N               Fixed random seed, so a scripted run repeats exactly
  --credits N            Start every run with N credits (whole number, 0 or more; for trying the upgrade dock)
  --ships N              Start every run with N ships (testing)
  --shields N            Start every run with N shield points (testing, e.g. damaged shields at the dock)
  --fuel N               Start every run with N fuel (testing, e.g. a nearly empty tank at the dock)
  --pup K,K,K            Place power-ups (shield, fuel, points) when play starts: in your path, beside it, off-screen
  --screenshot-at N,N    Save frames N,... as shot-N.png in the launch folder
```

**Crawls:** `--scene crawl:<key>` jumps to any named crawl. That covers every `CRAWL` task in `assets/sequence.txt` plus crawls the code starts directly (today, `death_final` on game over). `sss --help` prints the full list. A sequence crawl carries on from its place in the sequence; `crawl:death_final` plays and then goes to the title. `crawlN` still works for the sequence crawls. `sss --crawls` opens a browser of the same list: ↑/↓ select, ENTER plays and returns to the list, ←/→ picks the narration setting for the session (your saved setting isn't changed), ESC quits.

**Scripted playtests:** `--input-script <file>` replaces the keyboard and gamepad with a per-frame script. Each line is `<from> <to> KEY [KEY ...]`: hold those keys on frames from..to (inclusive, 60 per second). The keys are `LEFT RIGHT UP DOWN FIRE` (or `SPACE`) `ESC TAB ENTER BACKSPACE BACKTICK F1`-`F12`, any letter `A`-`Z` (either case counts), any digit `0`-`9`, and `#<code>` for any other `_KEYDOWN` code (e.g. `#21248` for Delete). The gamepad is `PAD_A PAD_B PAD_X PAD_Y PAD_START PAD_SELECT`, the left stick `PAD_LEFT PAD_RIGHT PAD_UP PAD_DOWN` and the d-pad `PAD_DPAD_UP PAD_DPAD_DOWN PAD_DPAD_LEFT PAD_DPAD_RIGHT` (an Xbox 360 layout), or raw: `PADBTN<n>` holds button n and `PADAXIS<n>-` / `PADAXIS<n>+` push axis n fully. These set the pad's raw state and go through the same mapping as a real controller (so `PAD_A` and `PAD_B` fire but are not the SPACE key to a menu that reads the keyboard). Every screen and dialog sees them, so menus can be scripted too: a key press registers once, on the first frame of its range. A line starting with `#` is a comment. Scripted runs skip the 60 fps throttle and go as fast as the machine allows. Gameplay steps per frame, so the result doesn't change. With `--seed`, the same script plays the same fight every time. Example (`tests/input/boss-hold-left.txt` holds left and fires for 25 s):

```bash
tools/dev headless --scene boss3 --god --no-telem --seed 1 --frames 1500 --input-script tests/input/boss-hold-left.txt
```

Add `--screenshot-at 200,700,1250` to save those frames as `shot-<frame>.png` (gitignored) to look at afterwards. A relative script path is resolved from the directory you launch from.

`--leaderboard-file <file>` fills the leaderboard from a saved `top_scores` response, so it can be checked without the network: `tools/dev headless --scene title --no-telem --seed 1 --frames 130 --leaderboard-file tests/input/leaderboard.json --input-script tests/input/open-leaderboard.txt --screenshot-at 120`.

## Testing

```bash
# full suite, in parallel -- the same script CI runs on Linux, macOS, and Windows
tools/test                  # native (uses the qb64pe on your PATH)
tools/dev test              # in the container
QB64_TEST_JOBS=4 tools/test # pick the worker count (default: half your logical CPUs, at least 2)

# one test on its own (native; in the container wrap it, e.g.
#   tools/dev shell bash -c "tools/buildqb tests/spore_test.bas && builds/spore_test")
tools/buildqb tests/spore_test.bas && builds/spore_test
tools/http_queue_test   # builds http_queue_test.bas, starts a local mock HTTP server, runs it
bash tests/tools_dev_test.sh  # checks the container command `tools/dev run` builds (display, GPU, controllers)
```

The runner builds and runs each test in `tests/` on one of several workers, then prints every test's output in order and a summary with build and run times. On Linux and macOS each worker compiles with its own copy of QB64-PE. Two compiles on one install can silently swap their output binaries, so never run two native builds at once on the same QB64-PE (#239). Each test prints `=== <name> ===` first, and the runner fails any binary that doesn't print its own banner. To add a test, put its name in `TESTS` in `.github/scripts/qb64test.sh`.

**A new controller:** record it once, commit the file, and it's tested. `tools/padrecord.bas` opens a small window that asks you to hold each control in turn (stick and d-pad directions, A, B, X, Y, Start, Back, and nothing at all) and press ENTER, then writes the pad's raw buttons and axes to `tests/input/pads/<name>.txt`. Build it and run it from the repo root with the pad plugged in: `tools/buildqb tools/padrecord.bas && builds/padrecord <name>`. `tests/pad_map_test` loads every file there and checks each control reaches the right game action, so a control the mapping drops fails CI by pad and control name (e.g. `xbox360_xpad: DPAD_UP produced nothing`).

**Full playthrough** (`tests/playthrough/`, #100): one scripted, seeded run (`--god --nerf --seed 1 --frames 20000`, input `tests/playthrough/playthrough.txt`) plays the whole game the way a fresh install sees it, from a launch folder with no `sss_settings.ini`: data notice, callsign, lead-in cards, intro crawl, emperor card, title, all six stages (crawls, combat, the three bosses, the asteroid field, planet arrivals and cinematics), the outro and back to the title.

```bash
tools/dev build                                  # the run needs builds/sss
tools/dev shell tests/playthrough/run.sh         # about 2.5 minutes; extra args go to sss, e.g. --screenshot-at 3000,9000
```

The game writes a milestone log when the `SSS_MILESTONE_LOG` env var names a file (off otherwise): one line per frame on which the game state or the sequence step changed (`<frame> <state> <seqIdx> <label> <TASK> <args>`), plus `<frame> EXIT` when `--frames` ends the run. `run.sh` checks that the game exited cleanly at `--frames`, that the log matches `tests/playthrough/expected.txt` in order with nothing missing or extra (so it reaches the final title inside the frame budget), and that the local telemetry CSV has one `boss_defeated` per boss and a winning `session_end`. A failure names the milestone where the run went wrong or stalled; the log, the game's output and the CSV stay in `builds/playthrough/` (CI uploads them as the `playthrough-logs` artifact). The binary must be built with an empty `assets/.env`, because the run OKs the data notice and would otherwise send its telemetry and leaderboard score. CI runs it on Linux as its own step. When the game flow changes on purpose (a stage added or reordered), update `expected.txt`, and `playthrough.txt` and `FRAMES` in `run.sh` if the run gets longer.

Each subsystem doc below has its own "test in isolation" section with more detail.

### Render tests

Golden-screenshot tests catch rendering regressions (blend state, font alpha, overlays) that the headless tests can't see. Each scene in `tests/render/scenes/` is a short seeded [scripted playtest](#cli-options): an input script whose `#!` lines give its `sss` options, the frames to screenshot, and any rectangles to leave out of the comparison. The runner plays each one under Xvfb with `--god --no-telem --seed 1` and compares every screenshot with `tests/render/golden/<scene>-<frame>.png` using `tools/imgdiff.bas`, a small QB64 compare tool. The font compositing rules themselves (glyph holes stay transparent, font calls leave blending on, partial opacity, rich colour codes) are pixel-checked off-screen by `tests/font_render_test.bas` in the regular suite, on every OS.

| Scene | Shows |
|---|---|
| `title` | title screen (the version string is masked: it changes every commit), then the ESC command console |
| `about` | About screen scrolled to the credits: panel UI, bitmap font, rich colour codes |
| `playing2` | level 2 combat: enemies, lock-on bracket, enemy bolts and impact rings, HUD |
| `boss3` | lead-aimed bolts with closing impact rings, then spore clouds |
| `boss5` | a cut's warning lines, then its beam |
| `boss6` | devour's pull streaks and chevrons |

Each scene is in one of two groups, set by a `#! group:` line in its file (`ui` if there is none). **ui** scenes (title, About, consent, callsign, dock) gate: a mismatch fails the run and CI. **gameplay** scenes (bosses, `playing2`, `pickups`, and the pause dialogs over live play) move with every tuning tweak before v0.1 (#319), so for now a mismatch is reported (per-group summary, a CI `::warning::` per scene, diffs uploaded) but doesn't fail the run. Don't re-bless gameplay goldens per PR during tuning. The switch is `GAMEPLAY_GATING=0` near the top of `tests/render/run.sh`. **At v0.1** (release checklist): re-bless the gameplay goldens once from the final build (`tools/dev render --update gameplay`), then flip it to `1`.

```bash
tools/dev render                # in the container: build sss, run every scene, compare (~2 min, mostly the build)
tools/dev render boss5 title    # just these scenes
tools/dev render --no-build     # reuse builds/sss
tools/dev render --update       # re-bless: run each scene 3 times, check the runs are byte-identical, save as goldens
tools/dev render --update ui    # re-bless one group only (ui, gameplay or all)
tests/render/run.sh             # natively on Linux (needs qb64pe on PATH and xvfb-run)
```

The comparison is exact by default (`RENDER_TOL=N` allows a per-channel difference of N, `RENDER_MAX_FRAC=F` lets a fraction F of pixels differ beyond it). Seeded scripted runs are byte-repeatable and the container matches CI's Linux runner, so nothing needs a tolerance today. On a mismatch the actual screenshots and a `diff-<frame>.png` (red = differs, yellow = within tolerance, blue = masked) are left in `tests/render/out/<scene>/`; CI uploads that folder as the `render-test-results` artifact. CI runs the suite on the Linux job only.

**When to update goldens:** only when a change is meant to change what's on screen (a new effect, a HUD tweak, different fonts or colours, changed gameplay timing that moves things). Run `tools/dev render --update`, look at every changed PNG in `git diff` before committing it, and say in the PR which goldens changed and why. If a golden changes and you didn't mean to change rendering, that's the bug the suite is for. Re-bless from the container, not a native build on another distro, so the goldens keep matching CI. To add a scene, write `tests/render/scenes/<name>.txt` (copy an existing one) and run `tools/dev render --update <name>`.

## Telemetry and leaderboards

The game can optionally send anonymous gameplay events and score submissions to a small backend we own: a [Cloudflare Worker](https://developers.cloudflare.com/workers/) backed by a [D1](https://developers.cloudflare.com/d1/) (SQLite) database, in [`server/`](server/). This is entirely off unless you configure it:

1. Create `assets/.env` (gitignored) at the repo root:
   ```
   DB_URL=https://sss-api.<your-account>.workers.dev
   DB_KEY=<the API_KEY you set on the Worker>
   ```
2. Leave it empty or absent to disable network telemetry entirely. The game still writes a local `sss_telemetry.csv`, and no network requests are made.
3. Players are asked for one-time consent in-game before anything is sent; `--no-telem` skips telemetry (and the consent prompt) for a single session.

See [`src/sys/README-telemetry.md`](src/sys/README-telemetry.md) for the event schema and [`src/sys/README-http.md`](src/sys/README-http.md) for the underlying HTTP layer.

### Deploying the backend

The Worker serves the three calls the game makes: `POST /sss_telemetry`, `POST /scores` (both need the key), and the public `GET /top_scores`. The schema is in `server/migrations/`. One-time setup, from `server/`:

1. Create a free [Cloudflare account](https://dash.cloudflare.com/sign-up).
2. `npm ci`, then `npx wrangler login`.
3. `npx wrangler d1 create sss` and paste the printed `database_id` into `server/wrangler.toml`.
4. `npm run migrate` to create the tables in the remote database.
5. `npx wrangler secret put API_KEY` and enter a long random string (e.g. `openssl rand -hex 32`). This is the game's `DB_KEY`. It identifies the client, it is not a secret: it is embedded in every build (`strings builds/sss` shows it), so anyone can post with it. The Worker's own checks are what protect the data (see below).
6. `npm run deploy`. Wrangler prints the Worker URL (`https://sss-api.<your-account>.workers.dev`).
7. In the GitHub repo settings, set the Actions secrets `DB_URL` to the Worker URL and `DB_KEY` to the `API_KEY`, then rebuild. CI writes them into `assets/.env`.

Run `npm test` in `server/` to test the Worker locally (Vitest in the Workers runtime with D1 migrations applied); CI runs it too. Later schema changes go in a new `server/migrations/NNNN_*.sql` file, applied with `npm run migrate`.

**Automatic deploys.** Pushes to `master` that change anything under `server/` deploy automatically: CI's "Deploy server" job applies the D1 migrations, then runs `wrangler deploy`, after the server tests pass. It needs two repo Actions secrets: `CLOUDFLARE_API_TOKEN` (Cloudflare dashboard → My Profile → API Tokens → the "Edit Cloudflare Workers" template, plus D1 Edit permission) and `CLOUDFLARE_ACCOUNT_ID`. The manual `npm run migrate` / `npm run deploy` steps above remain for first-time setup and emergencies.

**Local testing.** To run the Worker on your machine with a local D1, from `server/`:

```bash
echo "API_KEY=localkey" > .dev.vars            # the local DB_KEY; .dev.vars is gitignored
npx wrangler d1 migrations apply sss --local
npx wrangler dev --ip 0.0.0.0                  # serves http://localhost:8787
```

Then point the game at it in `assets/.env` with `DB_KEY=localkey` and a `DB_URL` that depends on where the game runs. A native build uses `DB_URL=http://localhost:8787`. A game run with `tools/dev run` uses `DB_URL=http://host.containers.internal:8787`, because inside the container `localhost` is the container, not your machine. `DB_URL` and `DB_KEY` are embedded at build time, so rebuild after editing `assets/.env`.

The free plan allows 100,000 Worker requests and 100,000 D1 rows written per day; past that, requests fail until the 00:00 UTC reset. Cloudflare's [Workers](https://developers.cloudflare.com/workers/platform/limits/) and [D1](https://developers.cloudflare.com/d1/platform/pricing/) limits pages list no inactivity pause.

**What the Worker accepts.** `POST /scores` takes exactly one row per request, a `score` up to 250,000 and a `wave` up to 100 (the derivation is next to `MAX_SCORE` in `server/src/index.ts`; raise it if scoring grows), and a `player_name` that follows the in-game callsign rules: 3 to 32 printable ASCII characters (32-126), `~X` colour tokens included. Each client IP may make 10 `POST /scores` and 30 `POST /sss_telemetry` requests a minute (the `[[ratelimits]]` bindings in `server/wrangler.toml`); past that the Worker answers 429. The game sends one of each per run.

**Moderating the leaderboard.** To look at and remove bad rows, from `server/`:

```bash
npx wrangler d1 execute sss --remote --command "SELECT id, player_name, score, wave, created_at FROM scores ORDER BY score DESC LIMIT 20"
npx wrangler d1 execute sss --remote --command "DELETE FROM scores WHERE id IN (123, 124)"
```

`DELETE FROM scores WHERE player_name = '...'` or `WHERE score > ...` work the same way. Run the `SELECT` with the same `WHERE` first to check what it matches.

---

## Under the hood

This is a from-scratch game engine written in QBasic. No game framework, no graphics library, no audio library. Everything described below is implemented in pure BASIC.

### Software 3D rendering pipeline

The renderer lives under `src/3d/` (`mesh.bas`, `poly.bas`, `matrix.bas`, `obj.bas`, `camera.bas`, `object.bas`, `scene.bas`, `collision.bas`). It loads a custom text-based mesh format (`assets/models.e3d`, convertible from Wavefront OBJ via `obj2e3d.bas`) at startup, applies 4×4 matrix transforms (translation, rotation, scale) for each object each frame, projects vertices through a perspective camera, and rasterizes filled polygons directly to an offscreen buffer. Backface culling and a per-face depth sort keep overdraw reasonable. There is no GPU involvement; every pixel is computed by the CPU. This true 3D pipeline is used for the things the player directly interacts with: ships, asteroids, pickups. Planets are 2D sprites and the background is a parallax starfield (`starfield.bas`), not modeled geometry. See [`src/engine3d.md`](src/engine3d.md).

### Procedural sound synthesis and software mixer

`src/audio/snd.bas` implements a real-time software audio mixer. Sound effects like laser shots, explosions, impacts, and pickups are synthesized mathematically at startup into sample buffers (sine waves, filtered noise, frequency sweeps) and mixed at the sample level into a single output stream each frame. No WAV files, no audio assets.

### Pseudo-MIDI music system

`src/audio/music.bas` implements a pattern-based music engine. Instruments are synthesized from first principles (oscillators, envelopes, filters). Patterns of notes are arranged into cues that the game triggers by name (`"intro"`, `"game"`, `"boss"`, `"outro"`), and the engine crossfades or cuts between them as the scene changes. It behaves like a MIDI sequencer but with no MIDI library, no sound font, and no external files.

### Digital voice synthesizer

`src/audio/speech.bas` implements a phoneme-based text-to-speech system driven by a dictionary baked from the CMU Pronouncing Dictionary. Input text is converted to an ARPAbet phoneme sequence, and each phoneme is synthesized using formant synthesis: additive sine harmonics tuned to the resonant frequencies of the human vocal tract, with per-phoneme noise for fricatives and stops. Coarticulation crossfades between adjacent phoneme wavetables so speech doesn't sound like disconnected clicks. The game uses this for the narrative crawl and in-flight callouts. See [`src/sys/README-speech.md`](src/sys/README-speech.md).

### Scene sequencer

`src/sys/sequence.bas` drives the full game flow as a linear sequence of named waypoints, covering crawl scenes, cutscene cards, the title screen, combat/boss/asteroid stages, and the outro. The sequence is defined in the plain-text `assets/sequence.txt`, not hardcoded. `SEQ_Load` parses the file once at startup; `SEQ_Advance` steps through it. The title screen is a waypoint in the sequence rather than a mode the game escapes to, so the game boots directly into the story and "New Game" from the title steps forward into the next stage rather than restarting from scratch. See [`src/sys/README-sequence.md`](src/sys/README-sequence.md).

### HTTP and telemetry

`src/sys/http.bas` is a small non-blocking HTTP client built on libcurl via QB64-PE's `DECLARE LIBRARY` C interop (`src/sys/curl_qb64.h`), used to POST/GET against the [Cloudflare Worker backend](server/) without blocking the game loop. `src/sys/telemetry.bas` logs gameplay events locally and, if configured, batches and POSTs them at session end; `src/sys/lbrd.bas` polls and parses the top-scores leaderboard. See [`src/sys/README-http.md`](src/sys/README-http.md) and [`src/sys/README-telemetry.md`](src/sys/README-telemetry.md).

### Architecture

The codebase is split across `$INCLUDE` modules organized by discipline under `src/`:

| Folder | Responsibility |
|---|---|
| `sys/` | Core systems: main loop wiring, game state, CLI, scene sequencer, settings, debug output, HTTP, telemetry, JSON, leaderboard |
| `3d/` | 3D engine: mesh/matrix/polygon/camera math, mesh loading, collision, starfield |
| `audio/` | Procedural music, sound effects, and speech synthesis |
| `gameplay/` | Player, enemies, boss, waves, enemy behavior, stage/level logic |
| `state/` | Per-screen game states: title, crawl, intro, combat, asteroids, game over, consent, username entry, leaderboard display, lead-in |
| `2d/` | 2D presentation: HUD, UI panels, bitmap font, particle effects, narrative crawl renderer, about screen |

`sss.bas` (repo root) is the entry point: it sets up `$EMBED`s for all assets, `$INCLUDE`s `src/game.bi` and `src/engine3d.bi` (which in turn `$INCLUDE` every module above in dependency order), parses CLI args, and runs the main game loop and top-level state dispatch. `src/sys/dims.bas` declares the shared global state (game objects, constants, HUD state) that every module reads and writes. QB64-PE has no module-private state, so this file is effectively the game's shared memory layout.

### Flight path math

**All spline flight-path math lives in [`math/formula.expr`](math/formula.expr)**, written in the [exprforge](https://www.npmjs.com/package/exprforge) DSL. It is the single source of truth for every flight-path calculation.

Gameplay doesn't use it today. The boss uses hand-coded hunt/evade movement, and spline routes are kept for possible cinematics. See [ADR-0001](docs/adr/0001-rail-shooter-scope.md).

Do not hand-edit the generated files. `node tools/emit-spline.js` (run from the repo root, after `npm install` in `math/`) regenerates both downstream targets from the DSL:

| Generated file | Language | Consumer |
|---|---|---|
| `src/gameplay/spline_path_gen.bi` | QB64-PE | Game runtime (`behavior.bas` flyover states; not used by gameplay) |
| `tools/TrailForge/src/math/spline_gen.ts` | TypeScript | TrailForge preview |

`tools/buildqb sss.bas` runs the emit script on every build (locally and in CI), and the test runner regenerates `spline_path_gen.bi` when it is missing or older than its inputs, so the QB64 output is always fresh. `spline_path_gen.bi` is gitignored: never commit it. `spline_gen.ts` is tracked: if you add or change a function in the DSL, run the emit script (or `tools/dev emit`) and commit the regenerated `spline_gen.ts` with your `formula.expr` change.

Implemented algorithms: Catmull-Rom position/tangent weights, Gram-Schmidt frame, standoff offset, arc-length reparameterization, and Rodrigues parallel transport for smooth ship-body orientation.

---

## Controls

To see the controls in game, open the pause dialog (ESC / Start) and press **C** (the roll button, X by default, on a gamepad), or pick CONTROLS in the title screen's command console.

The tables below show the default bindings. On-screen prompts follow the device you last touched: key names after a key press, the bound pad button (as a coloured badge) after a pad press. Every menu and dialog has a cursor: ↑ / ↓ (or the stick or d-pad) move it and ENTER / pad A picks, and the hotkeys listed below still work.

### Remapping

Settings > **CONTROLS** (ENTER / pad A on that row), or **K** / the nova button (Y by default) in the pause dialog, opens the remap page. It lists every action with its key and its pad button. ↑ / ↓ pick an action, ← / → switch between the KEY and PAD columns, and ENTER / pad A rebinds it: press the new key or button. **RUN PAD SETUP** asks for each pad action in turn, and **RESET TO DEFAULTS** restores both. ESC is always pause and back, and the arrow keys and the stick and d-pad always move, so those can't be rebound; W / A / S / D are the movement keys you can change. Leaving the page saves the bindings in `sss_settings.ini`, with pad bindings stored per controller name.

**First-run pad setup.** When a gamepad the game has no built-in layout for, and no saved bindings for, is connected at the title screen, the pad setup wizard opens on its own: press the button you want for each action. A stick, d-pad or arrow push skips an action (so does waiting 10 seconds), and keyboard ESC cancels. A cancelled setup isn't asked again for that pad; run it from Settings > CONTROLS > RUN PAD SETUP.

### In flight

| Key | Gamepad | Action |
|---|---|---|
| Arrow keys / WASD | Left stick | Move ship |
| Space (hold) | A or B | Fire (both bottom face buttons, so a Nintendo-labeled pad fires from either) |
| E | X | Evasive roll, once bought at the dock |
| Q | Y | Nova pulse, once bought at the dock |
| ESC | Start | Pause / abort-mission dialog: CONFIRM RETREAT, CONTROLS, REMAP CONTROLS, CANCEL. It opens on CANCEL, so ENTER / A resumes. Keyboard hotkeys: Y retreats, C shows the controls, K opens the remap page, N cancels. Pad: the roll button (X) shows the controls, the nova button (Y) opens the remap page, B cancels. ESC / Start closes it |
| TAB | Back / Select | Camera mode on/off. The game freezes while you adjust; pressing it again locks the angle and saves it |
| ↑ / ↓ (camera mode) | Stick up/down | Tilt the camera |
| R (camera mode) | — | Reset to the default chase camera |
| ESC (planet arrival / cutscene) | Start | Return to the title |

### Title and menus

| Key | Gamepad | Action |
|---|---|---|
| P | Start | Start a new game |
| ESC | Back / Select | Open/close the command console |
| A / C / S / L / Q / N | B (Cancel only) | Console: About / Controls / Settings / Leaderboard / Quit / Cancel |
| ↑ ↓ then ENTER | Stick up/down then A | Console: move the highlight and pick it |
| ↑ ↓ ← → | Left stick | Navigate and adjust Settings; scroll About; page through Controls |
| ENTER | A | Confirm (Settings callsign and CONTROLS rows, data notice, remap page) |
| ESC | B (or Start) | Back / cancel (Settings, About, Leaderboard, Controls, remap page, data notice) |
| F11 | — | Toggle fullscreen (any screen) |

### Story screens

| Key | Gamepad | Action |
|---|---|---|
| Space (hold) | A or B (hold) | Fast-forward the narrative crawl |
| Space + ESC | A or B + Start | Skip the crawl |
| Space | A | Continue (intro card, game over) |
| Any key | A / Start | Skip the logo cards |

On the data notice, X is "don't ask again" (S on the keyboard).

**Callsign entry.** On the keyboard, type the name, then ENTER (or SPACE) when done or ESC to skip. On a gamepad it's an arcade letter spinner: up / down spin the character under the cursor (A-Z, 0-9, space, `-`, `.`; hold to repeat), left / right move, A goes to the next character (adding one at the end), B deletes, Y cycles that character's colour, Start is done and Back skips. Both edit the same name, so you can switch device mid-entry.

### Upgrade dock

| Key | Gamepad | Action |
|---|---|---|
| ↑ / ↓ (or W / S) | Stick or d-pad up/down | Pick a row (the list scrolls) |
| ← / → (or A / D) | Stick or d-pad left/right | On REFUEL / SHIELDS: buy less / more (steps of 10% of the tank or shield) |
| ENTER | A | Buy the amount shown, or the next level (on LAUNCH: leave) |
| ESC | B or Start | Leave for the next stage at once |

### Debug

| Key | Action |
|---|---|
| `` ` `` | Toggle the debug HUD overlay. It starts on with `--debug`, but the key works in any build |

---

## Credits and the upgrade dock

Credits (`$`, shown next to the score) are a second currency, separate from score: spending them never lowers your score or rank. Kills, bosses, stage clears and the asteroid field (near misses, asteroids a nova pulse destroys, and getting through) earn them. After each planet arrival except the last, the **upgrade dock** opens: buy upgrades for the rest of the run, or leave with one press. Credits and upgrades reset on a new game. At the end of a run, win or death, leftover credits become score (1 point per credit by default, `credit_bonus_rate` in `assets/config/economy.ini`), shown as `CREDITS BONUS +N` on the game-over screen or the title after the outro, and counted in your high score and leaderboard score.

### Upgrades

| Upgrade | What it does | Levels |
|---|---|---|
| Laser capacitor | Bigger laser bank (LA) that recharges faster | 3 |
| Twin cannons → spread shot | Two parallel shots per trigger pull, then a three-way spread | 2 |
| Rapid fire | Shorter delay between shots | 2 |
| Shield capacity | Bigger shield (SH) | 3 |
| Shield regen | Shields refill on their own after a few seconds without a hit | 2 |
| Hull armour | Less damage from collisions and asteroids | 2 |
| Nova pulse | **Q** / pad **Y**: clears every enemy shot and blasts ships and asteroids near you; a boss loses a few points. Charges per stage refill at every dock | 3 |
| Thrusters | Faster sideways movement | 2 |
| Evasive roll | **E** / pad **X**: a quick sideways dash (the way you're steering) that nothing can hit; level 2 cools down faster | 2 |
| Tractor beam | Pulls power-ups toward the ship | 2 |
| Fuel tank | Bigger fuel tank (the extra room arrives empty: fill it at REFUEL) | 2 |

### Fuel and shields

The first two dock rows sell supplies by the amount. Nothing else refills them: a planet arrival tops up the laser only, and only losing a ship hands you a full tank and full shields.

- **REFUEL**: fuel at `fuel_price` per unit times the dock's surcharge (`fuel_mult`, see below).
- **SHIELDS**: shield points at a flat `shield_price` each.

The highlighted row shows the amount between ◂ ▸ arrows and its cost (red when you can't afford it, `FULL` when nothing is missing). The amount starts at what your credits fill and goes back there after every purchase, so one ENTER means "fill what I can afford"; ← → change it in steps of 10% of the capacity. Under the list, REFUEL shows the price per unit and `NEXT JUMP NEEDS 55 FU`, an honest estimate from the next leg's stages in `assets/sequence.txt`: their expected seconds (`fuel_kill_secs`, `fuel_asteroid_secs` in `economy.ini`, each boss fight's `secs=`) x the real burn in play (`fuel_burn`) x a margin (`fuel_margin`). Some legs need more than the base tank holds; the line then alternates with `TANK 100: UPGRADE TANK` and the need tick sits past the end of the FU bar. You are only stranded when your credits can't fill the tank to what it can hold of the leg: flying the rest dry is allowed; SHIELDS shows the price and the result (`SHIELD 40 > 100`).

**Fuel prices only go up.** After chapter 1 the Emperor blockades the refinery world, and every dock after that charges more: `fuel_mult` in `economy.ini` is 1.0, 1.4, 1.8, 2.2, 2.6 for docks 1 to 5, and it never eases. REFUEL shows the rise next to the price (`$2.80/U  ▲+40%`), and each dock reads out a news line about the blockade on arrival (shown as a ticker under the list; the `dock_news1`..`dock_news5` blocks in `assets/gametext.txt`).

**Stranded.** If you try to leave (LAUNCH or back) when the fuel in the tank plus all the fuel your credits can buy won't reach the next planet, the dock asks **ABANDON RUN AND EKE OUT A LIVING HERE?** with one answer, **[ YES ]**: back and the arrows do nothing, so spend what you can first. YES ends the run: leftover credits become score as on a death, a short crawl plays (`stranded_final` in `gametext.txt`), and the game-over card reads **STRANDED**. God mode is never stranded. `--scene dock2 --credits 0 --fuel 10` shows it.

A status box at the bottom left shows the ship's shields (SH), laser (LA) and fuel (FU) as absolute values over bars: a highlighted supply row adds a see-through segment for the amount being bought, and the fuel bar has a white tick at what the next jump needs. In the dock, the two lines under the list say what the highlighted upgrade does and exactly what its next level changes (for example `MAX 100>125, REGEN +20%`), or `MAXED`. The same list is in game on the Controls screen's **SHIP SYSTEMS** pages (pages 3 and 4: ← → or the stick). The first launch after buying the roll or the nova shows its key (`NOVA READY - Q / PAD Y`) for a few seconds. The descriptions sit next to each upgrade in `assets/config/upgrades.ini` (`upgdesc_*`); the hints are in `assets/config/abilities.ini` (`hint_*`).

Tuning lives in purpose-named config files under `assets/config/` (see [Config files](#config-files)): credit amounts, the economy maths and the fuel and shield prices in `economy.ini`, prices, levels, effects and descriptions in `upgrades.ini`, and nova / roll behaviour in `abilities.ini`. `--scene dockN` opens the dock after stage N, `--credits N` starts with N credits and `--fuel N` with N fuel, to try it out.

### Config files

Game data that isn't code lives in small `key=value` files (`;` starts a comment, no spaces around `=`), embedded at build time and parsed by one shared loader, `CFG_Parse$` / `CFG_Get$` in `src/sys/config.bas`:

| File | Holds |
|---|---|
| `assets/gamevalues.ini` | Text substitution tokens for `assets/gametext.txt` (names of the emperor, planets, ships). Only text tokens: `tools/bake_speech_dict` and the unused-token check read it with `gametext.txt` |
| `assets/config/economy.ini` | Credits earned per kill, boss, stage clear and asteroid event, with the economy maths; fuel and shield prices, the per-dock fuel surcharge and the next jump's fuel need |
| `assets/config/upgrades.ini` | The dock's upgrade table: names, prices per level, effect values per level, and each upgrade's description |
| `assets/config/abilities.ini` | Active ability behaviour: nova charges, radius and boss damage; roll cooldowns, length and speed; the first-purchase hints |

A new file needs an `$EMBED` line in `sss.bas` and a `CFG_Parse$` call next to the others.

**Dock background:** `assets/dock_bg.png`, a 320x240 PNG (the game's resolution; other sizes are scaled to fit), embedded at build time. Replace the file and rebuild to change it. The list sits on a see-through panel over the right two-thirds.

---

## Asset credits

| Asset | Author | License |
|---|---|---|
| Enemy ship models | Liz Reddington | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) via poly.pizza |
| Speedship model | Herminio Nieves | CC BY 3.0 via poly.pizza |
| Boss ship model ("Bob") | [@Quaternius](https://quaternius.com), Ultimate Spaceships (2021) | CC0, public domain |
| Planet imagery | [Voidweaver.space](https://voidweaver.space) | CC0, public domain |
| Title and emperor art | OpenAI / ChatGPT (modified in GIMP by theraccoonbear) | See [OpenAI usage policy](https://openai.com/policies/usage-policies) |
| CMU Pronouncing Dictionary | Carnegie Mellon University | © 1993–2015 CMU, all rights reserved |
| QB64 Phoenix Edition | QB64 Team / QB64-PE Team | MIT |

---

## License

**Source code:** GNU General Public License v3.0. See [`LICENSE`](LICENSE).
You are free to use, modify, and redistribute this code, but any derivative work must also be released under the GPL v3. This license explicitly prevents the code from being incorporated into proprietary closed-source products.

**Original assets** (art, writing, and audio not listed above): [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Share-alike: derivatives must use the same license.

**Third-party assets** retain their own licenses as noted in the table above.
