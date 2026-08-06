// 2D projection of the ship model for ortho canvas views.
// Geometry mirrors PerspView's Three.js model (local: X=fwd, Y=up, Z=right).

import { Vec3 } from '../math/vec3'

interface Part { color: string; v: [number,number,number][] }

// Four nose-pyramid faces + wings + dorsal fin.
const PARTS: Part[] = [
  // Nose: 4-face pyramid, tip at (+0.9, 0, 0), base diamond at x=0
  { color: '#f97316', v: [[0.9,0,0],[0, 0.12,0],[0,0,-0.12]] },
  { color: '#f97316', v: [[0.9,0,0],[0, 0.12,0],[0,0, 0.12]] },
  { color: '#f97316', v: [[0.9,0,0],[0,-0.12,0],[0,0,-0.12]] },
  { color: '#f97316', v: [[0.9,0,0],[0,-0.12,0],[0,0, 0.12]] },
  // Port wing (−Z)
  { color: '#22d3ee', v: [[ 0.35,0,-0.15],[-0.45,0,-0.15],[-0.25,0,-1.6]] },
  // Starboard wing (+Z)
  { color: '#a3e635', v: [[ 0.35,0, 0.15],[-0.45,0, 0.15],[-0.25,0, 1.6]] },
  // Dorsal fin (+Y)
  { color: '#f472b6', v: [[ 0.3,0.14,0],[-0.4,0.14,0],[-0.2,1.3,0]] },
]

function toWorld(
  lx: number, ly: number, lz: number,
  pos: Vec3, fwd: Vec3, up: Vec3, rgt: Vec3,
): Vec3 {
  return {
    x: pos.x + lx*fwd.x + ly*up.x + lz*rgt.x,
    y: pos.y + lx*fwd.y + ly*up.y + lz*rgt.y,
    z: pos.z + lx*fwd.z + ly*up.z + lz*rgt.z,
  }
}

// Draw the ship projected through `project(worldPoint) → [sx, sy]`.
// Caller supplies the view-specific projection; this fn handles all geometry.
export function drawShipModel(
  ctx:     CanvasRenderingContext2D,
  pos:     Vec3,
  fwd:     Vec3,   // local X → world  (facing direction)
  up:      Vec3,   // local Y → world  (craftRoll-adjusted)
  rgt:     Vec3,   // local Z → world  (craftRoll-adjusted right)
  project: (w: Vec3) => [number, number],
) {
  ctx.save()
  for (const { color, v } of PARTS) {
    const pts = v.map(([lx, ly, lz]) => project(toWorld(lx, ly, lz, pos, fwd, up, rgt)))
    ctx.beginPath()
    ctx.moveTo(pts[0][0], pts[0][1])
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
    ctx.closePath()
    ctx.fillStyle = color
    ctx.fill()
  }
  ctx.restore()
}

// Build craftRoll-adjusted up/right vectors from the base frame.
export function rollFrame(
  U: Vec3, R: Vec3, craftRollDeg: number,
): { rolledU: Vec3; rolledR: Vec3 } {
  const rad  = craftRollDeg * (Math.PI / 180)
  const c = Math.cos(rad), s = Math.sin(rad)
  return {
    rolledU: { x: c*U.x - s*R.x, y: c*U.y - s*R.y, z: c*U.z - s*R.z },
    rolledR: { x: s*U.x + c*R.x, y: s*U.y + c*R.y, z: s*U.z + c*R.z },
  }
}
