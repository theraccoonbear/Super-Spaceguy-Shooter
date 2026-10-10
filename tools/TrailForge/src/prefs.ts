// Unified localStorage preferences for TrailForge.
//
// ALL persistent UI and camera state flows through this module.
// Do not call localStorage directly anywhere else in the app.
//
// Two keys:
//   trailforge:ui     — panel toggles, sizes, sidebar state
//   trailforge:camera — ortho zoom/pan, linked mode, 3D camera mode
//
// Usage:
//   import { uiPrefs, camPrefs, saveUIPrefs, saveCamPrefs } from '../prefs'
//   const w = uiPrefs.sidebarWidth   // read at module init / useState init time
//   saveUIPrefs({ sidebarWidth: 280 }) // write + persist

const UI_KEY     = 'trailforge:ui'
const CAMERA_KEY = 'trailforge:camera'

// ── UI prefs ────────────────────────────────────────────────────────────────

export interface UIPrefs {
  showOverlays:    boolean
  behaviorsOpen:   boolean
  behaviorsHeight: number
  debugLog:        boolean
  sidebarWidth:    number
  sidebarTab:      'wp' | 'io' | 'routes'
}

const UI_DEFAULTS: UIPrefs = {
  showOverlays:    true,
  behaviorsOpen:   false,
  behaviorsHeight: 220,
  debugLog:        false,
  sidebarWidth:    220,
  sidebarTab:      'wp',
}

// ── Camera prefs ────────────────────────────────────────────────────────────

export interface CamState {
  scale:    number
  worldPan: { x: number; y: number; z: number }
}

export interface CameraPrefs {
  linked:     boolean
  cameraMode: 'orbit' | 'follow' | 'ingame'
  shared:     CamState
  top:        CamState
  side:       CamState
  front:      CamState
}

const DEFAULT_CAM_STATE: CamState = {
  scale:    12,
  worldPan: { x: 0, y: 0, z: 0 },
}

const CAMERA_DEFAULTS: CameraPrefs = {
  linked:     true,
  cameraMode: 'orbit',
  shared:     DEFAULT_CAM_STATE,
  top:        DEFAULT_CAM_STATE,
  side:       DEFAULT_CAM_STATE,
  front:      DEFAULT_CAM_STATE,
}

// ── Loaders ─────────────────────────────────────────────────────────────────

function loadUIPrefs(): UIPrefs {
  try {
    const raw = localStorage.getItem(UI_KEY)
    if (!raw) return { ...UI_DEFAULTS }
    const p = JSON.parse(raw) as Partial<UIPrefs>
    return {
      showOverlays:    typeof p.showOverlays    === 'boolean' ? p.showOverlays    : UI_DEFAULTS.showOverlays,
      behaviorsOpen:   typeof p.behaviorsOpen   === 'boolean' ? p.behaviorsOpen   : UI_DEFAULTS.behaviorsOpen,
      behaviorsHeight: typeof p.behaviorsHeight === 'number'  ? Math.max(80, Math.min(600, p.behaviorsHeight)) : UI_DEFAULTS.behaviorsHeight,
      debugLog:        typeof p.debugLog        === 'boolean' ? p.debugLog        : UI_DEFAULTS.debugLog,
      sidebarWidth:    typeof p.sidebarWidth    === 'number'  ? Math.max(160, Math.min(500, p.sidebarWidth)) : UI_DEFAULTS.sidebarWidth,
      sidebarTab:      (['wp', 'io', 'routes'] as const).includes(p.sidebarTab as 'wp' | 'io' | 'routes')
                         ? p.sidebarTab as 'wp' | 'io' | 'routes'
                         : UI_DEFAULTS.sidebarTab,
    }
  } catch {
    return { ...UI_DEFAULTS }
  }
}

function parseCamState(v: unknown): CamState {
  if (!v || typeof v !== 'object') return { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } }
  const o  = v as Record<string, unknown>
  const wp = (o.worldPan && typeof o.worldPan === 'object') ? o.worldPan as Record<string, unknown> : {}
  return {
    scale:    typeof o.scale === 'number' ? o.scale : DEFAULT_CAM_STATE.scale,
    worldPan: {
      x: typeof wp.x === 'number' ? wp.x : 0,
      y: typeof wp.y === 'number' ? wp.y : 0,
      z: typeof wp.z === 'number' ? wp.z : 0,
    },
  }
}

function loadCameraPrefs(): CameraPrefs {
  try {
    const raw = localStorage.getItem(CAMERA_KEY)
    if (!raw) return {
      ...CAMERA_DEFAULTS,
      shared: { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } },
      top:    { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } },
      side:   { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } },
      front:  { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } },
    }
    const p = JSON.parse(raw) as Record<string, unknown>
    return {
      linked:     typeof p.linked === 'boolean' ? p.linked : CAMERA_DEFAULTS.linked,
      cameraMode: (['orbit', 'follow', 'ingame'] as const).includes(p.cameraMode as 'orbit' | 'follow' | 'ingame')
                    ? p.cameraMode as 'orbit' | 'follow' | 'ingame'
                    : CAMERA_DEFAULTS.cameraMode,
      shared: parseCamState(p.shared),
      top:    parseCamState(p.top),
      side:   parseCamState(p.side),
      front:  parseCamState(p.front),
    }
  } catch {
    return {
      ...CAMERA_DEFAULTS,
      shared: { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } },
      top:    { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } },
      side:   { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } },
      front:  { scale: DEFAULT_CAM_STATE.scale, worldPan: { ...DEFAULT_CAM_STATE.worldPan } },
    }
  }
}

// ── Exported singletons (mutable, loaded once at module init) ────────────────

export const uiPrefs:  UIPrefs     = loadUIPrefs()
export const camPrefs: CameraPrefs = loadCameraPrefs()

// ── Save helpers ─────────────────────────────────────────────────────────────

export function saveUIPrefs(patch: Partial<UIPrefs>): void {
  Object.assign(uiPrefs, patch)
  try { localStorage.setItem(UI_KEY, JSON.stringify(uiPrefs)) } catch { /* ignore */ }
}

export function saveCamPrefs(patch: Partial<CameraPrefs>): void {
  Object.assign(camPrefs, patch)
  try { localStorage.setItem(CAMERA_KEY, JSON.stringify(camPrefs)) } catch { /* ignore */ }
}
