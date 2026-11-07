# Building and running in a container

If you'd rather not install QB64-PE natively, `tools/dev` runs everything inside an Ubuntu 24.04 container that mirrors CI's Linux job: the same apt packages, QB64-PE `v4.5.0` (pinned to match `QB64PE_VERSION` in `.github/workflows/build.yml`; bump `QB64PE_VERSION`/`QB64PE_ASSET` in `tools/container/Containerfile` together with it). You only need Podman or Docker. The script uses Podman if it finds it, otherwise Docker; set `SSS_ENGINE=docker` to override.

```bash
tools/dev image   # build the image (done automatically on first use)
tools/dev build   # tools/buildqb sss.bas + the --version smoke test
tools/dev test    # full test suite (.github/scripts/qb64test.sh, same as CI)
tools/dev bake    # tools/bake_speech_dict
tools/dev shell   # interactive shell in the container; `tools/dev shell <cmd>` runs one command
tools/dev run     # play the game in the container on your display; args pass through to sss
tools/dev headless  # run the game on an off-screen display (Xvfb), e.g. for scripted playtests (see [Scripted playtests](cli.md))
tools/dev viewer    # build and open viewer.bas (the model viewer) on your display; `viewer --sheets <outdir>` renders the enemy review PNGs headless
tools/dev bench   # frame-time bench: per-phase simulation and render times of a fixed busy run ([Frame-time bench](testing.md#frame-time-bench))
tools/dev record  # record the scripted playthrough, with sound, to builds/playthrough.mp4 ([Recording a video](#recording-a-video))
tools/dev completion  # print the bash tab-completion function (see Tab completion below)
```

Typical workflow:

```bash
git pull
tools/dev run --scene boss3 --god   # rebuilds first if any input changed (content hash), then plays
tools/dev test                      # full suite before the PR leaves draft (checklist in CLAUDE.md)
```

`run` takes any [CLI option](cli.md). Handy ones: `--scene boss3` / `boss5` / `boss6` jumps to a boss fight (`bossN` is the boss on level N; levels 3, 5 and 6 have one), `--scene playing4` starts a level, `--scene dock2 --credits 2000` opens the upgrade dock after stage 2 (docks follow stages 1-5) with 2000 credits to spend, `--god` stops you dying, `--nerf` gives short stages and weak bosses, `--debug` shows the debug HUD.

The repo is bind-mounted at its host path, not copied, so `builds/` and every generated file land in your checkout. They are owned by you, not root: Podman runs with `--userns=keep-id`, rootful Docker with `--user $(id -u):$(id -g)`, and rootless Docker needs neither. The mounts use `:Z`, so this works under SELinux (Fedora, Bazzite). Git worktrees work too, because the main checkout's git directory is mounted alongside. Finished agent worktrees under `.claude/worktrees/` are cleaned up with `tools/prune-worktrees` (dry run by default; `--apply` removes those whose PR is merged or closed, that are clean and not in use, and deletes their local branches).

**Tab completion.** `tools/dev completion` prints a bash completion function. To turn it on, add this line to `~/.bashrc` (use your checkout's path for `<checkout>`):

```bash
source <(<checkout>/tools/dev completion)
```

Then Tab completes the command (`tools/dev bu` gives `build`, `tools/dev re` offers `record` and `render`) and each command's options: `build --release`, `record`'s own options plus the game flags it passes on, the game flags for `run` and `headless`, and `render`'s options, groups and scene names. After `--scene` it offers the scene names from `builds/sss --help`, which prints and exits before the game opens a window (without a `builds/sss`, or with a release build, it offers the scene types). `--input-script`, `--leaderboard-file`, `--out` and `--script` complete file names. It is registered for `./tools/dev`, `tools/dev` and that checkout's absolute path. In zsh, run `autoload -U +X bashcompinit && bashcompinit` before the `source` line.

`tools/dev` itself only picks the engine, mounts and image. Anything that runs inside the container and is more than one command line is a script in `tools/container/in/`, called by path through the mount: `build.sh` (build plus the `--version` smoke test, or `--release` plus `tests/release_build_test.sh`), `current.sh` (is `builds/sss` current and loadable?), `headless.sh`, `record.sh` and `libs-ok.sh` (can the container load `builds/sss`?). Each one starts with a usage comment and can be run on its own in `tools/dev shell`, e.g. `tools/dev shell tools/container/in/headless.sh --scene title --frames 60`.

`tools/dev run` and `tools/dev headless` rebuild `builds/sss` if `tools/buildqb --check sss.bas` finds it stale: missing, or an included file, embedded asset, `VERSION` or the git state changed by content, not timestamp (so a `git pull` or a branch switch never plays a stale build, and a `touch` never forces a rebuild; see [Building](building.md)), or was built natively on a host with a newer glibc than the container, then runs it with your desktop passed through: the X11 socket and `DISPLAY`/`XAUTHORITY` (XWayland on Wayland desktops), the PulseAudio/PipeWire socket from `$XDG_RUNTIME_DIR`, `/dev/dri` for GPU rendering, and `/dev/input` so the game sees your controllers (bind-mounted, so a pad plugged in after launch works too). For that container only, SELinux labeling is turned off (`--security-opt label=disable`) so it can share the sockets, and `--ipc=host` lets X11 shared memory work. If no audio socket is found it warns and runs silently. Every other command stays headless. You can also run a container-built `builds/sss` directly on the host if it has the GL/X11/ALSA runtime libraries.

## Limits, queueing and runaway protection

Every container `tools/dev` starts is bounded, and the heavy commands queue, so a runaway program or several agents building at once cannot take the machine down (#427).

| Variable | Default | What it does |
|---|---|---|
| `SSS_DEV_MEMORY` | `4g` | RAM limit; the memory+swap limit is set to the same value, so a container never swaps |
| `SSS_DEV_CPUS` | `3` | CPUs the container may use (`--cpus`) |
| `SSS_DEV_PIDS` | `512` | process limit (`--pids-limit`) |
| `SSS_DEV_JOBS` | `3` | parallel test workers for `tools/dev test` (passed as `QB64_TEST_JOBS`); CI uses every vCPU |
| `SSS_DEV_TIMEOUT` | `3600` | wall-clock seconds for `build`, `test`, `render` and `bench`; the run is stopped and its container removed (exit 124). `run` has none; `headless`, `shell`, `record` and `bake` have none with a terminal (see the next row without one) |
| `SSS_DEV_NOTTY_TIMEOUT` | `600` | wall-clock seconds for every other container run (not `run` or the viewer window) when stdin or stdout is not a terminal; 0 turns it off. Also passed to podman as `--timeout`, so the engine stops the container even if the client is killed or a pipe closes |
| `SSS_DEV_STDIN` | (unset) | without a terminal stdin is /dev/null; `keep` passes the caller's stdin through |
| `SSS_DEV_SLOTS` | `2` | how many `build`, `test`, `render` and `bench` runs go at once; the rest wait |
| `SSS_DEV_SLOT_WAIT` | wait | give up (exit 1) after this many seconds without a free slot |
| `SSS_DEV_LOCKDIR` | `<git dir>/sss-dev-slots` | where the slot lock files live; all worktrees of one clone share the main `.git`, so their runs queue together |

Setting a limit to `0` or `none` turns it off. The container log is off (`--log-driver none`); output still reaches your terminal. A queued run prints `>>> waiting for a build slot` and `>>> got build slot N after Ns` when it starts. The slot is an `flock`, so it is released when the script ends, however it ends. Without `flock` (macOS) there is no queueing.

How the defaults were chosen, measured in the container with its cgroup counters (8 logical CPUs, 15 GiB host):

| Run | Wall time | Peak memory | Peak processes | CPU time |
|---|---|---|---|---|
| `tools/dev build` (`tools/buildqb sss.bas` + smoke test) | 164 s | 1.9 GiB | 18 | 288 s (about 1.8 CPUs busy) |
| `tools/dev test`, 3 workers (48 tests, 6 tools, HTTP test) | 282 s | 1.9 GiB | 53 | 899 s (about 3.2 CPUs busy) |

The peak is mostly page cache of the QB64-PE copies and the compiled objects, which the kernel reclaims under a limit, so 4 GiB is about twice what a run holds. Three workers keep about three cores busy; with two slots at most six of eight logical CPUs are in use and the desktop keeps the rest. Raise `SSS_DEV_JOBS` together with `SSS_DEV_MEMORY` and `SSS_DEV_CPUS` on a bigger machine. The process limit is about ten times the measured peak.

**Runtime errors end the run.** QB64-PE shows an unhandled runtime error as a dialog, or with no display as `Continue? y/n` on stdin, and at end of input it asks again forever. Every program the suite builds includes `src/sys/failfast.bi`, which exits 1 with `Runtime error N: message (line L)` instead (see [Testing](testing.md)). `tools/dev test` runs `tests/failfast_test.sh` first, and the test runner closes stdin and applies a per-test time limit as well.

### On the host (optional, not automated)

`tools/dev` limits what it starts. These host settings protect the rest of the machine, and none of them is applied by the repo:

- **A cgroup around heavy work.** Run `tools/dev` under a user scope so the kernel throttles and kills the whole group before the desktop stalls: `systemd-run --user --scope -p MemoryHigh=8G -p MemoryMax=10G -p CPUQuota=600% tools/dev test`.
- **systemd-oomd.** Check `systemctl status systemd-oomd`, and that `ManagedOOMMemoryPressure=kill` is set on the user slice (`systemctl --user show -p ManagedOOMMemoryPressure app.slice`), so memory pressure kills a runaway group instead of freezing the desktop. zram swap can hide the pressure until it is too late.
- **Evidence for the next freeze.** Install sysstat (`sar`) or log pressure-stall information (`/proc/pressure/{cpu,memory,io}`, for example from a one-line timer writing them to a file every few seconds). The journal alone did not show what led up to the last freeze.
- **Keep the indexer out.** Exclude the checkout and `builds/` from baloo (`balooctl6 config add excludeFolders <path>`, or System Settings, Search) so compiled objects and test output are not indexed as they are written.

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
