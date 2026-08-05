// Root layout + animation loop + toolbar + waypoint sidebar.
// Layout: Top XZ | Side XY | Front YZ | 3D Persp, with sidebar (waypoints + I/O).

import { useEffect, useRef, useCallback, useState } from 'react'
import { useStore } from './store'
import { tangentAt } from './math/spline'
import { v3 } from './math/vec3'
import { TopView }   from './views/TopView'
import { SideView }  from './views/SideView'
import { FrontView } from './views/FrontView'
import { PerspView } from './views/PerspView'
import { IOPanel }   from './io/IOPanel'
import { linked as orthoLinked, toggleLinked } from './views/orthoCamera'

// ── Animation loop ──────────────────────────────────────────────────────
function useAnimLoop() {
  const { playing, path, animT, setAnimT } = useStore()

  const playingRef    = useRef(playing)
  const pathRef       = useRef(path)
  const animTRef      = useRef(animT)
  const setAnimTRef   = useRef(setAnimT)
  playingRef.current  = playing
  pathRef.current     = path
  animTRef.current    = animT
  setAnimTRef.current = setAnimT

  useEffect(() => {
    let lastTs = 0, raf = 0
    const tick = (ts: number) => {
      raf = requestAnimationFrame(tick)
      if (!playingRef.current) { lastTs = 0; return }
      if (lastTs === 0) { lastTs = ts; return }
      const dt    = Math.min(ts - lastTs, 50)
      lastTs      = ts
      const p     = pathRef.current
      const nSegs = p.wps.length - 1
      if (nSegs < 1) return
      const tan   = tangentAt(p.wps, animTRef.current, p.closed)
      const dT    = (p.speed / (v3.len(tan) || 1)) * (dt / 16.667)
      let newT    = animTRef.current + dT
      if (newT >= nSegs) newT -= nSegs
      setAnimTRef.current(newT)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [])
}

// ── Toolbar ─────────────────────────────────────────────────────────────
function Toolbar({ isLinked, onToggleLinked }: { isLinked: boolean; onToggleLinked: () => void }) {
  const { path, playing, patchPath, setPlaying, setAnimT } = useStore()

  return (
    <div className="toolbar">
      <div className="tb-group">
        <span className="tb-label">Name</span>
        <input type="text" value={path.name} spellCheck={false}
          onChange={(e) => patchPath('name', e.target.value)} />
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <span className="tb-label">Speed</span>
        <input type="number" className="narrow" value={path.speed} step={0.005} min={0.001} max={2}
          onChange={(e) => patchPath('speed', parseFloat(e.target.value) || 0.025)} />
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <span className="tb-label">Orient</span>
        <button className={`orient-btn ${path.orient === 'path' ? 'active' : ''}`}
          onClick={() => patchPath('orient', 'path')}>PATH-FOLLOWING</button>
        <button className={`orient-btn ${path.orient === 'target' ? 'active target-mode' : ''}`}
          onClick={() => patchPath('orient', 'target')}>FIXED TARGET</button>
        {path.orient === 'target' && (
          <>
            <span className="tb-label" style={{ color: 'var(--target)' }}>@</span>
            {(['x','y','z'] as const).map((a) => (
              <input key={a} type="number" className="narrow" title={`Target ${a.toUpperCase()}`}
                value={path.target[a]} step={1}
                onChange={(e) => patchPath('target', { ...path.target, [a]: parseFloat(e.target.value) || 0 })} />
            ))}
          </>
        )}
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <span className="tb-label">Roll</span>
        <input type="number" className="wide" value={path.roll} step={45}
          title="Degrees of roll per full path loop (360 = barrel roll)"
          onChange={(e) => patchPath('roll', parseFloat(e.target.value) || 0)} />
        <span className="tb-label">°/loop</span>
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <span className="tb-label">Standoff</span>
        <input type="number" className="narrow" value={path.standoff} step={0.5} min={0}
          title="Perpendicular offset from wire (world units). With Roll: helix."
          onChange={(e) => patchPath('standoff', Math.max(0, parseFloat(e.target.value) || 0))} />
        <span className="tb-label">u</span>
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <label style={{ display:'flex', alignItems:'center', gap:5, cursor:'pointer' }}>
          <input type="checkbox" checked={path.closed}
            onChange={(e) => patchPath('closed', e.target.checked)} />
          <span className="tb-label">Closed</span>
        </label>
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <button className={playing ? 'playing' : 'primary'}
          onClick={() => { if (!playing) setAnimT(0); setPlaying(!playing) }}>
          {playing ? '■ Stop' : '▶ Play'}
        </button>
        <button className="icon" title="Reset" onClick={() => { setPlaying(false); setAnimT(0) }}>↺</button>
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <button
          className={isLinked ? 'link-btn linked' : 'link-btn'}
          title="Link ortho pan/zoom (L) — all three views stay in sync"
          onClick={onToggleLinked}
        >
          {isLinked ? '⊞ LINKED' : '⊟ FREE'}
        </button>
      </div>
    </div>
  )
}

// ── Sidebar ─────────────────────────────────────────────────────────────
function Sidebar() {
  const { path, selected, setWp, addWp, delWp, dupWp, setSelected } = useStore()
  const [tab, setTab] = useState<'wp' | 'io'>('wp')
  const { wps } = path

  const handleCoord = useCallback((i: number, axis: 'x'|'y'|'z', val: string) => {
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
      {/* Tab bar */}
      <div className="sidebar-tabs">
        <button className={`sidebar-tab ${tab === 'wp' ? 'active' : ''}`}
          onClick={() => setTab('wp')}>
          Waypoints <span className="count">{wps.length}</span>
        </button>
        <button className={`sidebar-tab ${tab === 'io' ? 'active' : ''}`}
          onClick={() => setTab('io')}>
          I / O
        </button>
      </div>

      {tab === 'wp' && (
        <>
          <div className="wp-list">
            {wps.map((wp, i) => (
              <div key={i} className={`wp-row ${i === selected ? 'selected' : ''}`}
                onClick={() => setSelected(i)}>
                <span className="wp-idx">{i}</span>
                <div className="wp-coords">
                  {(['x','y','z'] as const).map((axis) => (
                    <input key={axis} type="number"
                      value={parseFloat(wp[axis].toFixed(2))} step={1} title={axis.toUpperCase()}
                      onClick={(e) => e.stopPropagation()}
                      onChange={(e) => handleCoord(i, axis, e.target.value)} />
                  ))}
                </div>
                <button className="wp-del" title="Delete"
                  onClick={(e) => { e.stopPropagation(); delWp(i) }}>×</button>
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
            <span>Drag wp</span> → move in view plane<br />
            <span>3D gizmo</span> → drag X/Y/Z arrows<br />
            <span>Right drag</span> → pan · <span>Scroll</span> → zoom<br />
            <span>Del key</span> → remove selected
          </div>
        </>
      )}

      {tab === 'io' && <IOPanel />}
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

  const [isLinked, setIsLinked] = useState(orthoLinked)

  const handleToggleLinked = useCallback(() => {
    setIsLinked(toggleLinked())
  }, [])

  const onRootKeyDown = useCallback((e: React.KeyboardEvent) => {
    // Don't intercept L when an input is focused
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
    if (e.key === 'l' || e.key === 'L') handleToggleLinked()
  }, [handleToggleLinked])

  return (
    <div className="app" onKeyDown={onRootKeyDown} tabIndex={-1} style={{ outline: 'none' }}>
      <Toolbar isLinked={isLinked} onToggleLinked={handleToggleLinked} />
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
          <div className="view-label">FRONT · YZ</div>
          <FrontView />
        </div>
        <div className="view-cell">
          <div className="view-label">3D · ORBIT</div>
          <PerspView />
        </div>
        <Sidebar />
      </div>
      <StatusBar />
    </div>
  )
}
