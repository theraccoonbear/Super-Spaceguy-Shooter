# Path Behavior System — Design Plan

Status: **Implemented.** Tier 2 below (segment tracks + discrete triggers) reflects
the current `store.ts`/`math/segmentTrack.ts`/`math/craftRoll.ts`/`io/format.ts`
implementation, not just a proposal. The "Phased Implementation," "Resolved
Questions," and cinematic-track sections further down are historical design
record from before the segment-track model existed — read them for context on
*why*, not as a spec for *what's currently there*.  
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

### Tier 2 — Behavior overlay

**Exactly two categories.** Every current and future behavioral timeline
belongs to one or the other and inherits that category's full interaction
contract — canvas rendering, hit-testing/drag mechanics, add/delete UX, value
editing, and (optionally) loop-seam behavior. No per-item special-casing of
*interaction mechanics* is allowed; only the domain-specific value/glyph may
differ between members of a category (e.g. craftRoll's degrees+direction
fields vs. a scalar track's plain value field — same drag zones, same ease
model, same everything else).

#### A. Segment tracks (continuous)

A named array of **spans**, not points. Each segment covers `[t, t+duration)`
and eases the accumulated value toward a target over that span; the value
**holds** at whatever it arrived at between segments (and before the first /
after the last one, where it holds at 0). This is the same mechanics for
every segment track — implemented once in `math/segmentTrack.ts`'s
`evalGenericSegments()` / shared `SegmentTrackRow`-style panel UI /
`behaviorMarkers.ts` rendering+drag — and reused, not duplicated, by each
member:

```
Segment (generic shape; craftRoll's is its own domain-specific variant — see below)
  id:       string                stable id, not persisted (regenerated on file load)
  t:        number (0..1)         arc-length fraction where the segment begins
  duration: number (0..1)         arc-length extent (min 0.005)
  value:    number                relative: signed delta · absolute: target value (no wraparound)
  mode:     'relative' | 'absolute'
  ease:     'linear' | 'in' | 'out' | 'in-out'
```

`craftRoll` is the reference member of this category and predates the
generic engine — it keeps its own domain-specific fields (`degrees`,
`direction: 'cw'|'ccw'`) instead of a plain signed `value`, because absolute
mode needs a real "which way around" bit independent of the target angle
(mod-360 wraparound has no equivalent for a non-circular scalar like
standoff). Every other segment track uses the plain `value`/`mode` shape
above. Both plug into the same shared engine via a small `computeTarget`
adapter — see `math/craftRoll.ts`.

**Interaction contract (identical for every segment track):**
- Add: right-click empty ruler → "Add segment here", or **N** when the track
  is expanded (adds at the playhead). **Never** click-to-add — accidental
  clicks on the timeline must never create a segment.
- Select: click the segment block body.
- Move: drag the block body (changes `t` only).
- Resize: drag the left/right edge handles (changes `t`+`duration` or
  `duration` alone).
- Delete: right-click → "Delete segment", or select + Del in the expanded editor.
- Value editing: **NumInput only, never by dragging or mouse-wheel.**
- Canvas (ortho-view) drag: same body/left-edge/right-edge zones as the panel
  ruler, projected onto the wire — see "Canvas Interaction" below.
- Optional loop seam (⟲, only offered when the path is closed): eases the
  value from wherever the regular segments left it at `1−tailFrac` toward a
  `targetValue`, across `[1−tailFrac, 1]` and `[0, headFrac]`, so a looped
  pass starts identically every time. One seam per track, generic shape:
  `{ tailFrac, headFrac, ease, targetValue }` (craftRoll's is the same shape
  with `targetAngle` instead of `targetValue`, for the same historical reason
  as its segment fields above).

**Named segment tracks:**

| Track name        | Units       | Overrides                 | Notes |
|--------------------|-------------|---------------------------|-------|
| `craftRoll`       | degrees     | wp-interpolated craftRoll | visual roll of ship model; reference implementation of this category |
| `standoff`        | world units | global `standoff` field   | distance of craft from wire curve |
| `offsetAngle`     | degrees     | (none currently)          | rotates standoff offset vector around spline tangent; 0=up, 90=left |
| `speed`           | multiplier (×) | global `speed` field   | scales travel speed; use to make craft slow/accelerate at specific path positions. Note: with no segment active yet, the accumulated value is 0 (not 1×) — the craft doesn't move until the first speed segment fires, same as craftRoll holds at 0° before its first segment. This is the segment model's accumulate-from-zero semantics applied consistently, not a per-track special case. |
| `visible`         | 0..1        | (none)                    | craft opacity; 0=fully cloaked, 1=fully visible |
| `engineBrightness`| 0..1        | (none)                    | engine trail/glow intensity; visual only |

System is open — any string name is valid (`+ Add` → custom name…).
Consumers silently ignore names they don't understand.

#### B. Discrete triggers

An event list. Each trigger fires exactly once when the craft crosses its `t`
position (a single point, not a span). Order within a `t` is FIFO (insertion
order). Events do not lerp — there is no "value between two triggers."

```
Trigger
  .t:     number (0..1)
  .event: TriggerEvent (union)
```

**Interaction contract (identical for every trigger type — implemented once
in `TriggerTypeRow`, one row per type):**
- Add: right-click the type's ruler bar → places a new instance there.
- Select: click the marker (or the row, which selects the nearest instance).
- Move: drag the marker — 1D, `t` only (in the panel's position-scrub bar, or
  on the canvas via the same nearest-point-on-curve mechanics segment tracks
  use).
- Delete: the expanded editor's "Del evt" button, or the row's × to clear all
  instances of that type.
- Value editing: a type-specific widget (dropdown, text field, etc. — see
  `TriggerValueEditor`) — this is the *only* thing that varies between
  trigger types.

**Trigger event types:**

| type        | fields              | Meaning |
|-------------|---------------------|---------|
| `fireMode`  | `mode`              | `off` \| `on` \| `target` \| `willful` — "target" fires only when player is in arc; "willful" fires at will regardless |
| `weapon`    | `name`              | switch to named weapon (string key; game maps to actual weapon) |
| `shieldMode`| `mode`              | `off` \| `on` \| `partial` — boss shield state change |
| `invuln`    | `value`             | `0` \| `1` — invulnerability window close/open |
| `phase`     | `tag`               | signal the game state machine; game interprets meaning |
| `sound`     | `name`, `volume`, `loop` | trigger a sound cue |
| `custom`    | `tag`, `value`      | forward-compat escape hatch; both are strings |

More types added as needed. The `custom` type means we never need to
version-bump the format just to add a one-off game signal.

### Canvas Interaction (ortho views)

Both categories support click-and-drag directly on the 3D/ortho spline
curve, not just in the Behaviors panel — mirroring the panel's own
mechanics exactly (segment tracks: body/left-edge/right-edge zones,
`t`+`duration` only; triggers: `t` only). This is implemented once in
`views/behaviorMarkers.ts` (`hitTestBehaviors()`, `nearestArcFracOnScreen()`)
and wired identically into `TopView`, `SideView`, `FrontView` — not
duplicated per view. `nearestArcFracOnScreen()` is the screen-point → `t`
inverse of `wireAtFrac()`, used to convert cursor position into an
arc-length delta during a drag. PerspView remains read-only, consistent with
its existing "all editing happens in ortho views" design.

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

// ── Segment tracks (math/segmentTrack.ts) ──────────────────────────────────
type SegEase = 'linear' | 'in' | 'out' | 'in-out'

interface ScalarSegment {
  id:       string
  t:        number             // 0..1 arc-length fraction — start
  duration: number              // 0..1 arc-length fraction — extent, min 0.005
  value:    number              // relative: signed delta · absolute: target
  mode:     'relative' | 'absolute'
  ease:     SegEase
}

interface SegmentLoopSeam {
  tailFrac:    number           // [0, 0.45]
  headFrac:    number           // [0, 0.45]
  ease:        SegEase
  targetValue: number
}

// craftRoll's own segment shape (math/craftRoll.ts) — same mechanics, its
// own domain fields instead of a plain signed value (see Tier 2A above)
interface CraftRollSegment {
  id: string; t: number; duration: number
  degrees: number; direction: 'cw' | 'ccw'
  mode: 'relative' | 'absolute'; ease: SegEase
}
interface CraftRollLoopSeam {
  tailFrac: number; headFrac: number; ease: SegEase; targetAngle: number
}

// ── Discrete triggers ───────────────────────────────────────────────────────
type FireMode   = 'off' | 'on' | 'target' | 'willful'
type ShieldMode = 'off' | 'on' | 'partial'

type TriggerEvent =
  | { type: 'fireMode';   mode: FireMode }
  | { type: 'weapon';     name: string }
  | { type: 'shieldMode'; mode: ShieldMode }
  | { type: 'invuln';     value: 0 | 1 }
  | { type: 'phase';      tag: string }
  | { type: 'sound';      name: string; volume: number; loop: boolean }
  | { type: 'custom';     tag: string; value: string }

interface PathTrigger {
  t:     number
  event: TriggerEvent
}

// PathData (src/store.ts)
interface PathData {
  name:     string
  type:     PathType                                  // default 'craft'; absent = 'craft'
  speed:    number
  orient:   'path' | 'target'
  target:   Vec3
  closed:   boolean
  wps:      Waypoint[]
  triggers:          PathTrigger[]                     // [] when no triggers
  craftRollSegments: CraftRollSegment[]                 // [] when no roll segments
  craftRollLoopSeam: CraftRollLoopSeam | null
  segmentTracks:     Record<string, ScalarSegment[]>    // {} when no tracks
  segmentLoopSeams:  Record<string, SegmentLoopSeam | null>
}
```

`triggers`, `craftRollSegments`, and `segmentTracks` default to empty;
existing paths without them parse identically. Segment `id`s are UI-only
(React keys + drag tracking) — they are **not** persisted in the `.mvr`
format and are regenerated randomly on every file load.

---

## File Format Extension

The existing parser silently skips any line that doesn't match `[header]`,
`key=value` (alphanumeric key only), or "all numbers". New line prefixes are
therefore backward-compatible — old parsers ignore them.

**Line types (current, `io/format.ts`):**

```
segment: <name>, <t>, <duration>, <value>, <mode>, <ease>     — scalar segment tracks
segseam: <name>, <tailFrac>, <headFrac>, <targetValue>, <ease> — their loop seams
craftroll: <t>, <duration>, <degrees>, <direction>, <mode>, <ease>  — craftRoll (own line, own fields)
loopseam: <tailFrac>, <headFrac>, <targetAngle>, <ease>             — craftRoll's own seam
trigger: <t>, <eventType>, <args...>
```

craftRoll keeps distinct `craftroll:`/`loopseam:` lines (no `<name>` column —
the line prefix itself is the identity) rather than the generic `segment:`/
`segseam:` shape, matching its own domain-specific field set from Tier 2A.

Example:
```
[boss_sweep]
speed=0.25
orient=target:0,20,0
closed=0

  10   0   0
  25   8  15
  40   0   0

segment: standoff, 0.00, 0.20,  8, absolute, linear
segment: standoff, 0.50, 0.20, 18, absolute, ease-in
craftroll: 0.00, 0.30, 45, cw, relative, in-out
craftroll: 0.70, 0.15, 30, ccw, relative, in-out
trigger: 0.05, fireMode, on
trigger: 0.55, fireMode, target
trigger: 0.95, fireMode, off
```

**Trigger event serialization:**

| type       | wire format |
|------------|-------------|
| fireMode   | `trigger: 0.1, fireMode, on` |
| weapon     | `trigger: 0.2, weapon, spreadshot` |
| shieldMode | `trigger: 0.3, shieldMode, partial` |
| invuln     | `trigger: 0.4, invuln, 1` |
| phase      | `trigger: 0.5, phase, angry` |
| sound      | `trigger: 0.6, sound, klaxon, 1, 0` |
| custom     | `trigger: 0.8, custom, myTag, myValue` |

The `custom` and `sound` types take multiple trailing args; the rest take
one. Parser splits on `, ` (comma-space) after the t field.

No file-format back-compat is maintained for the old point-keyframe `track:`
line — there are no external consumers of `.mvr` yet, so it was replaced
outright rather than migrated.

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
