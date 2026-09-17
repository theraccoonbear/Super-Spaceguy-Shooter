// Gameplay context overlays for Trailforge.
// All constants sourced from dims.bas and assets/models.e3d.
// Frustum math via SpEfFrustumAtX (ExprForge-emitted — shared with game).

import { frustumAtX } from '../math/spline'

// ── Game constants ───────────────────────────────────────────────────────
// Camera offset from player (dims.bas: CAM_OFFSET_X=6.5, CAM_OFFSET_Y=2.0)
export const GAME_CAM_X = -6.5
export const GAME_CAM_Y =  2.0

// Player AABB half-extents (models.e3d "PLAYER": .8356 .2879 .7616)
// X = forward/length, Y = height, Z = lateral span
export const SHIP_HX = 0.8356
export const SHIP_HY = 0.2879
export const SHIP_HZ = 0.7616

// Scale reference planes — world X ahead of player origin
export const SCALE_PLANES = [
  { x:   5, label: 'boss close',  color: '#ef4444' },
  { x:  20, label: 'boss combat', color: '#f97316' },
  { x:  40, label: 'fire range',  color: '#eab308' },
  { x:  55, label: 'boss spawn',  color: '#84cc16' },
  { x:  70, label: 'spawn min',   color: '#22d3ee' },
  { x: 100, label: 'spawn max',   color: '#818cf8' },
] as const

export const SPAWN_SPREAD_Y = 18
export const SPAWN_SPREAD_Z = 22

// Camera look direction: camera at (CAM_X, CAM_Y) looks at (8, 0).
// Frustum center Y lerps from CAM_Y (at camera) toward 0 (at target X=8).
function frustumCY(worldX: number): number {
  const frac = (worldX - GAME_CAM_X) / (8 - GAME_CAM_X) // 0 at cam, 1 at target
  return GAME_CAM_Y * (1 - frac)
}

type Proj2 = (a: number, b: number) => [number, number]

// ── Top view (XZ plane) ──────────────────────────────────────────────────
// proj(worldX, worldZ) → [screenX, screenY]
export function drawOverlaysXZ(ctx: CanvasRenderingContext2D, proj: Proj2): void {
  ctx.save()
  const RANGE = 60, FAR_X = 100

  // Scale planes — vertical lines of constant X (dashed)
  for (const p of SCALE_PLANES) {
    ctx.strokeStyle = p.color; ctx.lineWidth = 0.75
    ctx.setLineDash([4, 3]); ctx.globalAlpha = 0.4
    const [x0, y0] = proj(p.x, -RANGE), [x1, y1] = proj(p.x, RANGE)
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
    ctx.setLineDash([]); ctx.globalAlpha = 0.45
    ctx.fillStyle = p.color; ctx.font = '11px Courier New,monospace'
    const [lx, ly] = proj(p.x, -RANGE * 0.85)
    ctx.fillText(p.label, lx + 2, ly)
  }
  ctx.setLineDash([]); ctx.globalAlpha = 1

  // Spawn spread band (X=70..100, Z=±22)
  const band: [number, number][] = [
    proj( 70, -SPAWN_SPREAD_Z), proj(FAR_X, -SPAWN_SPREAD_Z),
    proj(FAR_X, SPAWN_SPREAD_Z), proj( 70,  SPAWN_SPREAD_Z),
  ]
  ctx.fillStyle = 'rgba(34,211,238,0.05)'; ctx.strokeStyle = 'rgba(34,211,238,0.2)'; ctx.lineWidth = 0.75
  ctx.beginPath(); band.forEach(([sx, sy], i) => i ? ctx.lineTo(sx, sy) : ctx.moveTo(sx, sy))
  ctx.closePath(); ctx.fill(); ctx.stroke()

  // Frustum — camera at Z=0 in XZ view, spreading in ±Z
  const [cx, cy] = proj(GAME_CAM_X, 0)
  const { halfZ: farHZ } = frustumAtX(FAR_X)
  ctx.strokeStyle = 'rgba(253,224,71,0.3)'; ctx.lineWidth = 0.75; ctx.setLineDash([3, 4])
  const [fx0, fy0] = proj(FAR_X,  farHZ), [fx1, fy1] = proj(FAR_X, -farHZ)
  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(fx0, fy0); ctx.stroke()
  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(fx1, fy1); ctx.stroke()
  ctx.setLineDash([])
  // Cross-sections at each scale plane
  ctx.strokeStyle = 'rgba(253,224,71,0.18)'; ctx.lineWidth = 0.5
  for (const p of SCALE_PLANES) {
    const { halfZ } = frustumAtX(p.x)
    const [ax, ay] = proj(p.x,  halfZ), [bx, by] = proj(p.x, -halfZ)
    ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke()
  }

  // Camera cube (small filled square)
  const CR = 4
  ctx.fillStyle = '#fde047'; ctx.strokeStyle = '#78350f'; ctx.lineWidth = 1
  ctx.beginPath(); ctx.rect(cx - CR, cy - CR, CR * 2, CR * 2); ctx.fill(); ctx.stroke()

  // Player ship — delta-wing top silhouette (nose → +X)
  const sv: [number, number][] = [
    proj( SHIP_HX,        0),
    proj( SHIP_HX * 0.1, -SHIP_HZ),
    proj(-SHIP_HX * 0.5, -SHIP_HZ * 0.25),
    proj(-SHIP_HX,       -SHIP_HZ * 0.15),
    proj(-SHIP_HX,        SHIP_HZ * 0.15),
    proj(-SHIP_HX * 0.5,  SHIP_HZ * 0.25),
    proj( SHIP_HX * 0.1,  SHIP_HZ),
  ]
  ctx.fillStyle = 'rgba(99,102,241,0.5)'; ctx.strokeStyle = '#818cf8'; ctx.lineWidth = 1.5
  ctx.beginPath(); sv.forEach(([sx, sy], i) => i ? ctx.lineTo(sx, sy) : ctx.moveTo(sx, sy))
  ctx.closePath(); ctx.fill(); ctx.stroke()

  ctx.restore()
}

// ── Side view (XY plane) ─────────────────────────────────────────────────
// proj(worldX, worldY) → [screenX, screenY]
export function drawOverlaysXY(ctx: CanvasRenderingContext2D, proj: Proj2): void {
  ctx.save()
  const RANGE = 60, FAR_X = 100

  // Scale planes
  for (const p of SCALE_PLANES) {
    ctx.strokeStyle = p.color; ctx.lineWidth = 0.75
    ctx.setLineDash([4, 3]); ctx.globalAlpha = 0.4
    const [x0, y0] = proj(p.x, -RANGE), [x1, y1] = proj(p.x, RANGE)
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
    ctx.setLineDash([]); ctx.globalAlpha = 0.45
    ctx.fillStyle = p.color; ctx.font = '11px Courier New,monospace'
    const [lx, ly] = proj(p.x, RANGE * 0.85)
    ctx.fillText(p.label, lx + 2, ly)
  }
  ctx.setLineDash([]); ctx.globalAlpha = 1

  // Spawn spread band (Y=±18)
  const band: [number, number][] = [
    proj( 70, -SPAWN_SPREAD_Y), proj(FAR_X, -SPAWN_SPREAD_Y),
    proj(FAR_X, SPAWN_SPREAD_Y), proj( 70,  SPAWN_SPREAD_Y),
  ]
  ctx.fillStyle = 'rgba(34,211,238,0.05)'; ctx.strokeStyle = 'rgba(34,211,238,0.2)'; ctx.lineWidth = 0.75
  ctx.beginPath(); band.forEach(([sx, sy], i) => i ? ctx.lineTo(sx, sy) : ctx.moveTo(sx, sy))
  ctx.closePath(); ctx.fill(); ctx.stroke()

  // Frustum — camera at (CAM_X, CAM_Y), spreading in ±Y, center dips toward 0
  const [cx, cy] = proj(GAME_CAM_X, GAME_CAM_Y)
  const { halfY: farHY } = frustumAtX(FAR_X)
  const farCY = frustumCY(FAR_X)
  ctx.strokeStyle = 'rgba(253,224,71,0.3)'; ctx.lineWidth = 0.75; ctx.setLineDash([3, 4])
  const [fx0, fy0] = proj(FAR_X, farCY + farHY), [fx1, fy1] = proj(FAR_X, farCY - farHY)
  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(fx0, fy0); ctx.stroke()
  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(fx1, fy1); ctx.stroke()
  ctx.setLineDash([])
  ctx.strokeStyle = 'rgba(253,224,71,0.18)'; ctx.lineWidth = 0.5
  for (const p of SCALE_PLANES) {
    const { halfY } = frustumAtX(p.x)
    const pCY = frustumCY(p.x)
    const [ax, ay] = proj(p.x, pCY + halfY), [bx, by] = proj(p.x, pCY - halfY)
    ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke()
  }

  // Camera cube
  const CR = 4
  ctx.fillStyle = '#fde047'; ctx.strokeStyle = '#78350f'; ctx.lineWidth = 1
  ctx.beginPath(); ctx.rect(cx - CR, cy - CR, CR * 2, CR * 2); ctx.fill(); ctx.stroke()

  // Player ship — side profile (nose → +X), with dorsal fin
  const sv: [number, number][] = [
    proj( SHIP_HX,        0),             // nose tip
    proj( SHIP_HX * 0.5,  SHIP_HY),       // top-front
    proj(-SHIP_HX * 0.2,  SHIP_HY),       // top-mid
    proj(-SHIP_HX * 0.4,  SHIP_HY * 3.5), // dorsal fin tip
    proj(-SHIP_HX * 0.6,  SHIP_HY),       // top-rear
    proj(-SHIP_HX,         SHIP_HY * 0.5),// top-tail
    proj(-SHIP_HX,        -SHIP_HY),      // bottom-tail
    proj( SHIP_HX * 0.3,  -SHIP_HY),     // bottom-front
  ]
  ctx.fillStyle = 'rgba(99,102,241,0.5)'; ctx.strokeStyle = '#818cf8'; ctx.lineWidth = 1.5
  ctx.beginPath(); sv.forEach(([sx, sy], i) => i ? ctx.lineTo(sx, sy) : ctx.moveTo(sx, sy))
  ctx.closePath(); ctx.fill(); ctx.stroke()

  ctx.restore()
}

// ── Front view (YZ plane) ────────────────────────────────────────────────
// proj(worldZ, worldY) → [screenX, screenY]
// Looking along +X — scale planes appear as concentric frustum rectangles.
export function drawOverlaysYZ(ctx: CanvasRenderingContext2D, proj: Proj2): void {
  ctx.save()

  // Frustum cross-sections — concentric rects in YZ at each scale plane depth
  for (const p of SCALE_PLANES) {
    const { halfY, halfZ } = frustumAtX(p.x)
    const pCY = frustumCY(p.x)
    ctx.strokeStyle = p.color; ctx.lineWidth = 0.75; ctx.globalAlpha = 0.4
    ctx.setLineDash([3, 3])
    const corners: [number, number][] = [
      proj(-halfZ, pCY - halfY), proj( halfZ, pCY - halfY),
      proj( halfZ, pCY + halfY), proj(-halfZ, pCY + halfY),
    ]
    ctx.beginPath(); corners.forEach(([sx, sy], i) => i ? ctx.lineTo(sx, sy) : ctx.moveTo(sx, sy))
    ctx.closePath(); ctx.stroke()
    // Label at top-right corner
    ctx.setLineDash([]); ctx.fillStyle = p.color; ctx.globalAlpha = 0.45
    ctx.font = '11px Courier New,monospace'
    const [lx, ly] = proj(halfZ, pCY + halfY)
    ctx.fillText(`X=${p.x}`, lx + 2, ly)
  }
  ctx.setLineDash([]); ctx.globalAlpha = 1

  // Spawn spread rect (largest reference extent)
  ctx.strokeStyle = 'rgba(34,211,238,0.3)'; ctx.fillStyle = 'rgba(34,211,238,0.04)'; ctx.lineWidth = 0.75
  const [sa, sb] = proj(-SPAWN_SPREAD_Z, -SPAWN_SPREAD_Y)
  const [sc, sd] = proj( SPAWN_SPREAD_Z,  SPAWN_SPREAD_Y)
  ctx.beginPath(); ctx.rect(sa, sd, sc - sa, sb - sd); ctx.fill(); ctx.stroke()

  // Player ship — front-on profile: bounding rect + wing line + nose dot
  const sc2: [number, number][] = [
    proj(-SHIP_HZ, -SHIP_HY), proj( SHIP_HZ, -SHIP_HY),
    proj( SHIP_HZ,  SHIP_HY), proj(-SHIP_HZ,  SHIP_HY),
  ]
  ctx.fillStyle = 'rgba(99,102,241,0.3)'; ctx.strokeStyle = '#818cf8'; ctx.lineWidth = 1.5
  ctx.beginPath(); sc2.forEach(([sx, sy], i) => i ? ctx.lineTo(sx, sy) : ctx.moveTo(sx, sy))
  ctx.closePath(); ctx.fill(); ctx.stroke()
  // Wing span line
  const [wx0, wy0] = proj(-SHIP_HZ, 0), [wx1, wy1] = proj(SHIP_HZ, 0)
  ctx.strokeStyle = '#a5b4fc'; ctx.lineWidth = 1
  ctx.beginPath(); ctx.moveTo(wx0, wy0); ctx.lineTo(wx1, wy1); ctx.stroke()
  // Nose dot (ship is coming toward viewer)
  const [nx, ny] = proj(0, 0)
  ctx.fillStyle = '#f97316'
  ctx.beginPath(); ctx.arc(nx, ny, 3.5, 0, Math.PI * 2); ctx.fill()

  // Camera marker (camera is at Z=0, Y=CAM_Y — visible in YZ)
  const [cmx, cmy] = proj(0, GAME_CAM_Y)
  const CR = 4
  ctx.fillStyle = '#fde047'; ctx.strokeStyle = '#78350f'; ctx.lineWidth = 1
  ctx.beginPath(); ctx.rect(cmx - CR, cmy - CR, CR * 2, CR * 2); ctx.fill(); ctx.stroke()

  ctx.restore()
}
