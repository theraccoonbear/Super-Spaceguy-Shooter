// Shared drawing + hit-testing utilities for behavior markers — segment
// tracks (craftRoll + scalar tracks) and discrete triggers. Used identically
// by all three ortho views (TopView, SideView, FrontView) so canvas
// rendering and drag interaction never diverge between them.
//
// Exports:
//   wireAtFrac()              — wire world position at arc-length fraction f
//   nearestArcFracOnScreen()  — inverse of wireAtFrac: screen point → nearest t
//   drawRollIndicator()       — the roll-angle ring+arm glyph (shared by all callers)
//   drawBehaviorMarkers()     — draws segment spans + trigger diamonds; returns hit regions
//   hitTestBehaviors()        — nearest BehaviorHit under a screen point (or null)
//   hoveredEq()                — structural equality for HoveredBehavior

import type { PathData, HoveredBehavior } from '../store'
import type { Vec3 } from '../math/vec3'

// ── Color palette ─────────────────────────────────────────────────────────
// Chosen to be visually distinct from:
//   waypoint dots:     grey #555560
//   selected wp:       yellow #fbbf24
//   multiSel wp:       purple #a78bfa
//   spline curve:      white/light (varies by theme)
// We avoid yellow and purple so behavior markers never blend with those UI elements.

const TRACK_PALETTE = [
  '#34d399', // emerald-400
  '#f87171', // red-400
  '#38bdf8', // sky-400
  '#fb923c', // orange-400
  '#f472b6', // pink-400
  '#4ade80', // green-400
]

/** Stable color for a track by hashing its name. */
export function trackColor(name: string): string {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
  return TRACK_PALETTE[h % TRACK_PALETTE.length]
}

const TRIGGER_COLORS: Record<string, string> = {
  fireMode:   '#f87171', // red
  weapon:     '#60a5fa', // blue
  shieldMode: '#facc15', // yellow
  invuln:     '#a3e635', // lime
  phase:      '#c084fc', // purple
  sound:      '#2dd4bf', // teal
  custom:     '#94a3b8', // slate
}

/** Color for a trigger event by type name. */
export function triggerColor(type: string): string {
  return TRIGGER_COLORS[type] ?? '#94a3b8'
}

const CR_CW  = '#f97316'   // orange — clockwise
const CR_CCW = '#38bdf8'   // blue   — counter-clockwise

// ── Arc-length lookup ─────────────────────────────────────────────────────

/** Return the wire world position at arc-length fraction f (0..1).
 *  Samples must be uniformly spaced by arc length (as returned by buildSpline). */
export function wireAtFrac(samples: Array<{ wire: Vec3 }>, f: number): Vec3 | null {
  if (samples.length === 0) return null
  const clamped = Math.max(0, Math.min(1, f))
  const idx = clamped * (samples.length - 1)
  const lo  = Math.floor(idx)
  const hi  = Math.min(lo + 1, samples.length - 1)
  const u   = idx - lo
  if (lo === hi) return samples[lo].wire
  const a = samples[lo].wire, b = samples[hi].wire
  return { x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u, z: a.z + (b.z - a.z) * u }
}

/** Inverse of wireAtFrac: given a screen point, find the arc-length fraction
 *  of the nearest point on the projected wire. Used to convert cursor
 *  position into a `t` value when dragging a behavior marker on a canvas.
 *  Uses the SAME index/(length-1) convention as wireAtFrac so a marker
 *  placed via wireAtFrac and re-picked via this function round-trips to
 *  the same t. */
export function nearestArcFracOnScreen(
  samples: Array<{ wire: Vec3 }>,
  project: (v: Vec3) => [number, number],
  sx: number, sy: number,
): number {
  const n = samples.length
  if (n === 0) return 0
  if (n === 1) return 0
  const pts = samples.map(s => project(s.wire))

  let bestI = 0, bestD = Infinity
  for (let i = 0; i < n; i++) {
    const dx = pts[i][0] - sx, dy = pts[i][1] - sy
    const d = dx * dx + dy * dy
    if (d < bestD) { bestD = d; bestI = i }
  }

  // Sub-sample refinement: project the cursor onto the polyline edges on
  // either side of the nearest sample, keep whichever is closer.
  let bestFracI = bestI, bestRefD = bestD
  const tryEdge = (i0: number, i1: number) => {
    if (i0 < 0 || i1 >= n) return
    const [x0, y0] = pts[i0], [x1, y1] = pts[i1]
    const ex = x1 - x0, ey = y1 - y0
    const len2 = ex * ex + ey * ey
    if (len2 < 1e-9) return
    const u = Math.max(0, Math.min(1, ((sx - x0) * ex + (sy - y0) * ey) / len2))
    const px = x0 + ex * u, py = y0 + ey * u
    const dx = px - sx, dy = py - sy
    const d = dx * dx + dy * dy
    if (d < bestRefD) { bestRefD = d; bestFracI = i0 + u }
  }
  tryEdge(bestI - 1, bestI)
  tryEdge(bestI, bestI + 1)

  return Math.max(0, Math.min(1, bestFracI / (n - 1)))
}

function pointToPolylineDist2(pts: Array<[number, number]>, sx: number, sy: number): number {
  let best = Infinity
  for (let i = 0; i < pts.length - 1; i++) {
    const [x0, y0] = pts[i], [x1, y1] = pts[i + 1]
    const ex = x1 - x0, ey = y1 - y0
    const len2 = ex * ex + ey * ey
    const u = len2 < 1e-9 ? 0 : Math.max(0, Math.min(1, ((sx - x0) * ex + (sy - y0) * ey) / len2))
    const px = x0 + ex * u, py = y0 + ey * u
    const dx = px - sx, dy = py - sy
    const d = dx * dx + dy * dy
    if (d < best) best = d
  }
  return best
}

// ── Hover equality ────────────────────────────────────────────────────────

/** Structural equality for HoveredBehavior — used in view onMouseMove to avoid
 *  spurious setHoveredBehavior calls (which would trigger needless re-renders). */
export function hoveredEq(a: HoveredBehavior, b: HoveredBehavior): boolean {
  if (a === b) return true
  if (!a || !b) return false
  if (a.type !== b.type) return false
  if (a.type === 'track'   && b.type === 'track')   return a.name  === b.name
  if (a.type === 'trigger' && b.type === 'trigger') return a.index === b.index
  if (a.type === 'craftRoll') return true
  return false
}

// ── Canvas drawing + hit-testing ────────────────────────────────────────────

/** Screen-space hit region for a drawn marker — for hover/drag hit-testing in views.
 *  'segment' hits carry a zone: 'body' drags the whole span (moves t), 'left'/'right'
 *  drag that edge only (resizes duration), mirroring the panel ruler's drag zones. */
export type BehaviorHit =
  | { kind: 'trigger'; index: number; sx: number; sy: number }
  | { kind: 'segment'; category: 'craftRoll'; id: string; zone: 'body' | 'left' | 'right'; sx: number; sy: number }
  | { kind: 'segment'; category: 'scalar'; trackName: string; id: string; zone: 'body' | 'left' | 'right'; sx: number; sy: number }

function drawSegmentSpan(
  ctx: CanvasRenderingContext2D,
  samples: Array<{ wire: Vec3 }>,
  project: (v: Vec3) => [number, number],
  t: number, duration: number, color: string,
  dim: boolean, hovered: boolean,
): { bodyPts: Array<[number, number]>; startPt: [number, number]; endPt: [number, number] } | null {
  const STEPS = 8
  const bodyPts: Array<[number, number]> = []
  for (let i = 0; i <= STEPS; i++) {
    const wp = wireAtFrac(samples, t + (duration * i) / STEPS)
    if (!wp) return null
    bodyPts.push(project(wp))
  }
  const startPt = bodyPts[0], endPt = bodyPts[bodyPts.length - 1]

  ctx.save()
  ctx.globalAlpha = dim ? 0.25 : hovered ? 1 : 0.85
  ctx.strokeStyle = color
  ctx.lineWidth = hovered ? 4 : 3
  ctx.beginPath()
  bodyPts.forEach(([x, y], i) => i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y))
  ctx.stroke()

  for (const [x, y] of [startPt, endPt]) {
    ctx.beginPath(); ctx.arc(x, y, hovered ? 4.5 : 3.5, 0, Math.PI * 2)
    ctx.fillStyle = color; ctx.fill()
    ctx.strokeStyle = 'rgba(255,255,255,0.6)'; ctx.lineWidth = 1; ctx.stroke()
  }
  ctx.restore()

  return { bodyPts, startPt, endPt }
}

/**
 * Draw segment-track spans (craftRoll + generic scalar tracks) and trigger
 * diamonds onto a 2D canvas context. Returns hit regions for hover/drag.
 *
 * @param ctx               Canvas 2D context to draw into.
 * @param samples           Uniform arc-length samples from buildSpline.
 * @param path              Current PathData.
 * @param project           Maps world Vec3 → canvas [sx, sy] (view-specific).
 * @param hovered           Currently highlighted item (from store.hoveredBehavior).
 * @param activeBehaviorTrack  Track (or 'craftRoll') currently expanded in the panel.
 *                          When set, its markers render full-opacity; all others are dimmed.
 */
export function drawBehaviorMarkers(
  ctx: CanvasRenderingContext2D,
  samples: Array<{ wire: Vec3 }>,
  path: PathData,
  project: (v: Vec3) => [number, number],
  hovered?: HoveredBehavior,
  activeBehaviorTrack?: string | null
): BehaviorHit[] {
  const scalarNames = Object.keys(path.segmentTracks ?? {})
  const hasScalar    = scalarNames.length > 0
  const hasCraftRoll = (path.craftRollSegments ?? []).length > 0
  const hasTriggers  = path.triggers.length > 0
  if (!hasScalar && !hasCraftRoll && !hasTriggers) return []

  const hits: BehaviorHit[] = []
  const hasActive = activeBehaviorTrack != null

  // ── craftRoll segment spans ────────────────────────────────────────────
  if (hasCraftRoll) {
    const isAct = activeBehaviorTrack === 'craftRoll'
    const dim   = hasActive && !isAct
    for (const seg of path.craftRollSegments) {
      const isHov = hovered?.type === 'craftRoll'
      const color = seg.direction === 'cw' ? CR_CW : CR_CCW
      const drawn = drawSegmentSpan(ctx, samples, project, seg.t, seg.duration, color, dim, isHov)
      if (!drawn) continue
      const [lx, ly] = drawn.startPt, [rx, ry] = drawn.endPt
      hits.push({ kind: 'segment', category: 'craftRoll', id: seg.id, zone: 'left',  sx: lx, sy: ly })
      hits.push({ kind: 'segment', category: 'craftRoll', id: seg.id, zone: 'right', sx: rx, sy: ry })
      const [mx, my] = drawn.bodyPts[Math.floor(drawn.bodyPts.length / 2)]
      hits.push({ kind: 'segment', category: 'craftRoll', id: seg.id, zone: 'body',  sx: mx, sy: my })
    }
  }

  // ── Scalar segment-track spans ─────────────────────────────────────────
  for (const name of scalarNames) {
    const color = trackColor(name)
    const isAct = activeBehaviorTrack === name
    const dim   = hasActive && !isAct
    for (const seg of path.segmentTracks[name]) {
      const isHov = hovered?.type === 'track' && hovered.name === name
      const drawn = drawSegmentSpan(ctx, samples, project, seg.t, seg.duration, color, dim, isHov)
      if (!drawn) continue
      const [lx, ly] = drawn.startPt, [rx, ry] = drawn.endPt
      hits.push({ kind: 'segment', category: 'scalar', trackName: name, id: seg.id, zone: 'left',  sx: lx, sy: ly })
      hits.push({ kind: 'segment', category: 'scalar', trackName: name, id: seg.id, zone: 'right', sx: rx, sy: ry })
      const [mx, my] = drawn.bodyPts[Math.floor(drawn.bodyPts.length / 2)]
      hits.push({ kind: 'segment', category: 'scalar', trackName: name, id: seg.id, zone: 'body',  sx: mx, sy: my })
    }
  }

  // ── Trigger diamonds ──────────────────────────────────────────────────
  for (let index = 0; index < path.triggers.length; index++) {
    const tr    = path.triggers[index]
    const color = triggerColor(tr.event.type)
    const wp    = wireAtFrac(samples, tr.t)
    if (!wp) continue
    const [sx, sy] = project(wp)
    hits.push({ kind: 'trigger', index, sx, sy })

    const isHov = hovered?.type === 'trigger' && hovered.index === index
    const s     = isHov ? 6 : 4

    if (isHov) {
      const g = s + 4
      ctx.beginPath()
      ctx.moveTo(sx, sy - g); ctx.lineTo(sx + g, sy)
      ctx.lineTo(sx, sy + g); ctx.lineTo(sx - g, sy)
      ctx.closePath()
      ctx.strokeStyle = color + '40'; ctx.lineWidth = 3; ctx.stroke()
    }
    ctx.beginPath()
    ctx.moveTo(sx,     sy - s); ctx.lineTo(sx + s, sy)
    ctx.lineTo(sx,     sy + s); ctx.lineTo(sx - s, sy)
    ctx.closePath()
    ctx.fillStyle   = isHov ? color : color + 'bb'
    ctx.fill()
    ctx.strokeStyle = color; ctx.lineWidth = isHov ? 2 : 1.5; ctx.stroke()
  }

  return hits
}

/** Nearest BehaviorHit to a screen point within HIT_R2, or null. Segment
 *  'body' hits are tested against the drawn polyline (not just the midpoint
 *  marker) so grabbing anywhere along a span works, not just its center. */
export function hitTestBehaviors(
  hits: BehaviorHit[],
  samples: Array<{ wire: Vec3 }>,
  path: PathData,
  project: (v: Vec3) => [number, number],
  sx: number, sy: number,
  hitR2 = 64,
): BehaviorHit | null {
  let best: BehaviorHit | null = null
  let bestD = hitR2
  for (const hit of hits) {
    if (hit.kind === 'segment' && hit.zone === 'body') {
      const segs = hit.category === 'craftRoll'
        ? path.craftRollSegments
        : (path.segmentTracks[hit.trackName] ?? [])
      const seg = segs.find(s => s.id === hit.id)
      if (!seg) continue
      const STEPS = 8
      const pts: Array<[number, number]> = []
      for (let i = 0; i <= STEPS; i++) {
        const wp = wireAtFrac(samples, seg.t + (seg.duration * i) / STEPS)
        if (wp) pts.push(project(wp))
      }
      const d = pointToPolylineDist2(pts, sx, sy)
      if (d < bestD) { bestD = d; best = hit }
      continue
    }
    const dx = sx - hit.sx, dy = sy - hit.sy
    const d = dx * dx + dy * dy
    if (d < bestD) { bestD = d; best = hit }
  }
  return best
}

/** Convert a BehaviorHit to the HoveredBehavior it should light up in the panel. */
export function hitToHovered(hit: BehaviorHit | null): HoveredBehavior {
  if (!hit) return null
  if (hit.kind === 'trigger') return { type: 'trigger', index: hit.index }
  if (hit.category === 'craftRoll') return { type: 'craftRoll' }
  return { type: 'track', name: hit.trackName }
}

// ── Roll indicator glyph (shared — was duplicated per-view + per-callsite) ──

/** Draw the roll-angle ring + radial arm glyph at a screen position.
 *  Orange = CW (positive degrees), blue = CCW (negative), clock-face
 *  convention (12 o'clock = 0°, clockwise positive). Shared by every
 *  ortho view's per-waypoint indicators and playhead overlay so the
 *  drawing code exists exactly once. */
export function drawRollIndicator(
  ctx: CanvasRenderingContext2D,
  sx: number, sy: number,
  degrees: number,
  radius: number,
  alpha: number,
  lineWidth: number,
) {
  const rad = (degrees % 360) * Math.PI / 180
  ctx.save()
  ctx.globalAlpha = alpha
  ctx.strokeStyle = degrees > 0 ? CR_CW : CR_CCW
  ctx.lineWidth = lineWidth
  ctx.beginPath(); ctx.arc(sx, sy, radius, 0, Math.PI * 2); ctx.stroke()
  ctx.beginPath(); ctx.moveTo(sx, sy - radius * 0.3)
  ctx.lineTo(sx + radius * Math.sin(rad), sy - radius * Math.cos(rad)); ctx.stroke()
  ctx.restore()
}
