// 3D perspective view — Three.js + OrbitControls.
// Waypoints are selectable via click; use ortho views to move nodes.
// Follow mode: camera trails the ship; scroll adjusts distance.

import { useEffect, useMemo, useRef, useState, useCallback } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { useStore } from '../store'
import { camPrefs, saveCamPrefs } from '../prefs'
import { buildSpline, evalAt, tangentAt, shipFacing, makeFrame, frustumAtX, makeArcTable } from '../math/spline'
import { getFrameAt } from '../math/frameCache'
import { evalCraftRoll } from '../math/craftRoll'
import {
  GAME_CAM_X, GAME_CAM_Y,
  SHIP_HX, SHIP_HY, SHIP_HZ,
  SCALE_PLANES,
} from './overlays'

// ── Ship model colors ───────────────────────────────────────────────────
const COL_NOSE  = 0xf97316   // orange — nose cone
const COL_BODY  = 0x475569   // slate  — fuselage cylinder
const COL_PORT  = 0x22d3ee   // cyan   — port wing  (left,  −Z local)
const COL_STAR  = 0xa3e635   // lime   — starboard  (right, +Z local)
const COL_FIN   = 0xf472b6   // pink   — dorsal fin (top,   +Y local)

// ── Types ───────────────────────────────────────────────────────────────
type CameraMode = 'orbit' | 'follow' | 'ingame'

const CAMERA_MODE_LABEL: Record<CameraMode, string> = {
  orbit:  '⊙ ORBIT',
  follow: '⊙ FOLLOW',
  ingame: '⊙ IN-GAME',
}

interface SceneRefs {
  renderer:     THREE.WebGLRenderer
  scene:        THREE.Scene
  camera:       THREE.PerspectiveCamera
  controls:     OrbitControls
  raycaster:    THREE.Raycaster
  wireLine:     THREE.Line
  actualLine:   THREE.Line
  wpGroup:      THREE.Group
  bgGroup:      THREE.Group   // background scatter — rebuilt on path change
  shipGroup:    THREE.Group
  overlayGroup: THREE.Group   // player ship, camera cube, frustum, scale planes
  targetMesh:   THREE.Mesh
  gizmo:        THREE.Group
  gizmoHits:    THREE.Mesh[]
  raf:          number
  kick:         () => void   // request one render (no-op if loop already running)
  // Camera mode (mutated directly — not React state)
  cameraMode: CameraMode
  followDist: number
  shipPos:    THREE.Vector3
  shipFwd:    THREE.Vector3
  shipUp:     THREE.Vector3
}

// ── Helpers ─────────────────────────────────────────────────────────────
function makeLine(color: number): THREE.Line {
  return new THREE.Line(
    new THREE.BufferGeometry(),
    new THREE.LineBasicMaterial({ color }),
  )
}

// Flat triangle mesh (DoubleSide so visible from either face).
function makeTriMesh(
  v1: [number,number,number],
  v2: [number,number,number],
  v3: [number,number,number],
  color: number,
): THREE.Mesh {
  const geo = new THREE.BufferGeometry()
  geo.setAttribute('position', new THREE.Float32BufferAttribute([...v1, ...v2, ...v3], 3))
  geo.computeVertexNormals()
  return new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide }))
}

// Build the ship group: fuselage + nose + port wing + starboard wing + dorsal fin.
// Local coordinate system: X = forward, Y = up, Z = right.
function buildShipGroup(): THREE.Group {
  const g = new THREE.Group()

  // Body cylinder: axis along X, x=-0.5 to x=+0.3 (radius 0.12).
  // CylinderGeometry default axis is Y; rotateZ(-π/2) puts it along +X.
  // Height 0.8, centered at x=0 after rotation → translate -0.1 → [-0.5, 0.3].
  const bodyGeo = new THREE.CylinderGeometry(0.12, 0.12, 0.8, 8)
  bodyGeo.rotateZ(-Math.PI / 2)
  bodyGeo.translate(-0.1, 0, 0)
  g.add(new THREE.Mesh(bodyGeo, new THREE.MeshBasicMaterial({ color: COL_BODY })))

  // Nose cone: tip at +X, base joins body front at x=+0.3 (radius 0.12).
  // ConeGeometry height 0.6, centered at x=0 after rotation → translate +0.6 → base x=0.3, tip x=0.9.
  const noseGeo = new THREE.ConeGeometry(0.12, 0.6, 8)
  noseGeo.rotateZ(-Math.PI / 2)
  noseGeo.translate(0.6, 0, 0)
  g.add(new THREE.Mesh(noseGeo, new THREE.MeshBasicMaterial({ color: COL_NOSE })))

  // Port wing (−Z): root from body surface, swept back to tip.
  g.add(makeTriMesh([0.2, 0, -0.12], [-0.4, 0, -0.12], [-0.25, 0, -1.6], COL_PORT))

  // Starboard wing (+Z): mirror.
  g.add(makeTriMesh([0.2, 0,  0.12], [-0.4, 0,  0.12], [-0.25, 0,  1.6], COL_STAR))

  // Dorsal fin (+Y): root at top of body, swept back and up.
  g.add(makeTriMesh([0.2, 0.12, 0], [-0.4, 0.12, 0], [-0.2, 1.3, 0], COL_FIN))

  // Roll indicator: thin ring perpendicular to forward axis, plus up-arm.
  // The whole group rotates with the ship so these always reflect actual roll.
  const rollRingGeo = new THREE.TorusGeometry(1.85, 0.025, 8, 48)
  rollRingGeo.rotateZ(Math.PI / 2)  // torus normally in XY; rotate to be in YZ (⊥ to X=forward)
  g.add(new THREE.Mesh(rollRingGeo,
    new THREE.MeshBasicMaterial({ color: 0x94a3b8, transparent: true, opacity: 0.25 })))

  // Up-arm: center of ring → local +Y (rolled "up" direction)
  const armGeo = new THREE.BufferGeometry()
  armGeo.setAttribute('position', new THREE.Float32BufferAttribute([0, 0.25, 0,  0, 1.85, 0], 3))
  g.add(new THREE.Line(armGeo,
    new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.6 })))

  return g
}

// Scatter dark reference cubes well outside the flight path.
// Called from the path useEffect with all wire positions,
// so the exclusion zone covers every rotational variant of the offset.
// Deterministic LCG — consistent placement for a given path AABB.
function buildBackground(
  bgGroup:    THREE.Group,
  actualPts:  Array<{x: number; y: number; z: number}>,
) {
  // Dispose old meshes
  bgGroup.children.slice().forEach((c) => {
    const m = c as THREE.Mesh
    m.geometry.dispose()
    ;(m.material as THREE.Material).dispose()
  })
  bgGroup.clear()

  // AABB of all wire positions
  let x0 = 0, y0 = 0, z0 = 0, x1 = 0, y1 = 0, z1 = 0
  if (actualPts.length > 0) {
    x0 = x1 = actualPts[0].x
    y0 = y1 = actualPts[0].y
    z0 = z1 = actualPts[0].z
    for (const p of actualPts) {
      x0 = Math.min(x0, p.x); x1 = Math.max(x1, p.x)
      y0 = Math.min(y0, p.y); y1 = Math.max(y1, p.y)
      z0 = Math.min(z0, p.z); z1 = Math.max(z1, p.z)
    }
  }
  // Expand by: half-diagonal of max cube (√(5²+5²+5²)/2 ≈ 4.3) + visual breathing room
  const M = 10
  const cx0 = x0 - M, cx1 = x1 + M
  const cy0 = y0 - M, cy1 = y1 + M
  const cz0 = z0 - M, cz1 = z1 + M

  let seed = 0xdeadbeef
  const rand = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 0xffffffff }
  const rng  = (lo: number, hi: number) => lo + rand() * (hi - lo)
  const COLORS = [0x1e293b, 0x1a1f2e, 0x1c1a2e, 0x1c2022, 0x1c2a1c, 0x241515]

  // Generate up to 600 candidates; keep the first 50 that clear the path zone
  // and are at least 70 units from the origin (keeps them out of the flight space).
  const MIN_RADIUS = 70
  for (let i = 0; i < 600 && bgGroup.children.length < 50; i++) {
    const px = rng(-130, 130)
    const py = rng(-20, 50)
    const pz = rng(-130, 130)
    const sx = rng(0.4, 5), sy = rng(0.4, 5), sz = rng(0.4, 5)
    const rx = rng(0, Math.PI * 2)
    const ry = rng(0, Math.PI * 2)
    const rz = rng(0, Math.PI * 2)
    const col = COLORS[Math.floor(rand() * COLORS.length)]
    const wf  = rand() > 0.62

    // Bounding-sphere radius of this (possibly rotated) box — half-diagonal
    const hr = Math.sqrt(sx * sx + sy * sy + sz * sz) * 0.5

    // Reject if within the minimum radius exclusion zone
    if (Math.sqrt(px * px + py * py + pz * pz) < MIN_RADIUS) continue

    // Reject if the cube's bounding sphere overlaps the expanded path AABB
    if (px + hr > cx0 && px - hr < cx1 &&
        py + hr > cy0 && py - hr < cy1 &&
        pz + hr > cz0 && pz - hr < cz1) continue

    const geo  = new THREE.BoxGeometry(sx, sy, sz)
    const mat  = new THREE.MeshBasicMaterial({ color: col, wireframe: wf })
    const mesh = new THREE.Mesh(geo, mat)
    mesh.position.set(px, py, pz)
    mesh.rotation.set(rx, ry, rz)
    bgGroup.add(mesh)
  }
}

// ── Gameplay context overlay (player ref ship, camera cube, frustum, scale) ──
function buildOverlayGroup(): THREE.Group {
  const g = new THREE.Group()

  // Player reference ship — indigo semi-transparent box, nose cone in orange
  const shipMat = new THREE.MeshBasicMaterial({ color: 0x818cf8, transparent: true, opacity: 0.35 })
  g.add(new THREE.Mesh(new THREE.BoxGeometry(SHIP_HX * 2, SHIP_HY * 2, SHIP_HZ * 2), shipMat))
  g.add(new THREE.LineSegments(
    new THREE.EdgesGeometry(new THREE.BoxGeometry(SHIP_HX * 2, SHIP_HY * 2, SHIP_HZ * 2)),
    new THREE.LineBasicMaterial({ color: 0x818cf8 }),
  ))
  const noseGeo = new THREE.ConeGeometry(0.1, 0.45, 8)
  noseGeo.rotateZ(-Math.PI / 2)
  noseGeo.translate(SHIP_HX + 0.22, 0, 0)
  g.add(new THREE.Mesh(noseGeo, new THREE.MeshBasicMaterial({ color: 0xf97316 })))

  // Camera cube — yellow, at in-game camera resting position
  const camCube = new THREE.Mesh(
    new THREE.BoxGeometry(0.4, 0.4, 0.4),
    new THREE.MeshBasicMaterial({ color: 0xfde047 }),
  )
  camCube.position.set(GAME_CAM_X, GAME_CAM_Y, 0)
  g.add(camCube)

  // Frustum wireframe — from camera to 4 far corners + far rectangle
  const FAR_X = 100
  const { halfY: farHY, halfZ: farHZ } = frustumAtX(FAR_X)
  const cam = new THREE.Vector3(GAME_CAM_X, GAME_CAM_Y, 0)
  const farCorners = [
    new THREE.Vector3(FAR_X,  farHY,  farHZ),
    new THREE.Vector3(FAR_X,  farHY, -farHZ),
    new THREE.Vector3(FAR_X, -farHY, -farHZ),
    new THREE.Vector3(FAR_X, -farHY,  farHZ),
  ]
  const frustumPts: THREE.Vector3[] = []
  for (const fc of farCorners) frustumPts.push(cam.clone(), fc)
  frustumPts.push(farCorners[0], farCorners[1], farCorners[1], farCorners[2],
                  farCorners[2], farCorners[3], farCorners[3], farCorners[0])
  g.add(new THREE.LineSegments(
    new THREE.BufferGeometry().setFromPoints(frustumPts),
    new THREE.LineBasicMaterial({ color: 0xfde047, transparent: true, opacity: 0.3 }),
  ))

  // Scale plane outlines — translucent vertical rectangles perpendicular to X
  const planeColors = [0xef4444, 0xf97316, 0xeab308, 0x84cc16, 0x22d3ee, 0x818cf8]
  SCALE_PLANES.forEach((plane, i) => {
    const { halfY, halfZ } = frustumAtX(plane.x)
    const pts = [
      new THREE.Vector3(plane.x, -halfY, -halfZ),
      new THREE.Vector3(plane.x,  halfY, -halfZ),
      new THREE.Vector3(plane.x,  halfY,  halfZ),
      new THREE.Vector3(plane.x, -halfY,  halfZ),
      new THREE.Vector3(plane.x, -halfY, -halfZ),
    ]
    g.add(new THREE.Line(
      new THREE.BufferGeometry().setFromPoints(pts),
      new THREE.LineBasicMaterial({ color: planeColors[i], transparent: true, opacity: 0.5 }),
    ))
    // Fill
    const planeGeo = new THREE.PlaneGeometry(halfZ * 2, halfY * 2)
    planeGeo.rotateY(Math.PI / 2)
    const mesh = new THREE.Mesh(planeGeo,
      new THREE.MeshBasicMaterial({ color: planeColors[i], transparent: true, opacity: 0.04, side: THREE.DoubleSide }),
    )
    mesh.position.set(plane.x, 0, 0)
    g.add(mesh)
  })

  return g
}

function getNDC(e: PointerEvent, rect: DOMRect): THREE.Vector2 {
  return new THREE.Vector2(
    ((e.clientX - rect.left) / rect.width)  *  2 - 1,
    ((e.clientY - rect.top)  / rect.height) * -2 + 1,
  )
}

// ── Component ───────────────────────────────────────────────────────────
export function PerspView() {
  const mountRef  = useRef<HTMLDivElement>(null)
  const refsRef   = useRef<SceneRefs | null>(null)
  const [cameraMode, setCameraMode] = useState<CameraMode>(camPrefs.cameraMode as CameraMode)

  const { path, selected, playing, animT, frameR, frameU, showOverlays, debugLog, mutedTracks } = useStore()

  // craftRollSegments' t is arc-length fraction; animT is parameter-space — must convert
  // or roll timing drifts against the visual position. See math/spline.ts makeArcTable.
  const arcTable = useMemo(() => makeArcTable(path.wps, path.closed), [path])


  // ── Init ──────────────────────────────────────────────────────────────
  useEffect(() => {
    const mount = mountRef.current
    if (!mount) return

    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(window.devicePixelRatio)
    renderer.setClearColor(0x0c0c0d)
    renderer.domElement.style.cssText = 'position:absolute;inset:0;'
    mount.appendChild(renderer.domElement)

    const scene  = new THREE.Scene()
    const camera = new THREE.PerspectiveCamera(55, 1, 0.1, 1000)
    camera.position.set(22, 14, 22)

    const controls = new OrbitControls(camera, renderer.domElement)
    controls.target.set(5, 1, 0)
    controls.update()

    // Grid + axes
    scene.add(new THREE.GridHelper(80, 16, 0x252528, 0x1c1c1f))
    const addLine = (a: [number,number,number], b: [number,number,number], c: number) => {
      const g = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(...a), new THREE.Vector3(...b)])
      scene.add(new THREE.Line(g, new THREE.LineBasicMaterial({ color: c })))
    }
    addLine([-60,0,0],[60,0,0], 0x3f2020)
    addLine([0,-20,0],[0,20,0], 0x203f20)
    addLine([0,0,-60],[0,0,60], 0x20203f)

    // Background scatter group — populated by path useEffect so it knows the path AABB
    const bgGroup = new THREE.Group()
    scene.add(bgGroup)

    // Gameplay context overlays (player ref ship, camera cube, frustum, scale planes)
    const overlayGroup = buildOverlayGroup()
    scene.add(overlayGroup)

    // Player origin marker (small green dot at 0,0,0 — separate from the ship overlay)
    scene.add(Object.assign(
      new THREE.Mesh(new THREE.SphereGeometry(0.15, 8, 8), new THREE.MeshBasicMaterial({ color: 0x4ade80 }))
    ))

    // Target marker
    const targetMesh = new THREE.Mesh(
      new THREE.SphereGeometry(0.3, 6, 6),
      new THREE.MeshBasicMaterial({ color: 0xa78bfa, wireframe: true }),
    )
    targetMesh.visible = false
    scene.add(targetMesh)

    // Path lines
    const wireLine   = makeLine(0x38bdf8); scene.add(wireLine)
    const actualLine = makeLine(0xf97316); actualLine.visible = false; scene.add(actualLine)

    // Waypoint spheres
    const wpGroup = new THREE.Group(); scene.add(wpGroup)

    // Ship
    const shipGroup = buildShipGroup()
    shipGroup.visible = false
    scene.add(shipGroup)

    // Gizmo (kept invisible — 3D drag disabled, use ortho views)
    const gizmo     = new THREE.Group()
    const gizmoHits: THREE.Mesh[] = []
    gizmo.visible = false
    scene.add(gizmo)

    // ── Raycaster + pointer events ────────────────────────────────────
    const raycaster = new THREE.Raycaster()
    raycaster.params.Line!.threshold = 0.1

    const refs: SceneRefs = {
      renderer, scene, camera, controls, raycaster,
      wireLine, actualLine, wpGroup, bgGroup, overlayGroup, shipGroup, targetMesh,
      gizmo, gizmoHits, raf: 0,
      kick: () => {},         // replaced after render loop init
      cameraMode: camPrefs.cameraMode as CameraMode,
      followDist: 8,
      shipPos: new THREE.Vector3(),
      shipFwd: new THREE.Vector3(1, 0, 0),
      shipUp:  new THREE.Vector3(0, 1, 0),
    }
    refsRef.current = refs

    const cv = renderer.domElement

    const onPointerDown = (e: PointerEvent) => {
      if (!refsRef.current) return
      const rect = cv.getBoundingClientRect()
      const ndc  = getNDC(e, rect)
      refs.raycaster.setFromCamera(ndc, refs.camera)
      const wpMeshes: THREE.Object3D[] = []
      refs.wpGroup.traverse((o) => { if ((o as THREE.Mesh).isMesh) wpMeshes.push(o) })
      const wpHits = refs.raycaster.intersectObjects(wpMeshes, false)
      if (wpHits.length > 0) {
        e.stopPropagation()
        const idx = wpHits[0].object.userData.wpIdx as number
        useStore.getState().setSelected(idx)
      }
    }
    cv.addEventListener('pointerdown', onPointerDown)

    // Scroll: adjust follow distance when in follow mode;
    // otherwise orbit controls handles the wheel event natively.
    const onWheel = (e: WheelEvent) => {
      if (refs.cameraMode !== 'follow') return
      e.preventDefault()
      const factor = e.deltaY > 0 ? 1.12 : 0.89
      refs.followDist = Math.max(1.5, Math.min(40, refs.followDist * factor))
    }
    cv.addEventListener('wheel', onWheel, { passive: false })

    // ── Resize ────────────────────────────────────────────────────────
    const resize = () => {
      const rect = mount.getBoundingClientRect()
      renderer.setSize(rect.width, rect.height)
      camera.aspect = rect.width / (rect.height || 1)
      camera.updateProjectionMatrix()
    }
    resize()
    const ro = new ResizeObserver(resize)
    ro.observe(mount)

    // ── Render loop (demand-driven) ───────────────────────────────────
    // Continuous only while playing or in a non-orbit camera mode (follow/ingame
    // need per-frame camera updates). When orbit + paused, the loop stops and
    // kick() restarts it for a single frame whenever something changes.
    const render = () => {
      refs.raf = 0
      if (document.hidden) return            // tab not visible — skip & stop

      const { playing } = useStore.getState()

      switch (refs.cameraMode) {
        case 'follow':
          if (refs.shipGroup.visible) {
            refs.camera.position
              .copy(refs.shipPos)
              .addScaledVector(refs.shipFwd, -refs.followDist)
              .addScaledVector(refs.shipUp,   refs.followDist * 0.22)
            refs.camera.lookAt(
              refs.shipPos.x + refs.shipFwd.x * 2,
              refs.shipPos.y + refs.shipFwd.y * 2,
              refs.shipPos.z + refs.shipFwd.z * 2,
            )
          }
          break
        case 'ingame':
          refs.camera.position.set(GAME_CAM_X, GAME_CAM_Y, 0)
          refs.camera.lookAt(GAME_CAM_X + 100, GAME_CAM_Y, 0)
          break
        default: // 'orbit'
          controls.update()   // applies damping
          break
      }
      renderer.render(scene, camera)

      // Keep looping only when the scene changes every frame on its own.
      if (playing || refs.cameraMode !== 'orbit') {
        refs.raf = requestAnimationFrame(render)
      }
    }

    // Kick requests one frame; no-op if a frame is already scheduled.
    const kick = () => {
      if (refs.raf === 0 && !document.hidden) {
        refs.raf = requestAnimationFrame(render)
      }
    }
    refs.kick = kick

    // Render when OrbitControls moves (user drag + damping settling).
    controls.addEventListener('change', kick)

    // Resume rendering when the browser tab becomes visible again.
    const onVisibilityChange = () => { if (!document.hidden) kick() }
    document.addEventListener('visibilitychange', onVisibilityChange)

    kick() // initial render

    return () => {
      cancelAnimationFrame(refs.raf)
      document.removeEventListener('visibilitychange', onVisibilityChange)
      ro.disconnect()
      cv.removeEventListener('pointerdown', onPointerDown)
      cv.removeEventListener('wheel', onWheel)
      renderer.dispose()
      if (mount.contains(cv)) mount.removeChild(cv)
    }
  }, [])

  // ── Toggle gameplay overlays ─────────────────────────────────────────
  useEffect(() => {
    const refs = refsRef.current
    if (!refs) return
    refs.overlayGroup.visible = showOverlays
    refs.kick()
  }, [showOverlays])

  // ── Update path geometry + waypoints ─────────────────────────────────
  useEffect(() => {
    const refs = refsRef.current
    if (!refs) return

    const samples = buildSpline({ wps: path.wps, closed: path.closed })

    if (samples.length > 1) {
      const wirePos = new Float32Array(samples.length * 3)
      samples.forEach(({ wire }, i) => {
        wirePos[i*3]=wire.x; wirePos[i*3+1]=wire.y; wirePos[i*3+2]=wire.z
      })
      refs.wireLine.geometry.setAttribute('position', new THREE.BufferAttribute(wirePos, 3))
      refs.wireLine.geometry.computeBoundingSphere()
      refs.wireLine.visible = true
      refs.actualLine.visible = false
    } else {
      refs.wireLine.visible   = false
      refs.actualLine.visible = false
    }

    // Waypoint spheres
    refs.wpGroup.clear()
    path.wps.forEach((wp, i) => {
      const isSel = i === selected
      const geo   = new THREE.SphereGeometry(isSel ? 0.45 : 0.28, 8, 8)
      const mat   = new THREE.MeshBasicMaterial({ color: isSel ? 0xfbbf24 : 0x94a3b8 })
      const mesh  = new THREE.Mesh(geo, mat)
      mesh.position.set(wp.x, wp.y, wp.z)
      mesh.userData.wpIdx = i
      refs.wpGroup.add(mesh)
    })

    refs.targetMesh.visible = path.orient === 'target'
    if (path.orient === 'target') {
      refs.targetMesh.position.set(path.target.x, path.target.y, path.target.z)
    }

    refs.gizmo.visible = false

    // Rebuild background scatter outside the full actual-path AABB
    buildBackground(refs.bgGroup, samples.map(s => s.wire))
    refs.kick()
  }, [path, selected])

  // ── Update ship during animation ─────────────────────────────────────
  useEffect(() => {
    const refs = refsRef.current
    if (!refs || path.wps.length < 2) return
    // Ship is always shown while a valid path exists — paused or playing.
    // The scrubber sets animT when paused; this effect re-runs and repositions the ship.

    const nSegs        = path.closed ? path.wps.length : path.wps.length - 1
    const animFrac     = nSegs > 0 ? Math.max(0, Math.min(1, (animT % (nSegs || 1)) / (nSegs || 1))) : 0
    const wire         = evalAt(path.wps, animT, path.closed)
    const tan          = tangentAt(path.wps, animT, path.closed)
    const crSegs       = mutedTracks['craftRoll'] ? [] : (path.craftRollSegments ?? [])
    const craftRollDeg = evalCraftRoll(crSegs, arcTable.paramToArc(animFrac), path.craftRollLoopSeam)
    const facing       = shipFacing(wire, tan, path.orient, path.target)
    // Frame selection:
    // • target mode: makeFrame(facing) — tangent ≠ facing, transport frame is wrong axis.
    // • path mode, playing: frameR/frameU — parallel transport accumulated by the RAF loop,
    //   with holonomy correction applied each tick in useAnimLoop.
    // • path mode, scrubbing (!playing): sample the pre-computed frame table at animFrac.
    //   The table is built by buildFrameTable in useAnimLoop's path useEffect; it contains
    //   the same holonomy-corrected transport frame the playing loop would produce at that
    //   arc fraction. Falls back to makeFrame if the table isn't available yet.
    let R: typeof frameR, U: typeof frameU
    if (path.orient === 'target') {
      ;({ R, U } = makeFrame(facing))
    } else if (playing) {
      R = frameR; U = frameU
    } else {
      const cached = getFrameAt(animFrac)
      ;({ R, U } = cached ?? makeFrame(facing))
    }

    refs.shipGroup.position.set(wire.x, wire.y, wire.z)

    // Apply craftRoll: rotate U and R around the forward axis (facing).
    // CW roll: U gains +R (right-wing-down from pilot view), R gains -U.
    const crRad = craftRollDeg * (Math.PI / 180)
    const crCos = Math.cos(crRad), crSin = Math.sin(crRad)
    const rolledU = {
      x: crCos * U.x + crSin * R.x,
      y: crCos * U.y + crSin * R.y,
      z: crCos * U.z + crSin * R.z,
    }
    const rolledR = {
      x: -crSin * U.x + crCos * R.x,
      y: -crSin * U.y + crCos * R.y,
      z: -crSin * U.z + crCos * R.z,
    }

    // makeBasis: col0=local X (forward), col1=local Y (up), col2=local Z (right)
    refs.shipGroup.setRotationFromMatrix(new THREE.Matrix4().makeBasis(
      new THREE.Vector3(facing.x, facing.y, facing.z),
      new THREE.Vector3(rolledU.x, rolledU.y, rolledU.z),
      new THREE.Vector3(rolledR.x, rolledR.y, rolledR.z),
    ))
    refs.shipGroup.visible = true

    // Store ship state so the follow-cam render loop can read it.
    refs.shipPos.set(wire.x, wire.y, wire.z)
    refs.shipFwd.set(facing.x, facing.y, facing.z)
    refs.shipUp.set(rolledU.x, rolledU.y, rolledU.z)

    if (debugLog) {
      console.log(
        `[path] t=${animT.toFixed(4)}`,
        `pos=(${wire.x.toFixed(2)}, ${wire.y.toFixed(2)}, ${wire.z.toFixed(2)})`,
        `fwd=(${facing.x.toFixed(3)}, ${facing.y.toFixed(3)}, ${facing.z.toFixed(3)})`,
        `R=(${frameR.x.toFixed(3)}, ${frameR.y.toFixed(3)}, ${frameR.z.toFixed(3)})`,
        `U=(${frameU.x.toFixed(3)}, ${frameU.y.toFixed(3)}, ${frameU.z.toFixed(3)})`,
      )
    }

    void nSegs
    refs.kick()
  }, [animT, playing, path, arcTable, frameR, frameU, debugLog, mutedTracks])

  // ── Camera mode cycle: orbit → follow → ingame → orbit ───────────────
  const cycleCamera = useCallback(() => {
    const refs = refsRef.current
    if (!refs) return
    const next: CameraMode =
      refs.cameraMode === 'orbit'  ? 'follow' :
      refs.cameraMode === 'follow' ? 'ingame'  : 'orbit'
    refs.cameraMode = next
    refs.controls.enabled = next === 'orbit'
    saveCamPrefs({ cameraMode: next })
    setCameraMode(next)
    refs.kick()
  }, [])

  return (
    <div style={{ position: 'absolute', inset: 0, outline: 'none' }} tabIndex={0}
      onMouseEnter={e => (e.currentTarget as HTMLDivElement).focus()}>
      <div ref={mountRef} className="three-mount" />
      <button
        className={cameraMode !== 'orbit' ? 'primary' : ''}
        onClick={cycleCamera}
        title="Cycle camera: Orbit → Follow (chases ship; scroll to adjust distance) → In-Game (fixed at game camera position)"
        style={{ position: 'absolute', top: 22, right: 6, zIndex: 3, fontSize: 10 }}
      >
        {CAMERA_MODE_LABEL[cameraMode]}
      </button>
    </div>
  )
}
