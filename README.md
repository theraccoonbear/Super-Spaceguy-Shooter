# Super Spaceguy Shooter

> A political allegory wrapped in a love letter to 90s gaming — written entirely in QB64-PE (QBasic)

[![Build Linux](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=Linux)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)
[![Build macOS](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=macOS)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)
[![Build Windows](https://img.shields.io/github/actions/workflow/status/theraccoonbear/Super-Spaceguy-Shooter/build.yml?branch=master&label=Windows)](https://github.com/theraccoonbear/Super-Spaceguy-Shooter/actions/workflows/build.yml)

Built with [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe).

---

## What it is

Super Spaceguy Shooter is a cinematic space shooter with a full narrative arc: intro crawl, cutscenes, six combat stages, and an outro sequence. The player flies a ship on a forward rail with free Y/Z movement; velocity-driven bank and pitch sell the illusion of full 3D maneuvering. Enemy waves are shot down while a story unfolds around them.

It runs natively on Linux, macOS, and Windows as a single compiled binary with no runtime dependencies.

## Current state

- Full intro-to-credits scene sequence: crawl → cutscene → title → six stages → outro
- Combat with projectiles, collision, hit effects, and wave-based enemy spawning
- Dynamic starfield and 3D environment rendering
- Fully procedural audio: music, sound effects, and synthesized speech — no audio files
- Persistent settings (music/SFX/speech/narration volumes)
- Cross-platform CI/CD building and releasing on all three platforms

## Building

You need [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe) installed.

```bash
# recommended — bakes the speech phoneme dict then compiles
# run from the repo root
tools/buildqb sss.bas

# or directly, from the QB64-PE install directory
./qb64pe -x /path/to/repo/sss.bas -o /path/to/repo/builds/sss
```

Pre-built binaries for Linux, macOS, and Windows are produced by CI on every merge to `master` and attached to tagged releases.

---

## Under the hood

This is a from-scratch game engine written in QBasic. No game framework, no graphics library, no audio library. Everything described below is implemented in pure BASIC.

### Software 3D rendering pipeline

The renderer lives across `mesh.bas`, `poly.bas`, `matrix.bas`, `obj.bas`, and `camera.bas`. It loads Wavefront OBJ models at startup, applies 4×4 matrix transforms (translation, rotation, scale) for each object each frame, projects vertices through a perspective camera, and rasterizes filled polygons directly to an offscreen buffer. Backface culling and a basic depth sort keep overdraw reasonable. There is no GPU involvement — every pixel is computed by the CPU.

### Procedural sound synthesis and software mixer

`snd.bas` and `wave.bas` implement a real-time software audio mixer. Sound effects — laser shots, explosions, impacts, pickups — are synthesized mathematically at startup into sample buffers (sine waves, filtered noise, frequency sweeps) and mixed at the sample level into a single output stream each frame. No WAV files, no audio assets.

### Pseudo-MIDI music system

`music.bas` implements a pattern-based music engine. Instruments are synthesized from first principles (oscillators, envelopes, filters). Patterns of notes are arranged into cues that the game triggers by name — `"intro"`, `"stage1"`, `"outro"` — and the engine crossfades or cuts between them as the scene changes. It behaves like a MIDI sequencer but with no MIDI library, no sound font, and no external files.

### Digital voice synthesizer

`speech.bas` implements a phoneme-based text-to-speech system. Input text is converted to a phoneme sequence, and each phoneme is synthesized using formant synthesis — multiple sine oscillators tuned to the resonant frequencies of the human vocal tract. Coarticulation smooths transitions between phonemes so speech doesn't sound like disconnected clicks. The game uses this for in-flight callouts and narration.

### Scene sequencer

`sequence.bas` drives the full game flow as a linear sequence of named waypoints: crawl scenes, cutscene screens, the title/menu, combat stages, and the outro. Each scene registers itself with `SEQ_Add` and `SEQ_Advance` steps through them. The title screen is a waypoint in the sequence rather than a mode the game escapes to — so the game boots directly into the story, and "New Game" from the title steps forward into the next stage rather than restarting from scratch.

### Architecture

The codebase is split across ~30 `$INCLUDE` modules, each owning a vertical slice:

| Module | Responsibility |
|---|---|
| `sss.bas` | Main loop, game state machine |
| `mesh.bas` / `obj.bas` | 3D model loading and storage |
| `matrix.bas` / `poly.bas` | Matrix math and polygon rasterization |
| `camera.bas` | Perspective projection |
| `scene.bas` / `stage.bas` | Level layout and wave management |
| `behavior.bas` | Enemy AI and object behaviors |
| `collision.bas` | AABB collision detection |
| `effects.bas` | Particle and visual effects |
| `starfield.bas` | Parallax star background |
| `hud.bas` | In-game heads-up display |
| `snd.bas` / `wave.bas` | Sound synthesis and mixing |
| `music.bas` | Music sequencer and synthesis |
| `speech.bas` | Phoneme voice synthesizer |
| `font.bas` | Bitmap font renderer with color palettes |
| `ui.bas` | Sci-fi panel UI components |
| `crawl.bas` | Scrolling narrative text crawl |
| `sequence.bas` | Scene sequencer |
| `settings.bas` | Persistent INI-file settings |
| `input.bas` | Keyboard input with edge detection |

---

## Controls

| Key | Action |
|---|---|
| Arrow keys / WASD | Move ship |
| Space | Fire |
| ESC | Pause / options menu |
| `` ` `` | Toggle spoken-word overlay during crawl |
| Space (crawl) | Fast-forward narrative |

---

## Asset credits

| Asset | Author | License |
|---|---|---|
| Enemy ship models | Liz Reddington | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) via poly.pizza |
| Speedship model | Herminio Nieves | CC BY 3.0 via poly.pizza |
| Boss ship model ("Bob") | [@Quaternius](https://quaternius.com) — Ultimate Spaceships (2021) | CC0 — public domain |
| Planet imagery | [Voidweaver.space](https://voidweaver.space) | CC0 — public domain |
| Title and emperor art | OpenAI / ChatGPT (modified in GIMP by theraccoonbear) | See [OpenAI usage policy](https://openai.com/policies/usage-policies) |
| CMU Pronouncing Dictionary | Carnegie Mellon University | © 1993–2015 CMU, all rights reserved |
| QB64 Phoenix Edition | QB64 Team / QB64-PE Team | MIT |

---

## License

**Source code:** GNU General Public License v3.0 — see [`LICENSE`](LICENSE).
You are free to use, modify, and redistribute this code, but any derivative work must also be released under the GPL v3. This license explicitly prevents the code from being incorporated into proprietary closed-source products.

**Original assets** (art, writing, and audio not listed above): [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Share-alike — derivatives must use the same license.

**Third-party assets** retain their own licenses as noted in the table above.
test
