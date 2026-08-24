# Path Behavior System — Design Plan

Status: **Design / pre-implementation spitball**  
Context: TrailForge at `tools/TrailForge/`; game at `3d/`

---

## Problem Statement

The current `PathData` structure is purely geometric: waypoints define a spline
curve, plus two roll angles per node and a global standoff scalar. That's enough
to route a craft and orient it; it is not enough to script its combat behavior,
animate its visual state, or drive a cinematic sequence.

We need to attach behavioral intent to a path without coupling it to waypoint
placement. A boss's firing pattern should not require adding or moving routing
nodes.

---

## Two-Tier System

### Tier 1 — Routing nodes (existing, unchanged)

`wps[]` stays exactly as it is: `x, y, z, pathRoll, craftRoll`. These are purely
geometric. `pathRoll` and `craftRoll` in waypoints remain valid as "natural" roll
values for the path; they are always computed. Behavior tracks (below) **overlay**
them when present.

Do NOT collapse these into tracks. Waypoints have spatial meaning and belong in
the path editor's primary ortho/persp UI.

### Tier 2 — Behavior overlay (new)

Two sub-systems:

#### A. Continuous tracks

A named array of keyframes. Each keyframe specifies a value at an arc-length
position. Between keyframes the value is interpolated using the outgoing
keyframe's easing.

```
Track
  name:   string                 e.g. "craftRoll", "standoff"
  frames: Keyframe[]
    .t:     number (0..1)        arc-length fraction (NOT Catmull-Rom t)
    .value: number
    .ease:  EaseType             governs transition FROM this keyframe onward
```

Tracks take effect when present; absent = waypoint/global values apply.
A track with a single keyframe is a constant override (useful for "hold at 15°
the whole way").

**Initial named tracks (confirmed):**

| Track name        | Units       | Overrides                 | Notes |
|-------------------|-------------|---------------------------|-------|
| `craftRoll`       | degrees     | wp-interpolated craftRoll | visual roll of ship model; overrides wp values when present |
| `standoff`        | world units | global `standoff` field   | distance of craft from wire curve |
| `offsetAngle`     | degrees     | (new; none currently)     | rotates standoff offset vector around spline tangent; 0=up, 90=left |
| `speed`           | world-units/frame | global `speed` field | actual travel speed; scales the global value; use to make craft slow/accelerate at specific path positions |
| `visible`         | 0..1        | (new)                     | craft opacity; 0=fully cloaked, 1=fully visible |
| `engineBrightness`| 0..1        | (new)                     | engine trail/glow intensity; visual only |

System is open — any string name is valid. Consumers silently ignore names they
don't understand. No format versioning needed to add tracks.

**Discrete trigger event types (confirmed):**

| type        | args              | Meaning |
|-------------|-------------------|---------|
| `fireMode`  | `off\|on\|target\|willful` | halt / open / target-only / fire at will |
| `weapon`    | weapon name       | switch weapon type |
| `shieldMode`| `off\|on\|partial`| boss shield state change |
| `invuln`    | `0\|1`            | invulnerability window open/close |
| `phase`     | tag string        | signal game state machine (phase transition hook) |
| `custom`    | tag, value        | forward-compat escape hatch; both strings |

#### B. Discrete triggers

An event list. Each trigger fires exactly once when the craft crosses its `t`
position. Order within a `t` is FIFO (insertion order). Events do not lerp.

```
Trigger
  .t:     number (0..1)
  .event: TriggerEvent (union)
```

**Initial trigger event types:**

| type        | fields              | Meaning |
|-------------|---------------------|---------|
| `fireMode`  | `mode`              | `off` \| `on` \| `target` \| `willful` — "target" fires only when player is in arc; "willful" fires at will regardless |
| `weapon`    | `name`              | switch to named weapon (string key; game maps to actual weapon) |
| `phase`     | `tag`               | signal the game state machine; game interprets meaning |
| `custom`    | `tag`, `value`      | forward-compat escape hatch; both are strings |

More types added as needed. The `custom` type means we never need to version-bump
the format just to add a one-off game signal.

---

## Arc-length Normalization

Track and trigger `t` values are **arc-length fraction 0..1**, not Catmull-Rom
parameter space.

Rationale:
- `t=0.5` always means "halfway along the path by distance" regardless of waypoint count or spacing
- Invariant to adding/removing routing nodes
- Matches how human brains think about "the midpoint"

The game engine already arc-length-corrects speed; it will need the same lookup
to evaluate tracks and triggers. The editor already has `buildSpline()` which
produces arc-length samples — use that for the mapping.

---

## Easing

Easing is per-keyframe (outgoing), standard convention (same as Blender, Unity):

| Value      | Meaning |
|------------|---------|
| `linear`   | constant rate |
| `smooth`   | smoothstep S-curve (`3t²−2t³`) |
| `ease-in`  | slow start, fast end (cubic) |
| `ease-out` | fast start, slow end (cubic) |
| `instant`  | hold value until next keyframe, then snap — no lerp |

`instant` is how you express "immediately roll to 45°" without adding a second
keyframe a hair later.

---

## Easing Evaluation

Between keyframes A (t=a, v=A, ease=E) and B (t=b, v=B):

```
s = (t - a) / (b - a)     // 0..1 local fraction
apply easing E to s → u
result = lerp(A, B, u)
```

Before the first keyframe: hold the first keyframe's value.  
After the last keyframe: hold the last keyframe's value.

---

## Data Model Changes

```ts
type PathType = 'craft' | 'camera'   // omitted in file → 'craft'; old files unaffected

type EaseType = 'linear' | 'smooth' | 'ease-in' | 'ease-out' | 'instant'

interface TrackKeyframe {
  t:     number       // 0..1 arc-length normalized
  value: number
  ease:  EaseType     // outgoing: governs transition to NEXT keyframe
}

type FireMode = 'off' | 'on' | 'target' | 'willful'

type TriggerEvent =
  | { type: 'fireMode'; mode: FireMode }
  | { type: 'weapon';   name: string }
  | { type: 'phase';    tag: string }
  | { type: 'custom';   tag: string; value: string }

interface PathTrigger {
  t:     number
  event: TriggerEvent
}

// PathData extended (src/store.ts)
interface PathData {
  name:     string
  type:     PathType                          // default 'craft'; absent = 'craft'
  speed:    number
  orient:   'path' | 'target'
  target:   Vec3
  standoff: number
  closed:   boolean
  wps:      Waypoint[]
  tracks:   Record<string, TrackKeyframe[]>   // {} when no tracks
  triggers: PathTrigger[]                     // [] when no triggers
}
```

`tracks` and `triggers` default to empty; existing paths without them parse
identically to today.

---

## File Format Extension

The existing parser silently skips any line that doesn't match `[header]`,
`key=value` (alphanumeric key only), or "all numbers". New line prefixes are
therefore backward-compatible — old parsers ignore them.

**New line types:**

```
track: <name>, <t>, <value>, <ease>
trigger: <t>, <eventType>, <args...>
```

Examples:
```
[boss_sweep]
speed=0.25
orient=target:0,20,0
standoff=8
closed=0

  10   0   0
  25   8  15
  40   0   0

track: craftRoll,   0.00,   0, linear
track: craftRoll,   0.30,  45, smooth
track: craftRoll,   0.70, -30, smooth
track: craftRoll,   1.00,   0, instant
track: standoff,    0.00,   8, linear
track: standoff,    0.50,  18, ease-in
track: standoff,    1.00,   8, ease-out
trigger: 0.05, fireMode, on
trigger: 0.55, fireMode, target
trigger: 0.95, fireMode, off
```

**Trigger event serialization:**

| type      | wire format |
|-----------|-------------|
| fireMode  | `trigger: 0.1, fireMode, on` |
| weapon    | `trigger: 0.2, weapon, spreadshot` |
| phase     | `trigger: 0.5, phase, angry` |
| custom    | `trigger: 0.8, custom, myTag, myValue` |

The `custom` type takes two trailing args; all others take one. Parser splits on
`, ` (comma-space) after the t field.

---

## Parser Changes (format.ts)

Add `type` to the existing `switch (key)` block, and two new branches in the parse
loop (before the number-only waypoint branch):

```ts
// Track keyframe: "track: name, t, value, ease"
if (line.startsWith('track:')) {
  const parts = line.slice(6).split(',').map(s => s.trim())
  // [name, t, value, ease]
  ...push to cur.tracks[name]
  continue
}

// Discrete trigger: "trigger: t, type, ...args"
if (line.startsWith('trigger:')) {
  const parts = line.slice(8).split(',').map(s => s.trim())
  // [t, type, arg1, arg2?]
  ...push to cur.triggers
  continue
}
```

Also extend `exportBlock()` to emit `track:` and `trigger:` lines after the
waypoints block, sorted by `t` within each section.

---

## QB64-PE Parser Changes (game side)

The game's maneuver parser (wherever it lives) needs to:

1. Read `track:` lines → build per-track keyframe arrays
2. Read `trigger:` lines → build an event queue sorted by arc-length t
3. During path following:
   - Each frame, for each active track, evaluate the track at current arc-length
     fraction → override the corresponding behavioral value
   - Each frame, check the event queue; fire all triggers where craft has passed `t`

Arc-length fraction computation: the game already walks the spline
arc-length-corrected. The fraction is just `currentArcLen / totalArcLen`.

This is a **game-side implementation task** that follows this design being
ratified. It is **not** in scope for the path editor until the data model and
format are agreed.

---

## Editor UX

### Layout: bottom panel

The Behaviors panel lives **below the four views** as a horizontal resizable
strip. The four-view grid shrinks to give it room. A drag handle at the top
of the panel lets the user resize it vertically. A toggle button (keyboard
shortcut TBD — `B`?) shows/hides it. When hidden, the four views reclaim
full height.

```
┌──────────┬──────────┐
│  TOP     │  PERSP   │
│          │          │
├──────────┼──────────┤
│  SIDE    │  FRONT   │
│          │          │
├──────────────────────┤  ← drag handle
│ ◀━━━━●━━━━━━━━━━━━━▶ │  ← path ruler (synced to anim scrubber)
│ craftRoll  ╌╌◆╌╌╌◆╌ │
│ standoff   ╌╌╌╌◆╌╌╌ │
│ EVENTS  ↑0.1 ↑0.5   │
└──────────────────────┘
```

### Component architecture (future-proofing for moveable panes)

**The panel is a self-contained store-connected component.** It reads from
`useStore()` directly — no data props drilled from App.tsx. App.tsx owns only
the layout slot (the CSS grid row/column the panel occupies), not the panel's
data dependencies.

This matches the pattern the four views already follow. When moveable/tab-able
panes become a feature, every panel is already portable — no refactoring of
prop chains required. The panel is a named pane, not a child of another pane.

Store additions for panel state:
```ts
behaviorsOpen:   boolean   // panel visible
behaviorsHeight: number    // px; user-resized via drag handle
```
(These are UI state, not path data, so they are NOT tracked by the undo system.)

### Panel contents

**Shared path ruler** — top of panel:
- Horizontal bar 0.0 → 1.0
- Scrubber indicator synced with the animation T (bidirectional: drag here also
  drives playback position)
- Tick marks at each track keyframe and trigger position (colored by owner)

**Track rows** — one row per active track:
```
craftRoll °  [╌╌╌╌╌◆╌╌╌╌╌╌◆╌╌╌╌◆╌╌]  [×]
              0°   45°   -30°   0°
```
- `◆` diamonds are draggable horizontally (moves the keyframe's t position)
- Click empty bar area → add keyframe at that t, value pre-filled from current
  interpolated value at the scrubber's position
- Click existing `◆` → inline edit popover (t, value, ease dropdown)
- Right-click `◆` → context menu (delete, duplicate, set ease)
- The bar background shows a faint sparkline of the interpolated curve

**Trigger list** — below tracks, collapsible:
```
↑ 0.05  fireMode  on          [×]
↑ 0.55  fireMode  target      [×]
↑ 0.95  fireMode  off         [×]
```
- Click `↑` marker or row → inline popover (t, event type dropdown, args)
- Triggers also show as tick marks on the shared ruler, color-coded by type

**[+] button** (top-right of panel) → dropdown:
- Add continuous track → pick name from known list or type custom
- Add trigger event → pick event type → placed at current scrubber t

### Visualization in the path views

Every keyframe and trigger gets a spatial marker drawn along the spline curve
in all four views (ortho + persp):
- Track keyframe: small filled circle, color per track name (fixed palette)
- Trigger: small diamond, color per event type

Hovering a marker in a view highlights the corresponding row/diamond in the
Behaviors panel. Hovering a row in the panel highlights the spatial markers in
all views. This bi-directional highlight is the key spatial-to-timeline bridge.

### Authoring loop

1. Scrub/play to find the path position where you want a behavior change
2. Pause — scrubber is now at t
3. Click [+] on the Behaviors panel, pick track type
4. Keyframe drops at current t with current interpolated value pre-filled
5. Drag diamond or edit popover to set the target value
6. All four views update immediately to preview the result

This is the same mental model as placing a waypoint: you navigate to a position
spatially, then author data at that position. No typing t values by hand.

### What NOT to show the user

- Never display the raw `tracks` / `triggers` JSON
- Never show a matrix of t-values in a table
- Never require the user to type a t value to place a keyframe — the scrubber
  is always the cursor; clicking the bar places at the scrubber position
- Empty tracks should not be shown; only tracks that have at least one keyframe
  appear (the [+] button is how you add them)

---

## Resolved Questions

1. **pathRoll vs offsetAngle**: `pathRoll` in waypoints already rotates the
   standoff offset. The new `offsetAngle` track does the same but smoothly and
   independently. Decision: keep both; track overrides the waypoint roll when
   present. Rename discussion is a separate cleanup.

2. **craftRoll source-of-truth**: Track wins over wp interpolation when present.
   No track → fall back to waypoint-interpolated craftRoll. Editor should
   communicate this visually (e.g. grey out the wp roll display when a track
   overrides it).

3. **speedScale clock model — RESOLVED**: Triggers and track keyframes fire/evaluate
   based on **arc-length position**, not wall-clock time. Firing occurs at the same
   point on the path regardless of playback speed. `speedScale` changes how fast the
   craft covers distance per frame (world velocity), but triggers and keyframes are
   still anchored to the fraction of path covered. Concretely: the arc-length
   fraction advances based on distance traveled that frame; a slower craft takes
   more frames to reach `t=0.5`, but the trigger there still fires at that position.

4. **Trigger repeat on looped paths — RESOLVED**: The trigger queue **resets at
   t=0 each loop**. All triggers re-arm. This guarantees repeatability and keeps
   state reasoning outside the path format where it belongs. Any "fire once across
   the whole boss fight" logic lives in the game state machine, not here.

5. **Cinematic-specific tracks**: See Open Questions below — needs one more
   clarification before resolving.

6. **Extensible track list — RESOLVED**: The track namespace is open. Initial set
   defined below; anything not understood by a given consumer is silently ignored.
   Consumers (game engine, cinematic engine) only act on tracks they recognize.
   New tracks are added without format versioning. Confirmed additional candidates:
   - `shieldMode` → needs to be a trigger (discrete: `off | on | partial`)
   - `invuln` → trigger (`0 | 1`) — invulnerability window
   - `visible` → continuous track (`0..1`) — opacity, cloaking, dramatic reveals
   - `engineBrightness` → continuous track (`0..1`) — engine trail intensity
   - `speed` → continuous track (world-units/frame at 1:1; scales global speed)
     — renamed from `speedScale` for clarity; same meaning

---

## Open Questions

### Cinematic track namespace — RESOLVED

**Decision: Option C.** Camera sequences are just paths with `type=camera`.

A camera path is a fully valid `PathData` entry:
- `wps[]` define where the camera physically moves through space (can be empty
  for a static camera — single waypoint at the desired position)
- `orient=target:x,y,z` points the camera at a fixed subject
- `orient=path` makes the camera look along its direction of travel
- `speed` controls how fast the camera moves along its path
- Tracks like `fov`, `dof`, `bank` are camera-specific continuous values
- **No** `standoff`, `craftRoll`, `shieldMode`, `fireMode` — irrelevant fields
  are simply absent; consumers ignore what they don't understand

The game engine ignores `type=camera` entries entirely.
The cinematic engine runs multiple named paths simultaneously — craft paths and
camera paths alike — and assembles them into a scene.

Boss-fight paths have **no `type` field** (or `type=craft` by default). The
concept of "camera path" is not meaningful there and never appears.

**Format:**
```
[cutscene_intro_cam]
type=camera
speed=0.1
orient=target:0,20,0
closed=0

   0   30  -20
  10   25  -15

track: fov,  0.0, 60, linear
track: fov,  0.5, 90, smooth
track: fov,  1.0, 60, ease-out
track: bank, 0.2, 15, smooth
track: bank, 0.8,  0, smooth
```

**Data model:** `PathData` gains an optional `type` field:
```ts
type PathType = 'craft' | 'camera'   // default: 'craft'
```
Absent from file → parsed as `'craft'`. Old files are unaffected.

**Editor UX:** When `type=camera`, the editor hides craft-irrelevant controls
(standoff, fireMode, craftRoll panel) and surfaces camera-relevant track presets
(fov, dof, bank). Same ortho/persp views, same spline editing — just different
sidebar affordances. This is a future editor task; the format and data model are
the deliverable now.

---

## What's Explicitly NOT In Scope for the Path Format

- Compositing multiple paths (cinematic engine's job)
- Phase transition logic (game state machine)
- Player targeting logic (game references path, not vice versa)
- Dialogue / audio cues (separate system — don't interleave with path data)
- Multi-craft synchronization (orchestration layer above paths)

---

## Phased Implementation

### Phase 1 — Data model + format round-trip

- Extend `PathData`: add `type`, `tracks`, `triggers` (all default to empty/craft)
- Update `store.ts`: new actions `setTrack`, `addKeyframe`, `removeKeyframe`,
  `addTrigger`, `removeTrigger`, `patchTrigger`
- Update `format.ts`: parse + export `type=`, `track:`, `trigger:` lines
- Existing paths load and save correctly; no behavior on missing fields
- **No editor UI yet** — data round-trips cleanly through the file

### Phase 2 — Panel shell + spatial markers

- Add `behaviorsOpen` + `behaviorsHeight` to store (UI state, not undo-tracked)
- Add the bottom panel container to App.tsx layout: CSS grid row, drag handle
  for resize, toggle button/shortcut
- The panel is a self-contained store-connected component (BehaviorsPanel.tsx)
- Draw track keyframe markers (colored circles) and trigger markers (colored
  diamonds) along path curves in all four views
- Panel interior: read-only list of tracks and triggers, sorted by t
- This phase proves the spatial-to-panel connection before authoring exists

### Phase 3 — Full authoring UI

- Shared path ruler in panel, synced to animation scrubber (bidirectional)
- Track rows with draggable `◆` diamonds; click-to-add at scrubber position
- Keyframe inline popover: t, value, ease dropdown
- Trigger tick marks on ruler + editable event list below
- [+] menu: add track (name picker) or add trigger (type picker)
- Bi-directional hover highlight between views and panel

### Phase 4 — Game-side consumption (separate from editor, after Phase 3 is solid)

- QB64-PE parser extension: read `type=`, `track:`, `trigger:` lines
- Arc-length lookup table + track evaluator (lerp/ease per frame)
- Trigger queue: sorted by t, resets each loop
- Wire into boss behavior state machine
- Easing math goes through ExprForge DSL (emit to both TS and QB64-PE)

---

## Relationship to ExprForge

The easing math (`smoothstep`, cubic ease-in/out) is shared between the editor
(TypeScript) and the game (QB64-PE). Per the ExprForge contract, this math MUST
be expressed in the ExprForge DSL at `../../math/` and emitted to both targets.
Do NOT hand-write the lerp/ease functions in QB64 and TypeScript separately.

Add `easing.expr` to the math DSL and emit both `src/math/easing_gen.ts` and
the equivalent QB64-PE include.
