// Side View — XY plane (looking along +Z from the side).
// Screen X → world X (forward).  Screen Y up → world Y (altitude).
// Dragging moves waypoints in X and Y; Z is inherited from selected or 0.

import { useRef, useCallback } from 'react'
import { useStore } from '../store'
import { buildSpline, evalAt, tangentAt, actualPos, shipFacing } from '../math/spline'
import { useOrthoCanvas, OrthoCamera } from './useOrthoCanvas'

// ── World ↔ Screen ──────────────────────────────────────────────────────
function w2s(wx: number, wy: number, w: number, h: number, cam: OrthoCamera) {
  return { sx: w / 2 + cam.panX + wx * cam.scale, sy: h / 2 + cam.panY - wy * cam.scale }
}
function s2w(sx: number, sy: number, w: number, h: number, cam: OrthoCamera) {
  return {
    wx: (sx - w / 2 - cam.panX) / cam.scale,
    wy: (h / 2 + cam.panY - sy) / cam.scale,
  }
}

// ── Drawing ─────────────────────────────────────────────────────────────
function drawGrid(ctx: CanvasRenderingContext2D, w: number, h: number, cam: OrthoCamera) {
  const step = 5, range = 60
  ctx.lineWidth = 1
  for (let v = -range; v <= range; v += step) {
    const major = v % 20 === 0
    ctx.strokeStyle = major ? '#222225' : '#18181a'
    // Vertical lines (constant X)
    const { sx: x0, sy: y0 } = w2s(v, -range, w, h, cam)
    const { sx: x1, sy: y1 } = w2s(v,  range, w, h, cam)
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
    // Horizontal lines (constant Y)
    const { sx: x2, sy: y2 } = w2s(-range, v, w, h, cam)
    const { sx: x3, sy: y3 } = w2s( range, v, w, h, cam)
    ctx.beginPath(); ctx.moveTo(x2, y2); ctx.lineTo(x3, y3); ctx.stroke()
  }
  // X axis (Y=0)
  ctx.strokeStyle = '#2a2010'; ctx.lineWidth = 1
  const { sx: ax0, sy: ay0 } = w2s(-range, 0, w, h, cam)
  const { sx: ax1, sy: ay1 } = w2s( range, 0, w, h, cam)
  ctx.beginPath(); ctx.moveTo(ax0, ay0); ctx.lineTo(ax1, ay1); ctx.stroke()
  // Y axis (X=0)
  ctx.strokeStyle = '#10202a'; ctx.lineWidth = 1
  const { sx: bx0, sy: by0 } = w2s(0, -range, w, h, cam)
  const { sx: bx1, sy: by1 } = w2s(0,  range, w, h, cam)
  ctx.beginPath(); ctx.moveTo(bx0, by0); ctx.lineTo(bx1, by1); ctx.stroke()
}

function drawShipArrow(ctx: CanvasRenderingContext2D, sx: number, sy: number, fwdX: number, fwdY: number, color: string) {
  const angle = Math.atan2(-fwdY, fwdX)
  ctx.save()
  ctx.translate(sx, sy)
  ctx.rotate(angle)
  ctx.fillStyle = color
  ctx.beginPath()
  ctx.moveTo(9, 0)
  ctx.lineTo(-5, 5)
  ctx.lineTo(-3, 0)
  ctx.lineTo(-5, -5)
  ctx.closePath()
  ctx.fill()
  ctx.restore()
}

// ── Component ───────────────────────────────────────────────────────────
export function SideView() {
  const { path, selected, playing, animT, setWp, addWp, setSelected } = useStore()

  const draw = useCallback((ctx: CanvasRenderingContext2D, w: number, h: number, cam: OrthoCamera) => {
    ctx.clearRect(0, 0, w, h)
    drawGrid(ctx, w, h, cam)

    const samples = buildSpline({ wps: path.wps, closed: path.closed, roll: path.roll, standoff: path.standoff })

    // Wire path
    if (samples.length > 1) {
      ctx.beginPath()
      ctx.strokeStyle = '#38bdf8'
      ctx.lineWidth = 1.5
      samples.forEach(({ wire }, i) => {
        const { sx, sy } = w2s(wire.x, wire.y, w, h, cam)
        i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
      })
      ctx.stroke()

      // Actual path (orange) when standoff active
      if (path.standoff > 0.001) {
        ctx.beginPath()
        ctx.strokeStyle = '#f97316'
        ctx.lineWidth = 1
        ctx.setLineDash([3, 3])
        samples.forEach(({ actual }, i) => {
          const { sx, sy } = w2s(actual.x, actual.y, w, h, cam)
          i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
        })
        ctx.stroke()
        ctx.setLineDash([])
      }
    }

    // Player marker
    const { sx: px, sy: py } = w2s(0, 0, w, h, cam)
    ctx.strokeStyle = '#4ade80'; ctx.lineWidth = 1.5
    ctx.beginPath(); ctx.moveTo(px - 6, py); ctx.lineTo(px + 6, py); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(px, py - 6); ctx.lineTo(px, py + 6); ctx.stroke()
    ctx.beginPath(); ctx.arc(px, py, 3, 0, Math.PI * 2); ctx.fillStyle = '#4ade80'; ctx.fill()

    // Waypoints
    path.wps.forEach((wp, i) => {
      const { sx, sy } = w2s(wp.x, wp.y, w, h, cam)
      const isSel = i === selected
      ctx.beginPath()
      ctx.arc(sx, sy, isSel ? 6 : 4, 0, Math.PI * 2)
      ctx.fillStyle = isSel ? '#fbbf24' : '#94a3b8'
      ctx.fill()
      if (isSel) {
        ctx.strokeStyle = '#fbbf24'; ctx.lineWidth = 1.5; ctx.stroke()
      }
      ctx.fillStyle = isSel ? '#fbbf24' : '#555560'
      ctx.font = '9px Courier New, monospace'
      ctx.fillText(String(i), sx + 7, sy - 4)
    })

    // Animated ship
    if (playing && path.wps.length >= 2) {
      const nSegs = path.wps.length - 1
      const wire   = evalAt(path.wps, animT, path.closed)
      const tan    = tangentAt(path.wps, animT, path.closed)
      const frac   = animT / nSegs
      const ap     = actualPos(wire, tan, frac, path.roll, path.standoff)
      const facing = shipFacing(ap, tan, path.orient, path.target)
      const { sx, sy } = w2s(ap.x, ap.y, w, h, cam)
      drawShipArrow(ctx, sx, sy, facing.x, facing.y, '#f97316')
    }

    // Labels
    ctx.fillStyle = '#2a2a35'; ctx.font = '9px Courier New, monospace'
    ctx.fillText('X →', w - 28, h / 2 + cam.panY + 12)
    ctx.fillText('Y ↑', w / 2 + cam.panX + 6, 14)
  }, [path, selected, playing, animT])

  const { cvRef, camRef, draw: redraw } = useOrthoCanvas(draw, [path, selected, playing, animT])

  type DragState = { type: 'wp'; wpIdx: number; startSx: number; startSy: number; startWx: number; startWy: number }
                 | { type: 'pan'; startSx: number; startSy: number; startPanX: number; startPanY: number }
  const drag     = useRef<DragState | null>(null)
  const hasMoved = useRef(false)
  const drawRef  = useRef(redraw)
  drawRef.current = redraw

  const getRect = () => cvRef.current!.getBoundingClientRect()

  function findNearWp(sx: number, sy: number, w: number, h: number): number {
    const wps = useStore.getState().path.wps
    const cam = camRef.current
    for (let i = 0; i < wps.length; i++) {
      const { sx: wx, sy: wy } = w2s(wps[i].x, wps[i].y, w, h, cam)
      const dx = sx - wx, dy = sy - wy
      if (dx * dx + dy * dy < 64) return i
    }
    return -1
  }

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    const cam = camRef.current
    hasMoved.current = false

    if (e.button === 2 || e.button === 1) {
      drag.current = { type: 'pan', startSx: sx, startSy: sy, startPanX: cam.panX, startPanY: cam.panY }
      return
    }

    const idx = findNearWp(sx, sy, rect.width, rect.height)
    if (idx >= 0) {
      useStore.getState().setSelected(idx)
      const wp = useStore.getState().path.wps[idx]
      drag.current = { type: 'wp', wpIdx: idx, startSx: sx, startSy: sy, startWx: wp.x, startWy: wp.y }
    } else {
      drag.current = { type: 'pan', startSx: sx, startSy: sy, startPanX: cam.panX, startPanY: cam.panY }
    }
  }, [])

  const onMouseMove = useCallback((e: React.MouseEvent) => {
    if (!drag.current) return
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    const cam = camRef.current
    hasMoved.current = true

    if (drag.current.type === 'pan') {
      cam.panX = drag.current.startPanX + sx - drag.current.startSx
      cam.panY = drag.current.startPanY + sy - drag.current.startSy
      drawRef.current(); return
    }

    if (drag.current.type === 'wp') {
      const { startWx, startWy, startSx, startSy, wpIdx } = drag.current
      const dWx = (sx - startSx) / cam.scale
      const dWy = -(sy - startSy) / cam.scale
      const wps = useStore.getState().path.wps
      useStore.getState().setWp(wpIdx, { ...wps[wpIdx], x: startWx + dWx, y: startWy + dWy })
    }
  }, [])

  const onMouseUp = useCallback((e: React.MouseEvent) => {
    if (!drag.current) return
    if (!hasMoved.current && drag.current.type === 'pan') {
      const rect = getRect()
      const sx = e.clientX - rect.left, sy = e.clientY - rect.top
      const { wx, wy } = s2w(sx, sy, rect.width, rect.height, camRef.current)
      const sel = useStore.getState().selected
      const wps = useStore.getState().path.wps
      const wz  = sel >= 0 ? wps[sel].z : 0
      useStore.getState().addWp({ x: wx, y: wy, z: wz }, sel >= 0 ? sel : undefined)
    }
    drag.current = null
  }, [])

  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault()
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    const cam = camRef.current
    const { wx, wy } = s2w(sx, sy, rect.width, rect.height, cam)
    const factor = e.deltaY > 0 ? 0.88 : 1.14
    cam.scale *= factor
    cam.scale = Math.max(2, Math.min(80, cam.scale))
    cam.panX = sx - rect.width  / 2 - wx * cam.scale
    cam.panY = sy - rect.height / 2 + wy * cam.scale
    drawRef.current()
  }, [])

  const onKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Delete' || e.key === 'Backspace') {
      const sel = useStore.getState().selected
      if (sel >= 0) useStore.getState().delWp(sel)
    }
  }, [])

  return (
    <canvas
      ref={cvRef}
      style={{ cursor: 'crosshair' }}
      tabIndex={0}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onMouseLeave={() => { drag.current = null }}
      onWheel={onWheel}
      onKeyDown={onKeyDown}
      onContextMenu={(e) => e.preventDefault()}
    />
  )
}
