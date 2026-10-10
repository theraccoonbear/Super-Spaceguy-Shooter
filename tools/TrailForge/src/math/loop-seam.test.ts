// Regression coverage for the animation tick loop's per-frame position/frame
// advance (App.tsx's useAnimLoop), using the REAL exported spline functions
// against the real attack-pass.mvr data -- not a hand-reimplementation in a
// different language, which is exactly the kind of silent-divergence risk
// this whole investigation has been about eliminating.
import { describe, it, expect } from 'vitest'
import { evalAt, tangentAt, arcAdvanceAt, transportFrame, makeFrame, segCount } from './spline'
import type { Vec3 } from './vec3'

// attack-pass.mvr waypoints (turnDir=1), including its duplicate closing waypoint.
const wps: Vec3[] = [
  { x: 53.4405, y: 7.7616, z: -0.3503 },
  { x: 49.4578, y: 3.2207, z: 33.0769 },
  { x: 33.6243, y: 9.2982, z: 24.6690 },
  { x: 8.7777, y: -0.7114, z: 0.1266 },
  { x: -12.4921, y: -2.5898, z: 4.2717 },
  { x: -19.0767, y: 15.1416, z: 12.1857 },
  { x: -29.1371, y: 3, z: 4.0848 },
  { x: -23.7362, y: -3.6647, z: -4.2481 },
  { x: 0.3152, y: 3.6258, z: 0.5884 },
  { x: 33.1357, y: -1.6223, z: -2.9403 },
  { x: 42.0103, y: -1.6223, z: -21.8501 },
  { x: 54.0500, y: 1.1726, z: -26.2122 },
  { x: 53.4405, y: 7.7616, z: -0.3503 },
]
// store.ts's normalizePath() strips this exact duplicate from the LIVE
// in-memory path whenever a closed path's first/last waypoints coincide --
// so TrailForge's own animation loop can just as easily see this 12-waypoint
// shape as the 13-waypoint on-disk shape above. The game never sees this
// shape (its loader has no such normalization step -- see maneuvers.bas),
// so this array exists purely to prove the TS-side fix handles BOTH shapes
// identically, since TrailForge's own data can arrive in either one.
const wpsDeduped: Vec3[] = wps.slice(0, -1)

const closed = true
const SPEED = 0.25

// Mirrors App.tsx's tick() exactly: one arc-advance step per frame at 60fps
// (framesElapsed = 1), wrapping animT at nSegs, transporting the frame.
function simulateTicks(wps: Vec3[], numTicks: number) {
  const nSegs = segCount(wps, closed)
  let animT = 0
  let R: Vec3, U: Vec3
  ;({ R, U } = makeFrame(tangentAt(wps, animT, closed)))
  let prevTan = tangentAt(wps, animT, closed)

  const posJumps: number[] = []
  const paramJumps: number[] = []

  for (let i = 0; i < numTicks; i++) {
    const prevPos = evalAt(wps, animT, closed)
    const prevT = animT

    const dT = arcAdvanceAt(wps, animT, closed, SPEED)
    let newT = animT + dT
    if (newT >= nSegs) newT -= nSegs

    const newTan = tangentAt(wps, newT, closed)
    const transported = transportFrame(prevTan, newTan, R, U)
    R = transported.R; U = transported.U
    prevTan = newTan
    animT = newT

    const newPos = evalAt(wps, animT, closed)
    const posJump = Math.hypot(newPos.x - prevPos.x, newPos.y - prevPos.y, newPos.z - prevPos.z)
    posJumps.push(posJump)
    // Raw parameter delta, accounting for a legitimate wrap (paramJump should
    // reflect the ACTUAL arc-length step taken, not the wrapped discontinuity)
    let rawDelta = newT - prevT
    if (rawDelta < 0) rawDelta += nSegs   // wrapped this tick -- add nSegs back to get the true forward step
    paramJumps.push(rawDelta)
  }
  return { posJumps, paramJumps }
}

describe('attack-pass animation tick: per-frame advance stays bounded, including across the loop seam', () => {
  it('every single-tick position step at speed=0.25 stays close to nominal (no teleport)', () => {
    // Run enough ticks to loop around multiple times and cross the seam repeatedly.
    const { posJumps } = simulateTicks(wps, 2000)
    const worst = Math.max(...posJumps)
    const avg = posJumps.reduce((a, b) => a + b, 0) / posJumps.length
    console.log(`worst per-tick position jump: ${worst.toFixed(4)}  avg: ${avg.toFixed(4)}`)
    // Nominal per-tick travel is ~SPEED (0.25); anything wildly larger is a teleport.
    expect(worst).toBeLessThan(SPEED * 5)
  })

  it('every single-tick parameter step stays a small fraction of the full loop (no segment-skipping)', () => {
    const { paramJumps } = simulateTicks(wps, 2000)
    const worst = Math.max(...paramJumps)
    console.log(`worst per-tick parameter step: ${worst.toFixed(4)}  (nSegs=${segCount(wps, closed)})`)
    // A single tick should never cover more than a fraction of one segment.
    expect(worst).toBeLessThan(1)
  })
})

// Regression coverage for the actual reported bug: TrailForge's own store
// (normalizePath) strips the duplicate closing waypoint from the live path
// whenever it's loaded/edited, leaving segCount()/ghosts() to see a
// 12-waypoint array instead of the on-disk 13-waypoint one. Before segCount()
// detected this, the code unconditionally assumed nSegs = wps.length - 1 --
// on the deduped array that undercounts by exactly one segment, so the last
// tick before the wrap skipped straight from waypoint 11 to waypoint 0
// without ever traversing the final closing segment (issue's "teleport from
// node 11 to 0"). These tests pin both halves of the fix: segCount() reports
// the same segment count for both shapes, and playback is smooth in both.
describe('same maneuver with its duplicate closing waypoint already stripped (post-normalizePath shape)', () => {
  it('segCount agrees with the on-disk (duplicated) shape', () => {
    expect(segCount(wpsDeduped, closed)).toBe(segCount(wps, closed))
  })

  it('produces the identical trajectory to the on-disk shape at matching parameters', () => {
    const nSegs = segCount(wpsDeduped, closed)
    for (let i = 0; i <= 200; i++) {
      const t = (i / 200) * nSegs
      const a = evalAt(wps, t, closed)
      const b = evalAt(wpsDeduped, t, closed)
      expect(Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z)).toBeLessThan(1e-9)
    }
  })

  it('every single-tick position step stays bounded, including across the loop seam (no teleport)', () => {
    const { posJumps } = simulateTicks(wpsDeduped, 2000)
    const worst = Math.max(...posJumps)
    console.log(`[deduped] worst per-tick position jump: ${worst.toFixed(4)}`)
    expect(worst).toBeLessThan(SPEED * 5)
  })

  it('every single-tick parameter step stays a small fraction of the full loop (no segment-skipping)', () => {
    const { paramJumps } = simulateTicks(wpsDeduped, 2000)
    const worst = Math.max(...paramJumps)
    console.log(`[deduped] worst per-tick parameter step: ${worst.toFixed(4)}  (nSegs=${segCount(wpsDeduped, closed)})`)
    expect(worst).toBeLessThan(1)
  })
})
