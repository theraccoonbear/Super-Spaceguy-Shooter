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
- Persistent settings (music/SFX/speech/narration volumes, telemetry consent, player callsign)
- Optional anonymous gameplay telemetry and an online leaderboard (opt-in, disabled unless a backend is configured)
- Cross-platform CI/CD building, testing, and releasing on all three platforms

## Building

You need [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe) installed and on your `PATH` as `qb64pe`.

```bash
# recommended -- run from the repo root
tools/buildqb sss.bas
```

This bakes the speech phoneme dictionary, regenerates `src/sys/version.bas` from the `VERSION` file and the current git commit, links QB64-PE's asset directory to this repo's `assets/` (so `$EMBED:'assets/...'` resolves), and compiles. The binary lands in `builds/sss` (`builds/sss.exe` on Windows).

```bash
# smoke test
builds/sss --version
```

Pre-built binaries for Linux, macOS, and Windows are produced by CI on every merge to `master` and attached to tagged releases.

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

`run` takes any [CLI option](#cli-options). Handy ones: `--scene boss3` / `boss5` / `boss6` jumps to a boss fight (`bossN` is the boss on level N; levels 3, 5 and 6 have one), `--scene playing4` starts a level, `--god` stops you dying, `--nerf` gives short stages and weak bosses, `--debug` shows the debug HUD.

The repo is bind-mounted at its host path, not copied, so `builds/` and every generated file land in your checkout. They are owned by you, not root: Podman runs with `--userns=keep-id`, rootful Docker with `--user $(id -u):$(id -g)`, and rootless Docker needs neither. The mounts use `:Z`, so this works under SELinux (Fedora, Bazzite). Git worktrees work too, because the main checkout's git directory is mounted alongside.

`tools/dev run` and `tools/dev headless` rebuild `builds/sss` if it is missing, older than any file in `sss.bas`, `src/`, `assets/` or `VERSION` (so a `git pull` or a branch switch never plays a stale build), or was built natively on a host with a newer glibc than the container, then runs it with your desktop passed through: the X11 socket and `DISPLAY`/`XAUTHORITY` (XWayland on Wayland desktops), the PulseAudio/PipeWire socket from `$XDG_RUNTIME_DIR`, and `/dev/dri` for GPU rendering. For that container only, SELinux labeling is turned off (`--security-opt label=disable`) so it can share the sockets, and `--ipc=host` lets X11 shared memory work. If no audio socket is found it warns and runs silently. Every other command stays headless. You can also run a container-built `builds/sss` directly on the host if it has the GL/X11/ALSA runtime libraries.

### CLI options

```
sss [options]

  -v, --version          Print version and exit
  -h, --help             Show this help and exit
  --scene <name>         Jump to a named scene, skipping normal startup (see src/sys/README-sequence.md)
  --crawls               Crawl browser: list every named crawl with its scroll speed, play any of them
  --god                  God mode: shields, health, and laser never deplete
  --nerf                 Nerf mode: shorter stages, weaker bosses (for testing/streaming)
  --debug                Enable the debug HUD overlay and diagnostic console output
  --no-telem             Disable gameplay telemetry for this session (on by default; see below)
  --input-script <file>  Play from a script instead of the keyboard/gamepad (see below)
  --frames N             Quit after N frames (60 per second)
  --seed N               Fixed random seed, so a scripted run repeats exactly
  --screenshot-at N,N    Save frames N,... as shot-N.png in the launch folder
```

**Crawls:** `--scene crawl:<key>` jumps to any named crawl. That covers every `CRAWL` task in `assets/sequence.txt` plus crawls the code starts directly (today, `death_final` on game over). `sss --help` prints the full list. A sequence crawl carries on from its place in the sequence; `crawl:death_final` plays and then goes to the title. `crawlN` still works for the sequence crawls. `sss --crawls` opens a browser of the same list: ↑/↓ select, ENTER plays and returns to the list, ←/→ picks the narration setting for the session (your saved setting isn't changed), ESC quits.

**Scripted playtests:** `--input-script <file>` replaces the keyboard and gamepad with a per-frame script. Each line is `<from> <to> KEY [KEY ...]`: hold those keys on frames from..to (inclusive, 60 per second). The keys are `LEFT RIGHT UP DOWN FIRE ESC TAB`, and `#` starts a comment. Scripted runs skip the 60 fps throttle and go as fast as the machine allows. Gameplay steps per frame, so the result doesn't change. With `--seed`, the same script plays the same fight every time. Example (`tests/input/boss-hold-left.txt` holds left and fires for 25 s):

```bash
tools/dev headless --scene boss3 --god --no-telem --seed 1 --frames 1500 --input-script tests/input/boss-hold-left.txt
```

Add `--screenshot-at 200,700,1250` to save those frames as `shot-<frame>.png` (gitignored) to look at afterwards. A relative script path is resolved from the directory you launch from. While the branch is being tuned, boss fights append `[boss-volley]` / `[boss-shot]` lines to `boss-shots.log` there. This is temporary, for #26.

## Testing

```bash
# full suite -- same one CI runs on Linux, macOS, and Windows
tools/dev test                                           # in the container
QB64_BIN_DIR=/path/to/qb64pe .github/scripts/qb64test.sh # native

# or individually (native; in the container wrap one line, e.g.
#   tools/dev shell bash -c "tools/buildqb tests/spore_test.bas && builds/spore_test")
tools/buildqb tests/seq_trace_test.bas         && builds/seq_trace_test
tools/buildqb tests/seq_dispatch_test.bas      && builds/seq_dispatch_test
tools/buildqb tests/scene_jump_planet_test.bas && builds/scene_jump_planet_test
tools/buildqb tests/snd_init_test.bas          && builds/snd_init_test
tools/buildqb tests/telem_creds_test.bas       && builds/telem_creds_test
tools/buildqb tests/dbg_output_test.bas        && builds/dbg_output_test
tools/buildqb tests/mnv_load_test.bas          && builds/mnv_load_test
tools/buildqb tests/mnv_transition_test.bas    && builds/mnv_transition_test
tools/buildqb tests/mnv_conformance_test.bas   && builds/mnv_conformance_test
tools/buildqb tests/spk_timing_test.bas        && builds/spk_timing_test
tools/buildqb tests/crawl_plan_test.bas        && builds/crawl_plan_test
tools/buildqb tests/crawl_step_test.bas        && builds/crawl_step_test
tools/buildqb tests/spore_test.bas             && builds/spore_test
tools/buildqb tests/attack_test.bas            && builds/attack_test
tools/buildqb tests/inputscript_test.bas       && builds/inputscript_test
tools/buildqb tests/rng_test.bas               && builds/rng_test
tools/http_queue_test   # builds http_queue_test.bas, starts a local mock HTTP server, runs it
```

Each subsystem doc below has its own "test in isolation" section with more detail.

## Telemetry and leaderboards

The game can optionally send anonymous gameplay events and score submissions to a [Supabase](https://supabase.com) backend. This is entirely off unless you configure it:

1. Create `assets/.env` (gitignored) at the repo root:
   ```
   DB_URL=https://your-project.supabase.co/rest/v1
   DB_KEY=your-supabase-anon-key
   ```
2. Leave it empty or absent to disable network telemetry entirely. The game still writes a local `sss_telemetry.csv`, and no network requests are made.
3. Players are asked for one-time consent in-game before anything is sent; `--no-telem` skips telemetry (and the consent prompt) for a single session.

See [`src/sys/README-telemetry.md`](src/sys/README-telemetry.md) for the event schema and Supabase table layout, and [`src/sys/README-http.md`](src/sys/README-http.md) for the underlying HTTP layer.

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

`src/sys/http.bas` is a small non-blocking HTTP client built on libcurl via QB64-PE's `DECLARE LIBRARY` C interop (`src/sys/curl_qb64.h`), used to POST/GET against a Supabase backend without blocking the game loop. `src/sys/telemetry.bas` logs gameplay events locally and, if configured, batches and POSTs them at session end; `src/sys/lbrd.bas` polls and parses the top-scores leaderboard. See [`src/sys/README-http.md`](src/sys/README-http.md) and [`src/sys/README-telemetry.md`](src/sys/README-telemetry.md).

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

Do not hand-edit the generated files. Run `node tools/emit-spline.js` from the repo root to regenerate both downstream targets from the DSL:

| Generated file | Language | Consumer |
|---|---|---|
| `src/gameplay/spline_path_gen.bi` | QB64-PE | Game runtime (`behavior.bas` flyover states; not used by gameplay) |
| `tools/TrailForge/src/math/spline_gen.ts` | TypeScript | TrailForge preview |

The CI pipeline regenerates both files on every build, so the generated code is always fresh. If you add or change a function in the DSL, run the emit script locally and commit the regenerated files.

Implemented algorithms: Catmull-Rom position/tangent weights, Gram-Schmidt frame, standoff offset, arc-length reparameterization, and Rodrigues parallel transport for smooth ship-body orientation.

---

## Controls

To see the controls in game, open the pause dialog (ESC) and press **C**, or press **C** in the title screen's command console.

### In flight

| Key | Gamepad | Action |
|---|---|---|
| Arrow keys / WASD | Left stick | Move ship |
| Space (hold) | A | Fire |
| ESC | Start | Pause / abort-mission dialog (Y confirms the abort, C shows controls, ESC cancels) |
| TAB | Back / Select | Camera mode on/off. The game freezes while you adjust; pressing it again locks the angle and saves it |
| ↑ / ↓ (camera mode) | Stick up/down | Tilt the camera |
| R (camera mode) | — | Reset to the default chase camera |
| ESC (planet arrival / cutscene) | Start | Return to the title |

### Title and menus

| Key | Gamepad | Action |
|---|---|---|
| P | Start | Start a new game |
| ESC | — | Open/close the command console |
| A / C / S / L / Q | — | Console: About / Controls / Settings / Leaderboard / Quit |
| ↑ ↓ ← → | — | Navigate and adjust Settings; scroll About; page through Controls |
| F11 | — | Toggle fullscreen (any screen) |

### Story screens

| Key | Gamepad | Action |
|---|---|---|
| Space (hold) | A (hold) | Fast-forward the narrative crawl |
| Space + ESC | A + Start | Skip the crawl |
| Space | A | Continue (intro card, game over) |
| Any key | — | Skip the logo cards |

Menus other than the title and Controls screens are keyboard-only.

### Debug

| Key | Action |
|---|---|
| `` ` `` | Toggle the debug HUD overlay. It starts on with `--debug`, but the key works in any build |

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
