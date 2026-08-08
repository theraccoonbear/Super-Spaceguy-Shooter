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
