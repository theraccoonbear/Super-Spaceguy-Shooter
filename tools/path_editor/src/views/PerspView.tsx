// 3D perspective view — Three.js + OrbitControls.
// Waypoints are selectable via click; use ortho views to move nodes.

import { useEffect, useRef } from 'react'
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
  shipGroup:  THREE.Group
  targetMesh: THREE.Mesh
  gizmo:      THREE.Group
  gizmoHits:  THREE.Mesh[]
  raf:        number
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

// Build the ship group: nose + port wing + starboard wing + dorsal fin.
// Local coordinate system: X = forward, Y = up, Z = right.
// craftRoll rotates around X (forward), which banks Y toward Z.
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

function getNDC(e: PointerEvent, rect: DOMRect): THREE.Vector2 {
  return new THREE.Vector2(
    ((e.clientX - rect.left) / rect.width)  *  2 - 1,
    ((e.clientY - rect.top)  / rect.height) * -2 + 1,
  )
}

// ── Component ───────────────────────────────────────────────────────────
export function PerspView() {
  const mountRef = useRef<HTMLDivElement>(null)
  const refsRef  = useRef<SceneRefs | null>(null)

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
      wireLine, actualLine, wpGroup, shipGroup, targetMesh,
      gizmo, gizmoHits, raf: 0,
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
      controls.update()
      renderer.render(scene, camera)
    }
    render()

    return () => {
      cancelAnimationFrame(refs.raf)
      ro.disconnect()
      cv.removeEventListener('pointerdown', onPointerDown)
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
  }, [path, selected])

  // ── Update ship during animation ─────────────────────────────────────
  useEffect(() => {
    const refs = refsRef.current
    if (!refs || path.wps.length < 2) return
    if (!playing) { refs.shipGroup.visible = false; return }

    const nSegs      = path.closed ? path.wps.length : path.wps.length - 1
    const wire       = evalAt(path.wps, animT, path.closed)
    const tan        = tangentAt(path.wps, animT, path.closed)
    const pathRollDeg  = evalRollAt(path.wps, animT, path.closed, 'pathRoll')
    const craftRollDeg = evalRollAt(path.wps, animT, path.closed, 'craftRoll')
    const ap         = actualPos(wire, tan, pathRollDeg, path.standoff)
    const facing     = shipFacing(ap, tan, path.orient, path.target)
    const { R, U }   = makeFrame(facing)

    refs.shipGroup.position.set(ap.x, ap.y, ap.z)

    // Apply craftRoll: rotate U and R around the forward axis (facing).
    // Positive craftRoll banks the dorsal fin from +Y toward +Z (right-roll).
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

    // Suppress unused-variable warning; nSegs used to guard closed-path bounds above.
    void nSegs
  }, [animT, playing, path])

  return <div ref={mountRef} className="three-mount" />
}
