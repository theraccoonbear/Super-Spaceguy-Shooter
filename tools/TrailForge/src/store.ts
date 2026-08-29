import { create } from 'zustand'
import { temporal } from 'zundo'
import { Vec3, Waypoint } from './math/vec3'
import { CraftRollSegment, CraftRollLoopSeam } from './math/craftRoll'
import { ScalarSegment, SegmentLoopSeam } from './math/segmentTrack'
import { uiPrefs, saveUIPrefs } from './prefs'

export type { Waypoint }
export type { CraftRollSegment, CraftRollLoopSeam }
export type { ScalarSegment, SegmentLoopSeam }
export type OrientMode = 'path' | 'target'

/** 'craft' = a flight path for a ship (default, backward-compat).
 *  'camera' = a cinematic camera path; ignored by the game engine. */
export type PathType = 'craft' | 'camera'

export type FireMode = 'off' | 'on' | 'target' | 'willful'
export type ShieldMode = 'off' | 'on' | 'partial'

export type TriggerEvent =
  | { type: 'fireMode';  mode:  FireMode }
  | { type: 'weapon';    name:  string }
  | { type: 'shieldMode'; mode: ShieldMode }
  | { type: 'invuln';    value: 0 | 1 }
  | { type: 'phase';     tag:   string }
  | { type: 'sound';     name:  string; volume: number; loop: boolean }
  | { type: 'custom';    tag:   string; value: string }

/** A discrete event that fires when the craft crosses position t (0..1 arc-length). */
export interface PathTrigger {
  t:     number
  event: TriggerEvent
}

export interface PathData {
  name:     string
  /** Omitted in file = 'craft'. Old paths default to 'craft'. */
  type:     PathType
  speed:    number
  orient:   OrientMode
  target:   Vec3
  closed:   boolean
  wps:      Waypoint[]
  /** Discrete events fired when craft crosses position t. Sorted by t. */
  triggers: PathTrigger[]
  /** Segment-based craft roll authoring. */
  craftRollSegments: CraftRollSegment[]
  /** Loop-point seam: smoothly closes the roll angle gap when the path loops.
   *  null = no seam (may produce a snap at the loop point if roll angle ≠ 0 at end). */
  craftRollLoopSeam: CraftRollLoopSeam | null
  /** Named continuous behavior tracks — same span/ease/hold model as craftRoll,
   *  keyed by track name. Key = track name, value = segments sorted by t.
   *  Empty object ({}) when no tracks are defined. */
  segmentTracks: Record<string, ScalarSegment[]>
  /** Per-track loop-point seam, same purpose as craftRollLoopSeam. Key = track name. */
  segmentLoopSeams: Record<string, SegmentLoopSeam | null>
}

export type PaneName = 'top' | 'side' | 'front' | 'persp'

/** Which behavior item (track row or trigger) is currently highlighted, either
 *  by hovering a row in the panel or a spatial marker in an ortho view.
 *  UI-only state — NOT tracked in undo history. */
export type HoveredBehavior =
  | { type: 'track';     name:  string }
  | { type: 'trigger';   index: number }
  | { type: 'craftRoll' }
  | null

export interface EditorState {
  path:     PathData
  selected: number
  /** Indices of waypoints in the current marquee/multi-selection. Empty = single-select mode. */
  multiSel: number[]
  playing:  boolean
  animT:    number
  frameR:   Vec3
  frameU:   Vec3
  status:   string
  debugLog: boolean

  setPath:         (p: PathData) => void
  patchPath:       <K extends keyof PathData>(key: K, value: PathData[K]) => void
  setWp:           (i: number, wp: Waypoint) => void
  replaceWps:      (wps: Waypoint[]) => void
  addWp:           (wp: Vec3, after?: number) => void
  delWp:           (i: number) => void
  dupWp:           (i: number) => void
  setSelected:     (i: number) => void
  setMultiSel:     (indices: number[]) => void
  setPlaying:      (v: boolean) => void
  setAnimT:        (v: number) => void
  setPlayState:    (animT: number, frameR: Vec3, frameU: Vec3) => void
  setStatus:       (s: string) => void
  setDebugLog:     (v: boolean) => void
  showOverlays:    boolean
  setShowOverlays: (v: boolean) => void
  maximizedPane:    PaneName | null
  setMaximizedPane: (pane: PaneName | null) => void
  /** Ghost snapshot shown in all views while the node-edit dialog is open. */
  editGhost: { path: PathData; wpIdx: number } | null
  setEditGhost: (g: { path: PathData; wpIdx: number } | null) => void

  // ── Craft roll segment actions ────────────────────────────────────────────
  setCraftRollSegments:    (segs: CraftRollSegment[]) => void
  addCraftRollSegment:     (seg: CraftRollSegment) => void
  updateCraftRollSegment:  (id: string, patch: Partial<CraftRollSegment>) => void
  removeCraftRollSegment:  (id: string) => void
  // ── Craft roll loop seam actions ──────────────────────────────────────────
  setLoopSeam:             (seam: CraftRollLoopSeam | null) => void
  updateLoopSeam:          (patch: Partial<CraftRollLoopSeam>) => void

  // ── Generic segment-track actions (standoff, speed, offsetAngle, etc.) ────
  /** Replace all segments for a named track. Empty array removes the track. */
  setSegmentTrack:    (name: string, segs: ScalarSegment[]) => void
  addSegment:         (name: string, seg: ScalarSegment) => void
  updateSegment:      (name: string, id: string, patch: Partial<ScalarSegment>) => void
  removeSegment:      (name: string, id: string) => void
  // ── Generic segment-track loop seam actions ───────────────────────────────
  setSegmentLoopSeam:    (name: string, seam: SegmentLoopSeam | null) => void
  updateSegmentLoopSeam: (name: string, patch: Partial<SegmentLoopSeam>) => void

  /** Reverse the waypoint order, mirroring trigger t-values so spatial positions stay
   *  consistent (t_new = 1 − t_old after direction flip). Segment tracks (craftRoll and
   *  the generic segment tracks) are NOT mirrored here — a pre-existing gap, tracked
   *  identically across every segment track rather than fixed ad hoc for just one. */
  reverseWps: () => void

  // ── Trigger event actions ─────────────────────────────────────────────────
  /** Insert a trigger, keeping the list sorted by t. */
  addTrigger:    (trigger: PathTrigger) => void
  /** Replace one trigger by index. Re-sorts by t afterward. */
  updateTrigger: (index: number, trigger: PathTrigger) => void
  /** Remove one trigger by index. */
  removeTrigger: (index: number) => void

  // ── Behaviors panel UI state (NOT undo-tracked) ───────────────────────────
  behaviorsOpen:   boolean
  behaviorsHeight: number   // px; user-resized via drag handle
  setBehaviorsOpen:   (v: boolean) => void
  setBehaviorsHeight: (v: number) => void

  /** Highlighted behavior item — set by hovering a panel row OR a spatial marker in any view. */
  hoveredBehavior:    HoveredBehavior
  setHoveredBehavior: (h: HoveredBehavior) => void

  /** Set of track names whose effect is suppressed during preview (eye-toggle mute).
   *  UI-only, not persisted, not undo-tracked. */
  mutedTracks:       Record<string, boolean>
  toggleMutedTrack:  (name: string) => void

  /** Which behavior track is currently expanded/active in BehaviorsPanel.
   *  Ortho views use this to dim non-active track markers. UI-only, not undo-tracked. */
  activeBehaviorTrack:    string | null
  setActiveBehaviorTrack: (name: string | null) => void
}

function makeWp(x: number, y: number, z: number): Waypoint {
  return { x, y, z }
}

const DEFAULT_PATH: PathData = {
  name:     'new_path',
  type:     'craft',
  speed:    0.025,
  orient:   'path',
  target:   { x: 0, y: 6, z: 0 },  // offset from origin so it's visible when orient='target'
  closed:   true,
  wps: [
    makeWp( 20,  0,  0),
    makeWp(  8,  1,  3),
    makeWp( -5,  1,  6),
    makeWp( -8,  0,  5),
    makeWp( -5, -1,  2),
    makeWp(  8,  0,  2),
  ],
  triggers:          [],
  craftRollSegments: [],
  craftRollLoopSeam: null,
  segmentTracks:     {},
  segmentLoopSeams:  {},
}

function ensureWp(wp: Vec3): Waypoint {
  return { x: wp.x ?? 0, y: wp.y ?? 0, z: wp.z ?? 0 }
}

/** Fill in fields added after the initial release so old localStorage / file
 *  data loads cleanly without crashing. */
function migratePath(p: Partial<PathData>): PathData {
  return {
    ...DEFAULT_PATH,
    ...p,
    type:              (p.type ?? 'craft') as PathType,
    triggers:          Array.isArray(p.triggers)          ? p.triggers          : [],
    craftRollSegments: Array.isArray(p.craftRollSegments) ? p.craftRollSegments : [],
    craftRollLoopSeam: p.craftRollLoopSeam ?? null,
    segmentTracks:     (p.segmentTracks && typeof p.segmentTracks === 'object' && !Array.isArray(p.segmentTracks))
      ? p.segmentTracks : {},
    segmentLoopSeams:  (p.segmentLoopSeams && typeof p.segmentLoopSeams === 'object' && !Array.isArray(p.segmentLoopSeams))
      ? p.segmentLoopSeams : {},
  }
}

function normalizePath(p: PathData): PathData {
  let wps = p.wps.map(ensureWp)
  if (p.closed && wps.length >= 2) {
    const first = wps[0], last = wps[wps.length - 1]
    const eps = 0.001
    if (Math.abs(first.x - last.x) < eps &&
        Math.abs(first.y - last.y) < eps &&
        Math.abs(first.z - last.z) < eps) {
      wps = wps.slice(0, -1)
    }
  }
  return { ...p, wps }
}

function sortByT<T extends { t: number }>(arr: T[]): T[] {
  return [...arr].sort((a, b) => a.t - b.t)
}

function load(): PathData {
  try {
    const raw = localStorage.getItem('trailforge:session')
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<PathData>
      if ('roll' in parsed) delete (parsed as Record<string, unknown>).roll
      return normalizePath(migratePath(parsed))
    }
  } catch { /* ignore */ }
  return DEFAULT_PATH
}

function save(p: PathData) {
  try { localStorage.setItem('trailforge:session', JSON.stringify(p)) } catch { /* ignore */ }
}

export const useStore = create<EditorState>()(
  temporal(
    (set) => ({
      path:     load(),
      selected: -1,
      multiSel: [],
      playing:  false,
      animT:    0,
      frameR:   { x: 1, y: 0, z: 0 },
      frameU:   { x: 0, y: 0, z: 1 },
      status:   'session restored',
      debugLog: uiPrefs.debugLog,

      setPath: (p) => {
        const path = normalizePath(p)
        save(path)
        set({ path, status: 'loaded' })
      },

      patchPath: (key, value) => set((s) => {
        let path: PathData = { ...s.path, [key]: value }
        if (key === 'closed') path = normalizePath(path)
        save(path)
        return { path, status: 'modified' }
      }),

      setWp: (i, wp) => set((s) => {
        const wps = [...s.path.wps]
        wps[i] = ensureWp(wp)
        const path = { ...s.path, wps }
        save(path)
        return { path, status: 'modified' }
      }),

      replaceWps: (wps) => set((s) => {
        const path = { ...s.path, wps: wps.map(ensureWp) }
        save(path)
        return { path, status: 'modified' }
      }),

      addWp: (wp, after) => set((s) => {
        const wps = [...s.path.wps]
        const fullWp = ensureWp(wp)
        const idx = after !== undefined ? after + 1 : wps.length
        wps.splice(idx, 0, fullWp)
        const path = { ...s.path, wps }
        save(path)
        return { path, selected: idx, status: `added waypoint ${idx}` }
      }),

      delWp: (i) => set((s) => {
        const wps = s.path.wps.filter((_, j) => j !== i)
        const path = { ...s.path, wps }
        save(path)
        return { path, selected: -1, status: `deleted waypoint ${i}` }
      }),

      dupWp: (i) => set((s) => {
        const wps = [...s.path.wps]
        wps.splice(i + 1, 0, { ...wps[i] })
        const path = { ...s.path, wps }
        save(path)
        return { path, selected: i + 1, status: `duplicated waypoint ${i}` }
      }),

      setSelected:     (i) => set({ selected: i }),
      setMultiSel:     (indices) => set({ multiSel: indices }),
      setPlaying:      (v) => set({ playing: v }),
      setAnimT:        (v) => set({ animT: v }),
      setPlayState:    (animT, frameR, frameU) => set({ animT, frameR, frameU }),
      setStatus:       (s) => set({ status: s }),
      setDebugLog:     (v) => { saveUIPrefs({ debugLog: v }); set({ debugLog: v }) },
      showOverlays:    uiPrefs.showOverlays,
      setShowOverlays: (v) => { saveUIPrefs({ showOverlays: v }); set({ showOverlays: v }) },
      maximizedPane:    null,
      setMaximizedPane: (pane) => set({ maximizedPane: pane }),
      editGhost:    null,
      setEditGhost: (g) => set({ editGhost: g }),

      // ── Craft roll segment actions ──────────────────────────────────────
      setCraftRollSegments: (segs) => set((s) => {
        const path = { ...s.path, craftRollSegments: segs }
        save(path); return { path }
      }),
      addCraftRollSegment: (seg) => set((s) => {
        const craftRollSegments = sortByT([...s.path.craftRollSegments, seg])
        const path = { ...s.path, craftRollSegments }
        save(path); return { path }
      }),
      updateCraftRollSegment: (id, patch) => set((s) => {
        const craftRollSegments = sortByT(
          s.path.craftRollSegments.map(seg => seg.id === id ? { ...seg, ...patch } : seg)
        )
        const path = { ...s.path, craftRollSegments }
        save(path); return { path }
      }),
      removeCraftRollSegment: (id) => set((s) => {
        const craftRollSegments = s.path.craftRollSegments.filter(seg => seg.id !== id)
        const path = { ...s.path, craftRollSegments }
        save(path); return { path }
      }),

      // ── Craft roll loop seam actions ─────────────────────────────────────
      setLoopSeam: (seam) => set((s) => {
        const path = { ...s.path, craftRollLoopSeam: seam }
        save(path); return { path }
      }),
      updateLoopSeam: (patch) => set((s) => {
        if (!s.path.craftRollLoopSeam) return {}
        const path = { ...s.path, craftRollLoopSeam: { ...s.path.craftRollLoopSeam, ...patch } }
        save(path); return { path }
      }),

      // ── Generic segment-track actions ─────────────────────────────────────
      setSegmentTrack: (name, segs) => set((s) => {
        const segmentTracks = { ...s.path.segmentTracks }
        if (segs.length === 0) delete segmentTracks[name]
        else segmentTracks[name] = sortByT(segs)
        const path = { ...s.path, segmentTracks }
        save(path); return { path }
      }),
      addSegment: (name, seg) => set((s) => {
        const existing = s.path.segmentTracks[name] ?? []
        const segmentTracks = { ...s.path.segmentTracks, [name]: sortByT([...existing, seg]) }
        const path = { ...s.path, segmentTracks }
        save(path); return { path }
      }),
      updateSegment: (name, id, patch) => set((s) => {
        const existing = s.path.segmentTracks[name] ?? []
        const segmentTracks = {
          ...s.path.segmentTracks,
          [name]: sortByT(existing.map(seg => seg.id === id ? { ...seg, ...patch } : seg)),
        }
        const path = { ...s.path, segmentTracks }
        save(path); return { path }
      }),
      removeSegment: (name, id) => set((s) => {
        const existing = (s.path.segmentTracks[name] ?? []).filter(seg => seg.id !== id)
        const segmentTracks = { ...s.path.segmentTracks }
        if (existing.length === 0) delete segmentTracks[name]
        else segmentTracks[name] = existing
        const path = { ...s.path, segmentTracks }
        save(path); return { path }
      }),

      // ── Generic segment-track loop seam actions ───────────────────────────
      setSegmentLoopSeam: (name, seam) => set((s) => {
        const segmentLoopSeams = { ...s.path.segmentLoopSeams, [name]: seam }
        const path = { ...s.path, segmentLoopSeams }
        save(path); return { path }
      }),
      updateSegmentLoopSeam: (name, patch) => set((s) => {
        const cur = s.path.segmentLoopSeams[name]
        if (!cur) return {}
        const segmentLoopSeams = { ...s.path.segmentLoopSeams, [name]: { ...cur, ...patch } }
        const path = { ...s.path, segmentLoopSeams }
        save(path); return { path }
      }),

      reverseWps: () => set((s) => {
        const wps = [...s.path.wps].reverse()
        // Mirror trigger t-values: t_new = 1 - t_old, re-sort ascending
        const triggers = s.path.triggers
          .map(tr => ({ ...tr, t: 1 - tr.t }))
          .sort((a, b) => a.t - b.t)
        const path = { ...s.path, wps, triggers }
        save(path)
        return { path, status: 'path direction reversed' }
      }),

      // ── Trigger event actions ───────────────────────────────────────────
      addTrigger: (trigger) => set((s) => {
        const triggers = sortByT([...s.path.triggers, trigger])
        const path = { ...s.path, triggers }
        save(path)
        return { path }
      }),

      updateTrigger: (index, trigger) => set((s) => {
        const triggers = sortByT(
          s.path.triggers.map((tr, i) => i === index ? trigger : tr)
        )
        const path = { ...s.path, triggers }
        save(path)
        return { path }
      }),

      removeTrigger: (index) => set((s) => {
        const triggers = s.path.triggers.filter((_, i) => i !== index)
        const path = { ...s.path, triggers }
        save(path)
        return { path }
      }),

      // ── Behaviors panel UI state (NOT undo-tracked) ─────────────────────
      behaviorsOpen:      uiPrefs.behaviorsOpen,
      behaviorsHeight:    uiPrefs.behaviorsHeight,
      setBehaviorsOpen:   (v) => { saveUIPrefs({ behaviorsOpen: v }); set({ behaviorsOpen: v }) },
      setBehaviorsHeight: (v) => { saveUIPrefs({ behaviorsHeight: v }); set({ behaviorsHeight: v }) },
      hoveredBehavior:    null,
      setHoveredBehavior: (h) => set({ hoveredBehavior: h }),

      mutedTracks:      {},
      toggleMutedTrack: (name) => set((s) => {
        const mutedTracks = { ...s.mutedTracks }
        if (mutedTracks[name]) delete mutedTracks[name]
        else mutedTracks[name] = true
        return { mutedTracks }
      }),

      activeBehaviorTrack:    null,
      setActiveBehaviorTrack: (name) => set({ activeBehaviorTrack: name }),
    }),
    {
      limit: 100,
      // Only track path changes in undo history; skip animation / UI state.
      partialize: (state) => ({ path: state.path }),
      // Path is always a new object reference after any real edit (patchPath/setWp/etc.
      // use spread). Reference equality skips the flood of setPlayState ticks (which
      // don't touch path) so the ring doesn't fill with identical snapshots.
      equality: (a, b) => a.path === b.path,
    }
  )
)

// Keep localStorage in sync after undo/redo (which bypasses the action save() calls).
useStore.subscribe((state, prev) => {
  if (state.path !== prev.path) save(state.path)
})
