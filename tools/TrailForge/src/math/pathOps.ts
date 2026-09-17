// Whole-path operations: centroid, rotation around each axis, bulk translate.
// All functions return new Waypoint arrays; originals are not mutated.

import type { Waypoint } from './vec3'

export function centroid(wps: Waypoint[]): { x: number; y: number; z: number } {
  if (wps.length === 0) return { x: 0, y: 0, z: 0 }
  const s = wps.reduce((a, w) => ({ x: a.x + w.x, y: a.y + w.y, z: a.z + w.z }), { x: 0, y: 0, z: 0 })
  return { x: s.x / wps.length, y: s.y / wps.length, z: s.z / wps.length }
}

// Rotate around Y axis (TOP/XZ view). Positive theta = CCW when looking from +Y.
export function rotateAroundY(wps: Waypoint[], theta: number): Waypoint[] {
  const c = centroid(wps)
  const cos = Math.cos(theta), sin = Math.sin(theta)
  return wps.map(w => ({
    ...w,
    x: c.x + (w.x - c.x) * cos - (w.z - c.z) * sin,
    z: c.z + (w.x - c.x) * sin + (w.z - c.z) * cos,
  }))
}

// Rotate around Z axis (SIDE/XY view). Positive theta = CCW when looking from +Z.
export function rotateAroundZ(wps: Waypoint[], theta: number): Waypoint[] {
  const c = centroid(wps)
  const cos = Math.cos(theta), sin = Math.sin(theta)
  return wps.map(w => ({
    ...w,
    x: c.x + (w.x - c.x) * cos - (w.y - c.y) * sin,
    y: c.y + (w.x - c.x) * sin + (w.y - c.y) * cos,
  }))
}

// Rotate around X axis (FRONT/YZ view). Positive theta = CCW when looking from +X.
export function rotateAroundX(wps: Waypoint[], theta: number): Waypoint[] {
  const c = centroid(wps)
  const cos = Math.cos(theta), sin = Math.sin(theta)
  return wps.map(w => ({
    ...w,
    y: c.y + (w.y - c.y) * cos - (w.z - c.z) * sin,
    z: c.z + (w.y - c.y) * sin + (w.z - c.z) * cos,
  }))
}

// Translate all waypoints by (dx, dy, dz).
export function translateWps(wps: Waypoint[], dx: number, dy: number, dz: number): Waypoint[] {
  return wps.map(w => ({ ...w, x: w.x + dx, y: w.y + dy, z: w.z + dz }))
}
