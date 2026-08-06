import { Vec3, Waypoint, v3 } from './vec3'

// ── Ghost index wrapping ────────────────────────────────────────────────
// Mirrors the game's behavior.bas logic exactly.
// For a closed path: true modular wrap — no duplicate endpoint in wps[].
// For an open path: clamp to endpoints.
// Generic so it works for both Vec3[] and Waypoint[].
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

// ── Catmull-Rom basis — Vec3 ────────────────────────────────────────────
function crEval(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, t: number): Vec3 {
  const t2 = t * t, t3 = t2 * t
  const w0 = 0.5 * (-t3 + 2 * t2 - t)
  const w1 = 0.5 * (3 * t3 - 5 * t2 + 2)
  const w2 = 0.5 * (-3 * t3 + 4 * t2 + t)
  const w3 = 0.5 * (t3 - t2)
  return {
    x: w0 * p0.x + w1 * p1.x + w2 * p2.x + w3 * p3.x,
    y: w0 * p0.y + w1 * p1.y + w2 * p2.y + w3 * p3.y,
    z: w0 * p0.z + w1 * p1.z + w2 * p2.z + w3 * p3.z,
  }
}

function crTangent(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, t: number): Vec3 {
  const dw0 = 0.5 * (-3 * t * t + 4 * t - 1)
  const dw1 = 0.5 * (9 * t * t - 10 * t)
  const dw2 = 0.5 * (-9 * t * t + 8 * t + 1)
  const dw3 = 0.5 * (3 * t * t - 2 * t)
  return {
    x: dw0 * p0.x + dw1 * p1.x + dw2 * p2.x + dw3 * p3.x,
    y: dw0 * p0.y + dw1 * p1.y + dw2 * p2.y + dw3 * p3.y,
    z: dw0 * p0.z + dw1 * p1.z + dw2 * p2.z + dw3 * p3.z,
  }
}

// ── Catmull-Rom basis — scalar ──────────────────────────────────────────
// Used for per-node roll angle interpolation.
function crEval1D(p0: number, p1: number, p2: number, p3: number, t: number): number {
  const t2 = t * t, t3 = t2 * t
  const w0 = 0.5 * (-t3 + 2 * t2 - t)
  const w1 = 0.5 * (3 * t3 - 5 * t2 + 2)
  const w2 = 0.5 * (-3 * t3 + 4 * t2 + t)
  const w3 = 0.5 * (t3 - t2)
  return w0 * p0 + w1 * p1 + w2 * p2 + w3 * p3
}

// ── Path-local frame ────────────────────────────────────────────────────
export interface PathFrame {
  T: Vec3
  R: Vec3
  U: Vec3
}

export function makeFrame(tangent: Vec3): PathFrame {
  const T = v3.norm(tangent)
  const worldUp: Vec3 = Math.abs(T.y) > 0.98 ? { x: 0, y: 0, z: 1 } : { x: 0, y: 1, z: 0 }
  const R = v3.norm(v3.cross(T, worldUp))
  const U = v3.cross(R, T)
  return { T, R, U }
}

// ── Rodrigues' rotation ─────────────────────────────────────────────────
function rotateAround(v: Vec3, k: Vec3, cosA: number, sinA: number): Vec3 {
  const kxv = v3.cross(k, v)
  const kdv = v3.dot(k, v)
  return {
    x: v.x * cosA + kxv.x * sinA + k.x * kdv * (1 - cosA),
    y: v.y * cosA + kxv.y * sinA + k.y * kdv * (1 - cosA),
    z: v.z * cosA + kxv.z * sinA + k.z * kdv * (1 - cosA),
  }
}

// ── Parallel transport ──────────────────────────────────────────────────
function transportFrame(frame: PathFrame, newT: Vec3): PathFrame {
  const T1   = v3.norm(newT)
  const axis = v3.cross(frame.T, T1)
  const sinA = v3.len(axis)
  if (sinA < 1e-8) return { T: T1, R: frame.R, U: frame.U }
  const cosA = Math.max(-1, Math.min(1, v3.dot(frame.T, T1)))
  const k    = v3.scale(axis, 1 / sinA)
  return {
    T: T1,
    R: rotateAround(frame.R, k, cosA, sinA),
    U: rotateAround(frame.U, k, cosA, sinA),
  }
}

// ── Standoff position ───────────────────────────────────────────────────
// Offset the wire point by standoff in the direction given by pathRollDeg,
// measured in the path-local frame at that tangent.
// pathRollDeg is the direct node-interpolated angle (degrees), NOT a
// "degrees per loop" accumulator.
export function actualPos(wire: Vec3, tangent: Vec3, pathRollDeg: number, standoff: number): Vec3 {
  if (standoff < 0.001) return wire
  const rollRad = pathRollDeg * (Math.PI / 180)
  const { R, U } = makeFrame(tangent)
  const cr = Math.cos(rollRad), sr = Math.sin(rollRad)
  return {
    x: wire.x + standoff * (cr * U.x + sr * R.x),
    y: wire.y + standoff * (cr * U.y + sr * R.y),
    z: wire.z + standoff * (cr * U.z + sr * R.z),
  }
}

// ── Ship facing direction ───────────────────────────────────────────────
export function shipFacing(wirePos: Vec3, tangent: Vec3, orient: 'path' | 'target', target: Vec3): Vec3 {
  if (orient === 'target') {
    const d = v3.sub(target, wirePos)
    return v3.len2(d) < 1e-6 ? { x: 1, y: 0, z: 0 } : v3.norm(d)
  }
  const l = v3.len(tangent)
  return l < 1e-6 ? { x: 1, y: 0, z: 0 } : v3.scale(tangent, 1 / l)
}

// ── Public evaluation API ───────────────────────────────────────────────
export function evalAt(wps: Vec3[], at: number, closed: boolean): Vec3 {
  const nSegs = closed ? wps.length : wps.length - 1
  const seg = Math.min(Math.floor(at), nSegs - 1)
  const t = at - seg
  const [p0, p1, p2, p3] = ghosts(wps, seg, closed)
  return crEval(p0, p1, p2, p3, t)
}

export function tangentAt(wps: Vec3[], at: number, closed: boolean): Vec3 {
  const nSegs = closed ? wps.length : wps.length - 1
  const seg = Math.min(Math.floor(at), nSegs - 1)
  const t = at - seg
  const [p0, p1, p2, p3] = ghosts(wps, seg, closed)
  return crTangent(p0, p1, p2, p3, t)
}

// Catmull-Rom interpolation of a scalar roll field across waypoints.
// field: 'pathRoll' or 'craftRoll'
export function evalRollAt(
  wps: Waypoint[], at: number, closed: boolean,
  field: 'pathRoll' | 'craftRoll',
): number {
  if (wps.length === 0) return 0
  const nSegs = closed ? wps.length : wps.length - 1
  const seg = Math.min(Math.floor(at), nSegs - 1)
  const t = at - seg
  const [g0, g1, g2, g3] = ghosts(wps, seg, closed)
  return crEval1D(g0[field], g1[field], g2[field], g3[field], t)
}

// ── Spline sample for rendering ─────────────────────────────────────────
export interface SplineSample {
  wire:      Vec3    // position on the wire
  actual:    Vec3    // ship position after standoff+pathRoll
  tangent:   Vec3    // normalized tangent at this point
  frac:      number  // 0–1 fraction along full path
  craftRoll: number  // interpolated craftRoll (degrees) at this point
}

export interface SplineParams {
  wps:          Waypoint[]
  closed:       boolean
  standoff:     number     // world units
  stepsPerSeg?: number     // subdivision (default 32)
}

export function buildSpline({ wps, closed, standoff, stepsPerSeg = 32 }: SplineParams): SplineSample[] {
  if (wps.length < 2) return []
  const nSegs = closed ? wps.length : wps.length - 1

  // ── Pass 1: collect wire positions, tangents, and per-sample roll values ─
  // For closed paths, skip t=1 of the last segment (same wire as samples[0]);
  // we append it explicitly below.
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
      rawWire.push(crEval(g0, g1, g2, g3, t))
      rawTan.push(v3.norm(crTangent(g0, g1, g2, g3, t)))
      rawPathRoll.push(crEval1D(g0.pathRoll,  g1.pathRoll,  g2.pathRoll,  g3.pathRoll,  t))
      rawCraftRoll.push(crEval1D(g0.craftRoll, g1.craftRoll, g2.craftRoll, g3.craftRoll, t))
    }
  }
  const N = rawWire.length
  if (N === 0) return []

  // ── Pass 2: parallel-transport frames ──────────────────────────────────
  // Propagate frame from sample to sample by minimal rotation — no worldUp flip.
  const frames: PathFrame[] = new Array(N)
  frames[0] = makeFrame(rawTan[0])
  for (let i = 1; i < N; i++) {
    frames[i] = transportFrame(frames[i - 1], rawTan[i])
  }

  // ── Pass 3: holonomy correction (closed paths) ──────────────────────────
  // Parallel transport can accumulate a twist after one full loop. Measure it
  // and distribute the cancellation linearly so frame[0] == frame[N-1] after
  // correction, ensuring the standoff line closes seamlessly.
  let holonomy = 0
  if (closed && N > 1) {
    holonomy = Math.atan2(
      v3.dot(frames[N - 1].R, frames[0].U),
      v3.dot(frames[N - 1].R, frames[0].R),
    )
  }

  // ── Pass 4: actual positions ────────────────────────────────────────────
  const samples: SplineSample[] = []
  for (let i = 0; i < N; i++) {
    const wire    = rawWire[i]
    const tangent = rawTan[i]
    const frac    = rawAt[i] / nSegs
    let actual: Vec3

    if (standoff < 0.001) {
      actual = wire
    } else {
      // Cancel holonomy linearly, then apply per-node pathRoll on the clean frame.
      const corrAngle = -holonomy * frac
      const T   = frames[i].T
      const corrR = rotateAround(frames[i].R, T, Math.cos(corrAngle), Math.sin(corrAngle))
      const corrU = rotateAround(frames[i].U, T, Math.cos(corrAngle), Math.sin(corrAngle))
      const rollRad = rawPathRoll[i] * (Math.PI / 180)
      const cr = Math.cos(rollRad), sr = Math.sin(rollRad)
      actual = {
        x: wire.x + standoff * (cr * corrU.x + sr * corrR.x),
        y: wire.y + standoff * (cr * corrU.y + sr * corrR.y),
        z: wire.z + standoff * (cr * corrU.z + sr * corrR.z),
      }
    }

    samples.push({ wire, actual, tangent, frac, craftRoll: rawCraftRoll[i] })
  }

  // Close the loop: append samples[0] so both wire and actual lines return exactly
  // to the start position.
  if (closed && samples.length > 0) {
    samples.push({ ...samples[0] })
  }
  return samples
}
