# Explosions: data-defined 3D particles

Issue #198. An explosion is a list of layers (flash, fireball, embers, shock ring, smoke, delayed secondary bursts) in `assets/explosions.txt`. Particles live in world space, so they carry a velocity, slow down, fall and inherit the victim's motion. Code: `src/2d/explosion.bas` (prefix `XP_`): parse, validate, pool, simulate. It has no drawing and no game state; the game does not call it yet.

Status: this is the headless core. Drawing (projection through the game camera, size and glow by distance, the depth-buffer test), the dev tooling (live reload, on-demand detonation, stress test, `--explode name@frame`) and the call sites come in the later parts of #198. Until then nothing on screen changes.

## The file

```
; comments start with ;
explosion:enemy
    SHAKE frames=6
    BURST count=1 life=5 size=0.4,1.2 glow=2 ramp=ffffff,ffc060 occlude=0
    BURST count=18 speed=0.03..0.11 drag=0.96 gravity=0.0004 life=20..36 size=0.12,0.02 ramp=ffe080,ff7020,501808 inherit=0.5
```

`explosion:<name>` starts a definition (1 to 16 of `a-z 0-9 _`). Lines under it belong to it. Verbs and keys are case-insensitive; a value cannot contain a space. The same line format as `assets/backdrops.txt`.

**Units are world units and frames** (60 per second). Only `maxpx` and `minpx` are pixels. Speeds are world units per frame: an enemy kill burst is about 0.11 today and a boss about 0.2.

### SHAKE

`SHAKE frames=N` (0 to 600), once per explosion: how long the caller should shake the screen. `XP_ShakeFrames%(id)` returns it; nothing in the core applies it.

### BURST keys

| Key | Default | Meaning |
|---|---|---|
| `count=` | 1 | particles in the layer, 1 to 300 |
| `delay=` | 0 | frames after `XP_Spawn` before the layer starts, 0 to 600 |
| `at=x,y,z` | 0,0,0 | offset from the spawn point (each part within +-20) |
| `scatter=` | 0 | start points fill a ball of this radius (0 to 10) |
| `speed=` | 0 | launch speed (0 to 2) |
| `shape=` | sphere | `sphere`: every direction equally. `ring`: the plane perpendicular to the camera's forward axis. `cone`: about `dir` |
| `dir=x,y,z` | 0,1,0 | cone axis (normalised on load); cone only |
| `spread=` | 30 | cone half-angle in degrees, 0 to 180; cone only |
| `drag=` | 1 | velocity multiplier per frame, 0 to 1 |
| `gravity=` | 0 | taken off vy per frame, -0.1 to 0.1 (negative rises) |
| `inherit=` | 0 | share of the victim's velocity added to the launch velocity, 0 to 2 |
| `life=` | 30 | frames, 1 to 600 |
| `size=a[,b]` | 0.1 | world radius, `a` at birth and `b` at death (0 to 5); one number is constant |
| `glow=` | 0 | halo radius as a multiple of size, 0 to 16 |
| `ramp=c1,c2,...` | | a colour gradient over the particle's life, 1 to 6 `rrggbb` |
| `color=c1,c2,...` | | one colour per particle, picked from the list, 1 to 6 `rrggbb` |
| `maxpx=` `minpx=` | 0 / 1 | pixel clamps on the drawn size; `maxpx=0` means no upper clamp |
| `occlude=` | 1 | 1: ships in front hide the particle; 0: drawn over everything (flashes) |

Exactly one of `ramp=` and `color=` is required. `count`, `delay`, `scatter`, `speed`, `drag`, `gravity`, `inherit`, `life`, `size` (either end) and `glow` take a range `a..b`: each particle picks its own value (`count` and `delay`: each spawn picks one). The other keys take a single number.

### The camera and `ring`

The playing camera sits behind the player and looks along +X (`cam.pos.x = player.px - CAM_CHASE_X`, `cam.target.x = player.px + CAM_LEAD_X`), so a ring facing the camera lies in the YZ plane: its particles get no X velocity from the shape. `inherit` can still push it along X.

## Simulation

Each `XP_Update` frame, for every particle: `v *= drag`, then `vy -= gravity`, then `p += v`. Its age goes up first, and it is gone when age reaches `life`, so a particle of life L is alive for L - 1 updates. Delayed layers then count down; one with `delay=N` starts at the end of the Nth update and shows at age 0.

Launch velocity is `inherit x victim velocity + direction x speed x scale`. `XP_Spawn id, x, y, z, vx, vy, vz, scale` takes the victim's position and velocity; `scale` (above 0) multiplies size, speed, `at` and `scatter`.

### Randomness

Every random-looking choice is `BD_Hash!` (from `backdrop.bas`) keyed on a per-spawn serial, the layer and the particle. No RNG stream is read (`RNG_FX`, `Rnd`), so no seeded run and no star in a golden shifts, and a spawn always gives the same particles. `XP_Clear` restarts the serial at 0.

### Pool and limits

- **768 particles** alive at once (`XP_POOL`). When a spawn asks for more than the free slots, every layer keeps `count x free / asked` of its particles (rounded down), decided at spawn time; the particles that were cut are added to `xpDropped`. A full pool takes nothing and counts it all.
- **Pending queue:** 32 delayed layers at once. A layer that finds it full is dropped and counted.
- **Per explosion:** at most 12 BURST lines, 300 particles in all, 8 delayed layers, and a glow x count budget of 3000 (the sum over layers of the largest glow times the largest count). The file holds at most 16 explosions and 64 BURST lines. Going over any of these is a load error, never a silently dropped line.

## Errors

A problem is reported as `line N: ...` in `xpErrors`; a file with any error loads nothing (the tables stay empty). `XP_Validate$()` adds a missing BURST and the names the game looks up (`XP_REQUIRED`: `boss`, `enemy`). `XP_Find%(name)` gives an explosion's id (-1 when absent); `xpIdBoss` and `xpIdEnemy` are resolved when the file loads.

## API

| Call | |
|---|---|
| `XP_Load` | parse the embedded `EXPLOSIONS` at startup |
| `XP_Parse%(src)` | parse text; 1 when clean |
| `XP_Validate$()` | "" when sound |
| `XP_Find%(name)` | id or -1 |
| `XP_Spawn id,x,y,z,vx,vy,vz,scale` | start an explosion |
| `XP_Update` | one frame |
| `XP_Clear` | empty the pool and the queue, zero the counters |
| `XP_Live%`, `XP_Size!(slot)`, `XP_Color&(slot)` | what a renderer reads, with the `xpX/xpY/xpZ`, `xpAlive` and `xpGl` tables |

## Tests

`tests/explosion_test.bas` parses the real file and covers parse errors, ranges, determinism, an untouched `rngState`, pool overflow and reduction, delay timing, the drag and gravity steps, inherit and scale, ring planarity, cone spread, colours and name lookup.

```
tools/dev test
```
