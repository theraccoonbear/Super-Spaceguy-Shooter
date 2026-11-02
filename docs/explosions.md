# Explosions: data-defined 3D particles

Issue #198. An explosion is a list of layers (flash, fireball, embers, shock ring, smoke, delayed secondary bursts) in `assets/explosions.txt`. Particles live in world space, so they carry a velocity, slow down, fall and inherit the victim's motion. Code: `src/2d/explosion.bas` (prefix `XP_`): parse, validate, pool, simulate, no drawing and no game state; `src/2d/explosiondraw.bas` (prefix `XPD_`): drawing and dev tooling.


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
| `maxpx=` `minpx=` | 0 / 1 | pixel clamps on the drawn size; `maxpx=0` means the default 16 px; never above 64 |
| `alpha=` | 1 | opacity of the layer, 0.05 to 1 (smoke) |
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

## Drawing

Code: `src/2d/explosiondraw.bas` (prefix `XPD_`), included after `explosion.bas`. `XPD_Draw` runs in `GS_PLAYING_Update` right after `E3D_SceneFlush` and before `COMBAT_OverlayDraw`, so bolts and warnings stay on top of the particles and the particles on top of the scene.

### Units and depth scale

Particles are projected with the frame's `vpMat` (the same matrix the scene used), so a burst follows camera lag, orbit mode and the cinematic camera. For each particle, clip `w` is the view depth and:

- `focal = (scrH / 2) / tan(cam.fov / 2)`, once per frame (`XP_Focal!`)
- radius in pixels = `size x focal / w` (`XP_PxRadius!`); the glow radius is `glow x` that radius, at most 48 px
- the radius is capped at the layer's `maxpx` (`maxpx=0` means 16; never above 64, `XP_MaxPx!`)
- under `max(minpx, 1)` pixels the particle is one pixel and its alpha is scaled by `(r / that)^2` (`XP_DotFade!`), so a far ember fades out instead of flickering
- nearer than `w = 0.6` (`XP_NEAR`) it is not drawn; from 0.6 to 2.0 its alpha rises linearly (`XP_NearFade!`)
- the last quarter of a particle's life fades its alpha to 0 (`XP_LifeFade!`)
- a particle whose centre is off screen is skipped unless its radius (or glow) reaches into the screen

Colour comes from `XP_Color&` (the layer's ramp at the particle's age, or its own picked colour).

### Occlusion and order

`occlude=1` layers are tested against `E3D_zBuf` with the same NDC z the scene's polygons write (`z / w` of clip row 2, smaller is nearer; the buffer holds 2.0 where nothing was drawn). A small particle tests its centre pixel; a disc over 6 px is filled by scanline, each row split into the runs the buffer lets through. `occlude=0` layers skip the test and draw over ships.

Live bursts (one per `XP_Spawn`) are drawn back to front by the view depth of their spawn point (at most 32 are ordered; any further burst is drawn with the last one). Inside a burst the layers draw in file order. There is no additive blend, so a glow is a stack of translucent fills (a Circle stack up to 6 px, three nested discs above).

### Dev tooling

`--explosion-dev` (dev builds only; a release build rejects it) works in play (`GS_PLAYING`, not while the pause dialog is open):

| Key | |
|---|---|
| **Z** | select the next definition |
| **X** | detonate it 12 world units ahead of the ship (at the boss when one is out) |
| **C** | reload `assets/explosions.txt` from disk (the launch folder, else the repository next to the executable) |
| **V** | stress test: `boss` plus 8 `enemy` in one frame |

A readout at the bottom left shows the definition name, live particles and `xpDropped`. A reload error is listed wrapped in red above it (at most 8 rows), the particles are cleared and the effects stay off until the file loads clean; the game does not stop. A SHAKE applies as `fxShakeTimer = max(current, frames)`. Z, X, C and V are not read by play (a player can remap an action onto one of them, which would then also trigger the helper); the pause dialog reads C, but it is a different state.

`--explode name@frame[,name@frame...]` (dev builds only) spawns the named explosions 12 units ahead of the ship when the frame counter (the one `--screenshot-at` uses) reaches `frame` in play, for deterministic render scenes. An unknown name or a malformed value stops the launch with a usage error. `tests/render/scenes/explosion.txt` uses `--explode boss@20` with shots at 22 (flash), 35 (debris and ring) and 60 (embers and smoke).

### Tuning workflow

```
tools/dev run --scene playing2 --god --explosion-dev
```

Edit `assets/explosions.txt`, press **C** in the running game, press **X** to see it, **Z** for the next definition, **V** for the worst case. Look at it near and far (fly forward), behind a ship (the ship must hide it), with Tab's camera orbit, and check `drop` stays 0 in the stress test. Then bless a render scene deliberately (`tools/dev render --update gameplay explosion`).

## Where the game uses them

`XP_REQUIRED` names the definitions the game looks up; the ids are `xpIdBoss`, `xpIdEnemy` and so on.

| Definition | Used for |
|---|---|
| `boss` | `BOSS_Defeat` (`XPD_Boom` at the boss, drawn at scale `BOSS_DEATH_SCALE`: the boss is far, so the blast is made large); it vanishes on the same frame as before, with the same score, telemetry and stage transition |
| `enemy` | an enemy shot down |
| `enemy_col` | a ship that rams the player |
| `player` | the player's ship destroyed (the 20 frame shake and the flash stay in `PLAYER_TakeDamage`) |
| `asteroid` | an asteroid hitting the ship |
| `nova_kill` | an enemy or asteroid caught by a nova, the planet defence wipe, the tutorial's kill |
| `nova` | the nova's own ring |
| `spark` | a shot on the shielded boss, a shot cleared by a nova |

Spawns inherit the victim's velocity (`inherit`). Only the boss uses `XPD_Boom`, so only it shakes the screen from its SHAKE; every other call site is plain `XP_Spawn` and keeps the shake it had. The contrails and the ship's trail stay on the older `FX_` particles. The kill bursts are no longer coloured by enemy type.

## Errors

A problem is reported as `line N: ...` in `xpErrors`; a file with any error loads nothing (the tables stay empty). `XP_Validate$()` adds a missing BURST and the names the game looks up (`XP_REQUIRED`, listed under "Where the game uses them"). `XP_Find%(name)` gives an explosion's id (-1 when absent); `xpIdBoss`, `xpIdEnemy` and the rest are resolved when the file loads.

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
| `XP_Focal!`, `XP_PxRadius!`, `XP_MaxPx!`, `XP_NearFade!`, `XP_DotFade!`, `XP_LifeFade!` | the depth-scale maths the drawing uses |
| `XP_ParseExplode%(text)` | the `--explode` value |
| `XPD_Draw`, `XPD_Boom id,x,y,z,vx,vy,vz,scale` | draw the pool; `XP_Spawn` plus the SHAKE |

## Tests

`tests/explosion_test.bas` parses the real file and covers the depth-scale, pixel clamp, near fade and `--explode` parsing, and parse errors, ranges, determinism, an untouched `rngState`, pool overflow and reduction, delay timing, the drag and gravity steps, inherit and scale, ring planarity, cone spread, colours and name lookup.

```
tools/dev test
```
