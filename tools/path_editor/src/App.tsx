// Root layout + animation loop + toolbar + waypoint sidebar.

import { useEffect, useRef, useCallback } from 'react'
import { useStore } from './store'
import { tangentAt } from './math/spline'
import { v3 } from './math/vec3'
import { TopView }  from './views/TopView'
import { SideView } from './views/SideView'
import { PerspView } from './views/PerspView'
import { IOPanel }  from './io/IOPanel'

// ── Animation loop ──────────────────────────────────────────────────────
function useAnimLoop() {
  const { playing, path, animT, setAnimT } = useStore()

  // Keep mutable refs so the RAF closure always sees current values
  const playingRef = useRef(playing)
  const pathRef    = useRef(path)
  const animTRef   = useRef(animT)
  playingRef.current = playing
  pathRef.current    = path
  animTRef.current   = animT

  const setAnimTRef = useRef(setAnimT)
  setAnimTRef.current = setAnimT

  useEffect(() => {
    let lastTs = 0
    let raf = 0

    const tick = (ts: number) => {
      raf = requestAnimationFrame(tick)
      if (!playingRef.current) { lastTs = 0; return }
      if (lastTs === 0) { lastTs = ts; return }

      const dt = Math.min(ts - lastTs, 50)   // cap at 50 ms to handle tab-switch stalls
      lastTs = ts

      const p = pathRef.current
      const nSegs = p.wps.length - 1
      if (nSegs < 1) return

      // Arc-length reparameterization: advance by speed world-units per second
      const tan    = tangentAt(p.wps, animTRef.current, p.closed)
      const tanLen = v3.len(tan) || 1
      const dT     = (p.speed / tanLen) * (dt / 16.667)

      let newT = animTRef.current + dT
      if (newT >= nSegs) newT -= nSegs
      setAnimTRef.current(newT)
    }

    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, []) // runs once; all state accessed through refs
}

// ── Toolbar ─────────────────────────────────────────────────────────────
function Toolbar() {
  const { path, playing, patchPath, setPlaying, setAnimT } = useStore()

  const togglePlay = () => {
    if (!playing) setAnimT(0)
    setPlaying(!playing)
  }

  return (
    <div className="toolbar">
      {/* Path name */}
      <div className="tb-group">
        <span className="tb-label">Name</span>
        <input
          type="text"
          value={path.name}
          onChange={(e) => patchPath('name', e.target.value)}
          spellCheck={false}
        />
      </div>

      <div className="tb-sep" />

      {/* Speed */}
      <div className="tb-group">
        <span className="tb-label">Speed</span>
        <input
          type="number"
          className="narrow"
          value={path.speed}
          step={0.005}
          min={0.001}
          max={2}
          onChange={(e) => patchPath('speed', parseFloat(e.target.value) || 0.025)}
        />
      </div>

      <div className="tb-sep" />

      {/* Orientation */}
      <div className="tb-group">
        <span className="tb-label">Orient</span>
        <button
          className={`orient-btn ${path.orient === 'path' ? 'active' : ''}`}
          onClick={() => patchPath('orient', 'path')}
        >
          PATH-FOLLOWING
        </button>
        <button
          className={`orient-btn ${path.orient === 'target' ? 'active target-mode' : ''}`}
          onClick={() => patchPath('orient', 'target')}
        >
          FIXED TARGET
        </button>
        {path.orient === 'target' && (
          <>
            <span className="tb-label" style={{ color: 'var(--target)' }}>@</span>
            {(['x', 'y', 'z'] as const).map((axis) => (
              <input
                key={axis}
                type="number"
                className="narrow"
                title={`Target ${axis.toUpperCase()}`}
                value={path.target[axis]}
                step={1}
                onChange={(e) => patchPath('target', { ...path.target, [axis]: parseFloat(e.target.value) || 0 })}
              />
            ))}
          </>
        )}
      </div>

      <div className="tb-sep" />

      {/* Roll */}
      <div className="tb-group">
        <span className="tb-label">Roll</span>
        <input
          type="number"
          className="wide"
          value={path.roll}
          step={45}
          title="Degrees of roll per full path loop. 360 = one barrel roll."
          onChange={(e) => patchPath('roll', parseFloat(e.target.value) || 0)}
        />
        <span className="tb-label">°/loop</span>
      </div>

      <div className="tb-sep" />

      {/* Standoff */}
      <div className="tb-group">
        <span className="tb-label">Standoff</span>
        <input
          type="number"
          className="narrow"
          value={path.standoff}
          step={0.5}
          min={0}
          title="Perpendicular distance from wire (world units). Combine with Roll for helix."
          onChange={(e) => patchPath('standoff', Math.max(0, parseFloat(e.target.value) || 0))}
        />
        <span className="tb-label">u</span>
      </div>

      <div className="tb-sep" />

      {/* Closed loop */}
      <div className="tb-group">
        <label style={{ display: 'flex', alignItems: 'center', gap: 5, cursor: 'pointer' }}>
          <input
            type="checkbox"
            checked={path.closed}
            onChange={(e) => patchPath('closed', e.target.checked)}
          />
          <span className="tb-label">Closed</span>
        </label>
      </div>

      <div className="tb-sep" />

      {/* Playback */}
      <div className="tb-group">
        <button className={playing ? 'playing' : 'primary'} onClick={togglePlay}>
          {playing ? '■ Stop' : '▶ Play'}
        </button>
        <button className="icon" title="Reset animation" onClick={() => { setPlaying(false); setAnimT(0) }}>↺</button>
      </div>
    </div>
  )
}

// ── Sidebar (waypoint list) ─────────────────────────────────────────────
function Sidebar() {
  const { path, selected, setWp, addWp, delWp, dupWp, setSelected } = useStore()
  const { wps } = path

  const handleCoord = useCallback((i: number, axis: 'x' | 'y' | 'z', val: string) => {
    const n = parseFloat(val)
    if (isNaN(n)) return
    setWp(i, { ...wps[i], [axis]: n })
  }, [wps, setWp])

  const handleAdd = useCallback(() => {
    const last = wps[wps.length - 1] ?? { x: 20, y: 0, z: 0 }
    addWp({ ...last }, selected >= 0 ? selected : undefined)
  }, [wps, selected, addWp])

  return (
    <aside className="sidebar">
      <div className="sidebar-header">
        Waypoints
        <span className="count">{wps.length}</span>
      </div>

      <div className="wp-list">
        {wps.map((wp, i) => (
          <div
            key={i}
            className={`wp-row ${i === selected ? 'selected' : ''}`}
            onClick={() => setSelected(i)}
          >
            <span className="wp-idx">{i}</span>
            <div className="wp-coords">
              {(['x', 'y', 'z'] as const).map((axis) => (
                <input
                  key={axis}
                  type="number"
                  value={parseFloat(wp[axis].toFixed(2))}
                  step={1}
                  title={axis.toUpperCase()}
                  onClick={(e) => e.stopPropagation()}
                  onChange={(e) => handleCoord(i, axis, e.target.value)}
                />
              ))}
            </div>
            <button
              className="wp-del"
              title="Delete waypoint"
              onClick={(e) => { e.stopPropagation(); delWp(i) }}
            >
              ×
            </button>
          </div>
        ))}
      </div>

      <div className="sidebar-actions">
        <div className="row">
          <button onClick={handleAdd}>+ Add</button>
          <button className="danger" onClick={() => { if (selected >= 0) delWp(selected) }}>✕ Del</button>
          <button onClick={() => { if (selected >= 0) dupWp(selected) }}>⊕ Dup</button>
        </div>
      </div>

      <div className="sidebar-hint">
        <span>Click empty</span> → add wp<br />
        <span>Drag wp</span> → move<br />
        <span>Right drag</span> → pan<br />
        <span>Scroll</span> → zoom<br />
        <span>Del key</span> → remove sel
      </div>
    </aside>
  )
}

// ── Status bar ──────────────────────────────────────────────────────────
function StatusBar() {
  const { status } = useStore()
  return <div className="status-bar">{status}</div>
}

// ── App ─────────────────────────────────────────────────────────────────
export function App() {
  useAnimLoop()

  return (
    <div className="app">
      <Toolbar />
      <div className="workspace">
        <div className="view-cell">
          <div className="view-label">TOP · XZ</div>
          <TopView />
        </div>
        <div className="view-cell">
          <div className="view-label">SIDE · XY</div>
          <SideView />
        </div>
        <div className="view-cell">
          <div className="view-label">3D · ORBIT</div>
          <PerspView />
        </div>
        <div className="view-cell">
          <div className="view-label">I / O</div>
          <IOPanel />
        </div>
        <Sidebar />
      </div>
      <StatusBar />
    </div>
  )
}
