// Shortcut registry — single source of truth for keyboard shortcuts AND
// mouse/gesture interactions in Trailforge.
//
// HelpDialog renders this array directly, so it never drifts from reality.
// Entries with `match` + `handler` are wired globally in App.tsx's window listener.
// All other entries are documentation-only (mouse gestures, context-sensitive keys).

import { useStore } from './store'

export interface Shortcut {
  keys:         string    // human-readable display in help: "Ctrl+Z", "Alt+drag", "Scroll"
  desc:         string    // what it does — shown in help panel
  context:      string    // section grouping: "Global" | "Ortho views" | "3D view" | ...
  match?:       string    // "ctrl+z" | "b" | "ctrl+shift+z" — omit for doc-only entries
  fireInInput?: boolean   // if true, fires even when an <input> or <textarea> has focus
  handler?:     () => void  // action; only present when match is also present
}

export const SHORTCUTS: Shortcut[] = [

  // ── Global ───────────────────────────────────────────────────────────────
  { context: 'Global', keys: 'Ctrl+Z',      desc: 'Undo',
    match: 'ctrl+z',       fireInInput: true,
    handler: () => useStore.temporal.getState().undo() },

  { context: 'Global', keys: 'Ctrl+⇧Z',    desc: 'Redo',
    match: 'ctrl+shift+z', fireInInput: true,
    handler: () => useStore.temporal.getState().redo() },

  { context: 'Global', keys: 'B',           desc: 'Toggle behaviors panel',
    match: 'b',
    handler: () => { const s = useStore.getState(); s.setBehaviorsOpen(!s.behaviorsOpen) } },

  // Doc-only — handlers live in App.tsx (need component refs or local state)
  { context: 'Global', keys: 'F',           desc: 'Full-frame hovered pane (toggle back to restore)' },
  { context: 'Global', keys: 'L',           desc: 'Toggle linked ortho pan / zoom' },
  { context: 'Global', keys: 'Esc',         desc: 'Restore four-pane view' },
  { context: 'Global', keys: '?',           desc: 'Toggle this help dialog' },
  { context: 'Global', keys: '← / →',      desc: 'Step one frame (while paused)' },

  // ── Ortho views (Top · XZ / Side · XY / Front · YZ) ────────────────────
  { context: 'Ortho views', keys: 'Drag waypoint',        desc: 'Move waypoint in view plane' },
  { context: 'Ortho views', keys: 'Shift+drag (empty)',   desc: 'Marquee multi-select; then drag group' },
  { context: 'Ortho views', keys: 'Shift+click (empty)',  desc: 'Add waypoint at cursor' },
  { context: 'Ortho views', keys: 'Double-click (empty)', desc: 'Add waypoint at cursor' },
  { context: 'Ortho views', keys: 'Alt+drag',             desc: 'Rotate entire path around out-of-plane axis' },
  { context: 'Ortho views', keys: 'Ctrl+drag',            desc: 'Translate entire path in view plane' },
  { context: 'Ortho views', keys: 'Right drag / Mid drag',desc: 'Pan camera' },
  { context: 'Ortho views', keys: 'Scroll',               desc: 'Zoom' },
  { context: 'Ortho views', keys: 'Right-click waypoint', desc: 'Context menu: Edit Coords / Delete / Duplicate / Insert After' },
  { context: 'Ortho views', keys: 'Right-click empty',    desc: 'Add waypoint here' },
  { context: 'Ortho views', keys: 'Del / Backspace',      desc: 'Delete selected waypoint' },

  // ── 3D view ──────────────────────────────────────────────────────────────
  { context: '3D view', keys: 'Left drag',      desc: 'Orbit camera' },
  { context: '3D view', keys: 'Right drag',     desc: 'Pan camera' },
  { context: '3D view', keys: 'Scroll',         desc: 'Dolly / chase distance (follow mode)' },
  { context: '3D view', keys: 'Click waypoint', desc: 'Select waypoint' },
  { context: '3D view', keys: 'Camera button',  desc: 'Cycle camera: ORBIT → FOLLOW → IN-GAME' },

  // ── Behaviors panel ──────────────────────────────────────────────────────
  { context: 'Behaviors panel', keys: 'Drag ruler bar',      desc: 'Scrub animation position' },
  { context: 'Behaviors panel', keys: 'Click track bar',     desc: 'Add keyframe at click position' },
  { context: 'Behaviors panel', keys: 'Drag ◆',             desc: 'Move keyframe t (undo-safe)' },
  { context: 'Behaviors panel', keys: 'Click ◆ / row',      desc: 'Select — expand inline editor' },
  { context: 'Behaviors panel', keys: '+ Add',              desc: 'Add track or trigger at scrubber position' },
  { context: 'Behaviors panel', keys: 'Drag panel handle',  desc: 'Resize panel height' },

]

// ── Key matching ─────────────────────────────────────────────────────────────
// Matches a KeyboardEvent against a match string like "ctrl+z" or "ctrl+shift+z".
// Treats Ctrl and Meta (⌘) as interchangeable for cross-platform support.
export function matchesShortcut(e: KeyboardEvent, match: string): boolean {
  const parts = match.toLowerCase().split('+')
  const key   = parts[parts.length - 1]
  const ctrl  = parts.includes('ctrl')
  const shift = parts.includes('shift')
  const alt   = parts.includes('alt')
  return (
    e.key.toLowerCase()  === key  &&
    (e.ctrlKey || e.metaKey) === ctrl  &&
    Boolean(e.shiftKey)  === shift &&
    Boolean(e.altKey)    === alt
  )
}
