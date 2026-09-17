// Regression coverage for the closed-loop segment-count/ghost-index fix (issue
// #211): closed paths store an explicit duplicate of wps[0] as their last
// waypoint (see format.ts's exportBlock), so segment count must be
// wps.length-1 -- same as open paths -- with wraparound ghost points only at
// the two boundary segments. Treating it as truly cyclic (segment count =
// wps.length) double-closes the loop and creates a zero-length final segment,
// which reads as a sharp tangent flip right before a pass completes.
//
// Mirrors src/gameplay/spline_path.bi's SpCrGhosts; keep both in sync by hand
// (neither is ExprForge-generated -- see spline_path.bi's own header comment).
import { describe, it, expect } from 'vitest'
import { evalAt, tangentAt, arcAdvanceAt } from './spline'
import { Vec3 } from './vec3'

// A small closed square, using the same duplicate-closing-endpoint convention
// as real .mvr files: wps[4] === wps[0].
const square: Vec3[] = [
  { x: 0, y: 0, z: 0 },
  { x: 10, y: 0, z: 0 },
  { x: 10, y: 0, z: 10 },
  { x: 0, y: 0, z: 10 },
  { x: 0, y: 0, z: 0 },   // duplicate closing waypoint
]

// The real boss-x-flight.mvr waypoints (turnDir=1), including its duplicate
// closing waypoint -- a direct regression guard for the production data that
// originally exposed issue #211.
const bossXFlight: Vec3[] = [
  { x: 20.0737, y: 13.4158, z: -16.2593 },
  { x: 20, y: 3.7518, z: -0.8068 },
  { x: 19.8496, y: 13.7464, z: 16.7345 },
  { x: 20, y: 0.932, z: -1.2974 },
  { x: 20, y: -9, z: -14 },
  { x: 20, y: -0.8221, z: -0.965 },
  { x: 20, y: -9, z: 14 },
  { x: 20, y: 1.2881, z: -0.7013 },
  { x: 20.0737, y: 13.4158, z: -16.2593 },   // duplicate closing waypoint
]

function dist(a: Vec3, b: Vec3): number {
  return Math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2 + (a.z - b.z) ** 2)
}

describe('closed-path segment count', () => {
  it('treats a duplicated closing waypoint as n-1 segments (4, not 5)', () => {
    // 5 waypoints (4 unique + 1 duplicate) => 4 segments. Position approaching
    // the end of the valid parameter domain (just under nSegs=4) should be near
    // the shared corner wps[4]===wps[0], matching position approaching the
    // very start (just after 0) -- both converge on the same physical point.
    const nearEnd   = evalAt(square, 3.9999, true)
    const nearStart = evalAt(square, 0.0001, true)
    expect(dist(nearEnd, nearStart)).toBeLessThan(0.1)
  })
})

describe('closed-loop seam has no degenerate zero-length segment', () => {
  it('boss-x-flight: the final segment has a healthy, non-zero raw derivative throughout', () => {
    const nSegs = bossXFlight.length - 1   // 8
    // Sample across the final segment (index nSegs-1, the one that closes the
    // loop back to wps[0]). A zero-length/degenerate segment would report an
    // (near-)zero raw derivative at every t, however finely sampled.
    for (let t = 0.05; t < 1; t += 0.1) {
      const advance = arcAdvanceAt(bossXFlight, nSegs - 1 + t, true, 0.25)
      // advance = speed / |D|; a degenerate (|D|~0) segment blows this up.
      // A healthy segment keeps it within a modest multiple of the nominal step.
      expect(advance).toBeLessThan(2)
    }
  })

  it('square: tangent direction is continuous across the wrap seam', () => {
    const nSegs = square.length - 1   // 4
    const justBeforeWrap = tangentAt(square, nSegs - 0.001, true)
    const justAfterWrap  = tangentAt(square, 0.001, true)
    // Both samples are on the same straight final/first edge of the square
    // (through the shared corner at wps[0]), so their tangents should point
    // in nearly the same direction -- not flip.
    const dot = justBeforeWrap.x * justAfterWrap.x
              + justBeforeWrap.y * justAfterWrap.y
              + justBeforeWrap.z * justAfterWrap.z
    expect(dot).toBeGreaterThan(0.9)
  })
})
