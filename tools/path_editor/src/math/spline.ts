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
