# Backdrops: dynamic matte paintings

The title, the emperor card and the dock are still paintings. `assets/backdrops.txt` gives each one a few looping effects: a light that blinks, sparks that fly off a weld, a tug that drives across the tarmac, a laser bolt between two ships. Code: `src/2d/backdrop.bas` (the file, the timing; no game state) and `src/2d/backdropdraw.bas` (drawing, `--backdrop-dev`). Issue #369.

## The file

A declarative list, not a script. Each effect line is an independent loop: no waiting, no sequencing. `every=` and `phase=` are the only choreography. What an effect looks like on a frame is worked out from that frame's number.

```
; comments start with ;
backdrop:dock
    BLINK  at=78,67 color=ffc040 size=2 glow=8 rise=60 fall=60
    SPARK  at=50,117 color=ffd080,ffffff count=5 every=113 jitter=50 speed=1.2 gravity=0.05 life=22
```

`backdrop:<name>` starts a painting: `title`, `emperor` or `dock`. Lines under it belong to it. Verbs and keys are case-insensitive; a value cannot contain a space. Positions are pixels on the 320x240 painting, whatever size it is drawn at. Frames are 60 per second.

| Key | BLINK | SPARK | Meaning |
|---|---|---|---|
| `at=x,y` | required | required | where, in painting pixels (decimals allowed) |
| `color=` | one `rrggbb` | one to four, comma-separated | each spark takes one of them |
| `size=` | 0-8, default 1 | 1-6, default 1 | BLINK: radius of the lit core. SPARK: how big each spark is (1 is a 2x2 head with a 1 pixel trail; each step adds a pixel to both) |
| `glow=` | 0-12, default 3 | | pixels of soft glow around the core, drawn as stacked translucent rings; more glow reads brighter |
| `rise=` `hold=` `fall=` `rest=` | each 0-600, default 0; at least one must be above 0 | | the light's envelope in frames: fades up over `rise`, stays full for `hold`, fades down over `fall`, is dark for `rest`. The loop is the sum of the four, at least 1 frame. Fades are eased (half a cosine). `rise=0 fall=0` is a hard blink; `rise=N fall=N` is a smooth pulse of 2N frames |
| `count=` | | 1-16, default 3 | sparks per burst |
| `every=` | | 1-3600, default 60 | frames between bursts |
| `jitter=` | | 0-3599, default 0; below `every` | each burst comes up to this many frames late, a different amount each time (from the frame/effect hash, so the same every run). Bursts are then `every-jitter` to `every+jitter` frames apart; use it with periods that are not multiples of each other so effects never fall into step |
| `speed=` | | 0-10, default 0.6 | pixels per frame at launch (each spark gets half to all of it) |
| `gravity=` | | -1 to 1, default 0.05 | added to the downward speed each frame |
| `life=` | | 1-600, default 20 | frames before a spark has faded out |
| `dir=` `spread=` | | 0-360, default 270 / 120 | launch direction in degrees (0 right, 90 down, 270 up) and the fan around it |
| `phase=` | 0-9999 | 0-9999 | start that many frames into the loop |

SPRITE, LASER and CAMERA have their own keys, below. BLINK also takes `morse=` and `unit=`.

## Morse on a BLINK

`morse=TEXT` makes a BLINK flash a message instead of an envelope. `TEXT` is letters and digits, with `_` for a space (at most 24 characters; case does not matter; anything else, or a `_` at either end or doubled, is an error). Standard timing, in units: dot 1, dash 3, 1 dark between the symbols of a letter, 3 between letters, 7 between words. `unit=N` (1-60, default 6) is a unit in frames. `rest=` is the dark time after the whole message before it repeats; `rise=` and `fall=` ease each flash in and out (the shorter ramp wins when a flash is shorter than `rise + fall`); `phase=` shifts the loop. `hold=` is an error with `morse=` (the letters set the timing), and so is `unit=` without `morse=`.

```
    BLINK at=78,67 color=ff3030 size=2 glow=6 morse=sos unit=6 rest=120 rise=1 fall=2
```

## SPRITE: a small image on a straight path

```
    SPRITE img=baggage_cart at=6,146 to=84,156 frames=420 rest=240 scale=0.4,0.55 bob=1,12
```

An image from `assets/backdrops/<name>.png` (embedded; `baggage_cart.png` is 64 px wide, heading down-right, and `tug.png` is a 24x12 placeholder facing right) goes from `at` to `to` at a constant speed over `frames` (1-3600, default 300), then waits `rest` (0-3600, default 0) and repeats. Position is a pure function of the frame counter, as for BLINK, so screenshots are deterministic; `phase=` starts it that many frames in. `at` and `to` are the image's centre, in painting pixels, and may lie up to 64 pixels off the painting so a sprite can drive on and off the edge. The image is scaled with the painting.

- Without `pingpong=1` the sprite is hidden during `rest` and then starts again at `at`.
- With `pingpong=1` it drives back from `to` to `at` over another `frames`, and waits `rest` at both ends (visible there). The loop is `2 * (frames + rest)`.
- `flip=1` mirrors the image for the whole return leg. It only means something with `pingpong=1`, so `flip=1` without it is a parse error.
- `scale=a[,b]` (0.1 to 4 each, default 1) is the sprite's size along the path: `a` at `at`, `b` at `to`, linear in between. One value is a fixed size. The size follows the point on the path, so on the pingpong return leg it shrinks or grows back. The image is drawn into the scaled rectangle centred on the path point. A far-to-near route is `scale=0.4,0.55`.
- `bob=amp,period[,angle]` makes it hop like a wheeled thing on a rough road: its offset is `amp * |sin(pi * t / period)|` pixels along `angle`, times the current scale, where `t` counts frames of the current leg. `amp` is 0 to 64, `period` (frames per hop) 2 to 3600. `angle` is in degrees on the screen with the same convention as `dir=` on SPARK: 0 is right, 90 is **down**, 270 is **up** (the default). The hop pauses (offset 0) while the sprite waits at a pingpong end, so a parked vehicle does not bounce, and each leg starts its count at 0; for a clean stop make `frames` a multiple of `period`.
- An unknown `img` is an error that lists the known names (`BD_SPRITE_NAMES` in `backdrop.bas`).

To swap in real art: shrink the picture once to the size it is drawn at its largest (for example `magick big.png -filter Box -resize 64x assets/backdrops/name.png`, which keeps the alpha), commit that small file, and then use `scale=` of 1 or less at run time rather than scaling a large image down every frame (`baggage_cart.png` is 256x149 shrunk to 64 wide, drawn at 0.4 to 0.55). To replace an image keep its file name; for a new one add its name to `BD_SPRITE_NAMES`, add an `$EMBED:'assets/backdrops/<name>.png':'BDIMG<NAME>' (no underscores in the handle)` line to `sss.bas` and `tests/backdrop_test.bas`, and a load line in `BACKDROP_LoadArt`.

## LASER and CAMERA: a bolt in perspective

```
    CAMERA fov=60 horizon=120
    LASER from=158,104,40 to=60,150,10 color=ff3030 every=90 speed=4 length=12
```

Every `every` frames (1-3600, default 60) a bolt leaves `from` and flies to `to`, then disappears. `from` and `to` are `x,y,depth`. `speed` (0.1-50, default 4) is world units a frame and `length` (0.5-200, default 12) is the bolt's tail, both measured at depth 0 (one unit is one painting pixel there). `jitter=` delays each shot by up to that many frames (below `every`), `phase=` shifts the loop. The bolt is drawn by the game's bolt renderer (`COMBAT_DrawBoltM`) through a fixed camera of the backdrop's own. It never reads `vpMat`, so it is the same on the title, the dock and in the middle of a run. If the bolts could overlap more than 7 at a time the file does not load.

**The camera.** `CAMERA fov=<degrees> horizon=<y>` (at most once per backdrop, anywhere among its lines). `fov` (10-120, default 60) is the angle the painting's 320 pixel width spans at depth 0; a small value is a long lens with weak perspective. `horizon` (0-240, default 120) is the painting row of the vanishing point, which sits at x = 160. Depth increases away from the viewer: depth 0 is the painting plane, a positive depth is farther, a negative one nearer (down to -50).

The mapping is chosen so `x,y` can be read off the painting: **a point written as `x,y,depth` shows up at exactly painting pixel `x,y`, whatever the depth.** Depth changes only how that point behaves in motion: things at depth `d` are scaled by `F / (F + d)` with `F = 160 / tan(fov / 2)`, so a far bolt is smaller, thinner and crosses fewer painting pixels per frame, and a bolt flying to a greater depth than it started at converges on the vanishing point `(160, horizon)`. In practice: put `from` and `to` on the spots of the painting where the bolt should appear and vanish, give a far shooter a large depth and a near target a small one, and use `fov` and `horizon` to bend the path (a lower `horizon` pulls it up toward the sky). The camera is a plain pinhole built in `BD_CamMatrix`; `tests/backdrop_test.bas` checks the projection.

## Dev workflow notes for the new effects

With `--backdrop-dev` each SPRITE and LASER is marked with a small cross at the path's start and end, labelled `S0, S1...` and `L0, L1...` in file order within the backdrop, and the path faintly between them. A backdrop with a LASER also shows a faint horizon line and a `VP` cross at the vanishing point. R reloads the verbs and CAMERA like everything else.

### Landing lights

One envelope, three lights, `phase=` stepping each 10 frames behind the last, makes a chase:

```
    BLINK at=207,166 color=ffffcc size=3 glow=6 rise=10 fall=10 rest=40 phase=20
    BLINK at=241,148 color=ffffcc size=2 glow=3 rise=10 fall=10 rest=40 phase=10
    BLINK at=265,137 color=ffffcc size=1 glow=2 rise=10 fall=10 rest=40
```

Each loop is 60 frames; the lights peak 10 frames apart (the `phase=20` one first), then all stay dark for 40 frames. A plain hard blink is `hold=8 rest=52`. `on=`, `off=` and `mode=` no longer exist and are errors.

## Errors and limits

A problem is reported as `line N: ...`. Unknown effects (BLINK SPARK SPRITE LASER CAMERA) and keys, bad numbers and colours, positions off the painting, a missing `at=` or `color=` are all errors, and a file with any error draws nothing. The tables are fixed (96 effects, 12 backdrops, 1024 sparks alive at once per screen); going over is an error, never a silently dropped line. The spark limit is checked from `count`, `life` and `every - jitter` (the closest two bursts can come), so a file that could overflow the pool does not load.

## What it must not disturb

- **Time** is a per-screen frame counter that restarts when the screen is entered (the first frame, a gap in frames, or another backdrop). No wall-clock time is read, so a screenshot at frame N always shows the same picture.
- **Randomness** is a pure hash of the frame, the effect and the spark. No RNG stream is read (`RNG_FX`, `Rnd`, `RNG_UNIQUE`), so no other visual and no seeded run shifts.
- **Sparks** live in their own pool, not the shared `FX_*` one, so `FX_Update` on a menu cannot revive debris.
- `BACKDROP_Draw` runs right after the painting is put on the back buffer and before any UI, so panels and the title's dimming strip lay over the effects.

## Dev workflow

`--backdrop-dev` (dev builds only; a release build rejects it) shows the painting coordinates under the mouse cursor in the top-left corner, with a cross at the cursor, and re-reads `assets/backdrops.txt` from disk on **R**. A reload restarts the loops and says "reloaded N" (the effect count) in small text beside the readout for half a second, with no panel behind it. Parse problems are listed in small red text under the readout (wrapped to the 320 pixel width, at most eight rows) and stay until the file is fixed, with the effects off; the game does not stop. R is not used by the title (its menu hotkeys are A C S L T Q N and P), the emperor card or the dock; it is the one letter the helper takes.

```
tools/dev run --backdrop-dev --scene title --no-telem
tools/dev run --backdrop-dev --scene dock2 --credits 400 --no-telem
```

Edit `assets/backdrops.txt` on the host, switch to the game and press R. `tools/dev run` starts in the repository folder, so the file on disk is found; a native build finds it from the launch folder or one level up from the executable. The mouse reads the painting position even where a dock panel covers the art; on the dock the list panel (x >= 104) and the status panel (x 4-94, y 162-234) are see-through but carry text, so effects behind them show only faintly; keep bright effects clear of text.

Do not commit a change to the effects without checking the golden screenshots: `tools/dev render` fails on the title and dock scenes, and `tools/dev render --update` re-blesses them (look at every changed PNG).

## Tests

`tests/backdrop_test.bas` parses the real file, covers every failure case, the blink and Morse timing, SPRITE paths, LASER emission and the CAMERA projection, the hash, spark determinism, the pool limit, table overflow and screen entry.
