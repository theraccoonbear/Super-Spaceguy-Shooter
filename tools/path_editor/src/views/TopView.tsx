// Top View — XZ plane (looking down from +Y).
// Screen X → world Z (lateral).  Screen Y down → world X (forward).
// Clicking on empty space adds a waypoint; dragging moves it in X and Z.

import { useRef, useCallback } from 'react'
import { useStore } from '../store'
import { buildSpline, evalAt, tangentAt, actualPos, shipFacing } from '../math/spline'
import { useOrthoCanvas } from './useOrthoCanvas'
import { getCam, notifyAll, WorldPan } from './orthoCamera'

const VIEW = 'top' as const

// ── World ↔ Screen ──────────────────────────────────────────────────────
// sx = w/2 + (worldPan.z + wz) * scale
// sy = h/2 - (worldPan.x + wx) * scale
function w2s(wx: number, wz: number, w: number, h: number, scale: number, pan: WorldPan) {
  return { sx: w / 2 + (pan.z + wz) * scale, sy: h / 2 - (pan.x + wx) * scale }
}
function s2w(sx: number, sy: number, w: number, h: number, scale: number, pan: WorldPan) {
  return {
    wx: (h / 2 - sy) / scale - pan.x,
    wz: (sx - w / 2) / scale - pan.z,
  }
}

// ── Drawing ─────────────────────────────────────────────────────────────
function drawGrid(ctx: CanvasRenderingContext2D, w: number, h: number, scale: number, pan: WorldPan) {
  const step = 5, range = 60
  ctx.lineWidth = 1
  for (let v = -range; v <= range; v += step) {
    const major = v % 20 === 0
    ctx.strokeStyle = major ? '#222225' : '#18181a'
    const { sx: x0, sy: y0 } = w2s(v, -range, w, h, scale, pan)
    const { sx: x1, sy: y1 } = w2s(v,  range, w, h, scale, pan)
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
    const { sx: x2, sy: y2 } = w2s(-range, v, w, h, scale, pan)
    const { sx: x3, sy: y3 } = w2s( range, v, w, h, scale, pan)
    ctx.beginPath(); ctx.moveTo(x2, y2); ctx.lineTo(x3, y3); ctx.stroke()
  }
  ctx.strokeStyle = '#2a2010'; ctx.lineWidth = 1
  const { sx: ax0, sy: ay0 } = w2s(-range, 0, w, h, scale, pan)
  const { sx: ax1, sy: ay1 } = w2s( range, 0, w, h, scale, pan)
  ctx.beginPath(); ctx.moveTo(ax0, ay0); ctx.lineTo(ax1, ay1); ctx.stroke()
  ctx.strokeStyle = '#10202a'; ctx.lineWidth = 1
  const { sx: bx0, sy: by0 } = w2s(0, -range, w, h, scale, pan)
  const { sx: bx1, sy: by1 } = w2s(0,  range, w, h, scale, pan)
  ctx.beginPath(); ctx.moveTo(bx0, by0); ctx.lineTo(bx1, by1); ctx.stroke()
}

function drawShipArrow(ctx: CanvasRenderingContext2D, sx: number, sy: number, fwdX: number, fwdZ: number, color: string) {
  const angle = Math.atan2(-fwdX, fwdZ)
  ctx.save(); ctx.translate(sx, sy); ctx.rotate(angle)
  ctx.fillStyle = color
  ctx.beginPath(); ctx.moveTo(9, 0); ctx.lineTo(-5, 5); ctx.lineTo(-3, 0); ctx.lineTo(-5, -5); ctx.closePath()
  ctx.fill(); ctx.restore()
}

// ── Component ───────────────────────────────────────────────────────────
export function TopView() {
  const { path, selected, playing, animT } = useStore()

  const draw = useCallback((ctx: CanvasRenderingContext2D, w: number, h: number) => {
    const { scale, worldPan: pan } = getCam(VIEW)
    ctx.clearRect(0, 0, w, h)
    drawGrid(ctx, w, h, scale, pan)

    const samples = buildSpline({ wps: path.wps, closed: path.closed, roll: path.roll, standoff: path.standoff })

    if (samples.length > 1) {
      ctx.beginPath(); ctx.strokeStyle = '#38bdf8'; ctx.lineWidth = 1.5
      samples.forEach(({ wire }, i) => {
        const { sx, sy } = w2s(wire.x, wire.z, w, h, scale, pan)
        i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
      })
      ctx.stroke()

      if (path.standoff > 0.001) {
        ctx.beginPath(); ctx.strokeStyle = '#f97316'; ctx.lineWidth = 1; ctx.setLineDash([3, 3])
        samples.forEach(({ actual }, i) => {
          const { sx, sy } = w2s(actual.x, actual.z, w, h, scale, pan)
          i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
        })
        ctx.stroke(); ctx.setLineDash([])
      }
    }

    const { sx: px, sy: py } = w2s(0, 0, w, h, scale, pan)
    ctx.strokeStyle = '#4ade80'; ctx.lineWidth = 1.5
    ctx.beginPath(); ctx.moveTo(px - 6, py); ctx.lineTo(px + 6, py); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(px, py - 6); ctx.lineTo(px, py + 6); ctx.stroke()
    ctx.beginPath(); ctx.arc(px, py, 3, 0, Math.PI * 2); ctx.fillStyle = '#4ade80'; ctx.fill()

    if (path.orient === 'target') {
      const { sx: tx, sy: ty } = w2s(path.target.x, path.target.z, w, h, scale, pan)
      ctx.strokeStyle = '#a78bfa'; ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(tx - 5, ty); ctx.lineTo(tx + 5, ty)
      ctx.moveTo(tx, ty - 5); ctx.lineTo(tx, ty + 5)
      ctx.stroke()
      ctx.beginPath(); ctx.arc(tx, ty, 3, 0, Math.PI * 2); ctx.fillStyle = '#a78bfa'; ctx.fill()
    }

    path.wps.forEach((wp, i) => {
      const { sx, sy } = w2s(wp.x, wp.z, w, h, scale, pan)
      const isSel = i === selected
      ctx.beginPath(); ctx.arc(sx, sy, isSel ? 6 : 4, 0, Math.PI * 2)
      ctx.fillStyle = isSel ? '#fbbf24' : '#94a3b8'; ctx.fill()
      if (isSel) { ctx.strokeStyle = '#fbbf24'; ctx.lineWidth = 1.5; ctx.stroke() }
      ctx.fillStyle = isSel ? '#fbbf24' : '#555560'
      ctx.font = '9px Courier New, monospace'
      ctx.fillText(String(i), sx + 7, sy - 4)
    })

    if (playing && path.wps.length >= 2) {
      const nSegs = path.wps.length - 1
      const wire   = evalAt(path.wps, animT, path.closed)
      const tan    = tangentAt(path.wps, animT, path.closed)
      const frac   = animT / nSegs
      const ap     = actualPos(wire, tan, frac, path.roll, path.standoff)
      const facing = shipFacing(ap, tan, path.orient, path.target)
      const { sx, sy } = w2s(ap.x, ap.z, w, h, scale, pan)
      drawShipArrow(ctx, sx, sy, facing.x, facing.z, '#f97316')
    }

    ctx.fillStyle = '#2a2a35'; ctx.font = '9px Courier New, monospace'
    ctx.fillText('Z →', w - 28, h - 8)
    ctx.fillText('X ↑', 8, 14)
  }, [path, selected, playing, animT])

  const { cvRef, draw: redraw } = useOrthoCanvas(draw, [path, selected, playing, animT])

  // ── Interaction ──────────────────────────────────────────────────────
  type DragState =
    | { type: 'wp';  wpIdx: number; startSx: number; startSy: number; startWx: number; startWz: number }
    | { type: 'pan'; startSx: number; startSy: number; startPan: WorldPan; startScale: number }
  const drag     = useRef<DragState | null>(null)
  const hasMoved = useRef(false)
  const drawRef  = useRef(redraw)
  drawRef.current = redraw

  const getRect = () => cvRef.current!.getBoundingClientRect()

  function findNearWp(sx: number, sy: number, w: number, h: number): number {
    const wps = useStore.getState().path.wps
    const { scale, worldPan: pan } = getCam(VIEW)
    for (let i = 0; i < wps.length; i++) {
      const { sx: wx, sy: wy } = w2s(wps[i].x, wps[i].z, w, h, scale, pan)
      if ((sx - wx) ** 2 + (sy - wy) ** 2 < 64) return i
    }
    return -1
  }

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    hasMoved.current = false
    const cam = getCam(VIEW)

    if (e.button === 2 || e.button === 1) {
      drag.current = { type: 'pan', startSx: sx, startSy: sy, startPan: { ...cam.worldPan }, startScale: cam.scale }
      return
    }

    const idx = findNearWp(sx, sy, rect.width, rect.height)
    if (idx >= 0) {
      useStore.getState().setSelected(idx)
      const wp = useStore.getState().path.wps[idx]
      drag.current = { type: 'wp', wpIdx: idx, startSx: sx, startSy: sy, startWx: wp.x, startWz: wp.z }
    } else {
      drag.current = { type: 'pan', startSx: sx, startSy: sy, startPan: { ...cam.worldPan }, startScale: cam.scale }
    }
  }, [])

  const onMouseMove = useCallback((e: React.MouseEvent) => {
    if (!drag.current) return
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    hasMoved.current = true

    if (drag.current.type === 'pan') {
      const { startSx, startSy, startPan, startScale } = drag.current
      const cam = getCam(VIEW)
      // World-space pan: screen delta → world delta for the two axes this view controls (X, Z)
      cam.worldPan.z = startPan.z + (sx - startSx) / startScale
      cam.worldPan.x = startPan.x - (sy - startSy) / startScale
      notifyAll()
      return
    }

    if (drag.current.type === 'wp') {
      const { startWx, startWz, startSx, startSy, wpIdx } = drag.current
      const { scale } = getCam(VIEW)
      const wps = useStore.getState().path.wps
      const dx = sx - startSx, dy = sy - startSy
      const cv = cvRef.current
      if (e.shiftKey) {
        // Shift: constrain to dominant axis (total displacement from drag start).
        const lockH = Math.abs(dx) >= Math.abs(dy)
        if (cv) cv.style.cursor = lockH ? 'ew-resize' : 'ns-resize'
        useStore.getState().setWp(wpIdx, {
          ...wps[wpIdx],
          ...(lockH ? { z: startWz + dx / scale } : { x: startWx - dy / scale }),
        })
      } else {
        if (cv) cv.style.cursor = 'crosshair'
        useStore.getState().setWp(wpIdx, {
          ...wps[wpIdx],
          x: startWx - dy / scale,
          z: startWz + dx / scale,
        })
      }
    }
  }, [])

  const onMouseUp = useCallback((e: React.MouseEvent) => {
    if (!drag.current) return
    if (!hasMoved.current && drag.current.type === 'pan') {
      const rect = getRect()
      const sx = e.clientX - rect.left, sy = e.clientY - rect.top
      const { scale, worldPan: pan } = getCam(VIEW)
      const { wx, wz } = s2w(sx, sy, rect.width, rect.height, scale, pan)
      const sel = useStore.getState().selected
      const wps = useStore.getState().path.wps
      useStore.getState().addWp({ x: wx, y: sel >= 0 ? wps[sel].y : 0, z: wz }, sel >= 0 ? sel : undefined)
    }
    drag.current = null
  }, [])

  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault()
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    const cam = getCam(VIEW)
    const oldScale = cam.scale
    const newScale = Math.max(2, Math.min(80, oldScale * (e.deltaY > 0 ? 0.88 : 1.14)))
    // Adjust worldPan so the world point under cursor stays fixed on screen.
    // newPan.axis = oldPan.axis + screenOffset * (1/newScale - 1/oldScale)
    const f = 1 / newScale - 1 / oldScale
    cam.worldPan.z = cam.worldPan.z + (sx - rect.width  / 2) * f
    cam.worldPan.x = cam.worldPan.x + (rect.height / 2 - sy) * f
    cam.scale = newScale
    notifyAll()
  }, [])

  const onKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Delete' || e.key === 'Backspace') {
      const sel = useStore.getState().selected
      if (sel >= 0) useStore.getState().delWp(sel)
    }
  }, [])

  return (
    <canvas ref={cvRef} style={{ cursor: 'crosshair' }} tabIndex={0}
      onMouseDown={onMouseDown} onMouseMove={onMouseMove} onMouseUp={onMouseUp}
      onMouseLeave={() => { drag.current = null; if (cvRef.current) cvRef.current.style.cursor = 'crosshair' }}
      onWheel={onWheel} onKeyDown={onKeyDown}
      onContextMenu={(e) => e.preventDefault()} />
  )
}
