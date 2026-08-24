# Maneuver File Format (`.mvr`)

One `.mvr` file = one named flight-path route.
Files live in `assets/maneuvers/`.

---

## File naming

The filename stem is a **kebab-case encoding** of the route name.
The `[name]` header inside the file is the canonical identifier —
use it, not the filename.

```
assets/maneuvers/boss-spiral.mvr   →   [boss-spiral]
assets/maneuvers/browser-built.mvr →   [browser_built]   ← header wins
```

---

## Structure

Lines are processed top-to-bottom. Blank lines and lines beginning
with `#` are ignored. Sections may appear in any order after the
header block, though TrailForge always emits them in the order below.

```
[route-name]          ← required; first non-blank line
key=value …           ← route-level settings
                      ← blank line separates settings from waypoints
X  Y  Z …            ← one waypoint per line
…
track: …              ← behavior keyframes (optional)
trigger: …            ← one-shot events (optional)
craftroll: …          ← craft-roll animation segments (optional)
loopseam: …           ← loop-seam correction (optional, closed paths only)
```

---

## Route settings (`key=value`)

All fields except `speed` have defaults; omit them when using defaults.

| Key | Default | Values | Meaning |
|-----|---------|--------|---------|
| `type` | `craft` | `craft` \| `camera` | Route type. `type=` line is omitted when `craft`. |
| `speed` | `0.025` | float | Arc-length units advanced per game tick (60 Hz). |
| `orient` | `path` | `path` \| `target:X,Y,Z` | Ship-facing mode (see below). |
| `closed` | `1` | `0` \| `1` | Whether path loops. |

**`orient=path`** — ship faces its direction of travel (tangent).  
**`orient=target:X,Y,Z`** — ship always faces world point `(X,Y,Z)`.

---

## Waypoints

One waypoint per line; fields are whitespace-separated.

```
X  Y  Z
```

| Column | Type | Meaning |
|--------|------|---------|
| `X Y Z` | float | World-space position. |

### Closed-path endpoint convention

When `closed=1`, TrailForge appends a copy of waypoint 0 as the final
waypoint line so that `wps[last] == wps[0]`. **Strip this duplicate on
load** (check if the last point is within ~0.001 world units of the
first and drop it). TrailForge's own parser does this automatically.

---

## Behavior tracks (`track:`)

Continuously-interpolated keyframe values keyed by arc-length fraction.

```
track: <name>, <t>, <value>, <ease>
```

| Field | Type | Meaning |
|-------|------|---------|
| `name` | string | Track identifier — game-defined; unknown names are ignored. |
| `t` | float [0,1] | Arc-length fraction. `0` = path start, `1` = end/loop point. |
| `value` | float | Track-specific meaning (game-defined). |
| `ease` | `linear`\|`in`\|`out`\|`in-out` | Interpolation shape toward the next keyframe. |

Multiple keyframes per track, multiple tracks per file. TrailForge
round-trips unknown track names without loss.

**Known tracks:**

| Name | Value meaning |
|------|---------------|
| `offsetAngle` | Angular offset on the ship's lateral aim direction (degrees). |

---

## Trigger events (`trigger:`)

One-shot events fired when the ship crosses arc-length fraction `t`.

```
trigger: <t>, <type>, [args…]
```

| Type | Args | Meaning |
|------|------|---------|
| `fireMode` | `<mode>` | Change weapon fire mode. |
| `weapon` | `<name>` | Switch active weapon. |
| `shieldMode` | `<mode>` | Change shield behaviour. |
| `invuln` | `0`\|`1` | Disable/enable invulnerability. |
| `phase` | `<tag>` | Signal a boss-phase transition. |
| `sound` | `<name>, <volume>, <loop>` | Play a sound. `volume` ∈ [0,1]; `loop` = `1` to loop. |
| `custom` | `<tag>, <value>` | Freeform game event; both fields are arbitrary strings. |

`mode` and `name` values for `fireMode`, `weapon`, and `shieldMode`
are game-defined enumerations. Unknown trigger types are ignored.

---

## Craft-roll segments (`craftroll:`)

Time-windowed bank-angle animations. Controls the ship's rolling
motion independently of the path frame. Multiple segments may be
active simultaneously; they are applied in order of increasing `t`.

```
craftroll: <t>, <duration>, <degrees>, <direction>, <mode>, <ease>
```

| Field | Type | Meaning |
|-------|------|---------|
| `t` | float [0,1] | Arc-length fraction where the segment begins. |
| `duration` | float (0,1] | Arc-length extent of the segment. |
| `degrees` | integer ≥ 0 | Rotation magnitude. |
| `direction` | `cw`\|`ccw` | `cw` = right-wing-down from pilot view. |
| `mode` | `relative`\|`absolute` | `relative`: rotate by `degrees` from current roll. `absolute`: arrive at `degrees` regardless of current roll. |
| `ease` | `linear`\|`in`\|`out`\|`in-out` | Interpolation shape. |

---

## Loop seam (`loopseam:`)

**Closed paths only. At most one per file.**

Smoothly bridges the craft-roll discontinuity at the loop point
(where arc fraction `1.0` meets `0.0`). Without a seam, a sudden
jump in roll angle occurs if the cumulative craft roll at the end of
the loop differs from the start.

```
loopseam: <tailFrac>, <headFrac>, <targetAngle>, <ease>
```

| Field | Type | Meaning |
|-------|------|---------|
| `tailFrac` | float [0,0.45] | Arc fraction *before* the loop point to blend into the seam. |
| `headFrac` | float [0,0.45] | Arc fraction *after* the loop point to blend out of the seam. |
| `targetAngle` | float° | Craft-roll angle at the loop point itself (`0` = level). |
| `ease` | `linear`\|`in`\|`out`\|`in-out` | Interpolation shape for both sides of the seam. |

The seam occupies `[1-tailFrac, 1]` (tail side) and `[0, headFrac]`
(head side). Within the tail the roll blends from the angle at
`1-tailFrac` toward `targetAngle`; within the head it blends from
`targetAngle` toward the angle at `headFrac`. Continuity is guaranteed
at both loop-point ends.

---

## Full example

```
[twist_and_roll]
speed=0.25
orient=path
closed=1

 11.1181   -4.4059  -17.0546
 39.3595   -5.2064  -16.7136
 27.8394         0   15.5773
 45.4354         0   29.1127
 54.9101   11.8824  -11.0059
 43.3327    8.2100  -21.5096
 31.9313    2.0316  -21.5096
 21.4972   -8.5769   23.9693
 13.0229   -0.4992   12.5684
 11.1181   -4.4059  -17.0546

craftroll: 0.0912, 0.0283,  45, cw,  relative, in-out
craftroll: 0.1213, 0.0263,  45, ccw, relative, in-out
craftroll: 0.2187, 0.0303,  50, ccw, relative, in-out
craftroll: 0.5709, 0.0611,  45, ccw, relative, in-out
craftroll: 0.6855, 0.0740, 150, cw,  relative, in-out
craftroll: 0.8672, 0.0279,  30, ccw, relative, in-out
```

---

## Parser rules

- **Unknown `key=value` fields** — skip; new fields are added without bumping a version.
- **Unknown section prefixes** (e.g. a future `fx:` line) — skip the line.
- **Unknown track names** — skip during gameplay; round-trip without loss if re-saving.
- **Unknown trigger types** — skip.
- **Malformed lines** (wrong field count, non-numeric where numeric expected) — skip the line; do not abort parsing.
- **`type=craft`** is the default; the line is omitted when the type is `craft`.
- **`t` values** are always [0,1]; clamp on evaluation.
- **Extra waypoint columns** — any columns beyond X Y Z are ignored.
