# Testing

```bash
# full suite, in parallel -- the same script CI runs on Linux, macOS, and Windows
tools/test                  # native (uses the qb64pe on your PATH)
tools/dev test              # in the container
QB64_TEST_JOBS=4 tools/test # pick the worker count (default: half your logical CPUs, at least 2)

# one test on its own (native; in the container wrap it, e.g.
#   tools/dev shell bash -c "tools/buildqb tests/spore_test.bas && builds/spore_test")
tools/buildqb tests/spore_test.bas && builds/spore_test
tools/http_queue_test   # builds http_queue_test.bas, starts a local mock HTTP server, runs it
bash tests/tools_dev_test.sh  # checks the container commands `tools/dev run` and `record` build (display, GPU, controllers; options, DB_URL refusal) and its tab completion
```

The runner builds and runs each test in `tests/` on one of several workers, then prints every test's output in order and a summary with build and run times. On Linux and macOS each worker compiles with its own copy of QB64-PE. Two compiles on one install can silently swap their output binaries, so never run two native builds at once on the same QB64-PE (#239). Each test prints `=== <name> ===` first, and the runner fails any binary that doesn't print its own banner. To add a test, put its name in `TESTS` in `.github/scripts/qb64test.sh`.

**A new controller:** record it once, commit the file, and it's tested. `tools/padrecord.bas` opens a small window that asks you to hold each control in turn (stick and d-pad directions, A, B, X, Y, Start, Back, and nothing at all) and press ENTER, then writes the pad's raw buttons and axes to `tests/input/pads/<name>.txt`. Build it and run it from the repo root with the pad plugged in: `tools/buildqb tools/padrecord.bas && builds/padrecord <name>`. `tests/pad_map_test` loads every file there and checks each control reaches the right game action, so a control the mapping drops fails CI by pad and control name (e.g. `xbox360_xpad: DPAD_UP produced nothing`).

**Full playthrough** (`tests/playthrough/`, #100): one scripted, seeded run (`--god --nerf --seed 1 --frames 20000`, input `tests/playthrough/playthrough.txt`) plays the whole game the way a fresh install sees it, from a launch folder with no `sss_settings.ini`: data notice, callsign, lead-in cards, intro crawl, emperor card, title, all six stages (crawls, combat, the three bosses, the asteroid field, planet arrivals and cinematics), the outro and back to the title.

CI runs the playthrough as its own non-blocking job (`playthrough`), so there is normally no need to run it by hand. Run it locally only to debug a playthrough failure:

```bash
tools/dev build                                  # the run needs builds/sss
tools/dev shell tests/playthrough/run.sh         # about 2.5 minutes; extra args go to sss, e.g. --screenshot-at 3000,9000
```

The game writes a milestone log when the `SSS_MILESTONE_LOG` env var names a file (off otherwise): one line per frame on which the game state or the sequence step changed (`<frame> <state> <seqIdx> <label> <TASK> <args>`), plus `<frame> NARR <label> <paragraph>` when a crawl paragraph starts speaking and `<frame> EXIT` when `--frames` ends the run (`run.sh` skips the NARR lines). `run.sh` checks that the game exited cleanly at `--frames`, that the log matches `tests/playthrough/expected.txt` in order with nothing missing or extra (so it reaches the final title inside the frame budget), and that the local telemetry CSV has one `boss_defeated` per boss and a winning `session_end`. A failure names the milestone where the run went wrong or stalled; the log, the game's output and the CSV stay in `builds/playthrough/` (CI uploads them as the `playthrough-logs` artifact). The binary must be built with an empty `assets/.env`, because the run OKs the data notice and would otherwise send its telemetry and leaderboard score. CI runs it on Linux as its own step. When the game flow changes on purpose (a stage added or reordered), update `expected.txt`, and `playthrough.txt` and `FRAMES` in `run.sh` if the run gets longer.

`tests/playthrough/determinism.sh` runs the playthrough twice, flat out and with `--realtime` (60 fps), and checks that the two milestone logs (NARR lines included) and the telemetry CSVs (without time, session and player_id) are identical (#329). The 60 fps run takes about five minutes, so the Determinism workflow runs it nightly, on demand, and on PRs touching audio, the crawl, the input script or `sss.bas`, building once and running the two playthroughs in parallel jobs before a compare job (`determinism.sh run <mode> <outdir>` and `determinism.sh compare <dirA> <dirB>`, #341); it doesn't gate merging.

**Tutorial run (#240).** `tests/tutorial/run.sh` plays the real tutorial through `sss --scene tutorial` (so through `GAME_StartTutorial%`) with `tests/tutorial/tutorial.txt`, a pilot that never presses a skip key, flies, holds fire and toggles camera mode, so every WAIT in `assets/tutorial.txt` is met by doing what it asks. It checks the milestone log (the tutorial block, each of the five lessons, the end of the script, the title), that the script finishes by `DONE_FRAME_MAX`, and that nothing was recorded; a script that stalls names the step it stopped at. `run.sh waiver` plays `tests/tutorial/waiver.txt`: a tap of the skip key skips a line, N skips a lesson, holding the key 2 seconds files the waiver. `run.sh gated` plays `tests/tutorial/gated.txt` with `--gate-tutorial`, which keeps the first-play gate on under a script: the title's start runs the tutorial on the fresh launch folder, and its end flows into a normal New Game (stage 1's crawl and PLAY, one `session_start` in the telemetry CSV). Run it in the container (`tools/dev shell tests/tutorial/run.sh`); CI runs all three in the playthrough job. When the tutorial gets longer on purpose, raise `DONE_FRAME_MAX` and the `#! frames` of `tutorial.txt`, and say so in the PR. The runner and the script are unit-tested in `tests/tutorial_script_test.bas`, the first-play gate in `tests/tutorial_gate_test.bas`, the run's isolation in `tests/tutorial_run_test.bas`.

Each subsystem doc listed in the [README's Documentation table](../README.md#documentation) has its own "Testing in isolation" section with more detail.

## Render tests

Golden-screenshot tests catch rendering regressions (blend state, font alpha, overlays) that the headless tests can't see. Each scene in `tests/render/scenes/` is a short seeded [scripted playtest](cli.md): an input script whose `#!` lines give its seed and `sss` options (read by the game itself, see the input-script header above), the frames to screenshot, and any rectangles to leave out of the comparison. The runner plays each one under Xvfb and compares every screenshot with `tests/render/golden/<scene>-<frame>.png` using `tools/imgdiff.bas`, a small QB64 compare tool. The font compositing rules themselves (glyph holes stay transparent, font calls leave blending on, partial opacity, rich colour codes) are pixel-checked off-screen by `tests/font_render_test.bas` in the regular suite, on every OS.

| Scene | Shows |
|---|---|
| `title` | title screen (the version string is masked: it changes every commit), then the ESC command console (ABOUT, CONTROLS, SETTINGS, LEADERBOARD, TUTORIAL, QUIT GAME) |
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
