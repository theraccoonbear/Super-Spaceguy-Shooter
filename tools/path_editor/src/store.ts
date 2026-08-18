import { create } from 'zustand'
import { temporal } from 'zundo'
import { Vec3, Waypoint } from './math/vec3'

export type { Waypoint }
export type OrientMode = 'path' | 'target'

/** 'craft' = a flight path for a ship (default, backward-compat).
 *  'camera' = a cinematic camera path; ignored by the game engine. */
export type PathType = 'craft' | 'camera'

/** Easing applied from this keyframe outward toward the next one.
 *  'instant' = hold value until the next keyframe, then snap. */
export type EaseType = 'linear' | 'smooth' | 'ease-in' | 'ease-out' | 'instant'

/** One keyframe in a continuous behavior track. t is arc-length fraction 0..1. */
export interface TrackKeyframe {
  t:     number
  value: number
  ease:  EaseType
}

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
  standoff: number
  wps:      Waypoint[]
  /** Named continuous behavior tracks. Key = track name, value = keyframes sorted by t.
   *  Empty object ({}) when no tracks are defined. */
  tracks:   Record<string, TrackKeyframe[]>
  /** Discrete events fired when craft crosses position t. Sorted by t. */
  triggers: PathTrigger[]
}

export type PaneName = 'top' | 'side' | 'front' | 'persp'

/** Which behavior item (track row or trigger) is currently highlighted, either
 *  by hovering a row in the panel or a spatial marker in an ortho view.
 *  UI-only state — NOT tracked in undo history. */
export type HoveredBehavior =
  | { type: 'track';   name:  string }
  | { type: 'trigger'; index: number }
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

  // ── Behavior track actions ────────────────────────────────────────────────
  /** Replace all keyframes for a named track. Empty array removes the track. */
  setTrack:       (name: string, frames: TrackKeyframe[]) => void
  /** Insert a keyframe into a track, keeping the track sorted by t. Creates track if absent. */
  addKeyframe:    (trackName: string, kf: TrackKeyframe) => void
  /** Replace one keyframe by index within its track. Re-sorts by t afterward. */
  updateKeyframe: (trackName: string, index: number, kf: TrackKeyframe) => void
  /** Remove one keyframe by index. Removes the track entirely if it becomes empty. */
  removeKeyframe: (trackName: string, index: number) => void

  /** Reverse the waypoint order, mirroring track/trigger t-values so spatial positions stay
   *  consistent (t_new = 1 − t_old after direction flip). */
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

function makeWp(x: number, y: number, z: number, pathRoll = 0, craftRoll = 0): Waypoint {
  return { x, y, z, pathRoll, craftRoll }
}

const DEFAULT_PATH: PathData = {
  name:     'new_path',
  type:     'craft',
  speed:    0.025,
  orient:   'path',
  target:   { x: 0, y: 6, z: 0 },  // offset from origin so it's visible when orient='target'
  closed:   true,
  standoff: 0,
  wps: [
    makeWp( 20,  0,  0),
    makeWp(  8,  1,  3),
    makeWp( -5,  1,  6),
    makeWp( -8,  0,  5),
    makeWp( -5, -1,  2),
    makeWp(  8,  0,  2),
  ],
  tracks:   {},
  triggers: [],
}

function ensureRolls(wp: Vec3): Waypoint {
  const w = wp as Partial<Waypoint>
  return {
    x: w.x ?? 0, y: w.y ?? 0, z: w.z ?? 0,
    pathRoll:  w.pathRoll  ?? 0,
    craftRoll: w.craftRoll ?? 0,
  }
}

/** Fill in fields added after the initial release so old localStorage / file
 *  data loads cleanly without crashing. */
function migratePath(p: Partial<PathData>): PathData {
  return {
    ...DEFAULT_PATH,
    ...p,
    type:     (p.type     ?? 'craft') as PathType,
    tracks:   (p.tracks   && typeof p.tracks === 'object' && !Array.isArray(p.tracks))
                ? p.tracks as Record<string, TrackKeyframe[]>
                : {},
    triggers: Array.isArray(p.triggers) ? p.triggers : [],
  }
}

function normalizePath(p: PathData): PathData {
  let wps = p.wps.map(ensureRolls)
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
      debugLog: false,

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
        wps[i] = ensureRolls(wp)
        const path = { ...s.path, wps }
        save(path)
        return { path, status: 'modified' }
      }),

      replaceWps: (wps) => set((s) => {
        const path = { ...s.path, wps: wps.map(ensureRolls) }
        save(path)
        return { path, status: 'modified' }
      }),

      addWp: (wp, after) => set((s) => {
        const wps = [...s.path.wps]
        const fullWp = ensureRolls(wp)
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
      setDebugLog:     (v) => set({ debugLog: v }),
      showOverlays:    true,
      setShowOverlays: (v) => set({ showOverlays: v }),
      maximizedPane:    null,
      setMaximizedPane: (pane) => set({ maximizedPane: pane }),
      editGhost:    null,
      setEditGhost: (g) => set({ editGhost: g }),

      // ── Behavior track actions ──────────────────────────────────────────
      setTrack: (name, frames) => set((s) => {
        const tracks = { ...s.path.tracks }
        if (frames.length === 0) {
          delete tracks[name]
        } else {
          tracks[name] = sortByT(frames)
        }
        const path = { ...s.path, tracks }
        save(path)
        return { path }
      }),

      addKeyframe: (trackName, kf) => set((s) => {
        const existing = s.path.tracks[trackName] ?? []
        const tracks = { ...s.path.tracks, [trackName]: sortByT([...existing, kf]) }
        const path = { ...s.path, tracks }
        save(path)
        return { path }
      }),

      updateKeyframe: (trackName, index, kf) => set((s) => {
        const existing = [...(s.path.tracks[trackName] ?? [])]
        existing[index] = kf
        const tracks = { ...s.path.tracks, [trackName]: sortByT(existing) }
        const path = { ...s.path, tracks }
        save(path)
        return { path }
      }),

      removeKeyframe: (trackName, index) => set((s) => {
        const existing = [...(s.path.tracks[trackName] ?? [])]
        existing.splice(index, 1)
        const tracks = { ...s.path.tracks }
        if (existing.length === 0) {
          delete tracks[trackName]
        } else {
          tracks[trackName] = existing
        }
        const path = { ...s.path, tracks }
        save(path)
        return { path }
      }),

      reverseWps: () => set((s) => {
        const wps = [...s.path.wps].reverse()
        // Mirror all track keyframe t-values: t_new = 1 - t_old, re-sort ascending
        const tracks: Record<string, TrackKeyframe[]> = {}
        for (const [name, frames] of Object.entries(s.path.tracks)) {
          tracks[name] = frames.map(kf => ({ ...kf, t: 1 - kf.t })).sort((a, b) => a.t - b.t)
        }
        // Mirror trigger t-values the same way
        const triggers = s.path.triggers
          .map(tr => ({ ...tr, t: 1 - tr.t }))
          .sort((a, b) => a.t - b.t)
        const path = { ...s.path, wps, tracks, triggers }
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
      behaviorsOpen:      false,
      behaviorsHeight:    220,
      setBehaviorsOpen:   (v) => set({ behaviorsOpen: v }),
      setBehaviorsHeight: (v) => set({ behaviorsHeight: v }),
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
