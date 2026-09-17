// Shared segment-track engine — the walk/hold/ease/loop-seam mechanics behind
// EVERY continuous behavior track (craftRoll and all scalar tracks: standoff,
// speed, offsetAngle, visible, engineBrightness).
//
// A segment track is a list of spans [t, t+duration) that each carry an
// intent (an ease-toward-a-target transition, relative or absolute) over
// the arc-length fraction [0..1]. Segments are evaluated in t order; the
// value accumulates across them. Between segments the value holds at
// whatever it arrived at.
//
// Domain-specific tracks (craftRoll's mod-360 CW/CCW rotation; a plain
// scalar track's linear ease-to-value) supply only a `computeTarget`
// function — the walk, hold, easing curve, and loop-seam blending are
// identical for every track. See math/craftRoll.ts for the craftRoll
// adapter over this engine.

export type SegEase = 'linear' | 'in' | 'out' | 'in-out'

export interface ScalarSegment {
  id:       string            // stable id for React keys + drag tracking
  t:        number            // arc-fraction start [0, 1]
  duration: number            // arc-fraction extent — minimum 0.005
  value:    number            // relative: signed delta; absolute: target value
  mode:     'relative' | 'absolute'
  ease:     SegEase
}

/** Loop-point seam, generic over any segment track's value domain.
 *  Smoothly bridges the value gap at the closed-path loop point: the seam
 *  consumes [1−tailFrac, 1] and [0, headFrac] of the arc, easing from the
 *  value accumulated at (1−tailFrac) toward `targetValue` so each loop pass
 *  starts identically. Only meaningful when path.closed === true. */
export interface SegmentLoopSeam {
  tailFrac:    number         // arc extent BEFORE the seam  [0, 0.45]
  headFrac:    number         // arc extent AFTER  the seam  [0, 0.45]
  ease:        SegEase
  targetValue: number
}

function applyEase(t: number, ease: SegEase): number {
  t = Math.max(0, Math.min(1, t))
  switch (ease) {
    case 'linear':  return t
    case 'in':      return t * t
    case 'out':     return 1 - (1 - t) * (1 - t)
    case 'in-out':  return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2
  }
}

/**
 * Evaluate a generic segment track at arc-fraction af ∈ [0..1].
 * Segments are walked in t order; each one transitions the accumulated
 * value via computeTarget(entryValue, seg). Returns 0 for an empty list.
 *
 * seam (optional): if af is within the seam's tail or head zone, the seam
 * transition overrides the regular walk, easing the un-seamed value at
 * (1−tailFrac) toward `seam.target` so each loop pass starts identically.
 */
export function evalGenericSegments<S extends { t: number; duration: number; ease: SegEase }>(
  segments:     S[],
  af:           number,
  computeTarget: (entryValue: number, seg: S) => number,
  seam?:        { tailFrac: number; headFrac: number; ease: SegEase; target: number } | null,
): number {
  // ── Seam zones ─────────────────────────────────────────────────────────────
  if (seam) {
    const { tailFrac, headFrac, ease, target } = seam
    const tailStart = Math.max(0, 1 - tailFrac)
    const totalDur  = Math.max(0.001, tailFrac + headFrac)
    // Value at the start of the tail without the seam (no seam arg = no recursion)
    const tailValue = evalGenericSegments(segments, tailStart, computeTarget)
    const seamValue = (localT: number) =>
      tailValue + (target - tailValue) * applyEase(localT, ease)

    if (af >= tailStart && tailFrac > 0) {
      return seamValue((af - tailStart) / totalDur)
    }
    if (af <= headFrac && headFrac > 0) {
      return seamValue((tailFrac + af) / totalDur)
    }
  }

  // ── Regular segment evaluation ──────────────────────────────────────────────
  if (segments.length === 0) return 0
  const sorted = [...segments].sort((a, b) => a.t - b.t)
  let value = 0

  for (const seg of sorted) {
    if (af <= seg.t) break
    const dur        = Math.max(0.005, seg.duration)
    const segEnd     = seg.t + dur
    const valueAtEntry = value
    const target      = computeTarget(valueAtEntry, seg)

    if (af >= segEnd) {
      value = target
    } else {
      const localT = (af - seg.t) / dur
      value = valueAtEntry + (target - valueAtEntry) * applyEase(localT, seg.ease)
      break
    }
  }

  return value
}

/** Target-value function for a plain scalar segment: relative accumulates a
 *  signed delta onto the entry value; absolute eases straight to the value
 *  (no wraparound — unlike craftRoll's mod-360 rotation, scalar tracks have
 *  no natural "long way around"). */
export function evalScalarSegments(
  segments: ScalarSegment[],
  af:       number,
  loopSeam?: SegmentLoopSeam | null,
): number {
  const seam = loopSeam
    ? { tailFrac: loopSeam.tailFrac, headFrac: loopSeam.headFrac, ease: loopSeam.ease, target: loopSeam.targetValue }
    : null
  return evalGenericSegments(segments, af, (entryValue, seg) =>
    seg.mode === 'relative' ? entryValue + seg.value : seg.value, seam)
}

/** Create a default new segment positioned at the given arc-fraction. */
export function makeScalarSegment(t: number, defaultValue = 0): ScalarSegment {
  return {
    id:       Math.random().toString(36).slice(2, 9),
    t:        Math.max(0, Math.min(0.95, t)),
    duration: 0.15,
    value:    defaultValue,
    mode:     'relative',
    ease:     'in-out',
  }
}
