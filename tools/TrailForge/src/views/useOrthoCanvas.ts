// Shared canvas management for orthographic views.
// Camera state has moved to orthoCamera.ts; this hook only manages the
// canvas element, DPI scaling, resize observation, and registration with
// the shared redraw notification system so linked-pan/zoom works.

import { useRef, useEffect, useCallback } from 'react'
import { registerRedraw } from './orthoCamera'

export function useOrthoCanvas(
  drawCallback: (ctx: CanvasRenderingContext2D, w: number, h: number) => void,
  deps: unknown[],
) {
  const cvRef = useRef<HTMLCanvasElement>(null)

  const draw = useCallback(() => {
    const cv = cvRef.current
    if (!cv) return
    const dpr  = window.devicePixelRatio || 1
    const rect = cv.getBoundingClientRect()
    const w = rect.width, h = rect.height
    if (w === 0 || h === 0) return

    const needW = Math.round(w * dpr)
    const needH = Math.round(h * dpr)
    if (cv.width !== needW || cv.height !== needH) {
      cv.width  = needW
      cv.height = needH
    }

    const ctx = cv.getContext('2d')!
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    drawCallback(ctx, w, h)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)

  // Redraw when dependencies change
  useEffect(() => { draw() }, [draw])

  // Redraw on canvas resize
  useEffect(() => {
    const cv = cvRef.current
    if (!cv) return
    const ro = new ResizeObserver(() => draw())
    ro.observe(cv)
    return () => ro.disconnect()
  }, [draw])

  // Register with the shared camera so notifyAll() redraws this view
  useEffect(() => registerRedraw(draw), [draw])

  return { cvRef, draw }
}
