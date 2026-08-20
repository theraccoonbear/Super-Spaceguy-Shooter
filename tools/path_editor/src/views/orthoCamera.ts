// Shared orthographic camera state.
// When linked (default), all three ortho views share the same scale and
// world-space pan offsets. Panning or zooming in one view moves all three.
// Toggle linked/unlinked with L or the toolbar button.

export interface WorldPan { x: number; y: number; z: number }

interface OrthoCamera {
  scale:    number
  worldPan: WorldPan
}

// Shared state used by all views when linked=true
export const sharedCam: OrthoCamera = {
  scale:    12,
  worldPan: { x: 0, y: 0, z: 0 },
}

// Per-view independent cameras used when linked=false
export const localCam: Record<'top' | 'side' | 'front', OrthoCamera> = {
  top:   { scale: 12, worldPan: { x: 0, y: 0, z: 0 } },
  side:  { scale: 12, worldPan: { x: 0, y: 0, z: 0 } },
  front: { scale: 12, worldPan: { x: 0, y: 0, z: 0 } },
}

export let linked = true

// Callbacks registered by each view to redraw on camera change
const listeners = new Set<() => void>()

export function registerRedraw(fn: () => void): () => void {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

export function notifyAll(): void {
  listeners.forEach((fn) => fn())
}

// Returns the effective camera for a view (shared or local)
export function getCam(view: 'top' | 'side' | 'front'): OrthoCamera {
  return linked ? sharedCam : localCam[view]
}

// Toggle linked mode.  When unlinking, seed local cams from current shared state.
// When re-linking, leave shared as-is.
// Frame given waypoints to fit in the specified view.
// Sets worldPan and scale on the view's camera so the points fill the pane
// with ~25 % margin. Call notifyAll() at the end (already done here).
export function framePoints(
  view:    'top' | 'side' | 'front',
  wps:     Array<{ x: number; y: number; z: number }>,
  canvasW: number,
  canvasH: number,
): void {
  if (wps.length === 0 || canvasW === 0 || canvasH === 0) return
  const cam = getCam(view)
  const MARGIN = 1.25   // 25 % border

  // Each view exposes two world axes onto the screen:
  //   Top   (XZ): screen-X = worldZ, screen-Y = worldX (inverted)
  //   Side  (XY): screen-X = worldX, screen-Y = worldY (inverted)
  //   Front (YZ): screen-X = worldZ, screen-Y = worldY (inverted)
  // worldPan sign: w2s → sx = w/2 + (pan.A + wA) * scale
  //   → for wA_center to land at sx = w/2: pan.A = -wA_center

  let hVals: number[], vVals: number[]

  if (view === 'top') {
    hVals = wps.map(w => w.z); vVals = wps.map(w => w.x)
    const midH = (Math.min(...hVals) + Math.max(...hVals)) / 2
    const midV = (Math.min(...vVals) + Math.max(...vVals)) / 2
    cam.worldPan = { ...cam.worldPan, z: -midH, x: -midV }
  } else if (view === 'side') {
    hVals = wps.map(w => w.x); vVals = wps.map(w => w.y)
    const midH = (Math.min(...hVals) + Math.max(...hVals)) / 2
    const midV = (Math.min(...vVals) + Math.max(...vVals)) / 2
    cam.worldPan = { ...cam.worldPan, x: -midH, y: -midV }
  } else {
    hVals = wps.map(w => w.z); vVals = wps.map(w => w.y)
    const midH = (Math.min(...hVals) + Math.max(...hVals)) / 2
    const midV = (Math.min(...vVals) + Math.max(...vVals)) / 2
    cam.worldPan = { ...cam.worldPan, z: -midH, y: -midV }
  }

  const rangeH = Math.max(Math.max(...hVals) - Math.min(...hVals), 1)
  const rangeV = Math.max(Math.max(...vVals) - Math.min(...vVals), 1)
  cam.scale = Math.min(canvasW / rangeH, canvasH / rangeV) / MARGIN

  notifyAll()
}

export function toggleLinked(): boolean {
  linked = !linked
  if (!linked) {
    for (const v of ['top', 'side', 'front'] as const) {
      localCam[v].scale    = sharedCam.scale
      localCam[v].worldPan = { ...sharedCam.worldPan }
    }
  }
  notifyAll()
  return linked
}
