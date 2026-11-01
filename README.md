# Super Spaceguy Shooter

> A political allegory wrapped in a love letter to 90s gaming, written entirely in QB64-PE (QBasic)

[![Build Linux](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=Linux)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)
[![Build macOS](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=macOS)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)
[![Build Windows](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=Windows)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)

Built with [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe).

---

## What it is

Super Spaceguy Shooter is a cinematic space shooter with a full narrative arc: intro crawl, cutscenes, six combat/asteroid stages (three with boss fights), and an outro sequence. The player flies a ship on a forward rail with free Y/Z movement; velocity-driven bank and pitch sell the illusion of full 3D maneuvering. Enemy waves are shot down while a story unfolds around them.

It runs natively on Linux, macOS, and Windows as a single compiled binary with no runtime dependencies. Network telemetry and leaderboards are optional and off by default unless configured; see [Telemetry and leaderboards](server/README.md).

## Current state

- Full intro-to-credits scene sequence: crawl → cutscene → title → six stages → outro, driven by a data-defined [scene sequencer](src/sys/README-sequence.md)
- Combat with projectiles, collision, hit effects, and wave-based enemy spawning, plus three boss fights
- Parallax starfield backdrop, with true 3D-modeled ships, asteroids, and pickups (planets are 2D sprites)
- Fully procedural audio: music, sound effects, and synthesized speech, with no audio files
- Persistent settings (music/SFX/speech/narration volumes, fullscreen, telemetry consent, player callsign, key and gamepad bindings)
- Optional anonymous gameplay telemetry and an online leaderboard (opt-in, disabled unless a backend is configured)
- Cross-platform CI/CD building, testing, and releasing on all three platforms

## Download and run

Each [release](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/releases) has three binaries: `sss-linux`, `sss-macos` and `sss-windows.exe`. Download the one for your system. On Linux and macOS make it executable first:

```bash
chmod +x sss-linux    # or sss-macos
./sss-linux
```

- **Linux:** glibc 2.34 or newer (Ubuntu 22.04, Debian 12, RHEL/Rocky/Alma 9, Fedora 35+), plus OpenGL, X11 and libcurl.
- **macOS:** macOS 12 (Monterey) or newer on Apple Silicon. macOS quarantines downloads: run `xattr -d com.apple.quarantine sss-macos`, or right-click the file in Finder, choose **Open**, and confirm.
- **Windows:** Windows 10 or newer (64-bit).

The full requirements and the library install commands are in [docs/install.md](docs/install.md). Settings are saved in a per-user folder (`~/.config/sss` on Linux, `%APPDATA%\sss` on Windows, `~/Library/Application Support/sss` on macOS).

## Controls

Open the pause dialog (ESC / Start) and press **C**, or pick CONTROLS in the title screen's command console, to see every binding in game. The essentials:

| Key | Gamepad | Action |
|---|---|---|
| Arrow keys / WASD | Left stick | Move ship |
| Space (hold) | A or B | Fire |
| ESC | Start | Pause; ESC on the title opens the command console |
| E / Q | X / Y | Evasive roll / nova pulse, once bought at the dock |
| F11 | none | Toggle fullscreen |

Every key and button, remapping and the dock controls are in [docs/controls.md](docs/controls.md).

## Building from source

You need [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe) on your `PATH` as `qb64pe`, [Node.js](https://nodejs.org/) with `npm`, and network access on the first build (`npm install` fetches [exprforge](https://www.npmjs.com/package/exprforge)).

```bash
# from the repo root
tools/buildqb sss.bas

# smoke test
builds/sss --version
```

The binary lands in `builds/sss` (`builds/sss.exe` on Windows). If you'd rather not install QB64-PE, `tools/dev build` does the same build in a Podman or Docker container. See [docs/building.md](docs/building.md) for what the script does and release builds, and [docs/container.md](docs/container.md) for the container workflow.

## Documentation

| Topic | Where |
|---|---|
| Install requirements for each OS | [docs/install.md](docs/install.md) |
| Build details and release builds | [docs/building.md](docs/building.md) |
| Container workflow (`tools/dev`), tab completion, recording video | [docs/container.md](docs/container.md) |
| Command-line options, scenes, scripted playtests | [docs/cli.md](docs/cli.md) |
| Running and writing tests, render goldens, playthrough | [docs/testing.md](docs/testing.md) |
| Controls, remapping, menus | [docs/controls.md](docs/controls.md) |
| Credits, upgrades, fuel and shields | [docs/upgrades-and-economy.md](docs/upgrades-and-economy.md) |
| Config files in `assets/config/` | [docs/config-files.md](docs/config-files.md) |
| How the engine works (overview) | [docs/internals.md](docs/internals.md) |
| Flight path math (ExprForge) | [docs/flight-path-math.md](docs/flight-path-math.md) |
| Telemetry, leaderboard and deploying the backend | [server/README.md](server/README.md) |
| 3D engine | [src/engine3d.md](src/engine3d.md) |
| Scene sequencer | [src/sys/README-sequence.md](src/sys/README-sequence.md) |
| Speech synthesizer | [src/sys/README-speech.md](src/sys/README-speech.md) |
| HTTP client | [src/sys/README-http.md](src/sys/README-http.md) |
| Telemetry events | [src/sys/README-telemetry.md](src/sys/README-telemetry.md) |
| Codebase map, vocabulary and invariants | [CONTEXT.md](CONTEXT.md) |
| Design notes and decisions | [docs/DESIGN.md](docs/DESIGN.md), [docs/adr/](docs/adr/) |
| Contributor practices | [CLAUDE.md](CLAUDE.md) |

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
