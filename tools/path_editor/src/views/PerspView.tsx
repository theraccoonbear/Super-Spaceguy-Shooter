// 3D perspective view — Three.js + OrbitControls.
// Waypoints are selectable via click; use ortho views to move nodes.
// Follow mode: camera trails the ship; scroll adjusts distance.

import { useEffect, useRef, useState, useCallback } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { useStore } from '../store'
import { buildSpline, evalAt, tangentAt, actualPos, evalRollAt, shipFacing, makeFrame } from '../math/spline'

// ── Ship model colors ───────────────────────────────────────────────────
const COL_NOSE  = 0xf97316   // orange — nose cone
const COL_BODY  = 0x475569   // slate  — fuselage cylinder
const COL_PORT  = 0x22d3ee   // cyan   — port wing  (left,  −Z local)
const COL_STAR  = 0xa3e635   // lime   — starboard  (right, +Z local)
const COL_FIN   = 0xf472b6   // pink   — dorsal fin (top,   +Y local)

// ── Types ───────────────────────────────────────────────────────────────
interface SceneRefs {
  renderer:   THREE.WebGLRenderer
  scene:      THREE.Scene
  camera:     THREE.PerspectiveCamera
  controls:   OrbitControls
  raycaster:  THREE.Raycaster
  wireLine:   THREE.Line
  actualLine: THREE.Line
  wpGroup:    THREE.Group
  bgGroup:    THREE.Group   // background scatter — rebuilt on path change
  shipGroup:  THREE.Group
  targetMesh: THREE.Mesh
  gizmo:      THREE.Group
  gizmoHits:  THREE.Mesh[]
  raf:        number
  // Follow-cam state (mutated directly — not React state)
  followMode: boolean
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

  return g
}

// Scatter dark reference cubes well outside the flight path.
// Called from the path useEffect with all actual ship positions (wire + standoff),
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

  // AABB of all actual ship positions (covers wire + standoff in every orientation)
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

  // Generate up to 300 candidates; keep the first 50 that clear the path zone.
  for (let i = 0; i < 300 && bgGroup.children.length < 50; i++) {
    const px = rng(-55, 55)
    const py = rng(-1, 20)
    const pz = rng(-55, 55)
    const sx = rng(0.4, 5), sy = rng(0.4, 5), sz = rng(0.4, 5)
    const rx = rng(0, Math.PI * 2)
    const ry = rng(0, Math.PI * 2)
    const rz = rng(0, Math.PI * 2)
    const col = COLORS[Math.floor(rand() * COLORS.length)]
    const wf  = rand() > 0.62

    // Bounding-sphere radius of this (possibly rotated) box — half-diagonal
    const hr = Math.sqrt(sx * sx + sy * sy + sz * sz) * 0.5

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
  const [followMode, setFollowMode] = useState(false)

  const { path, selected, playing, animT } = useStore()

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

    // Player marker
    scene.add(Object.assign(
      new THREE.Mesh(new THREE.SphereGeometry(0.35, 8, 8), new THREE.MeshBasicMaterial({ color: 0x4ade80 }))
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
      wireLine, actualLine, wpGroup, bgGroup, shipGroup, targetMesh,
      gizmo, gizmoHits, raf: 0,
      followMode: false,
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
      if (!refs.followMode) return
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

    // ── Render loop ───────────────────────────────────────────────────
    const render = () => {
      refs.raf = requestAnimationFrame(render)
      if (refs.followMode && refs.shipGroup.visible) {
        // Chase cam: sit behind + slightly above ship, look slightly ahead
        refs.camera.position
          .copy(refs.shipPos)
          .addScaledVector(refs.shipFwd, -refs.followDist)
          .addScaledVector(refs.shipUp,   refs.followDist * 0.22)
        refs.camera.lookAt(
          refs.shipPos.x + refs.shipFwd.x * 2,
          refs.shipPos.y + refs.shipFwd.y * 2,
          refs.shipPos.z + refs.shipFwd.z * 2,
        )
      } else if (!refs.followMode) {
        controls.update()
      }
      // Follow mode + ship not visible: camera stays at last position; no controls.update()
      renderer.render(scene, camera)
    }
    render()

    return () => {
      cancelAnimationFrame(refs.raf)
      ro.disconnect()
      cv.removeEventListener('pointerdown', onPointerDown)
      cv.removeEventListener('wheel', onWheel)
      renderer.dispose()
      if (mount.contains(cv)) mount.removeChild(cv)
    }
  }, [])

  // ── Update path geometry + waypoints ─────────────────────────────────
  useEffect(() => {
    const refs = refsRef.current
    if (!refs) return

    const samples = buildSpline({
      wps: path.wps, closed: path.closed, standoff: path.standoff,
    })

    if (samples.length > 1) {
      const wirePos = new Float32Array(samples.length * 3)
      samples.forEach(({ wire }, i) => {
        wirePos[i*3]=wire.x; wirePos[i*3+1]=wire.y; wirePos[i*3+2]=wire.z
      })
      refs.wireLine.geometry.setAttribute('position', new THREE.BufferAttribute(wirePos, 3))
      refs.wireLine.geometry.computeBoundingSphere()
      refs.wireLine.visible = true

      if (path.standoff > 0.001) {
        const aPos = new Float32Array(samples.length * 3)
        samples.forEach(({ actual }, i) => {
          aPos[i*3]=actual.x; aPos[i*3+1]=actual.y; aPos[i*3+2]=actual.z
        })
        refs.actualLine.geometry.setAttribute('position', new THREE.BufferAttribute(aPos, 3))
        refs.actualLine.geometry.computeBoundingSphere()
        refs.actualLine.visible = true
      } else {
        refs.actualLine.visible = false
      }
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
    buildBackground(refs.bgGroup, samples.map(s => s.actual))
  }, [path, selected])

  // ── Update ship during animation ─────────────────────────────────────
  useEffect(() => {
    const refs = refsRef.current
    if (!refs || path.wps.length < 2) return
    if (!playing) { refs.shipGroup.visible = false; return }

    const nSegs        = path.closed ? path.wps.length : path.wps.length - 1
    const wire         = evalAt(path.wps, animT, path.closed)
    const tan          = tangentAt(path.wps, animT, path.closed)
    const pathRollDeg  = evalRollAt(path.wps, animT, path.closed, 'pathRoll')
    const craftRollDeg = evalRollAt(path.wps, animT, path.closed, 'craftRoll')
    const ap           = actualPos(wire, tan, pathRollDeg, path.standoff)
    const facing       = shipFacing(ap, tan, path.orient, path.target)
    const { R, U }     = makeFrame(facing)

    refs.shipGroup.position.set(ap.x, ap.y, ap.z)

    // Apply craftRoll: rotate U and R around the forward axis (facing).
    const crRad = craftRollDeg * (Math.PI / 180)
    const crCos = Math.cos(crRad), crSin = Math.sin(crRad)
    const rolledU = {
      x: crCos * U.x - crSin * R.x,
      y: crCos * U.y - crSin * R.y,
      z: crCos * U.z - crSin * R.z,
    }
    const rolledR = {
      x: crSin * U.x + crCos * R.x,
      y: crSin * U.y + crCos * R.y,
      z: crSin * U.z + crCos * R.z,
    }

    // makeBasis: col0=local X (forward), col1=local Y (up), col2=local Z (right)
    refs.shipGroup.setRotationFromMatrix(new THREE.Matrix4().makeBasis(
      new THREE.Vector3(facing.x, facing.y, facing.z),
      new THREE.Vector3(rolledU.x, rolledU.y, rolledU.z),
      new THREE.Vector3(rolledR.x, rolledR.y, rolledR.z),
    ))
    refs.shipGroup.visible = true

    // Store ship state so the follow-cam render loop can read it.
    refs.shipPos.set(ap.x, ap.y, ap.z)
    refs.shipFwd.set(facing.x, facing.y, facing.z)
    refs.shipUp.set(rolledU.x, rolledU.y, rolledU.z)

    void nSegs
  }, [animT, playing, path])

  // ── Follow-mode toggle ────────────────────────────────────────────────
  const toggleFollow = useCallback(() => {
    const refs = refsRef.current
    if (!refs) return
    const next = !refs.followMode
    refs.followMode = next
    refs.controls.enabled = !next  // disable orbit controls while following
    setFollowMode(next)
  }, [])

  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <div ref={mountRef} className="three-mount" />
      <button
        className={followMode ? 'primary' : ''}
        onClick={toggleFollow}
        title="Toggle follow-cam — camera chases the ship; scroll to adjust distance"
        style={{ position: 'absolute', top: 22, right: 6, zIndex: 3, fontSize: 10 }}
      >
        {followMode ? '⊙ FOLLOW' : '⊙ ORBIT'}
      </button>
    </div>
  )
}
