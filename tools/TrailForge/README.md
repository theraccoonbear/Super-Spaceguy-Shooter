# TrailForge

[![CI](https://github.com/theraccoonbear/TrailForge/actions/workflows/ci.yml/badge.svg)](https://github.com/theraccoonbear/TrailForge/actions/workflows/ci.yml)

A four-pane 3D spline path editor for Super Spaceguy Shooter. Lets you design and preview flight paths stored as individual `.mvr` files under `assets/maneuvers/`.

## Running

```bash
cd tools/TrailForge
npm install
npm run dev        # dev server at http://localhost:5173
npm run build      # production build → dist/
```

The Vite dev server hosts a `/api/maneuvers` REST API that reads and writes individual `.mvr` files under `assets/maneuvers/` — one file per route, atomic writes, no whole-file rewrites.

To migrate an existing `maneuvers.txt`: `node tools/migrate-maneuvers.js` from the repo root.

---

## Layout

| Pane | Axes shown | Controls |
|------|-----------|----------|
| **TOP · XZ** | X (forward) up, Z (lateral) right | Drag wp → move X/Z |
| **SIDE · XY** | X (forward) right, Y (altitude) up | Drag wp → move X/Y |
| **FRONT · YZ** | Z (lateral) right, Y (altitude) up | Drag wp → move Y/Z |
| **3D · ORBIT** | Full perspective | Click wp → select; camera mode button (top-right) |

Click the corner wedge on any pane to maximise/restore it. Press **Esc** to restore four-pane view.

---

## Mouse controls (ortho views)

| Action | Effect |
|--------|--------|
| Drag waypoint | Move in the view plane |
| Shift + drag wp | Constrain to dominant axis |
| Alt + drag (anywhere) | Rotate entire path around the out-of-plane axis |
| Ctrl + drag (anywhere) | Translate entire path in the view plane |
| Right-drag (empty) | Pan camera |
| Scroll | Zoom |
| Double-click (empty) | Add waypoint at cursor |
| Shift + left-click (empty) | Add waypoint at cursor |
| Right-click waypoint | Context menu: Edit Coords / Delete / Duplicate / Insert After |
| Right-click empty | Context menu: Add Waypoint Here |
| Del / Backspace | Delete selected waypoint |

---

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |
| `←` / `→` | Step one frame back/forward (only while paused) |
| `L` | Toggle linked ortho pan/zoom |
| `Esc` | Restore four-pane view |
| `?` | Open help dialog |

---

## Toolbar

| Control | Description |
|---------|-------------|
| **Name** | Route name as it appears in `maneuvers.txt` |
| **Speed** | World-unit/frame speed (arc-length correct — constant regardless of node spacing) |
| **Orient** | PATH-FOLLOWING = nose follows the curve; FIXED TARGET = nose always faces the target point |
| **Closed** | Loop the path back to the first waypoint |
| **▶ Play / ■ Stop** | Start/stop animation |
| **↺ Reset** | Stop and rewind to t=0 |
| **LINKED / FREE** | Sync or decouple pan/zoom across ortho views |
| **GAME CTX** | Show/hide gameplay overlays (reference ship, camera, frustum, scale planes) |
| **DBG LOG** | Stream per-frame position, forward, R, U vectors to the browser console |

---

## Sidebar tabs

### Waypoints (WPs)
Lists every waypoint with X/Y/Z coordinate inputs.

**Buttons:**
- `+ Add` — insert after the selected node (or append)
- `✕ Del` — delete selected
- `⊕ Dup` — duplicate selected
- `⬡ Gen` — open shape generator (circle, ellipse, figure-8, helix, arc)

### Routes
Connects to `assets/maneuvers/` via the dev-server REST API. Load/save named `.mvr` routes directly. Only available when `npm run dev` is running.

### I / O
Export/import the current path as JSON, or clear to defaults.

---

## 3D view camera modes

Cycle with the button in the top-right corner of the 3D pane:

| Mode | Behaviour |
|------|-----------|
| **ORBIT** | Standard trackball camera; drag to rotate, scroll to zoom |
| **FOLLOW** | Chase cam trailing the ship; scroll adjusts follow distance |
| **IN-GAME** | Fixed at the game's actual camera position, looking along +X |

---

## Shape generator (`⬡ Gen`)

Opens a dialog to replace the current waypoints with a geometric shape:

| Shape | Parameters |
|-------|-----------|
| Circle | N points, radius, center, plane (XZ/XY/YZ) |
| Ellipse | N points, radius A, radius B, center, plane |
| Figure-8 | N points, radius, center, plane (Lemniscate of Gerono) |
| Helix | N points, radius, length, turns, center (always along X axis) |
| Arc | N points, radius, arc angle, center, plane |

---

## .mvr file format

See [`maneuver-format.md`](maneuver-format.md) for the full specification.
Each file holds one named route: a `[name]` header, `key=value` settings,
whitespace-separated `X Y Z` waypoint lines, and optional `track:`,
`trigger:`, `craftroll:`, `loopseam:` behavior lines.
