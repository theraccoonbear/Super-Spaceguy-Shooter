// Shared logic for the two orthographic canvas views (Top XZ, Side XY).
// Each view has its own pan/scale camera state, stored in a ref to avoid
// React re-renders on every mouse move.

import { useRef, useEffect, useCallback } from 'react'

export interface OrthoCamera {
  panX:  number
  panY:  number
  scale: number
}

export function useOrthoCanvas(
  drawCallback: (ctx: CanvasRenderingContext2D, w: number, h: number, cam: OrthoCamera) => void,
  deps: unknown[],
) {
  const cvRef  = useRef<HTMLCanvasElement>(null)
  const camRef = useRef<OrthoCamera>({ panX: 0, panY: 0, scale: 12 })

  // Memoized draw function. Handles DPI scaling and canvas resize.
  const draw = useCallback(() => {
    const cv = cvRef.current
    if (!cv) return
    const dpr  = window.devicePixelRatio || 1
    const rect = cv.getBoundingClientRect()
    const w = rect.width, h = rect.height
    if (w === 0 || h === 0) return

    // Only reallocate canvas backing store when size actually changes
    const needW = Math.round(w * dpr)
    const needH = Math.round(h * dpr)
    if (cv.width !== needW || cv.height !== needH) {
      cv.width  = needW
      cv.height = needH
    }

    const ctx = cv.getContext('2d')!
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    drawCallback(ctx, w, h, camRef.current)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)

  // Redraw whenever deps change
  useEffect(() => { draw() }, [draw])

  // Redraw on resize
  useEffect(() => {
    const cv = cvRef.current
    if (!cv) return
    const ro = new ResizeObserver(() => draw())
    ro.observe(cv)
    return () => ro.disconnect()
  }, [draw])

  return { cvRef, camRef, draw }
}
