// frameCache.ts — module-level frame table for scrub-time holonomy-corrected frame lookup.
//
// App.tsx calls setFrameTable() whenever the path changes (alongside holonomy computation).
// PerspView.tsx calls getFrameAt() during scrub (!playing) to get the correct base frame
// instead of falling back to the world-up Gram-Schmidt makeFrame().
//
// Using a module-level singleton avoids both circular imports (App ↔ PerspView) and
// polluting the Zustand store with a large non-reactive data structure.

import type { FrameSample } from './spline'

let _table: FrameSample[] | null = null

export function setFrameTable(table: FrameSample[] | null): void {
  _table = table
}

// Returns the holonomy-corrected (R, U) frame at the given arc fraction [0, 1],
// or null if no table has been built (open path or fewer than 2 waypoints).
export function getFrameAt(arcFrac: number): FrameSample | null {
  if (!_table || _table.length < 2) return null
  const n  = _table.length - 1
  const fi = Math.max(0, Math.min(1, arcFrac)) * n
  const lo = Math.floor(fi)
  const hi = Math.min(n, lo + 1)
  const t  = fi - lo
  if (lo === hi || t < 1e-6) return _table[lo]
  const { R: R0, U: U0 } = _table[lo]
  const { R: R1, U: U1 } = _table[hi]
  return {
    R: { x: R0.x + t*(R1.x-R0.x), y: R0.y + t*(R1.y-R0.y), z: R0.z + t*(R1.z-R0.z) },
    U: { x: U0.x + t*(U1.x-U0.x), y: U0.y + t*(U1.y-U0.y), z: U0.z + t*(U1.z-U0.z) },
  }
}
