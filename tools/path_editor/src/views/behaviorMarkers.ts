// Shared drawing utilities for behavior track keyframe and trigger markers.
// Used by all three ortho views (TopView, SideView, FrontView).
//
// Exports:
//   evalTrack()          — evaluate a track at a given arc-frac t (0..1)
//   drawBehaviorMarkers() — draw colored circles + diamonds; returns hit regions
//   hoveredEq()          — structural equality for HoveredBehavior (avoids spurious re-renders)

import type { PathData, TrackKeyframe, HoveredBehavior } from '../store'
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

// ── Track evaluation (easing) ─────────────────────────────────────────────

function applyEase(s: number, ease: TrackKeyframe['ease']): number {
  switch (ease) {
    case 'linear':   return s
    case 'smooth':   return s * s * (3 - 2 * s)                    // smoothstep
    case 'ease-in':  return s * s * s                               // cubic ease-in
    case 'ease-out': { const t = 1 - s; return 1 - t * t * t }     // cubic ease-out
    case 'instant':  return 0                                       // unused (handled below)
    default:         return s
  }
}

/**
 * Evaluate a continuous track at arc-length fraction t (0..1).
 *
 * - Before the first keyframe: holds first value.
 * - After the last keyframe:   holds last value.
 * - Between keyframes: applies the outgoing keyframe's easing.
 * - 'instant' ease: holds the outgoing value; snaps to next at its t.
 *
 * NOTE: This math is editor-only for now. When Phase 4 starts (QB64-PE game-side
 * implementation), move the easing functions into the ExprForge DSL and emit both
 * TS and QB64 versions from there. Do NOT duplicate this in QB64 by hand.
 */
export function evalTrack(frames: TrackKeyframe[], t: number): number {
  if (frames.length === 0) return 0
  if (t <= frames[0].t) return frames[0].value
  if (t >= frames[frames.length - 1].t) return frames[frames.length - 1].value
  for (let i = 0; i < frames.length - 1; i++) {
    const a = frames[i], b = frames[i + 1]
    if (t >= a.t && t <= b.t) {
      const range = b.t - a.t
      if (range < 1e-9) return b.value
      if (a.ease === 'instant') return a.value     // hold; no lerp
      const s = (t - a.t) / range
      return a.value + (b.value - a.value) * applyEase(s, a.ease)
    }
  }
  return frames[frames.length - 1].value
}

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

// ── Hover equality ────────────────────────────────────────────────────────

/** Structural equality for HoveredBehavior — used in view onMouseMove to avoid
 *  spurious setHoveredBehavior calls (which would trigger needless re-renders). */
export function hoveredEq(a: HoveredBehavior, b: HoveredBehavior): boolean {
  if (a === b) return true
  if (!a || !b) return false
  if (a.type !== b.type) return false
  if (a.type === 'track'   && b.type === 'track')   return a.name  === b.name
  if (a.type === 'trigger' && b.type === 'trigger') return a.index === b.index
  return false
}

// ── Canvas drawing ────────────────────────────────────────────────────────

/** Screen-space hit region for a drawn marker — for hover detection in views. */
export type BehaviorHit =
  | { kind: 'track';   name:  string; sx: number; sy: number }
  | { kind: 'trigger'; index: number; sx: number; sy: number }

/**
 * Draw track keyframe circles and trigger diamonds onto a 2D canvas context.
 * Returns an array of hit regions (screen positions) for hover detection.
 *
 * @param ctx               Canvas 2D context to draw into.
 * @param samples           Uniform arc-length samples from buildSpline.
 * @param path              Current PathData (.tracks and .triggers).
 * @param project           Maps world Vec3 → canvas [sx, sy] (view-specific).
 * @param hovered           Currently highlighted item (from store.hoveredBehavior).
 * @param activeBehaviorTrack  Track currently expanded in BehaviorsPanel (or null).
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
  const hasTracks   = Object.keys(path.tracks).length > 0
  const hasTriggers = path.triggers.length > 0
  if (!hasTracks && !hasTriggers) return []

  ctx.save()
  const hits: BehaviorHit[] = []

  // ── Track keyframe circles ────────────────────────────────────────────
  // When a track is active (expanded in the panel), its markers are full opacity
  // and slightly larger; all others are dimmed so the active track stands out.
  const hasActive = activeBehaviorTrack != null
  for (const name of Object.keys(path.tracks)) {
    const color  = trackColor(name)
    const isHov  = hovered?.type === 'track' && hovered.name === name
    const isAct  = activeBehaviorTrack === name
    const dim    = hasActive && !isAct   // dim non-active tracks when any is active
    ctx.globalAlpha = dim ? 0.25 : 1
    for (const kf of path.tracks[name]) {
      const wp = wireAtFrac(samples, kf.t)
      if (!wp) continue
      const [sx, sy] = project(wp)
      hits.push({ kind: 'track', name, sx, sy })

      const r = isAct ? (isHov ? 7 : 5) : (isHov ? 6 : 4)
      if (isHov || isAct) {
        // Outer glow ring
        ctx.beginPath(); ctx.arc(sx, sy, r + 4, 0, Math.PI * 2)
        ctx.strokeStyle = color + '35'; ctx.lineWidth = 3; ctx.stroke()
      }
      ctx.beginPath(); ctx.arc(sx, sy, r, 0, Math.PI * 2)
      ctx.fillStyle   = isAct ? color : color + 'aa'
      ctx.fill()
      // White halo ring so markers read against both spline curve and background
      ctx.beginPath(); ctx.arc(sx, sy, r, 0, Math.PI * 2)
      ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.lineWidth = 1.5; ctx.stroke()
      ctx.beginPath(); ctx.arc(sx, sy, r, 0, Math.PI * 2)
      ctx.strokeStyle = color; ctx.lineWidth = isAct ? 2 : 1.5; ctx.stroke()
    }
    ctx.globalAlpha = 1
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
      // Outer glow ring (diamond shape, slightly larger)
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

  ctx.restore()
  return hits
}
