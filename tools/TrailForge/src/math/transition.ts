// Preview of the game's state-5 transition (BOSS_TransitionInit / Case 5 in
// src/gameplay/behavior.bas): a Hermite blend from an arbitrary incoming
// position + heading into a route's own entry point (wps[0], tangent at
// t=0). Wraps the same ExprForge-generated functions the game calls
// (SpEfHermiteTangentScale/SpEfHermitePos/SpEfHermiteTangent/SpEfArcAdvance)
// -- this is plumbing only, mirroring how spline.ts's evalAt/tangentAt wrap
// SpEfCrWeights/SpEfGhostIndices for the route itself.
//
// Until now this math had never been exercised in the editor at all --
// exactly the "shared in name, never actually checked" gap that let the
// boss orientation bugs hide for two months (see
// docs/proposals/exprforge-array-support.md's own framing of this class of
// risk). This file exists to close it for the transition specifically.
import { Vec3, Waypoint } from './vec3'
import { tangentAt } from './spline'
import {
  SpEfHermiteTangentScale,
  SpEfHermitePos,
  SpEfHermiteTangent,
  SpEfFacingNorm,
  SpEfArcAdvance,
} from './spline_gen'

/** Scaled Hermite blend endpoints -- the output of BOSS_TransitionInit's own
 *  SpEfHermiteTangentScale call, cached so repeated per-t sampling
 *  (evalTransitionAt/transitionTangentAt/transitionArcAdvance) doesn't
 *  recompute it every call, same as the game caches bsmTrM0/M1 once at
 *  transition entry rather than every tick. */
export interface HermiteBlend {
  p0: Vec3
  m0: Vec3
  p1: Vec3
  m1: Vec3
}

/** Mirrors BOSS_TransitionInit exactly: p1/endTangent come from the route's
 *  own entry (wps[0], tangent at t=0, wraparound-aware via tangentAt/
 *  SpEfGhostIndices for a closed path) -- `from`/`heading` are the only
 *  free inputs, matching "an arbitrary incoming position/heading" rather
 *  than a fixed spawn approach. `heading` need not be a unit vector --
 *  SpEfHermiteTangentScale normalizes it internally (and falls back safely
 *  if it's zero-length), exactly as it does for the game's boss.vx case. */
export function computeTransitionBlend(from: Vec3, heading: Vec3, wps: Waypoint[], closed: boolean): HermiteBlend {
  const p1 = wps[0]
  const endTangent = tangentAt(wps, 0, closed)
  const { m0x, m0y, m0z, m1x, m1y, m1z } = SpEfHermiteTangentScale(
    from.x, from.y, from.z, heading.x, heading.y, heading.z,
    p1.x, p1.y, p1.z, endTangent.x, endTangent.y, endTangent.z,
  )
  return { p0: from, m0: { x: m0x, y: m0y, z: m0z }, p1, m1: { x: m1x, y: m1y, z: m1z } }
}

/** Position at Hermite parameter t (0..1). t=0 is exactly `from`; t=1 is
 *  exactly the route's wps[0] -- same endpoint-interpolation guarantee the
 *  game relies on to snap cleanly into flyover at bsmTrT>=1 (Case 5). */
export function evalTransitionAt(blend: HermiteBlend, t: number): Vec3 {
  return SpEfHermitePos(
    blend.p0.x, blend.p0.y, blend.p0.z, blend.m0.x, blend.m0.y, blend.m0.z,
    blend.p1.x, blend.p1.y, blend.p1.z, blend.m1.x, blend.m1.y, blend.m1.z, t,
  )
}

/** Raw (unnormalized) derivative at t -- needed for arc-length speed
 *  correction (transitionArcAdvance), same reason SpTangentAt's normalized
 *  output alone isn't enough for SpEfArcAdvance in Case 6. */
function rawTangentAt(blend: HermiteBlend, t: number): Vec3 {
  const { dx, dy, dz } = SpEfHermiteTangent(
    blend.p0.x, blend.p0.y, blend.p0.z, blend.m0.x, blend.m0.y, blend.m0.z,
    blend.p1.x, blend.p1.y, blend.p1.z, blend.m1.x, blend.m1.y, blend.m1.z, t,
  )
  return { x: dx, y: dy, z: dz }
}

/** Normalized facing at t -- mirrors bsmFlTnX/Y/Z during state 5. */
export function transitionTangentAt(blend: HermiteBlend, t: number): Vec3 {
  const { x, y, z } = rawTangentAt(blend, t)
  const { fx, fy, fz } = SpEfFacingNorm(x, y, z)
  return { x: fx, y: fy, z: fz }
}

/** Arc-length-correct per-tick advance at the route's own speed -- same
 *  "no separate transition-duration constant" idiom as Case 5: farther/
 *  closer entries take proportionately longer/shorter at a consistent
 *  world-speed, matching the maneuver it leads into. */
export function transitionArcAdvance(blend: HermiteBlend, t: number, speed: number): number {
  const raw = rawTangentAt(blend, t)
  return SpEfArcAdvance(raw.x, raw.y, raw.z, speed).advance
}

export interface TransitionSample {
  wire:    Vec3
  tangent: Vec3
  frac:    number   // 0..1 Hermite parameter, NOT arc-length (matches buildSpline's own frac meaning within one segment)
}

/** Uniform-in-parameter samples of the blend curve, for rendering -- the
 *  transition-segment analogue of spline.ts's buildSpline(). One Hermite
 *  segment, so no ghost-point/segment-count machinery is needed here. */
export function buildTransitionSpline(blend: HermiteBlend, steps = 32): TransitionSample[] {
  const samples: TransitionSample[] = []
  for (let i = 0; i <= steps; i++) {
    const t = i / steps
    samples.push({ wire: evalTransitionAt(blend, t), tangent: transitionTangentAt(blend, t), frac: t })
  }
  return samples
}
