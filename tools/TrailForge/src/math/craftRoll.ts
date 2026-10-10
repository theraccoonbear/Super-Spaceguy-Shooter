// Craft Roll — segment-based authoring model for cinematic ship roll.
//
// Each segment encodes an intent (rotate CW/CCW by degrees, relative or
// absolute) with a duration over the arc-length fraction [0..1].
// Segments are evaluated in t order; angle accumulates across them.
// Between segments the ship holds at the angle it arrived at.
//
// The walk/hold/ease/loop-seam mechanics are shared with every other
// continuous behavior track via evalGenericSegments (math/segmentTrack.ts).
// craftRoll supplies only its own domain-specific target computation
// (mod-360 CW/CCW arithmetic) — everything else routes through the same
// engine every scalar track uses, so behavior here is unchanged from
// before this was factored out.

import { evalGenericSegments, type SegEase } from './segmentTrack'

export type CraftRollEase = SegEase

export interface CraftRollSegment {
  id:        string           // stable id for React keys + drag tracking
  t:         number           // arc-fraction start [0, 1]
  duration:  number           // arc-fraction extent — minimum 0.005
  degrees:   number           // 0–360, always positive; direction determines sign
  direction: 'cw' | 'ccw'
  mode:      'relative' | 'absolute'
  ease:      CraftRollEase
}

// Rotate `entryValue` degrees by this segment's intent — mod-360 CW/CCW math,
// used by both 'relative' (accumulate a signed delta) and 'absolute' (reach
// a target heading, rotating the specified direction) modes.
function craftRollTarget(entryValue: number, seg: CraftRollSegment): number {
  if (seg.mode === 'relative') {
    return entryValue + (seg.direction === 'cw' ? seg.degrees : -seg.degrees)
  }
  // Absolute: reach the given orientation (in the ship's path-following frame)
  // by rotating in the specified direction. 0° = level, 90° = right wing down, etc.
  const currentMod = ((entryValue % 360) + 360) % 360
  if (seg.direction === 'cw') {
    const dist = (seg.degrees - currentMod + 360) % 360
    return entryValue + dist
  }
  const dist = (currentMod - seg.degrees + 360) % 360
  return entryValue - dist
}

/**
 * Evaluate accumulated craft roll angle (degrees) at arc-fraction af ∈ [0..1].
 * Segments are walked in t order; each one transitions the accumulated angle.
 * Returns 0 for an empty list (ship remains level).
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
  const seam = loopSeam
    ? { tailFrac: loopSeam.tailFrac, headFrac: loopSeam.headFrac, ease: loopSeam.ease, target: loopSeam.targetAngle }
    : null
  return evalGenericSegments(segments, af, craftRollTarget, seam)
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
