// 3D perspective view — Three.js + OrbitControls.
// Waypoints are selectable and draggable via axis gizmo handles (X/Y/Z arrows).
// OrbitControls is suppressed while dragging a gizmo handle.

import { useEffect, useRef } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { useStore } from '../store'
import { buildSpline, evalAt, tangentAt, actualPos, shipFacing, makeFrame } from '../math/spline'
import { v3 } from '../math/vec3'

// ── Axis colours (standard: red X, green Y, blue Z) ────────────────────
const AXIS_X = 0xef4444
const AXIS_Y = 0x4ade80
const AXIS_Z = 0x60a5fa

// ── Types ───────────────────────────────────────────────────────────────
type AxisKey = 'x' | 'y' | 'z'

interface DragState {
  wpIdx:           number
  axis:            AxisKey
  axisVec:         THREE.Vector3
  plane:           THREE.Plane
  originWp:        THREE.Vector3   // waypoint world position at drag start
  originIntersect: THREE.Vector3 | null
}

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
  gizmo:      THREE.Group         // axis handles for selected waypoint
  gizmoHits:  THREE.Mesh[]        // invisible hit volumes, tagged with userData.axis
  drag:       DragState | null
  raf:        number
}

// ── Helpers ─────────────────────────────────────────────────────────────
function makeLine(color: number): THREE.Line {
  return new THREE.Line(
    new THREE.BufferGeometry(),
    new THREE.LineBasicMaterial({ color }),
  )
}

// Build one axis of the gizmo: visible arrow + invisible hit cylinder.
// Returns { visual: ArrowHelper, hit: Mesh }.
function makeGizmoAxis(dir: THREE.Vector3, color: number, axis: AxisKey) {
  // Visual arrow
  const arrow = new THREE.ArrowHelper(dir, new THREE.Vector3(), 1, color, 0.22, 0.1)

  // Invisible hit cylinder along the shaft (easier to click than a line).
  // Cylinder default runs along local Y — rotate to match axis direction.
  const hitGeo = new THREE.CylinderGeometry(0.08, 0.08, 0.85, 6)
  const hitMat = new THREE.MeshBasicMaterial({ visible: false, side: THREE.DoubleSide })
  const hit    = new THREE.Mesh(hitGeo, hitMat)
  hit.userData = { isGizmoHandle: true, axis }

  // Translate so cylinder bottom is at origin (tip at +dir)
  hit.position.addScaledVector(dir, 0.42)

  // Rotate local Y to match axis direction
  if (axis === 'x') hit.rotateZ(-Math.PI / 2)
  if (axis === 'z') hit.rotateX( Math.PI / 2)
  // Y needs no rotation

  return { arrow, hit }
}

// Build the drag plane: contains the drag axis, faces the camera.
function buildDragPlane(axisVec: THREE.Vector3, wpPos: THREE.Vector3, camPos: THREE.Vector3): THREE.Plane {
  const toCamera = new THREE.Vector3().subVectors(camPos, wpPos).normalize()
  // normal = axis × (toCamera × axis)  — perpendicular to axis, facing camera
  const perp   = new THREE.Vector3().crossVectors(toCamera, axisVec)
  const normal = new THREE.Vector3().crossVectors(axisVec, perp)
  if (normal.lengthSq() < 1e-6) {
    // Degenerate (camera nearly along axis) — fall back to world-up plane
    normal.set(0, 1, 0)
  } else {
    normal.normalize()
  }
  return new THREE.Plane().setFromNormalAndCoplanarPoint(normal, wpPos)
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
    const shipGroup = new THREE.Group()
    const coneGeo   = new THREE.ConeGeometry(0.35, 1.4, 6)
    coneGeo.rotateZ(-Math.PI / 2)
    shipGroup.add(new THREE.Mesh(coneGeo, new THREE.MeshBasicMaterial({ color: 0xf97316 })))
    shipGroup.visible = false
    scene.add(shipGroup)

    // ── Gizmo ────────────────────────────────────────────────────────
    const gizmo    = new THREE.Group()
    const gizmoHits: THREE.Mesh[] = []
    scene.add(gizmo)

    const axes: Array<{ dir: [number,number,number]; color: number; axis: AxisKey }> = [
      { dir: [1,0,0], color: AXIS_X, axis: 'x' },
      { dir: [0,1,0], color: AXIS_Y, axis: 'y' },
      { dir: [0,0,1], color: AXIS_Z, axis: 'z' },
    ]
    for (const { dir, color, axis } of axes) {
      const { arrow, hit } = makeGizmoAxis(new THREE.Vector3(...dir), color, axis)
      gizmo.add(arrow)
      gizmo.add(hit)
      gizmoHits.push(hit)
    }
    gizmo.visible = false

    // ── Raycaster + pointer events ────────────────────────────────────
    const raycaster = new THREE.Raycaster()
    raycaster.params.Line!.threshold = 0.1

    const refs: SceneRefs = {
      renderer, scene, camera, controls, raycaster,
      wireLine, actualLine, wpGroup, shipGroup, targetMesh,
      gizmo, gizmoHits, drag: null, raf: 0,
    }
    refsRef.current = refs

    // Pointer events — attached to canvas so we control propagation
    const cv = renderer.domElement

    const onPointerDown = (e: PointerEvent) => {
      if (!refsRef.current) return
      const r   = refs
      const rect = cv.getBoundingClientRect()
      const ndc  = getNDC(e, rect)
      r.raycaster.setFromCamera(ndc, r.camera)

      // 1. Check gizmo handles first
      if (r.gizmo.visible) {
        const hits = r.raycaster.intersectObjects(r.gizmoHits, false)
        if (hits.length > 0) {
          e.stopPropagation()
          r.controls.enabled = false
          cv.setPointerCapture(e.pointerId)

          const axis    = hits[0].object.userData.axis as AxisKey
          const axisVec = new THREE.Vector3(axis==='x'?1:0, axis==='y'?1:0, axis==='z'?1:0)
          const sel     = useStore.getState().selected
          const wp      = useStore.getState().path.wps[sel]
          const wpPos   = new THREE.Vector3(wp.x, wp.y, wp.z)
          const plane   = buildDragPlane(axisVec, wpPos, r.camera.position)

          r.drag = { wpIdx: sel, axis, axisVec, plane, originWp: wpPos, originIntersect: null }
          return
        }
      }

      // 2. Check waypoint spheres
      const wpMeshes: THREE.Object3D[] = []
      r.wpGroup.traverse((o) => { if ((o as THREE.Mesh).isMesh) wpMeshes.push(o) })
      const wpHits = r.raycaster.intersectObjects(wpMeshes, false)
      if (wpHits.length > 0) {
        e.stopPropagation()
        const idx = wpHits[0].object.userData.wpIdx as number
        useStore.getState().setSelected(idx)
      }
      // 3. Otherwise let OrbitControls orbit
    }

    const onPointerMove = (e: PointerEvent) => {
      const r = refsRef.current
      if (!r || !r.drag) return
      const rect = cv.getBoundingClientRect()
      const ndc  = getNDC(e, rect)
      r.raycaster.setFromCamera(ndc, r.camera)

      const intersectPt = new THREE.Vector3()
      const hit = r.raycaster.ray.intersectPlane(r.drag.plane, intersectPt)
      if (!hit) return

      if (!r.drag.originIntersect) {
        r.drag.originIntersect = intersectPt.clone()
        return
      }

      const delta    = new THREE.Vector3().subVectors(intersectPt, r.drag.originIntersect)
      const movement = delta.dot(r.drag.axisVec)
      const newPos   = r.drag.originWp.clone().addScaledVector(r.drag.axisVec, movement)

      const wps = useStore.getState().path.wps
      useStore.getState().setWp(r.drag.wpIdx, {
        ...wps[r.drag.wpIdx],
        [r.drag.axis]: newPos[r.drag.axis],
      })
    }

    const onPointerUp = (e: PointerEvent) => {
      const r = refsRef.current
      if (!r) return
      if (r.drag) {
        cv.releasePointerCapture(e.pointerId)
        r.drag = null
        r.controls.enabled = true
      }
    }

    cv.addEventListener('pointerdown', onPointerDown)
    cv.addEventListener('pointermove', onPointerMove)
    cv.addEventListener('pointerup',   onPointerUp)

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

      // Keep gizmo scaled to constant apparent size
      if (refs.gizmo.visible) {
        const dist = refs.camera.position.distanceTo(refs.gizmo.position)
        refs.gizmo.scale.setScalar(dist * 0.13)
      }

      controls.update()
      renderer.render(scene, camera)
    }
    render()

    return () => {
      cancelAnimationFrame(refs.raf)
      ro.disconnect()
      cv.removeEventListener('pointerdown', onPointerDown)
      cv.removeEventListener('pointermove', onPointerMove)
      cv.removeEventListener('pointerup',   onPointerUp)
      renderer.dispose()
      if (mount.contains(cv)) mount.removeChild(cv)
    }
  }, [])

  // ── Update path geometry + waypoints + gizmo ────────────────────────
  useEffect(() => {
    const refs = refsRef.current
    if (!refs) return

    const samples = buildSpline({
      wps: path.wps, closed: path.closed, roll: path.roll, standoff: path.standoff,
    })

    // Wire line
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

    // Waypoint spheres — tag each mesh with its index for raycasting
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

    // Target marker
    refs.targetMesh.visible = path.orient === 'target'
    if (path.orient === 'target') {
      refs.targetMesh.position.set(path.target.x, path.target.y, path.target.z)
    }

    // Gizmo — position at selected waypoint
    if (selected >= 0 && selected < path.wps.length) {
      const wp = path.wps[selected]
      refs.gizmo.position.set(wp.x, wp.y, wp.z)
      refs.gizmo.visible = true
    } else {
      refs.gizmo.visible = false
    }
  }, [path, selected])

  // Keep gizmo position in sync during live drag (store updates wps each move event)
  useEffect(() => {
    const refs = refsRef.current
    if (!refs || !refs.drag || selected < 0) return
    const wp = path.wps[selected]
    if (wp) refs.gizmo.position.set(wp.x, wp.y, wp.z)
  }, [path.wps, selected])

  // ── Update ship during animation ─────────────────────────────────────
  useEffect(() => {
    const refs = refsRef.current
    if (!refs || path.wps.length < 2) return

    if (!playing) { refs.shipGroup.visible = false; return }

    const nSegs  = path.wps.length - 1
    const wire   = evalAt(path.wps, animT, path.closed)
    const tan    = tangentAt(path.wps, animT, path.closed)
    const frac   = animT / nSegs
    const ap     = actualPos(wire, tan, frac, path.roll, path.standoff)
    const facing = shipFacing(ap, tan, path.orient, path.target)
    const { R, U } = makeFrame(facing)

    refs.shipGroup.position.set(ap.x, ap.y, ap.z)
    refs.shipGroup.setRotationFromMatrix(new THREE.Matrix4().makeBasis(
      new THREE.Vector3(R.x, R.y, R.z),
      new THREE.Vector3(U.x, U.y, U.z),
      new THREE.Vector3(facing.x, facing.y, facing.z),
    ))
    refs.shipGroup.visible = true
  }, [animT, playing, path])

  return <div ref={mountRef} className="three-mount" />
}
