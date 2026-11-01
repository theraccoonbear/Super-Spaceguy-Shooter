# Backdrops: dynamic matte paintings

The title, the emperor card and the dock are still paintings. `assets/backdrops.txt` gives each one a few looping effects: a light that blinks, sparks that fly off a weld. Code: `src/2d/backdrop.bas` (the file, the timing; no game state) and `src/2d/backdropdraw.bas` (drawing, `--backdrop-dev`). Issue #369.

## The file

A declarative list, not a script. Each effect line is an independent loop: no waiting, no sequencing. `every=` and `phase=` are the only choreography. What an effect looks like on a frame is worked out from that frame's number.

```
; comments start with ;
backdrop:dock
    BLINK  at=78,67 color=ffc040 size=2 glow=8 mode=pulse on=60 off=60
    SPARK  at=50,117 color=ffd080,ffffff count=5 every=113 jitter=50 speed=1.2 gravity=0.05 life=22
```

`backdrop:<name>` starts a painting: `title`, `emperor` or `dock`. Lines under it belong to it. Verbs and keys are case-insensitive; a value cannot contain a space. Positions are pixels on the 320x240 painting, whatever size it is drawn at. Frames are 60 per second.

| Key | BLINK | SPARK | Meaning |
|---|---|---|---|
| `at=x,y` | required | required | where, in painting pixels (decimals allowed) |
| `color=` | one `rrggbb` | one to four, comma-separated | each spark takes one of them |
| `size=` | 0-8, default 1 | 1-6, default 1 | BLINK: radius of the lit core. SPARK: how big each spark is (1 is a 2x2 head with a 1 pixel trail; each step adds a pixel to both) |
| `glow=` | 0-12, default 3 | | pixels of soft glow around the core, drawn as stacked translucent rings; more glow reads brighter |
| `on=` `off=` | 1-600 / 0-600, default 30 / 30 | | frames lit and frames dark; in `pulse` mode their sum is the period |
| `mode=` | `hard` (default) or `pulse` | | `pulse` is a sine swell from dark to lit and back |
| `count=` | | 1-16, default 3 | sparks per burst |
| `every=` | | 1-3600, default 60 | frames between bursts |
| `jitter=` | | 0-3599, default 0; below `every` | each burst comes up to this many frames late, a different amount each time (from the frame/effect hash, so the same every run). Bursts are then `every-jitter` to `every+jitter` frames apart; use it with periods that are not multiples of each other so effects never fall into step |
| `speed=` | | 0-10, default 0.6 | pixels per frame at launch (each spark gets half to all of it) |
| `gravity=` | | -1 to 1, default 0.05 | added to the downward speed each frame |
| `life=` | | 1-600, default 20 | frames before a spark has faded out |
| `dir=` `spread=` | | 0-360, default 270 / 120 | launch direction in degrees (0 right, 90 down, 270 up) and the fan around it |
| `phase=` | 0-9999 | 0-9999 | start that many frames into the loop |

A problem is reported as `line N: ...`. Unknown effects and keys, bad numbers and colours, positions off the painting, a missing `at=` or `color=` are all errors, and a file with any error draws nothing. The tables are fixed (96 effects, 12 backdrops, 64 sparks alive at once per screen); going over is an error, never a silently dropped line. The spark limit is checked from `count`, `life` and `every - jitter` (the closest two bursts can come), so a file that could overflow the pool does not load.

## What it must not disturb

- **Time** is a per-screen frame counter that restarts when the screen is entered (the first frame, a gap in frames, or another backdrop). No wall-clock time is read, so a screenshot at frame N always shows the same picture.
- **Randomness** is a pure hash of the frame, the effect and the spark. No RNG stream is read (`RNG_FX`, `Rnd`, `RNG_UNIQUE`), so no other visual and no seeded run shifts.
- **Sparks** live in their own pool, not the shared `FX_*` one, so `FX_Update` on a menu cannot revive debris.
- `BACKDROP_Draw` runs right after the painting is put on the back buffer and before any UI, so panels and the title's dimming strip lay over the effects.

## Dev workflow

`--backdrop-dev` (dev builds only; a release build rejects it) shows the painting coordinates under the mouse cursor in the top-left corner, with a cross at the cursor, and re-reads `assets/backdrops.txt` from disk on **R**. A reload restarts the loops. Parse problems are listed on screen and the effects stay off until the file is fixed; the game does not stop. R is not used by the title (its menu hotkeys are A C S L T Q N and P), the emperor card or the dock; it is the one letter the helper takes.

```
tools/dev run --backdrop-dev --scene title --no-telem
tools/dev run --backdrop-dev --scene dock2 --credits 400 --no-telem
```

Edit `assets/backdrops.txt` on the host, switch to the game and press R. `tools/dev run` starts in the repository folder, so the file on disk is found; a native build finds it from the launch folder or one level up from the executable. The mouse reads the painting position even where a dock panel covers the art; on the dock only about 100x160 pixels of painting stay visible (the list panel covers x >= 104, the status panel x 4-94, y 162-234), so keep effects clear of text.

Do not commit a change to the effects without checking the golden screenshots: `tools/dev render` fails on the title and dock scenes, and `tools/dev render --update` re-blesses them (look at every changed PNG).

## Tests

`tests/backdrop_test.bas` parses the real file, covers every failure case, the blink timing, the hash, spark determinism, the pool limit, table overflow and screen entry.
