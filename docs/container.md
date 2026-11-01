# Building and running in a container

If you'd rather not install QB64-PE natively, `tools/dev` runs everything inside an Ubuntu 24.04 container that mirrors CI's Linux job: the same apt packages, QB64-PE `v4.5.0` (pinned to match `QB64PE_VERSION` in `.github/workflows/build.yml`; bump `QB64PE_VERSION`/`QB64PE_ASSET` in `tools/container/Containerfile` together with it), and Node 22 for ExprForge. You only need Podman or Docker. The script uses Podman if it finds it, otherwise Docker; set `SSS_ENGINE=docker` to override.

```bash
tools/dev image   # build the image (done automatically on first use)
tools/dev build   # tools/buildqb sss.bas + the --version smoke test
tools/dev test    # full test suite (.github/scripts/qb64test.sh, same as CI)
tools/dev bake    # tools/bake_speech_dict
tools/dev emit    # regenerate spline math (npm install in math/ + node tools/emit-spline.js)
tools/dev shell   # interactive shell in the container; `tools/dev shell <cmd>` runs one command
tools/dev run     # play the game in the container on your display; args pass through to sss
tools/dev headless  # run the game on an off-screen display (Xvfb), e.g. for scripted playtests (see [Scripted playtests](cli.md))
tools/dev record  # record the scripted playthrough, with sound, to builds/playthrough.mp4 ([Recording a video](#recording-a-video))
tools/dev completion  # print the bash tab-completion function (see Tab completion below)
```

Typical workflow:

```bash
git pull
tools/dev run --scene boss3 --god   # rebuilds first if any source changed, then plays
tools/dev test                      # full suite before you commit (pre-commit checklist in CLAUDE.md)
```

`run` takes any [CLI option](cli.md). Handy ones: `--scene boss3` / `boss5` / `boss6` jumps to a boss fight (`bossN` is the boss on level N; levels 3, 5 and 6 have one), `--scene playing4` starts a level, `--scene dock2 --credits 2000` opens the upgrade dock after stage 2 (docks follow stages 1-5) with 2000 credits to spend, `--god` stops you dying, `--nerf` gives short stages and weak bosses, `--debug` shows the debug HUD.

The repo is bind-mounted at its host path, not copied, so `builds/` and every generated file land in your checkout. They are owned by you, not root: Podman runs with `--userns=keep-id`, rootful Docker with `--user $(id -u):$(id -g)`, and rootless Docker needs neither. The mounts use `:Z`, so this works under SELinux (Fedora, Bazzite). Git worktrees work too, because the main checkout's git directory is mounted alongside.

**Tab completion.** `tools/dev completion` prints a bash completion function. To turn it on, add this line to `~/.bashrc` (use your checkout's path for `<checkout>`):

```bash
source <(<checkout>/tools/dev completion)
```

Then Tab completes the command (`tools/dev bu` gives `build`, `tools/dev re` offers `record` and `render`) and each command's options: `build --release`, `record`'s own options plus the game flags it passes on, the game flags for `run` and `headless`, and `render`'s options, groups and scene names. After `--scene` it offers the scene names from `builds/sss --help`, which prints and exits before the game opens a window (without a `builds/sss`, or with a release build, it offers the scene types). `--input-script`, `--leaderboard-file`, `--out` and `--script` complete file names. It is registered for `./tools/dev`, `tools/dev` and that checkout's absolute path. In zsh, run `autoload -U +X bashcompinit && bashcompinit` before the `source` line.

`tools/dev` itself only picks the engine, mounts and image. Anything that runs inside the container and is more than one command line is a script in `tools/container/in/`, called by path through the mount: `build.sh` (build plus the `--version` smoke test, or `--release` plus `tests/release_build_test.sh`), `headless.sh`, `record.sh`, `emit.sh` and `libs-ok.sh` (can the container load `builds/sss`?). Each one starts with a usage comment and can be run on its own in `tools/dev shell`, e.g. `tools/dev shell tools/container/in/headless.sh --scene title --frames 60`.

`tools/dev run` and `tools/dev headless` rebuild `builds/sss` if it is missing, older than any file in `sss.bas`, `src/`, `assets/` or `VERSION` (so a `git pull` or a branch switch never plays a stale build), or was built natively on a host with a newer glibc than the container, then runs it with your desktop passed through: the X11 socket and `DISPLAY`/`XAUTHORITY` (XWayland on Wayland desktops), the PulseAudio/PipeWire socket from `$XDG_RUNTIME_DIR`, `/dev/dri` for GPU rendering, and `/dev/input` so the game sees your controllers (bind-mounted, so a pad plugged in after launch works too). For that container only, SELinux labeling is turned off (`--security-opt label=disable`) so it can share the sockets, and `--ipc=host` lets X11 shared memory work. If no audio socket is found it warns and runs silently. Every other command stays headless. You can also run a container-built `builds/sss` directly on the host if it has the GL/X11/ALSA runtime libraries.

## Recording a video

`tools/dev record` makes an MP4, picture and sound, of a scripted run. With no options it records the [full playthrough](testing.md) (`--god --nerf --seed 1 --frames 20000`, input `tests/playthrough/playthrough.txt`) to `builds/playthrough.mp4`, which takes about 6 minutes (the run plays at normal speed). Nothing appears on your desktop or comes out of your speakers: inside the container the game runs on its own Xvfb display at 320x240, its sound goes to a PulseAudio server whose only output is a null sink, and `ffmpeg` records the display (`x11grab`, 60 fps) and that sink's monitor into H.264/AAC. The game starts from a fresh, empty launch folder, as the playthrough test does, so your saved settings and callsign don't change what the script does, and the same seed gives the same run.

```bash
tools/dev record                                   # the playthrough -> builds/playthrough.mp4
tools/dev record --out ~/Videos/boss3.mp4 --script tests/input/boss-hold-left.txt --frames 1500 --scene boss3 --god
```

| Option | Default | |
|---|---|---|
| `--out FILE` | `builds/playthrough.mp4` | where the MP4 goes (relative to where you run it) |
| `--script FILE` | `tests/playthrough/playthrough.txt` | the input script; it must be inside the repo |
| `--frames N` | `20000` | stop after N frames |
| `--seed N` | `1` | random seed |
| `--scale N` | `2` | whole-number upscale, nearest-neighbour (2 gives 640x480) |
| `--timeout S` | frames / 60 + 120 | wall-clock limit; a hung game is stopped and the command fails |
| `--rebuild` | | rebuild `builds/record/sss` even if it is up to date |

Any other arguments (or everything after `--`) go to `sss` in place of the default `--god --nerf`. The recording stops when the game exits at `--frames`. `record` adds `--realtime`, a dev-only flag that keeps the 60 fps throttle a scripted run otherwise skips, so the video plays at normal speed and the sound lines up with it.

`record` never sends telemetry or posts a score, even when your `assets/.env` has real credentials. The playthrough script OKs the data notice, so `record` plays its own binary, `builds/record/sss`. It builds that binary in the container with an empty file mounted over `assets/.env`, so the credentials never get embedded. Before every recording it checks that the binary contains no `DB_URL`/`DB_KEY` value and no copy of your `DB_URL`, and it deletes the binary and stops if it finds one. Your `assets/.env` and `builds/sss` are never touched. The record binary is reused while it is newer than every source file; `--rebuild` forces a fresh build. It needs `ffmpeg` and PulseAudio in the dev image, so an image built before `record` existed needs a `tools/dev image` first (it tells you).
