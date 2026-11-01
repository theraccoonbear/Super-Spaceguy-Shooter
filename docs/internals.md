# Under the hood

This is a from-scratch game engine written in QBasic. No game framework, no graphics library, no audio library. Everything described below is implemented in pure BASIC.*

## Software 3D rendering pipeline

The renderer lives under `src/3d/` (`mesh.bas`, `poly.bas`, `matrix.bas`, `obj.bas`, `camera.bas`, `object.bas`, `scene.bas`, `collision.bas`). It loads a custom text-based mesh format (`assets/models.e3d`, convertible from Wavefront OBJ via `obj2e3d.bas`) at startup, applies 4×4 matrix transforms (translation, rotation, scale) for each object each frame, projects vertices through a perspective camera, and rasterizes filled polygons directly to an offscreen buffer. Backface culling and a per-face depth sort keep overdraw reasonable. There is no GPU involvement; every pixel is computed by the CPU. This true 3D pipeline is used for the things the player directly interacts with: ships, asteroids, pickups. Planets are 2D sprites and the background is a parallax starfield (`starfield.bas`), not modeled geometry. See [`src/engine3d.md`](../src/engine3d.md).

## Procedural sound synthesis and software mixer

`src/audio/snd.bas` implements a real-time software audio mixer. Sound effects like laser shots, explosions, impacts, and pickups are synthesized mathematically at startup into sample buffers (sine waves, filtered noise, frequency sweeps) and mixed at the sample level into a single output stream each frame. No WAV files, no audio assets.

## Pseudo-MIDI music system

`src/audio/music.bas` implements a pattern-based music engine. Instruments are synthesized from first principles (oscillators, envelopes, filters). Patterns of notes are arranged into cues that the game triggers by name (`"intro"`, `"game"`, `"boss"`, `"outro"`), and the engine crossfades or cuts between them as the scene changes. It behaves like a MIDI sequencer but with no MIDI library, no sound font, and no external files.

## Digital voice synthesizer

`src/audio/speech.bas` implements a phoneme-based text-to-speech system driven by a dictionary baked from the CMU Pronouncing Dictionary. Input text is converted to an ARPAbet phoneme sequence, and each phoneme is synthesized using formant synthesis: additive sine harmonics tuned to the resonant frequencies of the human vocal tract, with per-phoneme noise for fricatives and stops. Coarticulation crossfades between adjacent phoneme wavetables so speech doesn't sound like disconnected clicks. The game uses this for the narrative crawl and in-flight callouts. See [`src/sys/README-speech.md`](../src/sys/README-speech.md).

## Scene sequencer

`src/sys/sequence.bas` drives the full game flow as a linear sequence of named waypoints, covering crawl scenes, cutscene cards, the title screen, combat/boss/asteroid stages, and the outro. The sequence is defined in the plain-text `assets/sequence.txt`, not hardcoded. `SEQ_Load` parses the file once at startup; `SEQ_Advance` steps through it. The title screen is a waypoint in the sequence rather than a mode the game escapes to, so the game boots directly into the story and "New Game" from the title steps forward into the next stage rather than restarting from scratch. See [`src/sys/README-sequence.md`](../src/sys/README-sequence.md).

## HTTP and telemetry

`src/sys/http.bas` is a small non-blocking HTTP client built on libcurl via QB64-PE's `DECLARE LIBRARY` C interop (`src/sys/curl_qb64.h`), used to POST/GET against the [Cloudflare Worker backend](../server/) without blocking the game loop. `src/sys/telemetry.bas` logs gameplay events locally and, if configured, batches and POSTs them at session end; `src/sys/lbrd.bas` polls and parses the top-scores leaderboard. See [`src/sys/README-http.md`](../src/sys/README-http.md) and [`src/sys/README-telemetry.md`](../src/sys/README-telemetry.md).

\* "Pure BASIC" describes the game: every subsystem above, from the rasterizer to the mixer to the voice synthesizer, is built from scratch in BASIC at each level, the way many hand-crafted games of the golden era were. It does not describe everything around the game. The build and test tooling (shell scripts, the container image) and the CI/CD pipeline are not BASIC, and the leaderboard backend in `server/` remains a TypeScript Worker. The build and test tooling is no longer Node or Python: the HTTP mock server the tests use is a QB64-PE program too. Underneath, modern QB64-PE translates the BASIC to C++ and links the platform's OpenGL and X11 layers to open a window and present the frame. QB itself has no networking, so the supplemental online features, the leaderboard and telemetry, go through libcurl via `DECLARE LIBRARY`. Those features are optional, and the game plays fully without them.
