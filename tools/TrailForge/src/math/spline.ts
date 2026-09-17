import { Vec3, Waypoint, v3 } from './vec3'
import {
  SpEfCrWeights,
  SpEfCrDerivWeights,
  SpEfMkFrame,
  SpEfFacingNorm,
  SpEfArcAdvance,
  SpEfTransportFrame,
  SpEfFrustumAtX,
  SpEfApplyHolonomyCorrection,
  SpEfMeasureHolonomy,
  SpEfHolonomyAngle,
  SpEfGhostIndices,
  SpEfIsClosingDuplicate,
} from './spline_gen'

// ── Frustum math ────────────────────────────────────────────────────────
// Half-extents of the game frustum at a given world X depth.
// Constants from dims.bas: GAME_FOV=72, CAM_OFFSET_X=6.5; aspect=320/240=4/3.
const _TAN_HALF_FOV = Math.tan(Math.PI * 72 / 360)
export function frustumAtX(worldX: number): { halfY: number; halfZ: number } {
  return SpEfFrustumAtX(worldX, -6.5, _TAN_HALF_FOV, 4 / 3)
}

// ── Ghost index wrapping ────────────────────────────────────────────────
// The actual wrap/clamp index math now lives in SpEfGhostIndices, generated
// from math/formula.expr into both this file's spline_gen.ts AND the game's
// spline_path_gen.bi -- previously hand-written twice (SpCrGhosts here as
// ghosts(), independently in QB64), which drifted apart and caused two real
// bugs: issue #211's tangent flip, and a closed-loop teleport caused by
// this file's normalizePath()-stripped waypoint shape not matching what the
// index math assumed. See docs/proposals/exprforge-array-support.md.
//
// On disk, closed paths store an explicit duplicate of wps[0] as their last
// waypoint (see format.ts's exportBlock) -- that's the convention the game
// always sees, since it reads the file as-is. But TrailForge's own store
// (store.ts's normalizePath) strips that duplicate from the live in-memory
// path whenever first/last coincide, so the SAME PathData can arrive here
// either with or without it. hasDuplicateClosingPoint() (also now
// ExprForge-generated, as SpEfIsClosingDuplicate) detects which convention
// the given array is actually in, so segCount() and ghosts() are correct
// either way.
const DUP_EPS = 0.001   // matches store.ts's normalizePath coincidence threshold

function hasDuplicateClosingPoint(wps: Vec3[]): boolean {
  if (wps.length < 2) return false
  const first = wps[0], last = wps[wps.length - 1]
  return SpEfIsClosingDuplicate(first.x, first.y, first.z, last.x, last.y, last.z, DUP_EPS).isDup > 0
}

// Number of Catmull-Rom segments for this waypoint array as given (whichever
// closing convention it's actually in). Use this everywhere instead of the
// old blanket `wps.length - 1` so segment count never depends on whether the
// duplicate closing waypoint happens to still be present.
export function segCount(wps: Vec3[], closed: boolean): number {
  if (!closed) return wps.length - 1
  return hasDuplicateClosingPoint(wps) ? wps.length - 1 : wps.length
}

// For an open path: clamp to endpoints. For a closed path: wrap modulo the
// number of logically-distinct points (n-1 when a duplicate closing waypoint
// is present, n when it's not), taken from the *other* end of the array at
// the two boundary segments, to keep curvature smooth across the seam
// without an extra zero-length segment (issue #211).
//
// SpEfGhostIndices's own "n" parameter always subtracts exactly 1 when
// closed (giM = n-1) -- correct for the game, which only ever calls it with
// the raw on-disk waypoint count (a closed path there ALWAYS carries its
// duplicate closing waypoint, since the QB64 loader has no normalization
// step -- see maneuvers.bas). This file's wps can ALSO arrive already
// deduped (store.ts's normalizePath), where that same "-1" would be wrong
// by one. So for a closed path, n is deliberately NOT wps.length -- it's
// segCount(wps, true) + 1, i.e. whatever value makes SpEfGhostIndices's own
// internal "-1" land on the correct distinct-point cycle length either way.
// For an open path there's no such adjustment; n is the real array bound.
function ghosts<T extends Vec3>(wps: T[], seg: number, closed: boolean): [T, T, T, T] {
  const n = closed ? segCount(wps, true) + 1 : wps.length
  const { i0, i1, i2, i3 } = SpEfGhostIndices(n, seg, closed ? 1 : 0)
  return [wps[i0], wps[i1], wps[i2], wps[i3]]
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
  return SpEfHolonomyAngle(dotRR, dotRU).angle
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
  const nSegs = segCount(wps, closed)
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
  const nSegs = segCount(wps, closed)
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
  const nSegs = segCount(wps, closed)
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
  const nSegs = segCount(wps, closed)
  const seg = Math.min(Math.floor(at), nSegs - 1)
  const t = at - seg
  const [p0, p1, p2, p3] = ghosts(wps, seg, closed)
  const { dw0, dw1, dw2, dw3 } = SpEfCrDerivWeights(t)
  const dtx = dw0 * p0.x + dw1 * p1.x + dw2 * p2.x + dw3 * p3.x
  const dty = dw0 * p0.y + dw1 * p1.y + dw2 * p2.y + dw3 * p3.y
  const dtz = dw0 * p0.z + dw1 * p1.z + dw2 * p2.z + dw3 * p3.z
  return SpEfArcAdvance(dtx, dty, dtz, speed).advance
}

// ── Spline sample for rendering ─────────────────────────────────────────
export interface SplineSample {
  wire:    Vec3
  tangent: Vec3
  frac:    number
}

export interface SplineParams {
  wps:          Waypoint[]
  closed:       boolean
  stepsPerSeg?: number
}

export function buildSpline({ wps, closed, stepsPerSeg = 32 }: SplineParams): SplineSample[] {
  if (wps.length < 2) return []
  const nSegs = segCount(wps, closed)

  const samples: SplineSample[] = []

  for (let seg = 0; seg < nSegs; seg++) {
    const [g0, g1, g2, g3] = ghosts(wps, seg, closed)
    const iMax = (closed && seg === nSegs - 1) ? stepsPerSeg - 1 : stepsPerSeg
    for (let i = 0; i <= iMax; i++) {
      const t = i / stepsPerSeg

      const { w0, w1, w2, w3 } = SpEfCrWeights(t)
      const wire: Vec3 = {
        x: w0 * g0.x + w1 * g1.x + w2 * g2.x + w3 * g3.x,
        y: w0 * g0.y + w1 * g1.y + w2 * g2.y + w3 * g3.y,
        z: w0 * g0.z + w1 * g1.z + w2 * g2.z + w3 * g3.z,
      }

      const { dw0, dw1, dw2, dw3 } = SpEfCrDerivWeights(t)
      const dtx = dw0 * g0.x + dw1 * g1.x + dw2 * g2.x + dw3 * g3.x
      const dty = dw0 * g0.y + dw1 * g1.y + dw2 * g2.y + dw3 * g3.y
      const dtz = dw0 * g0.z + dw1 * g1.z + dw2 * g2.z + dw3 * g3.z
      const { fx, fy, fz } = SpEfFacingNorm(dtx, dty, dtz)
      const tangent: Vec3 = { x: fx, y: fy, z: fz }

      samples.push({ wire, tangent, frac: (seg + t) / nSegs })
    }
  }

  if (closed && samples.length > 0) {
    samples.push({ ...samples[0] })
  }
  return samples
}

// ── Parameter-fraction ↔ arc-length-fraction conversion ─────────────────
// Catmull-Rom parameter fraction (animT / nSegs) does NOT advance at constant
// arc-length rate on unevenly-spaced waypoints — a long chord "eats" more
// parameter range per unit distance than a short one. Anything keyed to
// arc-length fraction (craftRollSegments' t, the behaviors ruler) MUST go
// through paramToArc() before being compared against animFrac, or it drifts
// out of sync with the visual position by however uneven the spacing is.
export interface ArcTable {
  paramToArc(pf: number): number   // parameter fraction [0..1] → arc-length fraction [0..1]
  arcToParam(af: number): number   // arc-length fraction [0..1] → parameter fraction [0..1]
}

const IDENTITY_ARC: ArcTable = { paramToArc: p => p, arcToParam: a => a }

export function makeArcTable(wps: Waypoint[], closed: boolean): ArcTable {
  if (wps.length < 2) return IDENTITY_ARC

  const samples = buildSpline({ wps, closed })
  if (samples.length < 2) return IDENTITY_ARC

  // Cumulative arc lengths and matching parameter fractions for each sample
  // SplineSample.frac is rawAt[i]/nSegs — already parameter fraction [0..1]
  const paramFracs: number[] = [samples[0].frac]
  const cumArc: number[]     = [0]
  for (let i = 1; i < samples.length; i++) {
    const s = samples[i], p = samples[i - 1]
    const dx = s.wire.x - p.wire.x, dy = s.wire.y - p.wire.y, dz = s.wire.z - p.wire.z
    cumArc.push(cumArc[i - 1] + Math.sqrt(dx * dx + dy * dy + dz * dz))
    paramFracs.push(s.frac)
  }
  const totalArc = cumArc[cumArc.length - 1]
  if (totalArc === 0) return IDENTITY_ARC

  // Largest index where arr[i] <= val
  function lb(arr: number[], val: number): number {
    let lo = 0, hi = arr.length - 1
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (arr[mid] <= val) lo = mid; else hi = mid - 1 }
    return lo
  }

  function paramToArc(pf: number): number {
    pf = Math.max(0, Math.min(1, pf))
    const i = lb(paramFracs, pf)
    if (i >= paramFracs.length - 1) return 1
    const span = paramFracs[i + 1] - paramFracs[i]
    const t    = span < 1e-10 ? 0 : (pf - paramFracs[i]) / span
    return (cumArc[i] + t * (cumArc[i + 1] - cumArc[i])) / totalArc
  }

  function arcToParam(af: number): number {
    af = Math.max(0, Math.min(1, af))
    const arcVal = af * totalArc
    const i = lb(cumArc, arcVal)
    if (i >= cumArc.length - 1) return 1
    const span = cumArc[i + 1] - cumArc[i]
    const t    = span < 1e-10 ? 0 : (arcVal - cumArc[i]) / span
    return paramFracs[i] + t * (paramFracs[i + 1] - paramFracs[i])
  }

  return { paramToArc, arcToParam }
}
