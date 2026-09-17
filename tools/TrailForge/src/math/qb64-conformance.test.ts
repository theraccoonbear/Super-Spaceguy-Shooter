// Cross-language conformance guard, TS side of the pair with
// tests/mnv_conformance_test.bas (QB64 side). See that file's header comment
// for why this exists: SpEvalAt/SpTangentAt (QB64) and evalAt/tangentAt (TS)
// are two independently hand-written implementations of the same closed-loop
// wraparound logic (ExprForge generates the underlying weight/frame math
// identically into both, but has no array/indexing primitive to also
// generate the ghost-point selection itself -- see SpCrGhosts / ghosts()).
//
// This test pins the TS side against real values printed by the actual QB64
// SpEvalAt/SpTangentAt (single-precision, as the game computes them) on the
// same attack-pass waypoints and t values used by the QB64 test. If either
// side's hand-written wraparound logic ever drifts from the other, this test
// (or its QB64 counterpart) fails instead of the two silently diverging.
//
// To regenerate after an intentional math change: build and run
// tests/mnv_conformance_test.bas with a temporary `Print "QBCSV," + ...`
// line after computing px/py/pz/tx/ty/tz (see git history of that file for
// the exact line), and copy its output into QB64_GOLDEN below.
import { describe, it, expect } from 'vitest'
import { evalAt, tangentAt } from './spline'
import type { Vec3 } from './vec3'

// Must match tests/mnv_conformance_test.bas's `wps`.
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
const closed = true

// From builds/mnv_conformance_test's real (single-precision) SpEvalAt/SpTangentAt
// output at t = (i/25)*12 for i = 0..24: t, px,py,pz, tx,ty,tz
const QB64_GOLDEN: number[][] = [
  [0,        53.4405,   7.7616,   -0.3503,   -0.07717728,  0.03442073,  0.9964231],
  [0.48,     52.45762,  5.668169,  17.70989,  -0.06826675, -0.1780859,  0.981644],
  [0.96,     49.83813,  3.215165,  32.50511,  -0.493903,   -0.02569253, 0.8691373],
  [1.44,     43.79725,  6.034265,  33.13833,  -0.7535576,   0.4573379, -0.4722213],
  [1.92,     35.23101,  9.325384,  26.01105,  -0.7583375,   0.04595405,-0.6502404],
  [2.4,      24.16291,  6.062332,  14.63672,  -0.6240164,  -0.2950851, -0.7235526],
  [2.88,     11.6502,   0.2138707,  1.840978, -0.7727742,  -0.2907428, -0.5641708],
  [3.36,      0.2478401,-2.800378, -0.6525404,-0.9640968,  -0.2008067,  0.173764],
  [3.84,     -9.956338, -3.483617,  3.087288, -0.8883362,   0.1709954,  0.4261682],
  [4.32,    -15.56463,   2.673499,  7.082918, -0.2429132,   0.8781739,  0.4120725],
  [4.8,     -17.77229,  13.19344,  11.56755,  -0.2902905,   0.8961436,  0.3356458],
  [5.28,    -22.07773,  13.75543,  11.08629,  -0.6789944,  -0.6207752, -0.3919246],
  [5.76,    -27.71818,   6.188226,  6.395628, -0.4205269,  -0.7587714, -0.4974164],
  [6.24,    -29.32076,   0.7154078, 1.812735,  0.06369623, -0.6712721, -0.7384691],
  [6.72,    -27.03841,  -2.965976, -2.864121,  0.7029656,  -0.3889068, -0.5954754],
  [7.2,     -20.25986,  -2.899117, -3.989799,  0.9298481,   0.3193161,  0.1828103],
  [7.68,     -8.679361,  1.73463,  -0.798896,  0.9189737,   0.3181429,  0.2329645],
  [8.16,      5.328943,  3.437456,  0.6613843, 0.9956834,  -0.09268219, 0.004964177],
  [8.64,     22.72214,   0.4000823,-0.1890303, 0.9701411,  -0.2074241, -0.1257037],
  [9.12,     35.29322,  -1.883856, -4.586981,  0.6888905,  -0.0788919, -0.7205595],
  [9.6,      39.38198,  -2.075441,-14.59533,   0.2130823,   0.02950376,-0.9765887],
  [10.08,    42.90356,  -1.504502,-22.78057,   0.7114418,   0.09330691,-0.6965231],
  [10.56,    49.45366,  -0.4704233,-27.16669,  0.9233459,   0.1943958, -0.3311231],
  [11.04,    54.26136,   1.374775,-25.74062,   0.3299783,   0.3669455,  0.8697501],
  [11.52,    54.7097,    5.093888,-15.0655,   -0.06348368,  0.2762943,  0.9589741],
]

// Single-precision QB64 round trip loses a bit more than TS's doubles --
// tolerance reflects that, not sloppiness (matches the QB64 test's tolerance).
const POS_TOL = 0.01
const TAN_TOL = 0.002

describe('TS evalAt/tangentAt agrees with the real QB64 SpEvalAt/SpTangentAt output', () => {
  it('every sampled position and tangent matches within tolerance', () => {
    let worstPosErr = 0, worstTanErr = 0
    for (const [t, px, py, pz, tx, ty, tz] of QB64_GOLDEN) {
      const p = evalAt(wps, t, closed)
      const tan = tangentAt(wps, t, closed)
      const posErr = Math.hypot(p.x - px, p.y - py, p.z - pz)
      const tanErr = Math.hypot(tan.x - tx, tan.y - ty, tan.z - tz)
      worstPosErr = Math.max(worstPosErr, posErr)
      worstTanErr = Math.max(worstTanErr, tanErr)
    }
    console.log(`worst position error vs QB64: ${worstPosErr.toFixed(6)}  worst tangent error: ${worstTanErr.toFixed(6)}`)
    expect(worstPosErr).toBeLessThan(POS_TOL)
    expect(worstTanErr).toBeLessThan(TAN_TOL)
  })
})
