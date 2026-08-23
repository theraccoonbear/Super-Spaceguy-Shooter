// Craft Roll — segment-based authoring model for cinematic ship roll.
//
// Each segment encodes an intent (rotate CW/CCW by degrees, relative or
// absolute) with a duration over the arc-length fraction [0..1].
// Segments are evaluated in t order; angle accumulates across them.
// Between segments the ship holds at the angle it arrived at.

export type CraftRollEase = 'linear' | 'in' | 'out' | 'in-out'

export interface CraftRollSegment {
  id:        string           // stable id for React keys + drag tracking
  t:         number           // arc-fraction start [0, 1]
  duration:  number           // arc-fraction extent — minimum 0.005
  degrees:   number           // 0–360, always positive; direction determines sign
  direction: 'cw' | 'ccw'
  mode:      'relative' | 'absolute'
  ease:      CraftRollEase
}

function applyEase(t: number, ease: CraftRollEase): number {
  t = Math.max(0, Math.min(1, t))
  switch (ease) {
    case 'linear':  return t
    case 'in':      return t * t
    case 'out':     return 1 - (1 - t) * (1 - t)
    case 'in-out':  return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2
  }
}

/**
 * Evaluate accumulated craft roll angle (degrees) at arc-fraction af ∈ [0..1].
 * Segments are walked in t order; each one transitions the accumulated angle.
 * Returns 0 for an empty list (caller falls back to waypoint craftRoll).
 *
 * loopSeam (optional): if present and af is within the seam's tail or head zone,
 * the seam transition overrides the regular segments, easing the angle accumulated
 * at (1−tailFrac) toward `targetAngle` so each loop pass starts identically.
 */
export function evalCraftRoll(
  segments:  CraftRollSegment[],
  af:        number,
  loopSeam?: CraftRollLoopSeam | null,
): number {
  // ── Seam zones ─────────────────────────────────────────────────────────────
  if (loopSeam) {
    const { tailFrac, headFrac, ease, targetAngle } = loopSeam
    const tailStart  = Math.max(0, 1 - tailFrac)
    const totalDur   = Math.max(0.001, tailFrac + headFrac)
    // Compute the angle at the start of the tail without the seam (no seam arg = no recursion)
    const tailAngle  = evalCraftRoll(segments, tailStart)
    const seamAngle  = (localT: number) =>
      tailAngle + (targetAngle - tailAngle) * applyEase(localT, ease)

    if (af >= tailStart && tailFrac > 0) {
      // Tail zone: [1−tail, 1]
      return seamAngle((af - tailStart) / totalDur)
    }
    if (af <= headFrac && headFrac > 0) {
      // Head zone: [0, head]
      return seamAngle((tailFrac + af) / totalDur)
    }
  }

  // ── Regular segment evaluation ──────────────────────────────────────────────
  if (segments.length === 0) return 0
  const sorted = [...segments].sort((a, b) => a.t - b.t)
  let angle = 0

  for (const seg of sorted) {
    if (af <= seg.t) break
    const dur          = Math.max(0.005, seg.duration)
    const segEnd       = seg.t + dur
    const angleAtEntry = angle

    let target: number
    if (seg.mode === 'relative') {
      target = angleAtEntry + (seg.direction === 'cw' ? seg.degrees : -seg.degrees)
    } else {
      // Absolute: reach the given orientation (in the ship's path-following frame)
      // by rotating in the specified direction. 0° = level, 90° = right wing down, etc.
      const currentMod = ((angleAtEntry % 360) + 360) % 360
      if (seg.direction === 'cw') {
        const dist = (seg.degrees - currentMod + 360) % 360
        target = angleAtEntry + dist
      } else {
        const dist = (currentMod - seg.degrees + 360) % 360
        target = angleAtEntry - dist
      }
    }

    if (af >= segEnd) {
      angle = target
    } else {
      const localT = (af - seg.t) / dur
      angle = angleAtEntry + (target - angleAtEntry) * applyEase(localT, seg.ease)
      break
    }
  }

  return angle
}

// ── Loop seam ────────────────────────────────────────────────────────────────
// Smoothly bridges the roll-angle gap at the closed-path loop point.
// The seam consumes [1−tailFrac, 1] and [0, headFrac] of the arc, easing
// from the angle at (1−tailFrac) toward `targetAngle` so each pass starts
// identically. Only meaningful when path.closed === true.
export interface CraftRollLoopSeam {
  tailFrac:    number        // arc extent BEFORE the seam  [0, 0.45]
  headFrac:    number        // arc extent AFTER  the seam  [0, 0.45]
  ease:        CraftRollEase
  targetAngle: number        // degrees — angle to arrive at (default 0)
}

/** Create a default new segment positioned at the given arc-fraction. */
export function makeCraftRollSegment(t: number): CraftRollSegment {
  return {
    id:        Math.random().toString(36).slice(2, 9),
    t:         Math.max(0, Math.min(0.95, t)),
    duration:  0.15,
    degrees:   360,
    direction: 'cw',
    mode:      'relative',
    ease:      'in-out',
  }
}
