// Front View — YZ plane (looking forward along +X from behind player).
// Screen X → world Z (lateral).  Screen Y up → world Y (altitude).
// Dragging moves waypoints in Y and Z; X inherited from selected wp on click-to-add.

import { useRef, useCallback } from 'react'
import { useStore } from '../store'
import { buildSpline, evalAt, tangentAt, actualPos } from '../math/spline'
import { useOrthoCanvas } from './useOrthoCanvas'
import { getCam, notifyAll, WorldPan } from './orthoCamera'

const VIEW = 'front' as const

// ── World ↔ Screen ──────────────────────────────────────────────────────
// sx = w/2 + (worldPan.z + wz) * scale
// sy = h/2 - (worldPan.y + wy) * scale
function w2s(wz: number, wy: number, w: number, h: number, scale: number, pan: WorldPan) {
  return { sx: w / 2 + (pan.z + wz) * scale, sy: h / 2 - (pan.y + wy) * scale }
}
function s2w(sx: number, sy: number, w: number, h: number, scale: number, pan: WorldPan) {
  return {
    wz: (sx - w / 2) / scale - pan.z,
    wy: (h / 2 - sy) / scale - pan.y,
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
  ctx.strokeStyle = '#10202a'; ctx.lineWidth = 1
  const { sx: ax0, sy: ay0 } = w2s(-range, 0, w, h, scale, pan)
  const { sx: ax1, sy: ay1 } = w2s( range, 0, w, h, scale, pan)
  ctx.beginPath(); ctx.moveTo(ax0, ay0); ctx.lineTo(ax1, ay1); ctx.stroke()
  ctx.strokeStyle = '#102010'; ctx.lineWidth = 1
  const { sx: bx0, sy: by0 } = w2s(0, -range, w, h, scale, pan)
  const { sx: bx1, sy: by1 } = w2s(0,  range, w, h, scale, pan)
  ctx.beginPath(); ctx.moveTo(bx0, by0); ctx.lineTo(bx1, by1); ctx.stroke()
}

function drawShipDot(ctx: CanvasRenderingContext2D, sx: number, sy: number, color: string) {
  ctx.beginPath(); ctx.arc(sx, sy, 5, 0, Math.PI * 2); ctx.fillStyle = color; ctx.fill()
  ctx.strokeStyle = color; ctx.lineWidth = 1
  ctx.beginPath(); ctx.moveTo(sx - 8, sy); ctx.lineTo(sx + 8, sy); ctx.stroke()
  ctx.beginPath(); ctx.moveTo(sx, sy - 8); ctx.lineTo(sx, sy + 8); ctx.stroke()
}

// ── Component ───────────────────────────────────────────────────────────
export function FrontView() {
  const { path, selected, playing, animT } = useStore()

  const draw = useCallback((ctx: CanvasRenderingContext2D, w: number, h: number) => {
    const { scale, worldPan: pan } = getCam(VIEW)
    ctx.clearRect(0, 0, w, h)
    drawGrid(ctx, w, h, scale, pan)

    const samples = buildSpline({ wps: path.wps, closed: path.closed, roll: path.roll, standoff: path.standoff })

    if (samples.length > 1) {
      ctx.beginPath(); ctx.strokeStyle = '#38bdf8'; ctx.lineWidth = 1.5
      samples.forEach(({ wire }, i) => {
        const { sx, sy } = w2s(wire.z, wire.y, w, h, scale, pan)
        i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
      })
      ctx.stroke()

      if (path.standoff > 0.001) {
        ctx.beginPath(); ctx.strokeStyle = '#f97316'; ctx.lineWidth = 1; ctx.setLineDash([3, 3])
        samples.forEach(({ actual }, i) => {
          const { sx, sy } = w2s(actual.z, actual.y, w, h, scale, pan)
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
      const { sx: tx, sy: ty } = w2s(path.target.z, path.target.y, w, h, scale, pan)
      ctx.strokeStyle = '#a78bfa'; ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(tx - 5, ty); ctx.lineTo(tx + 5, ty)
      ctx.moveTo(tx, ty - 5); ctx.lineTo(tx, ty + 5)
      ctx.stroke()
      ctx.beginPath(); ctx.arc(tx, ty, 3, 0, Math.PI * 2); ctx.fillStyle = '#a78bfa'; ctx.fill()
    }

    path.wps.forEach((wp, i) => {
      const { sx, sy } = w2s(wp.z, wp.y, w, h, scale, pan)
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
      const wire  = evalAt(path.wps, animT, path.closed)
      const tan   = tangentAt(path.wps, animT, path.closed)
      const frac  = animT / nSegs
      const ap    = actualPos(wire, tan, frac, path.roll, path.standoff)
      const { sx, sy } = w2s(ap.z, ap.y, w, h, scale, pan)
      drawShipDot(ctx, sx, sy, '#f97316')
    }

    ctx.fillStyle = '#2a2a35'; ctx.font = '9px Courier New, monospace'
    ctx.fillText('Z →', w - 28, h - 8)
    ctx.fillText('Y ↑', 8, 14)
  }, [path, selected, playing, animT])

  const { cvRef, draw: redraw } = useOrthoCanvas(draw, [path, selected, playing, animT])

  type DragState =
    | { type: 'wp';  wpIdx: number; startSx: number; startSy: number; startWz: number; startWy: number }
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
      const { sx: wx, sy: wy } = w2s(wps[i].z, wps[i].y, w, h, scale, pan)
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
      drag.current = { type: 'wp', wpIdx: idx, startSx: sx, startSy: sy, startWz: wp.z, startWy: wp.y }
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
      cam.worldPan.z = startPan.z + (sx - startSx) / startScale
      cam.worldPan.y = startPan.y - (sy - startSy) / startScale
      notifyAll()
      return
    }

    if (drag.current.type === 'wp') {
      const { startWz, startWy, startSx, startSy, wpIdx } = drag.current
      const { scale } = getCam(VIEW)
      const wps = useStore.getState().path.wps
      useStore.getState().setWp(wpIdx, {
        ...wps[wpIdx],
        z: startWz + (sx - startSx) / scale,
        y: startWy - (sy - startSy) / scale,
      })
    }
  }, [])

  const onMouseUp = useCallback((e: React.MouseEvent) => {
    if (!drag.current) return
    if (!hasMoved.current && drag.current.type === 'pan') {
      const rect = getRect()
      const sx = e.clientX - rect.left, sy = e.clientY - rect.top
      const { scale, worldPan: pan } = getCam(VIEW)
      const { wz, wy } = s2w(sx, sy, rect.width, rect.height, scale, pan)
      const sel = useStore.getState().selected
      const wps = useStore.getState().path.wps
      const wx  = sel >= 0 ? wps[sel].x : 20
      useStore.getState().addWp({ x: wx, y: wy, z: wz }, sel >= 0 ? sel : undefined)
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
    const f = 1 / newScale - 1 / oldScale
    cam.worldPan.z = cam.worldPan.z + (sx - rect.width  / 2) * f
    cam.worldPan.y = cam.worldPan.y + (rect.height / 2 - sy) * f
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
      onMouseLeave={() => { drag.current = null }}
      onWheel={onWheel} onKeyDown={onKeyDown}
      onContextMenu={(e) => e.preventDefault()} />
  )
}
