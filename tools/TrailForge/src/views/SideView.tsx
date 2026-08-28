// Side View — XY plane (looking along +Z from the side).
// Screen X → world X (forward).  Screen Y up → world Y (altitude).
// Dragging moves waypoints in X and Y; Z inherited from selected wp on click-to-add.

import { useRef, useCallback, useMemo, useState, useEffect } from 'react'
import { useStore, PathData } from '../store'
import { CtxMenu } from '../ui/ContextMenu'
import type { Waypoint, Vec3 } from '../math/vec3'
import { buildSpline, evalAt, tangentAt, shipFacing, makeFrame, makeArcTable, type SplineSample } from '../math/spline'
import { getFrameAt } from '../math/frameCache'
import { evalCraftRoll } from '../math/craftRoll'
import { useOrthoCanvas } from './useOrthoCanvas'
import { getCam, notifyAll, WorldPan, framePoints } from './orthoCamera'
import { drawShipModel, rollFrame } from './shipModel2D'
import { drawOverlaysXY } from './overlays'
import { rotateAroundZ, translateWps } from '../math/pathOps'
import {
  drawBehaviorMarkers, hoveredEq, BehaviorHit,
  nearestArcFracOnScreen, hitTestBehaviors, hitToHovered, drawRollIndicator,
} from './behaviorMarkers'
import { pauseAfterCheckpoint, resumeTemporal } from './undoHelpers'

const VIEW = 'side' as const

// ── World ↔ Screen ──────────────────────────────────────────────────────
// sx = w/2 + (worldPan.x + wx) * scale
// sy = h/2 - (worldPan.y + wy) * scale
function w2s(wx: number, wy: number, w: number, h: number, scale: number, pan: WorldPan) {
  return { sx: w / 2 + (pan.x + wx) * scale, sy: h / 2 - (pan.y + wy) * scale }
}
function s2w(sx: number, sy: number, w: number, h: number, scale: number, pan: WorldPan) {
  return {
    wx: (sx - w / 2) / scale - pan.x,
    wy: (h / 2 - sy) / scale - pan.y,
  }
}
function projectFor(w: number, h: number, scale: number, pan: WorldPan) {
  return (v: Vec3): [number, number] => {
    const s = w2s(v.x, v.y, w, h, scale, pan)
    return [s.sx, s.sy]
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

// ── Component ───────────────────────────────────────────────────────────
export function SideView() {
  const { path, selected, multiSel, playing, animT, frameR, frameU, showOverlays, editGhost, setEditGhost,
          hoveredBehavior, mutedTracks, activeBehaviorTrack, behaviorsOpen } = useStore()
  const behaviorHitsRef = useRef<BehaviorHit[]>([])
  const samplesRef = useRef<SplineSample[]>([])

  // craftRollSegments' t is arc-length fraction; animT/wp-index are parameter-space —
  // must convert or roll timing drifts against the visual position (worse the more
  // unevenly waypoints are spaced). See math/spline.ts makeArcTable.
  const arcTable = useMemo(() => makeArcTable(path.wps, path.closed), [path])

  const ghostRef = useRef<{ path: PathData; wpIdx: number } | null>(null)
  const marqueeRef = useRef<{ startSx: number; startSy: number; curSx: number; curSy: number } | null>(null)

  const [ctxMenu, setCtxMenu] = useState<{ x: number; y: number; wpIdx: number; wx?: number; wy?: number } | null>(null)
  const rightCtxRef  = useRef<{ idx: number; x: number; y: number; wx?: number; wy?: number } | null>(null)
  const rightMovedRef = useRef(false)

  const draw = useCallback((ctx: CanvasRenderingContext2D, w: number, h: number) => {
    const { scale, worldPan: pan } = getCam(VIEW)
    ctx.clearRect(0, 0, w, h)
    drawGrid(ctx, w, h, scale, pan)

    if (showOverlays) {
      drawOverlaysXY(ctx, (wx, wy) => {
        const { sx, sy } = w2s(wx, wy, w, h, scale, pan)
        return [sx, sy]
      })
    }

    // ── Ghost ────────────────────────────────────────────────────────────
    if (ghostRef.current !== null) {
      const { path: gp, wpIdx } = ghostRef.current
      const gSamples = buildSpline({ wps: gp.wps, closed: gp.closed })
      if (gSamples.length > 1) {
        ctx.save()
        ctx.globalAlpha = 0.25; ctx.setLineDash([5, 4])
        ctx.beginPath(); ctx.strokeStyle = '#38bdf8'; ctx.lineWidth = 1.5
        gSamples.forEach(({ wire }, i) => {
          const { sx, sy } = w2s(wire.x, wire.y, w, h, scale, pan)
          i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
        })
        ctx.stroke(); ctx.restore()
      }
      const gWp = gp.wps[wpIdx]
      const { sx: gx, sy: gy } = w2s(gWp.x, gWp.y, w, h, scale, pan)
      const cur = path.wps[wpIdx]
      if (cur) {
        const { sx: cx, sy: cy } = w2s(cur.x, cur.y, w, h, scale, pan)
        ctx.save()
        ctx.globalAlpha = 0.4; ctx.setLineDash([2, 3])
        ctx.strokeStyle = '#fbbf24'; ctx.lineWidth = 1
        ctx.beginPath(); ctx.moveTo(gx, gy); ctx.lineTo(cx, cy); ctx.stroke()
        ctx.restore()
      }
      ctx.save()
      ctx.globalAlpha = 0.35; ctx.setLineDash([3, 3])
      ctx.beginPath(); ctx.arc(gx, gy, 5, 0, Math.PI * 2)
      ctx.strokeStyle = '#94a3b8'; ctx.lineWidth = 1.5; ctx.stroke()
      ctx.restore()
    }

    // ── Store ghost (shown in all views while node-edit dialog is open) ───
    if (ghostRef.current === null && editGhost !== null) {
      const { path: gp, wpIdx } = editGhost
      const gSamples = buildSpline({ wps: gp.wps, closed: gp.closed })
      if (gSamples.length > 1) {
        ctx.save()
        ctx.globalAlpha = 0.25; ctx.setLineDash([5, 4])
        ctx.beginPath(); ctx.strokeStyle = '#38bdf8'; ctx.lineWidth = 1.5
        gSamples.forEach(({ wire }, i) => {
          const { sx, sy } = w2s(wire.x, wire.y, w, h, scale, pan)
          i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
        })
        ctx.stroke(); ctx.restore()
      }
      const gWp = gp.wps[wpIdx]
      const { sx: gx, sy: gy } = w2s(gWp.x, gWp.y, w, h, scale, pan)
      const cur = path.wps[wpIdx]
      if (cur) {
        const { sx: cx, sy: cy } = w2s(cur.x, cur.y, w, h, scale, pan)
        ctx.save()
        ctx.globalAlpha = 0.4; ctx.setLineDash([2, 3])
        ctx.strokeStyle = '#fbbf24'; ctx.lineWidth = 1
        ctx.beginPath(); ctx.moveTo(gx, gy); ctx.lineTo(cx, cy); ctx.stroke()
        ctx.restore()
      }
      ctx.save()
      ctx.globalAlpha = 0.35; ctx.setLineDash([3, 3])
      ctx.beginPath(); ctx.arc(gx, gy, 5, 0, Math.PI * 2)
      ctx.strokeStyle = '#94a3b8'; ctx.lineWidth = 1.5; ctx.stroke()
      ctx.restore()
    }

    const samples = buildSpline({ wps: path.wps, closed: path.closed })
    samplesRef.current = samples

    if (samples.length > 1) {
      ctx.beginPath(); ctx.strokeStyle = '#38bdf8'; ctx.lineWidth = 1.5
      samples.forEach(({ wire }, i) => {
        const { sx, sy } = w2s(wire.x, wire.y, w, h, scale, pan)
        i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
      })
      ctx.stroke()
    }

    const { sx: px, sy: py } = w2s(0, 0, w, h, scale, pan)
    ctx.strokeStyle = '#4ade80'; ctx.lineWidth = 1.5
    ctx.beginPath(); ctx.moveTo(px - 6, py); ctx.lineTo(px + 6, py); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(px, py - 6); ctx.lineTo(px, py + 6); ctx.stroke()
    ctx.beginPath(); ctx.arc(px, py, 3, 0, Math.PI * 2); ctx.fillStyle = '#4ade80'; ctx.fill()

    if (path.orient === 'target') {
      const { sx: tx, sy: ty } = w2s(path.target.x, path.target.y, w, h, scale, pan)
      ctx.strokeStyle = '#a78bfa'; ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(tx - 5, ty); ctx.lineTo(tx + 5, ty)
      ctx.moveTo(tx, ty - 5); ctx.lineTo(tx, ty + 5)
      ctx.stroke()
      ctx.beginPath(); ctx.arc(tx, ty, 3, 0, Math.PI * 2); ctx.fillStyle = '#a78bfa'; ctx.fill()
    }

    // Segment-track spans + craftRoll spans + trigger diamonds (draggable; under waypoint dots)
    if (behaviorsOpen) {
      behaviorHitsRef.current = drawBehaviorMarkers(ctx, samples, path, projectFor(w, h, scale, pan),
        hoveredBehavior, activeBehaviorTrack)
    } else {
      behaviorHitsRef.current = []
    }

    // ── Roll arc indicators at each waypoint ──────────────────────────────
    const crSegsAll = path.craftRollSegments ?? []
    if (crSegsAll.length > 0) {
      const nSegsWp = path.closed ? path.wps.length : Math.max(path.wps.length - 1, 1)
      path.wps.forEach((wp, i) => {
        const pf  = nSegsWp > 0 ? i / nSegsWp : 0
        const deg = evalCraftRoll(crSegsAll, arcTable.paramToArc(pf), path.craftRollLoopSeam)
        if (Math.abs(deg) < 0.5) return
        const { sx, sy } = w2s(wp.x, wp.y, w, h, scale, pan)
        drawRollIndicator(ctx, sx, sy, deg, 10, 0.65, 1.2)
      })
    }

    path.wps.forEach((wp, i) => {
      const { sx, sy } = w2s(wp.x, wp.y, w, h, scale, pan)
      const isSel = i === selected
      const isMulti = !isSel && multiSel.includes(i)
      ctx.beginPath(); ctx.arc(sx, sy, isSel ? 6 : isMulti ? 5 : 4, 0, Math.PI * 2)
      ctx.fillStyle = isSel ? '#fbbf24' : isMulti ? '#a78bfa' : '#94a3b8'; ctx.fill()
      if (isSel || isMulti) { ctx.strokeStyle = isSel ? '#fbbf24' : '#a78bfa'; ctx.lineWidth = 1.5; ctx.stroke() }
      ctx.fillStyle = isSel ? '#fbbf24' : isMulti ? '#a78bfa' : '#555560'
      ctx.font = '9px Courier New, monospace'
      ctx.fillText(String(i), sx + 7, sy - 4)
    })

    if (path.wps.length >= 2) {
      const nSegs     = path.closed ? path.wps.length : path.wps.length - 1
      const animFrac  = nSegs > 0 ? Math.max(0, Math.min(1, (animT % nSegs) / nSegs)) : 0
      const wire      = evalAt(path.wps, animT, path.closed)
      const tan       = tangentAt(path.wps, animT, path.closed)

      // Apply behavior track overrides (skip muted tracks)
      const crSegs       = mutedTracks['craftRoll'] ? [] : (path.craftRollSegments ?? [])
      const craftRollDeg = evalCraftRoll(crSegs, arcTable.paramToArc(animFrac), path.craftRollLoopSeam)

      const facing = shipFacing(wire, tan, path.orient, path.target)
      let R, U
      if (path.orient === 'target') {
        ;({ R, U } = makeFrame(facing))
      } else if (playing) {
        R = frameR; U = frameU
      } else {
        ;({ R, U } = getFrameAt(animFrac) ?? makeFrame(facing))
      }
      const { rolledU, rolledR } = rollFrame(U, R, craftRollDeg)
      drawShipModel(ctx, wire, facing, rolledU, rolledR, (wv) => {
        const s = w2s(wv.x, wv.y, w, h, scale, pan)
        return [s.sx, s.sy]
      })
      // Roll arc overlay at playhead (always shown while path exists)
      if (Math.abs(craftRollDeg) > 0.5) {
        const { sx: shipSx, sy: shipSy } = w2s(wire.x, wire.y, w, h, scale, pan)
        drawRollIndicator(ctx, shipSx, shipSy, craftRollDeg, 14, 0.9, 1.5)
      }
    }

    ctx.fillStyle = '#2a2a35'; ctx.font = '9px Courier New, monospace'
    ctx.fillText('X →', w - 28, h - 8)
    ctx.fillText('Y ↑', 8, 14)

    if (opHintRef.current) {
      ctx.save()
      ctx.font = 'bold 11px Courier New, monospace'
      ctx.fillStyle = '#fbbf24'
      ctx.textAlign = 'center'
      ctx.fillText(opHintRef.current, w / 2, 22)
      ctx.textAlign = 'left'
      ctx.restore()
    }

    if (marqueeRef.current) {
      const { startSx, startSy, curSx, curSy } = marqueeRef.current
      const rx = Math.min(startSx, curSx), ry = Math.min(startSy, curSy)
      const rw = Math.abs(curSx - startSx), rh = Math.abs(curSy - startSy)
      ctx.save()
      ctx.setLineDash([4, 3]); ctx.strokeStyle = '#a78bfa'; ctx.lineWidth = 1
      ctx.strokeRect(rx, ry, rw, rh)
      ctx.fillStyle = 'rgba(167,139,250,0.08)'; ctx.fillRect(rx, ry, rw, rh)
      ctx.restore()
    }
  }, [path, arcTable, selected, multiSel, playing, animT, frameR, frameU, showOverlays, editGhost, hoveredBehavior, mutedTracks, activeBehaviorTrack, behaviorsOpen])

  const { cvRef, draw: redraw } = useOrthoCanvas(draw, [path, selected, multiSel, playing, animT, editGhost, hoveredBehavior])

  // ── Frame-to-fit listener (F key / period) ────────────────────────────
  useEffect(() => {
    const fn = (e: Event) => {
      const { pane, wps } = (e as CustomEvent<{ pane: string; wps: Array<{ x: number; y: number; z: number }> }>).detail
      if (pane !== 'side' && pane !== 'all') return
      const canvas = cvRef.current
      if (!canvas) return
      const rect = canvas.getBoundingClientRect()
      framePoints('side', wps.length > 0 ? wps : useStore.getState().path.wps, rect.width, rect.height)
    }
    window.addEventListener('tf-frame', fn)
    return () => window.removeEventListener('tf-frame', fn)
  }, [cvRef])

  type DragState =
    | { type: 'wp';        wpIdx: number; startSx: number; startSy: number; startWx: number; startWy: number }
    | { type: 'mwp';       startSx: number; startSy: number; starts: Array<{ idx: number; wx: number; wy: number }> }
    | { type: 'marquee' }
    | { type: 'pan';       startSx: number; startSy: number; startPan: WorldPan; startScale: number }
    | { type: 'rotate';    startSx: number; snapshotWps: Waypoint[] }
    | { type: 'translate'; startSx: number; startSy: number; snapshotWps: Waypoint[] }
    | { type: 'behavior';  hit: BehaviorHit; startArcFrac: number; startT: number; startDur: number }
  const drag      = useRef<DragState | null>(null)
  const hasMoved  = useRef(false)
  const drawRef   = useRef(redraw)
  const opHintRef = useRef('')
  drawRef.current = redraw

  const getRect = () => cvRef.current!.getBoundingClientRect()

  function findNearWp(sx: number, sy: number, w: number, h: number): number {
    const wps = useStore.getState().path.wps
    const { scale, worldPan: pan } = getCam(VIEW)
    for (let i = 0; i < wps.length; i++) {
      const { sx: wx, sy: wy } = w2s(wps[i].x, wps[i].y, w, h, scale, pan)
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

    if (e.button === 0 && e.altKey) {
      const p = useStore.getState().path
      pauseAfterCheckpoint()
      drag.current = { type: 'rotate', startSx: sx, snapshotWps: p.wps.map(w => ({ ...w })) }
      if (cvRef.current) cvRef.current.style.cursor = 'grabbing'
      return
    }
    if (e.button === 0 && e.ctrlKey) {
      const p = useStore.getState().path
      pauseAfterCheckpoint()
      drag.current = { type: 'translate', startSx: sx, startSy: sy, snapshotWps: p.wps.map(w => ({ ...w })) }
      if (cvRef.current) cvRef.current.style.cursor = 'move'
      return
    }

    if (e.button === 1) {
      drag.current = { type: 'pan', startSx: sx, startSy: sy, startPan: { ...cam.worldPan }, startScale: cam.scale }
      return
    }
    if (e.button === 2) {
      const nearIdx = findNearWp(sx, sy, rect.width, rect.height)
      rightMovedRef.current = false
      if (nearIdx >= 0) {
        rightCtxRef.current = { idx: nearIdx, x: e.clientX, y: e.clientY }
      } else {
        const { scale, worldPan: pan } = getCam(VIEW)
        const { wx, wy } = s2w(sx, sy, rect.width, rect.height, scale, pan)
        rightCtxRef.current = { idx: -1, x: e.clientX, y: e.clientY, wx, wy }
      }
      drag.current = { type: 'pan', startSx: sx, startSy: sy, startPan: { ...cam.worldPan }, startScale: cam.scale }
      return
    }

    const idx = findNearWp(sx, sy, rect.width, rect.height)
    if (idx >= 0) {
      const { multiSel: ms } = useStore.getState()
      if (ms.length > 0 && ms.includes(idx)) {
        const wps = useStore.getState().path.wps
        pauseAfterCheckpoint()
        const starts = ms.map(i => ({ idx: i, wx: wps[i].x, wy: wps[i].y }))
        drag.current = { type: 'mwp', startSx: sx, startSy: sy, starts }
        const p = useStore.getState().path
        ghostRef.current = { path: { ...p, wps: [...p.wps] }, wpIdx: idx }
      } else {
        useStore.getState().setMultiSel([])
        useStore.getState().setSelected(idx)
        const wp = useStore.getState().path.wps[idx]
        drag.current = { type: 'wp', wpIdx: idx, startSx: sx, startSy: sy, startWx: wp.x, startWy: wp.y }
        const p = useStore.getState().path
        pauseAfterCheckpoint()
        ghostRef.current = { path: { ...p, wps: [...p.wps] }, wpIdx: idx }
      }
      return
    }

    if (behaviorsOpen) {
      const { scale, worldPan: pan } = getCam(VIEW)
      const project = projectFor(rect.width, rect.height, scale, pan)
      const hit = hitTestBehaviors(behaviorHitsRef.current, samplesRef.current, useStore.getState().path, project, sx, sy)
      if (hit) {
        pauseAfterCheckpoint()
        const startArcFrac = nearestArcFracOnScreen(samplesRef.current, project, sx, sy)
        const st = useStore.getState()
        let startT = 0, startDur = 0
        if (hit.kind === 'trigger') {
          startT = st.path.triggers[hit.index]?.t ?? 0
        } else if (hit.category === 'craftRoll') {
          const seg = st.path.craftRollSegments.find(s => s.id === hit.id)
          startT = seg?.t ?? 0; startDur = seg?.duration ?? 0
        } else {
          const seg = (st.path.segmentTracks[hit.trackName] ?? []).find(s => s.id === hit.id)
          startT = seg?.t ?? 0; startDur = seg?.duration ?? 0
        }
        drag.current = { type: 'behavior', hit, startArcFrac, startT, startDur }
        useStore.getState().setHoveredBehavior(hitToHovered(hit))
        return
      }
    }

    if (e.shiftKey) {
      marqueeRef.current = { startSx: sx, startSy: sy, curSx: sx, curSy: sy }
      drag.current = { type: 'marquee' }
    } else {
      useStore.getState().setMultiSel([])
      drag.current = { type: 'pan', startSx: sx, startSy: sy, startPan: { ...cam.worldPan }, startScale: cam.scale }
    }
  }, [behaviorsOpen])

  const onMouseMove = useCallback((e: React.MouseEvent) => {
    if (rightCtxRef.current !== null) rightMovedRef.current = true
    // Hover hit-test for behavior markers when not dragging
    if (!drag.current) {
      const rect = getRect()
      const sx = e.clientX - rect.left, sy = e.clientY - rect.top
      const { scale, worldPan: pan } = getCam(VIEW)
      const project = projectFor(rect.width, rect.height, scale, pan)
      const hit = hitTestBehaviors(behaviorHitsRef.current, samplesRef.current, useStore.getState().path, project, sx, sy)
      const found = hitToHovered(hit)
      const cur = useStore.getState().hoveredBehavior
      if (!hoveredEq(found, cur)) useStore.getState().setHoveredBehavior(found)
      return
    }
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    hasMoved.current = true

    if (drag.current.type === 'rotate') {
      const dx = sx - drag.current.startSx
      const theta = dx * Math.PI / 180
      const rotated = rotateAroundZ(drag.current.snapshotWps, theta)
      useStore.getState().replaceWps(rotated)
      opHintRef.current = `↻ Z  ${(theta * 180 / Math.PI).toFixed(1)}°`
      drawRef.current()
      return
    }

    if (drag.current.type === 'translate') {
      const { startSx, startSy, snapshotWps } = drag.current
      const { scale } = getCam(VIEW)
      const dx = sx - startSx, dy = sy - startSy
      // SIDE: screen-X → world-X, screen-Y → world-Y (inverted)
      const translated = translateWps(snapshotWps, dx / scale, -dy / scale, 0)
      useStore.getState().replaceWps(translated)
      opHintRef.current = `⇥ X ${(dx / scale).toFixed(1)}  Y ${(-dy / scale).toFixed(1)}`
      drawRef.current()
      return
    }

    if (drag.current.type === 'pan') {
      const { startSx, startSy, startPan, startScale } = drag.current
      const cam = getCam(VIEW)
      cam.worldPan.x = startPan.x + (sx - startSx) / startScale
      cam.worldPan.y = startPan.y - (sy - startSy) / startScale
      notifyAll()
      return
    }

    if (drag.current.type === 'marquee') {
      if (marqueeRef.current) {
        marqueeRef.current.curSx = sx
        marqueeRef.current.curSy = sy
        drawRef.current()
      }
      return
    }

    if (drag.current.type === 'mwp') {
      const { startSx, startSy, starts } = drag.current
      const { scale } = getCam(VIEW)
      const dx = sx - startSx, dy = sy - startSy
      for (const s of starts) {
        const wps = useStore.getState().path.wps
        useStore.getState().setWp(s.idx, { ...wps[s.idx], x: s.wx + dx / scale, y: s.wy - dy / scale })
      }
      return
    }

    if (drag.current.type === 'behavior') {
      const { hit, startArcFrac, startT, startDur } = drag.current
      const { scale, worldPan: pan } = getCam(VIEW)
      const project = projectFor(rect.width, rect.height, scale, pan)
      const curArcFrac = nearestArcFracOnScreen(samplesRef.current, project, sx, sy)
      const delta = curArcFrac - startArcFrac
      const st = useStore.getState()

      if (hit.kind === 'trigger') {
        const tr = st.path.triggers[hit.index]
        if (tr) st.updateTrigger(hit.index, { ...tr, t: Math.max(0, Math.min(1, startT + delta)) })
      } else if (hit.category === 'craftRoll') {
        const seg = st.path.craftRollSegments.find(s => s.id === hit.id)
        if (seg) {
          if (hit.zone === 'body') {
            st.updateCraftRollSegment(hit.id, { t: Math.max(0, Math.min(1 - seg.duration, startT + delta)) })
          } else if (hit.zone === 'right') {
            st.updateCraftRollSegment(hit.id, { duration: Math.max(0.01, Math.min(1 - seg.t, startDur + delta)) })
          } else {
            const newT   = Math.max(0, Math.min(startT + startDur - 0.01, startT + delta))
            const newDur = Math.max(0.01, startT + startDur - newT)
            st.updateCraftRollSegment(hit.id, { t: newT, duration: newDur })
          }
        }
      } else {
        const seg = (st.path.segmentTracks[hit.trackName] ?? []).find(s => s.id === hit.id)
        if (seg) {
          if (hit.zone === 'body') {
            st.updateSegment(hit.trackName, hit.id, { t: Math.max(0, Math.min(1 - seg.duration, startT + delta)) })
          } else if (hit.zone === 'right') {
            st.updateSegment(hit.trackName, hit.id, { duration: Math.max(0.01, Math.min(1 - seg.t, startDur + delta)) })
          } else {
            const newT   = Math.max(0, Math.min(startT + startDur - 0.01, startT + delta))
            const newDur = Math.max(0.01, startT + startDur - newT)
            st.updateSegment(hit.trackName, hit.id, { t: newT, duration: newDur })
          }
        }
      }
      drawRef.current()
      return
    }

    if (drag.current.type === 'wp') {
      const { startWx, startWy, startSx, startSy, wpIdx } = drag.current
      const { scale } = getCam(VIEW)
      const wps = useStore.getState().path.wps
      const dx = sx - startSx, dy = sy - startSy
      const cv = cvRef.current
      if (e.shiftKey) {
        const lockH = Math.abs(dx) >= Math.abs(dy)
        if (cv) cv.style.cursor = lockH ? 'ew-resize' : 'ns-resize'
        useStore.getState().setWp(wpIdx, {
          ...wps[wpIdx],
          ...(lockH ? { x: startWx + dx / scale } : { y: startWy - dy / scale }),
        })
      } else {
        if (cv) cv.style.cursor = 'crosshair'
        useStore.getState().setWp(wpIdx, {
          ...wps[wpIdx],
          x: startWx + dx / scale,
          y: startWy - dy / scale,
        })
      }
    }
  }, [])

  const onMouseUp = useCallback((_e: React.MouseEvent) => {
    if (!drag.current) return
    const wasWpDrag        = drag.current.type === 'wp'
    const wasMwpDrag       = drag.current.type === 'mwp'
    const wasTransformDrag = drag.current.type === 'rotate' || drag.current.type === 'translate'
    const wasMarquee       = drag.current.type === 'marquee'
    const wasBehaviorDrag  = drag.current.type === 'behavior'
    if (ghostRef.current !== null) { ghostRef.current = null; drawRef.current() }

    if (wasBehaviorDrag) {
      drag.current = null
      resumeTemporal()
      return
    }

    if (wasTransformDrag) {
      opHintRef.current = ''
      if (cvRef.current) cvRef.current.style.cursor = 'crosshair'
      drag.current = null
      resumeTemporal()
      return
    }

    if (wasWpDrag || wasMwpDrag) {
      drag.current = null
      resumeTemporal()
      return
    }

    if (wasMarquee) {
      const mr = marqueeRef.current
      if (mr) {
        const rect = getRect()
        const { scale, worldPan: pan } = getCam(VIEW)
        const minSx = Math.min(mr.startSx, mr.curSx), maxSx = Math.max(mr.startSx, mr.curSx)
        const minSy = Math.min(mr.startSy, mr.curSy), maxSy = Math.max(mr.startSy, mr.curSy)
        const wps = useStore.getState().path.wps
        const found: number[] = []
        wps.forEach((wp, i) => {
          const { sx, sy } = w2s(wp.x, wp.y, rect.width, rect.height, scale, pan)
          if (sx >= minSx && sx <= maxSx && sy >= minSy && sy <= maxSy) found.push(i)
        })
        useStore.getState().setMultiSel(found)
        if (found.length > 0) useStore.getState().setSelected(found[0])
        marqueeRef.current = null
        drawRef.current()
      }
      drag.current = null
      return
    }

    drag.current = null
  }, [])

  const onDoubleClick = useCallback((e: React.MouseEvent) => {
    if (e.button !== 0) return
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    if (findNearWp(sx, sy, rect.width, rect.height) >= 0) return
    const { scale, worldPan: pan } = getCam(VIEW)
    const { wx, wy } = s2w(sx, sy, rect.width, rect.height, scale, pan)
    const sel = useStore.getState().selected
    const wps = useStore.getState().path.wps
    useStore.getState().addWp({ x: wx, y: wy, z: sel >= 0 ? wps[sel].z : 0 }, sel >= 0 ? sel : undefined)
  }, [])

  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault()
    const rect = getRect()
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top
    const cam = getCam(VIEW)
    const oldScale = cam.scale
    const newScale = Math.max(2, Math.min(80, oldScale * (e.deltaY > 0 ? 0.88 : 1.14)))
    const f = 1 / newScale - 1 / oldScale
    cam.worldPan.x = cam.worldPan.x + (sx - rect.width  / 2) * f
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
    <>
      <canvas ref={cvRef} style={{ cursor: 'crosshair' }} tabIndex={0}
        onMouseEnter={() => cvRef.current?.focus()}
        onMouseDown={onMouseDown} onMouseMove={onMouseMove} onMouseUp={onMouseUp} onDoubleClick={onDoubleClick}
        onMouseLeave={() => {
          drag.current = null
          opHintRef.current = ''
          rightCtxRef.current = null
          if (cvRef.current) cvRef.current.style.cursor = 'crosshair'
          if (ghostRef.current !== null) ghostRef.current = null
          if (marqueeRef.current !== null) marqueeRef.current = null
          useStore.getState().setHoveredBehavior(null)
          drawRef.current()
        }}
        onWheel={onWheel} onKeyDown={onKeyDown}
        onContextMenu={(e) => {
          e.preventDefault()
          const rc = rightCtxRef.current
          if (rc !== null && !rightMovedRef.current) {
            setCtxMenu({ x: e.clientX, y: e.clientY, wpIdx: rc.idx, wx: rc.wx, wy: rc.wy })
          }
          rightCtxRef.current = null
        }} />
      {ctxMenu && (
        <CtxMenu x={ctxMenu.x} y={ctxMenu.y} wpIdx={ctxMenu.wpIdx}
          onClose={() => setCtxMenu(null)}
          onAddHere={ctxMenu.wpIdx < 0 && ctxMenu.wx !== undefined ? () => {
            const sel = useStore.getState().selected
            const wps = useStore.getState().path.wps
            useStore.getState().addWp(
              { x: ctxMenu.wx!, y: ctxMenu.wy!, z: sel >= 0 ? wps[sel].z : 0 },
              sel >= 0 ? sel : undefined,
            )
          } : undefined}
          onEditCoords={ctxMenu.wpIdx >= 0 ? () => {
            const p = useStore.getState().path
            pauseAfterCheckpoint()
            setEditGhost({ path: { ...p, wps: [...p.wps] }, wpIdx: ctxMenu.wpIdx })
          } : undefined}
        />
      )}
    </>
  )
}
