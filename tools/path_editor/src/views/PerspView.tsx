// 3D perspective view using Three.js + OrbitControls.
// Read-only (no waypoint editing here); shows wire, actual path, waypoints, ship.

import { useEffect, useRef } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { useStore } from '../store'
import { buildSpline, evalAt, tangentAt, actualPos, shipFacing, makeFrame } from '../math/spline'
import { v3 } from '../math/vec3'

// ── Scene refs held outside React state ────────────────────────────────
interface SceneRefs {
  renderer:   THREE.WebGLRenderer
  scene:      THREE.Scene
  camera:     THREE.PerspectiveCamera
  controls:   OrbitControls
  wireLine:   THREE.Line
  actualLine: THREE.Line
  wpGroup:    THREE.Group
  shipGroup:  THREE.Group
  targetMesh: THREE.Mesh
  raf:        number
}

function makeLine(color: number): THREE.Line {
  const geo = new THREE.BufferGeometry()
  const mat = new THREE.LineBasicMaterial({ color })
  return new THREE.Line(geo, mat)
}

export function PerspView() {
  const mountRef = useRef<HTMLDivElement>(null)
  const sceneRef = useRef<SceneRefs | null>(null)

  const { path, selected, playing, animT } = useStore()

  // ── Init Three.js scene once ──────────────────────────────────────────
  useEffect(() => {
    const mount = mountRef.current
    if (!mount) return

    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(window.devicePixelRatio)
    renderer.setClearColor(0x0c0c0d)
    mount.appendChild(renderer.domElement)
    renderer.domElement.style.position = 'absolute'
    renderer.domElement.style.inset = '0'

    const scene = new THREE.Scene()

    const camera = new THREE.PerspectiveCamera(55, 1, 0.1, 1000)
    camera.position.set(22, 14, 22)
    camera.lookAt(0, 0, 0)

    const controls = new OrbitControls(camera, renderer.domElement)
    controls.target.set(5, 1, 0)
    controls.update()

    // Grid (XZ plane at Y=0)
    const grid = new THREE.GridHelper(80, 16, 0x252528, 0x1c1c1f)
    scene.add(grid)

    // Faint axis lines
    const addAxis = (from: [number,number,number], to: [number,number,number], color: number) => {
      const g = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(...from), new THREE.Vector3(...to)])
      scene.add(new THREE.Line(g, new THREE.LineBasicMaterial({ color })))
    }
    addAxis([-60,0,0],[60,0,0], 0x3f2020)  // X
    addAxis([0,-20,0],[0,20,0], 0x203f20)  // Y
    addAxis([0,0,-60],[0,0,60], 0x20203f)  // Z

    // Player marker
    const playerGeo = new THREE.SphereGeometry(0.35, 8, 8)
    const playerMat = new THREE.MeshBasicMaterial({ color: 0x4ade80 })
    scene.add(new THREE.Mesh(playerGeo, playerMat))

    // Target marker (orient=target)
    const targetGeo = new THREE.SphereGeometry(0.3, 6, 6)
    const targetMat = new THREE.MeshBasicMaterial({ color: 0xa78bfa, wireframe: true })
    const targetMesh = new THREE.Mesh(targetGeo, targetMat)
    targetMesh.visible = false
    scene.add(targetMesh)

    // Wire path
    const wireLine = makeLine(0x38bdf8)
    scene.add(wireLine)

    // Actual path (standoff offset)
    const actualLine = makeLine(0xf97316)
    actualLine.visible = false
    scene.add(actualLine)

    // Waypoint spheres group
    const wpGroup = new THREE.Group()
    scene.add(wpGroup)

    // Ship group: cone for body + arrow for forward direction
    const shipGroup = new THREE.Group()
    const coneGeo = new THREE.ConeGeometry(0.35, 1.4, 6)
    coneGeo.rotateZ(-Math.PI / 2)            // point in local +X
    const coneMat = new THREE.MeshBasicMaterial({ color: 0xf97316 })
    shipGroup.add(new THREE.Mesh(coneGeo, coneMat))
    shipGroup.visible = false
    scene.add(shipGroup)

    const refs: SceneRefs = { renderer, scene, camera, controls, wireLine, actualLine, wpGroup, shipGroup, targetMesh, raf: 0 }
    sceneRef.current = refs

    // Resize
    const resize = () => {
      const rect = mount.getBoundingClientRect()
      renderer.setSize(rect.width, rect.height)
      camera.aspect = rect.width / (rect.height || 1)
      camera.updateProjectionMatrix()
    }
    resize()
    const ro = new ResizeObserver(resize)
    ro.observe(mount)

    // Render loop
    const render = () => {
      refs.raf = requestAnimationFrame(render)
      controls.update()
      renderer.render(scene, camera)
    }
    render()

    return () => {
      cancelAnimationFrame(refs.raf)
      ro.disconnect()
      renderer.dispose()
      if (mount.contains(renderer.domElement)) mount.removeChild(renderer.domElement)
    }
  }, [])

  // ── Update scene when path or selection changes ───────────────────────
  useEffect(() => {
    const refs = sceneRef.current
    if (!refs) return
    const { wireLine, actualLine, wpGroup, targetMesh } = refs

    const samples = buildSpline({
      wps: path.wps, closed: path.closed, roll: path.roll, standoff: path.standoff,
    })

    // Wire line geometry
    if (samples.length > 1) {
      const wirePos = new Float32Array(samples.length * 3)
      samples.forEach(({ wire }, i) => {
        wirePos[i * 3] = wire.x; wirePos[i * 3 + 1] = wire.y; wirePos[i * 3 + 2] = wire.z
      })
      wireLine.geometry.setAttribute('position', new THREE.BufferAttribute(wirePos, 3))
      wireLine.geometry.computeBoundingSphere()
      wireLine.visible = true

      // Actual path (only when standoff > 0)
      if (path.standoff > 0.001) {
        const actualPos2 = new Float32Array(samples.length * 3)
        samples.forEach(({ actual }, i) => {
          actualPos2[i * 3] = actual.x; actualPos2[i * 3 + 1] = actual.y; actualPos2[i * 3 + 2] = actual.z
        })
        actualLine.geometry.setAttribute('position', new THREE.BufferAttribute(actualPos2, 3))
        actualLine.geometry.computeBoundingSphere()
        actualLine.visible = true
      } else {
        actualLine.visible = false
      }
    } else {
      wireLine.visible = false
      actualLine.visible = false
    }

    // Waypoints
    wpGroup.clear()
    path.wps.forEach((wp, i) => {
      const isSel = i === selected
      const geo = new THREE.SphereGeometry(isSel ? 0.45 : 0.28, 8, 8)
      const mat = new THREE.MeshBasicMaterial({ color: isSel ? 0xfbbf24 : 0x94a3b8 })
      const mesh = new THREE.Mesh(geo, mat)
      mesh.position.set(wp.x, wp.y, wp.z)
      wpGroup.add(mesh)
    })

    // Target marker
    if (path.orient === 'target') {
      targetMesh.position.set(path.target.x, path.target.y, path.target.z)
      targetMesh.visible = true
    } else {
      targetMesh.visible = false
    }
  }, [path, selected])

  // ── Update ship position each animation tick ──────────────────────────
  useEffect(() => {
    const refs = sceneRef.current
    if (!refs || path.wps.length < 2) return

    const { shipGroup } = refs

    if (!playing) {
      shipGroup.visible = false
      return
    }

    const nSegs = path.wps.length - 1
    const wire   = evalAt(path.wps, animT, path.closed)
    const tan    = tangentAt(path.wps, animT, path.closed)
    const frac   = animT / nSegs
    const ap     = actualPos(wire, tan, frac, path.roll, path.standoff)
    const facing = shipFacing(ap, tan, path.orient, path.target)

    shipGroup.position.set(ap.x, ap.y, ap.z)

    // Align cone to face forward direction
    // The cone's local +X = forward; build rotation from that
    const { R, U } = makeFrame(facing)
    // Three.js: setFromRotationMatrix needs a matrix whose columns are (right, up, forward)
    // Our frame: T=facing, R=right, U=up
    // Matrix columns: [R, U, T] for a standard right-hand frame
    const m = new THREE.Matrix4().makeBasis(
      new THREE.Vector3(R.x, R.y, R.z),
      new THREE.Vector3(U.x, U.y, U.z),
      new THREE.Vector3(facing.x, facing.y, facing.z),
    )
    shipGroup.setRotationFromMatrix(m)
    shipGroup.visible = true
  }, [animT, playing, path])

  return <div ref={mountRef} className="three-mount" />
}
