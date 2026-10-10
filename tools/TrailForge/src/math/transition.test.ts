// Verifies the transition-preview math against the guarantees the game's
// Case 5 (behavior.bas) actually relies on -- endpoint interpolation exact
// enough to snap cleanly into flyover, and tangent DIRECTION continuity at
// both ends (magnitude differs; Hermite scaling is chord-distance-based,
// not unit) -- using the real spline.ts/transition.ts exports against real
// route data, per this project's "test TS with TS" rule.
import { describe, it, expect } from 'vitest'
import {
  computeTransitionBlend,
  evalTransitionAt,
  transitionTangentAt,
  transitionArcAdvance,
  buildTransitionSpline,
} from './transition'
import { tangentAt } from './spline'
import { SpEfFacingNorm } from './spline_gen'
import type { Waypoint } from './vec3'

// A real, unevenly-spaced open route (no closed-loop wraparound involved --
// that's already covered by spline.ts's own tests).
const wps: Waypoint[] = [
  { x: 20, y: 0, z: 0 },
  { x: 8, y: 1, z: 3 },
  { x: -5, y: 1, z: 6 },
  { x: -8, y: 0, z: 5 },
]
const closed = false

describe('computeTransitionBlend / evalTransitionAt', () => {
  it('t=0 lands exactly on the incoming position, t=1 exactly on the route entry (wps[0])', () => {
    const from = { x: 40, y: 5, z: -10 }
    const heading = { x: -1, y: 0, z: 0 }
    const blend = computeTransitionBlend(from, heading, wps, closed)

    const at0 = evalTransitionAt(blend, 0)
    const at1 = evalTransitionAt(blend, 1)
    expect(at0.x).toBeCloseTo(from.x, 9)
    expect(at0.y).toBeCloseTo(from.y, 9)
    expect(at0.z).toBeCloseTo(from.z, 9)
    expect(at1.x).toBeCloseTo(wps[0].x, 9)
    expect(at1.y).toBeCloseTo(wps[0].y, 9)
    expect(at1.z).toBeCloseTo(wps[0].z, 9)
  })

  it('tangent direction at t=0 matches the incoming heading; at t=1 matches the route\'s own entry tangent', () => {
    // A deliberately unnormalized, non-axis-aligned heading -- mirrors the
    // game passing raw boss.vx (unnormalized) as the first-entry heading.
    const from = { x: 40, y: 5, z: -10 }
    const heading = { x: -3, y: 0.6, z: -1.2 }
    const blend = computeTransitionBlend(from, heading, wps, closed)

    const expectedStart = SpEfFacingNorm(heading.x, heading.y, heading.z)
    const startTan = transitionTangentAt(blend, 0)
    expect(startTan.x).toBeCloseTo(expectedStart.fx, 9)
    expect(startTan.y).toBeCloseTo(expectedStart.fy, 9)
    expect(startTan.z).toBeCloseTo(expectedStart.fz, 9)

    const routeEntryTan = tangentAt(wps, 0, closed)
    const endTan = transitionTangentAt(blend, 1)
    expect(endTan.x).toBeCloseTo(routeEntryTan.x, 9)
    expect(endTan.y).toBeCloseTo(routeEntryTan.y, 9)
    expect(endTan.z).toBeCloseTo(routeEntryTan.z, 9)
  })

  it('handles a zero-length heading (degenerate input) without producing NaN', () => {
    const from = { x: 0, y: 0, z: 0 }
    const blend = computeTransitionBlend(from, { x: 0, y: 0, z: 0 }, wps, closed)
    const mid = evalTransitionAt(blend, 0.5)
    expect(Number.isFinite(mid.x)).toBe(true)
    expect(Number.isFinite(mid.y)).toBe(true)
    expect(Number.isFinite(mid.z)).toBe(true)
  })
})

describe('transitionArcAdvance', () => {
  it('is positive and roughly proportional to speed for a non-degenerate blend', () => {
    const from = { x: 40, y: 5, z: -10 }
    const blend = computeTransitionBlend(from, { x: -1, y: 0, z: 0 }, wps, closed)
    const adv1 = transitionArcAdvance(blend, 0.5, 0.05)
    const adv2 = transitionArcAdvance(blend, 0.5, 0.10)
    expect(adv1).toBeGreaterThan(0)
    expect(adv2).toBeCloseTo(adv1 * 2, 9)
  })
})

describe('buildTransitionSpline', () => {
  it('produces steps+1 samples spanning exactly from the incoming position to the route entry', () => {
    const from = { x: 40, y: 5, z: -10 }
    const blend = computeTransitionBlend(from, { x: -1, y: 0, z: 0 }, wps, closed)
    const samples = buildTransitionSpline(blend, 16)
    expect(samples).toHaveLength(17)
    expect(samples[0].frac).toBe(0)
    expect(samples[16].frac).toBe(1)
    expect(samples[0].wire.x).toBeCloseTo(from.x, 9)
    expect(samples[16].wire.x).toBeCloseTo(wps[0].x, 9)
  })
})
