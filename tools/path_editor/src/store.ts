import { create } from 'zustand'
import { Vec3 } from './math/vec3'

export type OrientMode = 'path' | 'target'

export interface PathData {
  name:     string
  speed:    number
  orient:   OrientMode
  target:   Vec3      // fixed look-at point (used when orient='target')
  closed:   boolean   // wps[n-1] === wps[0]; last waypoint duplicates first
  roll:     number    // degrees per full loop (360 = one barrel roll)
  standoff: number    // perpendicular distance from wire (world units)
  wps:      Vec3[]
}

export interface EditorState {
  path:     PathData
  selected: number    // selected waypoint index, -1 = none
  playing:  boolean
  animT:    number    // 0..nSegs (Catmull-Rom parameter)
  status:   string    // displayed in status bar

  setPath:     (p: PathData) => void
  patchPath:   <K extends keyof PathData>(key: K, value: PathData[K]) => void
  setWp:       (i: number, wp: Vec3) => void
  addWp:       (wp: Vec3, after?: number) => void
  delWp:       (i: number) => void
  dupWp:       (i: number) => void
  setSelected: (i: number) => void
  setPlaying:  (v: boolean) => void
  setAnimT:    (v: number) => void
  setStatus:   (s: string) => void
}

const DEFAULT_PATH: PathData = {
  name:     'new_path',
  speed:    0.025,
  orient:   'path',
  target:   { x: 0, y: 0, z: 0 },
  closed:   true,
  roll:     0,
  standoff: 0,
  wps: [
    { x: 20, y:  0, z:  0 },
    { x:  8, y:  1, z:  3 },
    { x: -5, y:  1, z:  6 },
    { x: -8, y:  0, z:  5 },
    { x: -5, y: -1, z:  2 },
    { x:  8, y:  0, z:  2 },
    { x: 20, y:  0, z:  0 },
  ],
}

function load(): PathData {
  try {
    const raw = localStorage.getItem('pe_session')
    if (raw) return JSON.parse(raw) as PathData
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
    save(p)
    set({ path: p, status: 'loaded' })
  },

  patchPath: (key, value) => set((s) => {
    const path = { ...s.path, [key]: value }
    save(path)
    return { path, status: 'modified' }
  }),

  setWp: (i, wp) => set((s) => {
    const wps = [...s.path.wps]
    wps[i] = wp
    const path = { ...s.path, wps }
    save(path)
    return { path, status: 'modified' }
  }),

  addWp: (wp, after) => set((s) => {
    const wps = [...s.path.wps]
    const idx = after !== undefined ? after + 1 : wps.length
    wps.splice(idx, 0, wp)
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
