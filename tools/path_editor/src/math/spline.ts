import { Vec3, v3 } from './vec3'

// ── Ghost index wrapping ────────────────────────────────────────────────
// Mirrors the game's behavior.bas logic exactly.
// For a closed path: true modular wrap — no duplicate endpoint in wps[].
// For an open path: clamp to endpoints.
function ghosts(wps: Vec3[], seg: number, closed: boolean): [Vec3, Vec3, Vec3, Vec3] {
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

// ── Catmull-Rom basis ───────────────────────────────────────────────────
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

// ── Path-local frame ────────────────────────────────────────────────────
// Stable right-hand frame from tangent direction.
// T = forward, R = right, U = up
export interface PathFrame {
  T: Vec3
  R: Vec3
  U: Vec3
}

export function makeFrame(tangent: Vec3): PathFrame {
  const T = v3.norm(tangent)
  // Avoid degenerate cross product when T is nearly vertical
  const worldUp: Vec3 = Math.abs(T.y) > 0.98 ? { x: 0, y: 0, z: 1 } : { x: 0, y: 1, z: 0 }
  const R = v3.norm(v3.cross(T, worldUp))
  const U = v3.cross(R, T)   // already unit length since R and T are orthonormal
  return { T, R, U }
}

// ── Standoff + roll offset ──────────────────────────────────────────────
// Computes the actual ship position given a wire position, tangent, and
// path fraction (0–1). Roll is in degrees per full loop; standoff is world units.
//
//   actual = wire + standoff * (cos(rollRad) * U + sin(rollRad) * R)
//
// At roll=0, standoff=5: ship is 5u above the wire (along U).
// At roll=360 over one loop: ship executes one barrel roll around the wire.
export function actualPos(wire: Vec3, tangent: Vec3, frac: number, roll: number, standoff: number): Vec3 {
  if (standoff < 0.001) return wire
  const rollRad = frac * roll * (Math.PI / 180)
  const { R, U } = makeFrame(tangent)
  const cr = Math.cos(rollRad), sr = Math.sin(rollRad)
  return {
    x: wire.x + standoff * (cr * U.x + sr * R.x),
    y: wire.y + standoff * (cr * U.y + sr * R.y),
    z: wire.z + standoff * (cr * U.z + sr * R.z),
  }
}

// ── Ship facing direction ───────────────────────────────────────────────
// orient='path': nose follows the spline tangent
// orient='target': nose always points toward a fixed world point
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

// ── Spline sample for rendering ─────────────────────────────────────────
export interface SplineSample {
  wire:    Vec3    // position on the wire
  actual:  Vec3    // ship position after standoff+roll
  tangent: Vec3    // normalized tangent at this point
  frac:    number  // 0–1 fraction along full path
}

export interface SplineParams {
  wps:         Vec3[]
  closed:      boolean
  roll:        number   // degrees per full loop
  standoff:    number   // world units
  stepsPerSeg?: number  // subdivision (default 32)
}

export function buildSpline({ wps, closed, roll, standoff, stepsPerSeg = 32 }: SplineParams): SplineSample[] {
  if (wps.length < 2) return []
  const nSegs = closed ? wps.length : wps.length - 1
  const samples: SplineSample[] = []
  for (let seg = 0; seg < nSegs; seg++) {
    const [p0, p1, p2, p3] = ghosts(wps, seg, closed)
    for (let i = 0; i <= stepsPerSeg; i++) {
      const t = i / stepsPerSeg
      const at = seg + t
      const frac = at / nSegs
      const wire = crEval(p0, p1, p2, p3, t)
      const tangent = v3.norm(crTangent(p0, p1, p2, p3, t))
      const ap = actualPos(wire, tangent, frac, roll, standoff)
      samples.push({ wire, actual: ap, tangent, frac })
    }
  }
  return samples
}
