# Maneuver File Format (`.mvr`)

Each file in `assets/maneuvers/` describes one flight-path route.
One route per file; no multi-block files.

---

## File Naming

Filename stem is the **kebab-case encoding** of the route name:

| Route name (`[name]` header) | Filename |
|------------------------------|----------|
| `drift`                      | `drift.mvr` |
| `browser_built`              | `browser-built.mvr` |
| `Boss Spiral`                | `boss-spiral.mvr` |

The `[name]` header inside the file is the **canonical** route name;
the filename is derived from it. Parsers should use the header value,
not the filename, as the route identifier.

---

## Overall Structure

```
[route-name]
<key=value headers>

<waypoints>

<optional sections in any order>
```

Blank lines are ignored. Lines starting with `#` are comments.
Sections (waypoints, tracks, triggers, craftroll, loopseam) may appear
in any order after the headers, though the serializer always emits them
in the order shown below.

---

## 1. Route Header

The first non-blank, non-comment line must be `[route-name]`.

```
[my-route]
```

---

## 2. Key=Value Fields

All fields except `speed` and `closed` are optional; defaults are shown.

| Field | Default | Description |
|-------|---------|-------------|
| `type` | `craft` | Route type. `craft` = ship-piloted flight path. `camera` = camera path. |
| `speed` | `0.025` | Arc-length units per game tick at 60 Hz. `0.025` ≈ 1.5 u/s. |
| `orient` | `path` | Ship orientation mode. See §2.1. |
| `standoff` | `0` | Perpendicular offset from the wire curve, in world units. Omitted when zero. |
| `closed` | `1` | `1` = loop (last waypoint connects back to first). `0` = open path. |

### 2.1 `orient` values

```
orient=path
```
Ship faces its direction of travel (tangent to the spline).

```
orient=target:X,Y,Z
```
Ship always faces the world-space point `(X, Y, Z)`, e.g. `orient=target:0,6,0`.

---

## 3. Waypoints

One waypoint per line, after a blank line following the headers.
Fields are whitespace-separated; extra whitespace is ignored.

```
X  Y  Z  [pathRoll  [craftRoll]]
```

| Column | Type | Description |
|--------|------|-------------|
| `X Y Z` | float | World-space position, world units. |
| `pathRoll` | float (degrees) | Bank angle applied perpendicular to the spline tangent. Positive = right-wing-down (CW from pilot view). Omit or `0` when unused. |
| `craftRoll` | float (degrees) | Legacy per-waypoint craft roll (interpolated). Superseded by `craftroll:` segments. Omit or `0` when unused. |

**Closed-path convention:** For `closed=1` routes the serializer appends a
copy of waypoint 0 as the final line (so the game receives `n+1` waypoints
with `wps[last] == wps[0]`). Parsers **should strip** this duplicate
before storing, or handle the wrap-around explicitly. TrailForge's
`parseBlocks` / `parseFile` strip it automatically.

### Example — 4-waypoint closed loop

```
[drift]
speed=0.025
orient=path
closed=1

      20         0         0
      12         2         4
       8        -2         7
      16         0         1
      20         0         0   ← duplicate of first wp; strip on load
```

---

## 4. Behavior Tracks (`track:`)

Keyframe tracks for continuously-interpolated values. Any number of
keyframes per named track; any number of named tracks per route.

```
track: <name>, <t>, <value>, <ease>
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Track identifier. Game-defined; unknown names are ignored. |
| `t` | float [0, 1] | Arc-length fraction along the route. `0` = start, `1` = end (or loop point). |
| `value` | float | Track-specific meaning; game-defined. |
| `ease` | enum | Interpolation shape. See §4.1. |

### 4.1 Ease types

| Value | Shape |
|-------|-------|
| `linear` | Constant rate |
| `in` | Ease in (slow start) |
| `out` | Ease out (slow end) |
| `in-out` | Ease in and out |

### Known track names (game-defined)

| Name | Value meaning |
|------|---------------|
| `offsetAngle` | Angular offset applied to the ship's lateral aim direction (degrees). |

Unknown track names are stored by TrailForge and round-tripped without loss;
the game silently ignores tracks it doesn't recognize.

---

## 5. Trigger Events (`trigger:`)

One-shot events fired when the ship passes arc-length fraction `t`.

```
trigger: <t>, <type>, [args...]
```

| Event type | Arguments | Description |
|------------|-----------|-------------|
| `fireMode` | `<mode>` | Switch weapon fire mode. |
| `weapon` | `<name>` | Switch active weapon. |
| `shieldMode` | `<mode>` | Switch shield behaviour. |
| `invuln` | `0` or `1` | Set invulnerability off (`0`) or on (`1`). |
| `phase` | `<tag>` | Signal a boss-phase transition. Tag is game-defined. |
| `sound` | `<name>, <volume>, <loop>` | Play a sound. `volume` ∈ [0, 1]. `loop` = `1` to loop. |
| `custom` | `<tag>, <value>` | Game-specific event; both fields are arbitrary strings. |

Triggers are emitted sorted by `t`; parsers need not assume sorted order.

---

## 6. Craft Roll Segments (`craftroll:`)

Time-windowed bank-angle animations along the arc. Multiple segments may
overlap or chain; they are evaluated in order of increasing `t`.

```
craftroll: <t>, <duration>, <degrees>, <direction>, <mode>, <ease>
```

| Field | Type | Description |
|-------|------|-------------|
| `t` | float [0, 1] | Arc-length fraction where the segment begins. |
| `duration` | float (0, 1] | Arc-length extent of the segment. `t + duration` may exceed 1 on open paths; clamped on evaluation. |
| `degrees` | integer ≥ 0 | Rotation magnitude. |
| `direction` | `cw` or `ccw` | CW = right-wing-down from pilot view. CCW = left-wing-down. |
| `mode` | `relative` or `absolute` | `relative`: rotate by `degrees` from current roll. `absolute`: arrive at `degrees` regardless of current roll. |
| `ease` | enum | See §4.1. |

Segments are emitted sorted by `t`; parsers need not assume sorted order.

---

## 7. Loop Seam (`loopseam:`)

**Closed paths only.** A single optional line that smoothly bridges the
roll-angle discontinuity at the loop point (arc `1.0` / `0.0`).

At most one `loopseam:` line per file.

```
loopseam: <tailFrac>, <headFrac>, <targetAngle>, <ease>
```

| Field | Type | Description |
|-------|------|-------------|
| `tailFrac` | float [0, 0.45] | Arc fraction before the loop point blended into the seam. `0.05` means the last 5 % of the arc is the seam tail. |
| `headFrac` | float [0, 0.45] | Arc fraction after the loop point blended from the seam. `0.05` means the first 5 % of the arc is the seam head. |
| `targetAngle` | float (degrees) | The craft-roll angle to target at the loop point itself. `0` = level flight. |
| `ease` | enum | See §4.1. |

The seam occupies `[1 - tailFrac, 1]` (tail) and `[0, headFrac]` (head).
Within the seam the roll angle is interpolated from the angle at `1 - tailFrac`
toward `targetAngle` (tail side) or from `targetAngle` toward the angle
at `headFrac` (head side), ensuring continuity at both ends.

---

## 8. Complete Example

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
 11.1181   -4.4059  -17.0546   ← duplicate endpoint; strip on load

craftroll: 0.0912, 0.0283, 45, cw, relative, in-out
craftroll: 0.1213, 0.0263, 45, ccw, relative, in-out
craftroll: 0.2187, 0.0303, 50, ccw, relative, in-out
craftroll: 0.5709, 0.0611, 45, ccw, relative, in-out
craftroll: 0.6855, 0.0740, 150, cw, relative, in-out
craftroll: 0.8672, 0.0279, 30, ccw, relative, in-out
```

---

## 9. Parser Guidance

- **Unknown `key=value` lines** — skip silently. Future fields will be added.
- **Unknown section keywords** (e.g. a new `fx:` prefix) — skip the line silently.
- **Unknown track names** — store and round-trip; ignore during gameplay.
- **Unknown trigger types** — skip silently.
- **Field count mismatches** — skip the malformed line; do not abort.
- **Numeric parse failures** — skip the line; do not abort.
- **`type=craft` is the default** — the `type=` line is omitted from files
  where the type is `craft`; assume `craft` if the line is absent.
- **`standoff=`** is omitted when zero (< 0.01); assume `0` if absent.
- **Arc-length `t` values** are always in `[0, 1]`. Values outside this
  range should be clamped on evaluation.
- **Closed-path duplicate endpoint**: if `closed=1` and the last waypoint
  is within 0.001 world units of the first, discard the last waypoint.
  The game may instead choose to keep it and let its Catmull-Rom sampler
  handle the wrap — either approach is correct as long as the loop closes.

---

## 10. Versioning

There is no explicit version field. The format is designed to be
**forward-compatible**: parsers that follow §9 will silently ignore
unknown fields added in future versions. New fields are always optional
with a sensible default so older files remain valid.
