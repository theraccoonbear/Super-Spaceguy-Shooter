// Shared drawing utilities for behavior markers — segment tracks (craftRoll +
// scalar tracks) and discrete triggers. Used identically by all three ortho
// views (TopView, SideView, FrontView) so rendering never diverges between
// them.
//
// Behavior markers are VIEW-ONLY reference overlays in ortho/3D views --
// never hit-tested, hovered, or draggable there. They're editable exclusively
// on the behavior's own timeline in BehaviorsPanel.tsx (which has its own,
// separate ruler-pixel hit-testing -- it does not use this module beyond the
// trackColor/triggerColor helpers). Do not reintroduce canvas hit-testing for
// behavior markers in any ortho/3D view -- see TrailForge's own CLAUDE.md,
// "Behaviors Panel — Invariants".
//
// Exports:
//   wireAtFrac()         — wire world position at arc-length fraction f
//   drawRollIndicator()  — the roll-angle ring+arm glyph (shared by all callers)
//   drawBehaviorMarkers() — draws segment spans + trigger diamonds (view-only)

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

// ── Canvas drawing ──────────────────────────────────────────────────────────

function drawSegmentSpan(
  ctx: CanvasRenderingContext2D,
  samples: Array<{ wire: Vec3 }>,
  project: (v: Vec3) => [number, number],
  t: number, duration: number, color: string,
  dim: boolean, hovered: boolean,
): void {
  const STEPS = 8
  const bodyPts: Array<[number, number]> = []
  for (let i = 0; i <= STEPS; i++) {
    const wp = wireAtFrac(samples, t + (duration * i) / STEPS)
    if (!wp) return
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
}

/**
 * Draw segment-track spans (craftRoll + generic scalar tracks) and trigger
 * diamonds onto a 2D canvas context. View-only reference overlay -- the
 * caller never hit-tests against this; editing happens exclusively on the
 * behavior's own timeline in BehaviorsPanel.tsx.
 *
 * @param ctx               Canvas 2D context to draw into.
 * @param samples           Uniform arc-length samples from buildSpline.
 * @param path              Current PathData.
 * @param project           Maps world Vec3 → canvas [sx, sy] (view-specific).
 * @param hovered           Currently highlighted item (from store.hoveredBehavior,
 *                          set by BehaviorsPanel -- never by this view's own mouse events).
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
): void {
  const scalarNames = Object.keys(path.segmentTracks ?? {})
  const hasScalar    = scalarNames.length > 0
  const hasCraftRoll = (path.craftRollSegments ?? []).length > 0
  const hasTriggers  = path.triggers.length > 0
  if (!hasScalar && !hasCraftRoll && !hasTriggers) return

  const hasActive = activeBehaviorTrack != null

  // ── craftRoll segment spans ────────────────────────────────────────────
  if (hasCraftRoll) {
    const isAct = activeBehaviorTrack === 'craftRoll'
    const dim   = hasActive && !isAct
    for (const seg of path.craftRollSegments) {
      const isHov = hovered?.type === 'craftRoll'
      const color = seg.direction === 'cw' ? CR_CW : CR_CCW
      drawSegmentSpan(ctx, samples, project, seg.t, seg.duration, color, dim, isHov)
    }
  }

  // ── Scalar segment-track spans ─────────────────────────────────────────
  for (const name of scalarNames) {
    const color = trackColor(name)
    const isAct = activeBehaviorTrack === name
    const dim   = hasActive && !isAct
    for (const seg of path.segmentTracks[name]) {
      const isHov = hovered?.type === 'track' && hovered.name === name
      drawSegmentSpan(ctx, samples, project, seg.t, seg.duration, color, dim, isHov)
    }
  }

  // ── Trigger diamonds ──────────────────────────────────────────────────
  for (let index = 0; index < path.triggers.length; index++) {
    const tr    = path.triggers[index]
    const color = triggerColor(tr.event.type)
    const wp    = wireAtFrac(samples, tr.t)
    if (!wp) continue
    const [sx, sy] = project(wp)

    const isHov = hovered?.type === 'trigger' && hovered.index === index
    const s     = isHov ? 7 : 5

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
