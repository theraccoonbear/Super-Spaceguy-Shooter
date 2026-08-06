import { create } from 'zustand'
import { Vec3, Waypoint } from './math/vec3'

export type { Waypoint }
export type OrientMode = 'path' | 'target'

export interface PathData {
  name:     string
  speed:    number
  orient:   OrientMode
  target:   Vec3      // fixed look-at point (used when orient='target')
  closed:   boolean   // when true, last segment wraps back to wps[0] (no duplicate endpoint)
  standoff: number    // perpendicular distance from wire (world units)
  wps:      Waypoint[]
}

export interface EditorState {
  path:     PathData
  selected: number    // selected waypoint index, -1 = none
  playing:  boolean
  animT:    number    // 0..nSegs (Catmull-Rom parameter)
  status:   string    // displayed in status bar

  setPath:     (p: PathData) => void
  patchPath:   <K extends keyof PathData>(key: K, value: PathData[K]) => void
  setWp:       (i: number, wp: Waypoint) => void
  addWp:       (wp: Vec3, after?: number) => void
  delWp:       (i: number) => void
  dupWp:       (i: number) => void
  setSelected: (i: number) => void
  setPlaying:  (v: boolean) => void
  setAnimT:    (v: number) => void
  setStatus:   (s: string) => void
}

function makeWp(x: number, y: number, z: number, pathRoll = 0, craftRoll = 0): Waypoint {
  return { x, y, z, pathRoll, craftRoll }
}

const DEFAULT_PATH: PathData = {
  name:     'new_path',
  speed:    0.025,
  orient:   'path',
  target:   { x: 0, y: 0, z: 0 },
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
}

// Ensure every waypoint has roll fields (backward compat when loading old sessions).
function ensureRolls(wp: Vec3): Waypoint {
  const w = wp as Partial<Waypoint>
  return {
    x: w.x ?? 0, y: w.y ?? 0, z: w.z ?? 0,
    pathRoll:  w.pathRoll  ?? 0,
    craftRoll: w.craftRoll ?? 0,
  }
}

// Strip duplicate endpoint from old-format closed paths (wps[last] === wps[0]).
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

function load(): PathData {
  try {
    const raw = localStorage.getItem('pe_session')
    if (raw) {
      const parsed = JSON.parse(raw) as PathData
      // Migrate old sessions that had a global 'roll' field
      if ('roll' in parsed) delete (parsed as Record<string, unknown>).roll
      return normalizePath(parsed)
    }
  } catch { /* ignore */ }
  return DEFAULT_PATH
}

function save(p: PathData) {
  try { localStorage.setItem('pe_session', JSON.stringify(p)) } catch { /* ignore */ }
}

export const useStore = create<EditorState>((set) => ({
  path:     load(),
  selected: -1,
  playing:  false,
  animT:    0,
  status:   'session restored',

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

  setSelected: (i) => set({ selected: i }),
  setPlaying:  (v) => set({ playing: v }),
  setAnimT:    (v) => set({ animT: v }),
  setStatus:   (s) => set({ status: s }),
}))
