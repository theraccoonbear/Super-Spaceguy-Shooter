import { Vec3, Waypoint, v3 } from './vec3'
import {
  SpEfCrWeights,
  SpEfCrDerivWeights,
  SpEfMkFrame,
  SpEfActualPos,
  SpEfFacingNorm,
  SpEfArcAdvance,
  SpEfTransportFrame,
  SpEfFrustumAtX,
  SpEfApplyHolonomyCorrection,
  SpEfMeasureHolonomy,
} from './spline_gen'

// ── Frustum math ────────────────────────────────────────────────────────
// Half-extents of the game frustum at a given world X depth.
// Constants from dims.bas: GAME_FOV=72, CAM_OFFSET_X=6.5; aspect=320/240=4/3.
const _TAN_HALF_FOV = Math.tan(Math.PI * 72 / 360)
export function frustumAtX(worldX: number): { halfY: number; halfZ: number } {
  return SpEfFrustumAtX(worldX, -6.5, _TAN_HALF_FOV, 4 / 3)
}

// ── Ghost index wrapping ────────────────────────────────────────────────
// Mirrors the game's behavior.bas logic exactly.
// For a closed path: true modular wrap — no duplicate endpoint in wps[].
// For an open path: clamp to endpoints.
function ghosts<T extends Vec3>(wps: T[], seg: number, closed: boolean): [T, T, T, T] {
  const n = wps.length
  if (closed) {
    return [
      wps[((seg - 1) % n + n) % n],
      wps[seg % n],
      wps[(seg + 1) % n],
      wps[(seg + 2) % n],
    ]
  }
  return [
    wps[Math.max(0, seg - 1)],
    wps[seg],
    wps[Math.min(n - 1, seg + 1)],
    wps[Math.min(n - 1, seg + 2)],
  ]
}

// ── Path-local frame ────────────────────────────────────────────────────
export interface PathFrame {
  T: Vec3
  R: Vec3
  U: Vec3
}

// Gram-Schmidt frame from tangent — wraps generated SpEfMkFrame.
// Used for one-shot frame initialization; parallel transport accumulates from here.
export function makeFrame(tangent: Vec3): PathFrame {
  const T = v3.norm(tangent)
  const { rx, ry, rz, ux, uy, uz } = SpEfMkFrame(T.x, T.y, T.z)
  return {
    T,
    R: { x: rx, y: ry, z: rz },
    U: { x: ux, y: uy, z: uz },
  }
}

// Rodrigues parallel transport: rotates frame from T0 to T1 preserving orientation.
// T0 and T1 must be unit vectors. Falls back to identity when T0 ≈ T1.
// Use this for accumulating frame state across animation ticks.
export function transportFrame(T0: Vec3, T1: Vec3, R: Vec3, U: Vec3): { R: Vec3; U: Vec3 } {
  const { newRx, newRy, newRz, newUx, newUy, newUz } = SpEfTransportFrame(
    T0.x, T0.y, T0.z,
    T1.x, T1.y, T1.z,
    R.x, R.y, R.z,
    U.x, U.y, U.z,
  )
  return {
    R: { x: newRx, y: newRy, z: newRz },
    U: { x: newUx, y: newUy, z: newUz },
  }
}

// Per-tick holonomy counter-twist: distributes the closed-loop geometric phase
// correction evenly so the parallel-transport frame closes after one full pass.
// Call after transportFrame each tick; noop when holonomy ≈ 0 (open paths).
export function applyHolonomyCorrection(
  R: Vec3, U: Vec3, holonomy: number, dArcFrac: number,
): { R: Vec3; U: Vec3 } {
  const r = SpEfApplyHolonomyCorrection(
    R.x, R.y, R.z, U.x, U.y, U.z, holonomy, dArcFrac,
  )
  return {
    R: { x: r.corrRx, y: r.corrRy, z: r.corrRz },
    U: { x: r.corrUx, y: r.corrUy, z: r.corrUz },
  }
}

// Returns dotRR and dotRU for atan2(dotRU, dotRR) = holonomy in radians.
// Pass the R after one full loop and the initial R0, U0.
export function measureHolonomy(
  finalR: Vec3, R0: Vec3, U0: Vec3,
): number {
  const { dotRR, dotRU } = SpEfMeasureHolonomy(
    finalR.x, finalR.y, finalR.z,
    R0.x, R0.y, R0.z,
    U0.x, U0.y, U0.z,
  )
  return Math.atan2(dotRU, dotRR)
}


// Pre-compute the holonomy-corrected parallel-transport frame at nSteps uniform
// arc-fraction intervals across one full closed-loop traversal.
// The returned table has nSteps+1 entries at arcFrac = 0/n, 1/n, …, n/n.
// holonomy must already be computed via measureHolonomy().
// For open paths, pass holonomy=0 and the table is pure parallel transport from t=0.
export interface FrameSample { R: Vec3; U: Vec3 }

export function buildFrameTable(
  wps: Vec3[], closed: boolean, holonomy: number, nSteps = 512,
): FrameSample[] {
  const nSegs = closed ? wps.length : wps.length - 1
  const tan0  = tangentAt(wps, 0, closed)
  const f0    = makeFrame(tan0)
  let R: Vec3 = { ...f0.R }
  let U: Vec3 = { ...f0.U }
  const table: FrameSample[] = [{ R: { ...R }, U: { ...U } }]
  let prevTan = tan0
  for (let i = 1; i <= nSteps; i++) {
    const newTan  = tangentAt(wps, (i / nSteps) * nSegs, closed)
    const tr      = transportFrame(prevTan, newTan, R, U)
    R = tr.R; U = tr.U
    if (closed && Math.abs(holonomy) > 1e-6) {
      const cr = applyHolonomyCorrection(R, U, holonomy, 1 / nSteps)
      R = cr.R; U = cr.U
    }
    prevTan = newTan
    table.push({ R: { ...R }, U: { ...U } })
  }
  return table
}

// Linearly interpolate a frame table at the given arc fraction in [0, 1].
export function sampleFrameTable(table: FrameSample[], arcFrac: number): FrameSample {
  const n  = table.length - 1
  const fi = Math.max(0, Math.min(1, arcFrac)) * n
  const lo = Math.floor(fi)
  const hi = Math.min(n, lo + 1)
  const t  = fi - lo
  if (lo === hi || t < 1e-6) return table[lo]
  const { R: R0, U: U0 } = table[lo]
  const { R: R1, U: U1 } = table[hi]
  return {
    R: { x: R0.x + t*(R1.x-R0.x), y: R0.y + t*(R1.y-R0.y), z: R0.z + t*(R1.z-R0.z) },
    U: { x: U0.x + t*(U1.x-U0.x), y: U0.y + t*(U1.y-U0.y), z: U0.z + t*(U1.z-U0.z) },
  }
}

// ── Standoff position ───────────────────────────────────────────────────
export function actualPos(wire: Vec3, tangent: Vec3, pathRollDeg: number, standoff: number): Vec3 {
  if (standoff < 0.001) return wire
  const pos = SpEfActualPos(
    wire.x, wire.y, wire.z,
    tangent.x, tangent.y, tangent.z,
    pathRollDeg, standoff,
  )
  return { x: pos.x, y: pos.y, z: pos.z }
}

// ── Ship facing direction ───────────────────────────────────────────────
export function shipFacing(wirePos: Vec3, tangent: Vec3, orient: 'path' | 'target', target: Vec3): Vec3 {
  if (orient === 'target') {
    const d = v3.sub(target, wirePos)
    const { fx, fy, fz } = SpEfFacingNorm(d.x, d.y, d.z)
    return { x: fx, y: fy, z: fz }
  }
  const { fx, fy, fz } = SpEfFacingNorm(tangent.x, tangent.y, tangent.z)
  return { x: fx, y: fy, z: fz }
}

// ── Public evaluation API ───────────────────────────────────────────────
export function evalAt(wps: Vec3[], at: number, closed: boolean): Vec3 {
  const nSegs = closed ? wps.length : wps.length - 1
  const seg = Math.min(Math.floor(at), nSegs - 1)
  const t = at - seg
  const [p0, p1, p2, p3] = ghosts(wps, seg, closed)
  const { w0, w1, w2, w3 } = SpEfCrWeights(t)
  return {
    x: w0 * p0.x + w1 * p1.x + w2 * p2.x + w3 * p3.x,
    y: w0 * p0.y + w1 * p1.y + w2 * p2.y + w3 * p3.y,
    z: w0 * p0.z + w1 * p1.z + w2 * p2.z + w3 * p3.z,
  }
}

export function tangentAt(wps: Vec3[], at: number, closed: boolean): Vec3 {
  const nSegs = closed ? wps.length : wps.length - 1
  const seg = Math.min(Math.floor(at), nSegs - 1)
  const t = at - seg
  const [p0, p1, p2, p3] = ghosts(wps, seg, closed)
  const { dw0, dw1, dw2, dw3 } = SpEfCrDerivWeights(t)
  const dtx = dw0 * p0.x + dw1 * p1.x + dw2 * p2.x + dw3 * p3.x
  const dty = dw0 * p0.y + dw1 * p1.y + dw2 * p2.y + dw3 * p3.y
  const dtz = dw0 * p0.z + dw1 * p1.z + dw2 * p2.z + dw3 * p3.z
  const { fx, fy, fz } = SpEfFacingNorm(dtx, dty, dtz)
  return { x: fx, y: fy, z: fz }
}

// Arc-length advance using the raw (unnormalized) derivative — wraps SpEfArcAdvance.
// Use this for animating along the path; tangentAt returns a unit vector and cannot
// be used for arc-length compensation.
export function arcAdvanceAt(wps: Vec3[], at: number, closed: boolean, speed: number): number {
  const nSegs = closed ? wps.length : wps.length - 1
  const seg = Math.min(Math.floor(at), nSegs - 1)
  const t = at - seg
  const [p0, p1, p2, p3] = ghosts(wps, seg, closed)
  const { dw0, dw1, dw2, dw3 } = SpEfCrDerivWeights(t)
  const dtx = dw0 * p0.x + dw1 * p1.x + dw2 * p2.x + dw3 * p3.x
  const dty = dw0 * p0.y + dw1 * p1.y + dw2 * p2.y + dw3 * p3.y
  const dtz = dw0 * p0.z + dw1 * p1.z + dw2 * p2.z + dw3 * p3.z
  return SpEfArcAdvance(dtx, dty, dtz, speed).advance
}

export function evalRollAt(
  wps: Waypoint[], at: number, closed: boolean,
  field: 'pathRoll' | 'craftRoll',
): number {
  if (wps.length === 0) return 0
  const nSegs = closed ? wps.length : wps.length - 1
  const seg = Math.min(Math.floor(at), nSegs - 1)
  const t = at - seg
  const [g0, g1, g2, g3] = ghosts(wps, seg, closed)
  const { w0, w1, w2, w3 } = SpEfCrWeights(t)
  return w0 * g0[field] + w1 * g1[field] + w2 * g2[field] + w3 * g3[field]
}

// ── Spline sample for rendering ─────────────────────────────────────────
export interface SplineSample {
  wire:      Vec3
  actual:    Vec3
  tangent:   Vec3
  frac:      number
  craftRoll: number
}

export interface SplineParams {
  wps:          Waypoint[]
  closed:       boolean
  standoff:     number
  stepsPerSeg?: number
}

export function buildSpline({ wps, closed, standoff, stepsPerSeg = 32 }: SplineParams): SplineSample[] {
  if (wps.length < 2) return []
  const nSegs = closed ? wps.length : wps.length - 1

  // ── Pass 1: wire positions, normalized tangents, roll values ─────────
  // SpEfCrWeights for position/roll; SpEfCrDerivWeights+SpEfFacingNorm
  // for tangent — identical to game runtime.
  const rawWire:      Vec3[]   = []
  const rawTan:       Vec3[]   = []
  const rawAt:        number[] = []
  const rawPathRoll:  number[] = []
  const rawCraftRoll: number[] = []

  for (let seg = 0; seg < nSegs; seg++) {
    const [g0, g1, g2, g3] = ghosts(wps, seg, closed)
    const iMax = (closed && seg === nSegs - 1) ? stepsPerSeg - 1 : stepsPerSeg
    for (let i = 0; i <= iMax; i++) {
      const t = i / stepsPerSeg
      rawAt.push(seg + t)

      const { w0, w1, w2, w3 } = SpEfCrWeights(t)
      rawWire.push({
        x: w0 * g0.x + w1 * g1.x + w2 * g2.x + w3 * g3.x,
        y: w0 * g0.y + w1 * g1.y + w2 * g2.y + w3 * g3.y,
        z: w0 * g0.z + w1 * g1.z + w2 * g2.z + w3 * g3.z,
      })
      rawPathRoll.push(w0 * g0.pathRoll + w1 * g1.pathRoll + w2 * g2.pathRoll + w3 * g3.pathRoll)
      rawCraftRoll.push(w0 * g0.craftRoll + w1 * g1.craftRoll + w2 * g2.craftRoll + w3 * g3.craftRoll)

      const { dw0, dw1, dw2, dw3 } = SpEfCrDerivWeights(t)
      const dtx = dw0 * g0.x + dw1 * g1.x + dw2 * g2.x + dw3 * g3.x
      const dty = dw0 * g0.y + dw1 * g1.y + dw2 * g2.y + dw3 * g3.y
      const dtz = dw0 * g0.z + dw1 * g1.z + dw2 * g2.z + dw3 * g3.z
      const { fx, fy, fz } = SpEfFacingNorm(dtx, dty, dtz)
      rawTan.push({ x: fx, y: fy, z: fz })
    }
  }
  const N = rawWire.length
  if (N === 0) return []

  // ── Pass 2: actual positions via SpEfActualPos (Gram-Schmidt, game-matching) ─
  const samples: SplineSample[] = []
  for (let i = 0; i < N; i++) {
    const wire    = rawWire[i]
    const tangent = rawTan[i]
    const frac    = rawAt[i] / nSegs
    let actual: Vec3

    if (standoff < 0.001) {
      actual = wire
    } else {
      const pos = SpEfActualPos(
        wire.x, wire.y, wire.z,
        tangent.x, tangent.y, tangent.z,
        rawPathRoll[i], standoff,
      )
      actual = { x: pos.x, y: pos.y, z: pos.z }
    }

    samples.push({ wire, actual, tangent, frac, craftRoll: rawCraftRoll[i] })
  }

  if (closed && samples.length > 0) {
    samples.push({ ...samples[0] })
  }
  return samples
}
