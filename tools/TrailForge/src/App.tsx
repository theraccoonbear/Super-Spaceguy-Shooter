// Root layout + animation loop + toolbar + waypoint sidebar.
// Layout: Top XZ | Side XY | Front YZ | 3D Persp, with sidebar (waypoints + I/O).

import { useEffect, useRef, useCallback, useState, useMemo } from 'react'
import { useStore, type PaneName } from './store'
import { TopView }   from './views/TopView'
import { SideView }  from './views/SideView'
import { FrontView } from './views/FrontView'
import { PerspView } from './views/PerspView'
import { IOPanel }   from './io/IOPanel'
import { RoutesPanel } from './io/RoutesPanel'
import { GenerateDialog }  from './ui/GenerateDialog'
import { HelpDialog }     from './ui/HelpDialog'
import { NodeEditDialog } from './ui/NodeEditDialog'
import { BehaviorsPanel } from './ui/BehaviorsPanel'
import { linked as orthoLinked, toggleLinked } from './views/orthoCamera'
import { uiPrefs, saveUIPrefs } from './prefs'
import { tangentAt, makeFrame, transportFrame, arcAdvanceAt, applyHolonomyCorrection, measureHolonomy, buildFrameTable, makeArcTable } from './math/spline'
import { setFrameTable } from './math/frameCache'
import { evalScalarSegments } from './math/segmentTrack'
import type { Vec3 } from './math/vec3'
import { SHORTCUTS, matchesShortcut, shortcutKeys } from './shortcuts'
import splashUrl from './assets/trail-forge-splash.png'

// ── Animation loop ──────────────────────────────────────────────────────
function useAnimLoop() {
  const { playing, path, animT, setPlayState, mutedTracks } = useStore()

  const playingRef      = useRef(playing)
  const pathRef         = useRef(path)
  const animTRef        = useRef(animT)
  const setPlayStateRef = useRef(setPlayState)
  const mutedTracksRef  = useRef(mutedTracks)
  playingRef.current      = playing
  pathRef.current         = path
  animTRef.current        = animT
  setPlayStateRef.current = setPlayState
  mutedTracksRef.current  = mutedTracks

  // Segment tracks' t is arc-length fraction; the RAF loop's animFrac below is
  // parameter-space — must convert via arcTable or speed timing drifts against
  // the visual position. Recomputed only when path changes, not per-frame.
  const arcTable    = useMemo(() => makeArcTable(path.wps, path.closed), [path])
  const arcTableRef = useRef(arcTable)
  arcTableRef.current = arcTable

  // Frame accumulation state — lives in refs so RAF closure stays stale-free
  const frameRRef   = useRef<Vec3>({ x: 1, y: 0, z: 0 })
  const frameURef   = useRef<Vec3>({ x: 0, y: 0, z: 1 })
  const prevTanRef  = useRef<Vec3 | null>(null)
  // Holonomy correction: for closed paths, the parallel-transport frame accumulates
  // a geometric phase (holonomy) each loop. We pre-compute it and distribute a
  // counter-twist evenly so orientation is identical at the start of every pass.
  const holonomyRef = useRef<number>(0) // radians, updated when path changes

  // Recompute holonomy + scrub frame table whenever path changes.
  // buildFrameTable uses 512 steps (matching holonomy nSteps for identical cumulative
  // correction), so scrub-mode and playing-mode frames agree at any arc fraction.
  useEffect(() => {
    if (path.wps.length < 2) {
      holonomyRef.current = 0
      setFrameTable(null)
      return
    }
    if (!path.closed) {
      // Open path: no holonomy. Still build a transport table so scrub
      // frame is consistent with playing rather than world-up makeFrame.
      holonomyRef.current = 0
      setFrameTable(buildFrameTable(path.wps, false, 0, 512))
      return
    }
    // Closed path: measure holonomy first (high-res pass), then build table.
    const nSegs  = path.wps.length
    const nSteps = 1200
    const tan0   = tangentAt(path.wps, 0, true)
    const frame0 = makeFrame(tan0)
    let R = { ...frame0.R }
    let U = { ...frame0.U }
    let prevTan = tan0
    for (let i = 1; i <= nSteps; i++) {
      const newTan = tangentAt(path.wps, (i / nSteps) * nSegs, true)
      const res    = transportFrame(prevTan, newTan, R, U)
      R = res.R; U = res.U
      prevTan = newTan
    }
    const h = measureHolonomy(R, frame0.R, frame0.U)
    holonomyRef.current = h
    setFrameTable(buildFrameTable(path.wps, true, h, 512))
  }, [path])

  useEffect(() => {
    let lastTs = 0, raf = 0
    const tick = (ts: number) => {
      raf = requestAnimationFrame(tick)
      if (!playingRef.current) { lastTs = 0; prevTanRef.current = null; return }
      const p     = pathRef.current
      const nSegs = p.closed ? p.wps.length : p.wps.length - 1
      if (nSegs < 1) return

      if (lastTs === 0) {
        // First tick after play start: initialize frame via Gram-Schmidt
        lastTs = ts
        const t0  = animTRef.current
        const tan = tangentAt(p.wps, t0, p.closed)
        const { R, U } = makeFrame(tan)
        frameRRef.current  = R
        frameURef.current  = U
        prevTanRef.current = tan
        setPlayStateRef.current(t0, R, U)
        return
      }

      const dt   = Math.min(ts - lastTs, 50)
      lastTs     = ts
      // Arc-length-correct advance: dT is scaled by local derivative magnitude so
      // world-space speed stays constant regardless of inter-node spacing.
      const framesElapsed = dt / 16.667
      // Apply speed track: scale base speed by segment value at current arc-length fraction
      const muted      = mutedTracksRef.current
      const speedSegs  = muted['speed'] ? [] : (p.segmentTracks['speed'] ?? [])
      const speedSeam  = muted['speed'] ? null : (p.segmentLoopSeams['speed'] ?? null)
      const paramFrac  = nSegs > 0 ? Math.max(0, Math.min(1, (animTRef.current % nSegs) / nSegs)) : 0
      const arcFrac    = arcTableRef.current.paramToArc(paramFrac)
      const speedScale = speedSegs.length > 0 ? evalScalarSegments(speedSegs, arcFrac, speedSeam) : 1
      const dT   = arcAdvanceAt(p.wps, animTRef.current, p.closed, p.speed * speedScale * framesElapsed)
      let newT   = animTRef.current + dT
      if (newT >= nSegs) newT -= nSegs

      // Parallel transport: rotate frame from previous tangent to current tangent
      const newTan = tangentAt(p.wps, newT, p.closed)
      const prevTan = prevTanRef.current
      if (prevTan) {
        const { R, U } = transportFrame(prevTan, newTan, frameRRef.current, frameURef.current)
        frameRRef.current = R
        frameURef.current = U
      }
      prevTanRef.current = newTan

      // Holonomy correction: distribute counter-twist proportional to arc fraction
      // advanced this tick so the frame closes exactly after one full loop.
      // Rotation is in the (R, U) plane — the plane perpendicular to the tangent.
      const holonomy = holonomyRef.current
      if (p.closed && Math.abs(holonomy) > 1e-6) {
        const corrected = applyHolonomyCorrection(
          frameRRef.current, frameURef.current, holonomy, dT / nSegs,
        )
        frameRRef.current = corrected.R
        frameURef.current = corrected.U
      }

      setPlayStateRef.current(newT, frameRRef.current, frameURef.current)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [])
}

// ── NumInput ────────────────────────────────────────────────────────────
// Defers store updates until blur/Enter so partial values (e.g. "0.") don't
// get clobbered mid-keystroke by React resetting the controlled value.
interface NumInputProps {
  value: number
  step?: number
  min?: number
  max?: number
  className?: string
  title?: string
  onClick?: (e: React.MouseEvent<HTMLInputElement>) => void
  commit: (n: number) => void
}
function NumInput({ value, step, min, max, className, title, onClick, commit }: NumInputProps) {
  const [text, setText] = useState<string | null>(null) // null = not focused
  const display = text !== null ? text : String(value)

  // If value changes externally (undo/redo) while not focused, nothing to do —
  // display derives from `value` when text===null. If focused, leave the user's
  // in-progress text alone.

  function tryCommit(raw: string) {
    const n = parseFloat(raw)
    if (isNaN(n)) { setText(String(value)); return } // revert invalid
    const clamped = min !== undefined ? Math.max(min, n) : n
    commit(clamped)
    setText(null)
  }

  return (
    <input
      type="number"
      className={className}
      title={title}
      step={step}
      min={min}
      max={max}
      value={display}
      onChange={e => setText(e.target.value)}
      onFocus={e => { setText(String(value)); e.target.select() }}
      onBlur={e => tryCommit(e.target.value)}
      onClick={onClick}
      onKeyDown={e => { if (e.key === 'Enter') e.currentTarget.blur() }}
    />
  )
}

// ── Toolbar ─────────────────────────────────────────────────────────────
function Toolbar({ isLinked, onToggleLinked, onHelp }: { isLinked: boolean; onToggleLinked: () => void; onHelp: () => void }) {
  const { path, playing, patchPath, setPlaying, setAnimT, showOverlays, setShowOverlays, debugLog, setDebugLog,
          behaviorsOpen, setBehaviorsOpen, reverseWps } = useStore()

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
        <NumInput value={path.speed} step={0.001} min={0.0001} max={2}
          commit={(n) => patchPath('speed', n)} />
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
              <NumInput key={a} className="narrow" title={`Target ${a.toUpperCase()}`}
                value={path.target[a]} step={1}
                commit={(n) => patchPath('target', { ...path.target, [a]: n })} />
            ))}
          </>
        )}
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <label style={{ display:'flex', alignItems:'center', gap:5, cursor:'pointer' }}>
          <input type="checkbox" checked={path.closed}
            onChange={(e) => patchPath('closed', e.target.checked)} />
          <span className="tb-label">Closed</span>
        </label>
        <button
          title="Reverse traversal direction — mirrors all keyframe/trigger positions"
          onClick={reverseWps}
        >⇄ Rev</button>
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
      <div className="tb-sep" />

      <div className="tb-group">
        <button
          className={showOverlays ? 'link-btn linked' : 'link-btn'}
          title="Toggle gameplay context overlays — player ship, camera, frustum, scale planes"
          onClick={() => setShowOverlays(!showOverlays)}
        >
          {showOverlays ? '⊞ GAME CTX' : '⊟ GAME CTX'}
        </button>
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <button
          className={debugLog ? 'link-btn linked' : 'link-btn'}
          title="Toggle per-frame console debug log — logs position, forward, R, U vectors each animation tick"
          onClick={() => setDebugLog(!debugLog)}
        >
          {debugLog ? '⊞ DBG LOG' : '⊟ DBG LOG'}
        </button>
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <button
          className={behaviorsOpen ? 'link-btn linked' : 'link-btn'}
          title={`Toggle behaviors panel (${shortcutKeys('`')}) — track keyframes and trigger events`}
          onClick={() => setBehaviorsOpen(!behaviorsOpen)}
        >
          {behaviorsOpen ? '⊞ BEHAVIORS' : '⊟ BEHAVIORS'}
        </button>
      </div>
      <div className="tb-sep" />

      <div className="tb-group">
        <button onClick={onHelp} title="Help — keyboard shortcuts and controls (?)">?</button>
      </div>
    </div>
  )
}

// ── Sidebar ─────────────────────────────────────────────────────────────
function Sidebar({ onResizeStart }: { onResizeStart: (e: React.MouseEvent) => void }) {
  const { path, selected, setWp, addWp, delWp, dupWp, setSelected } = useStore()
  const [tab, setTabRaw] = useState<'wp' | 'io' | 'routes'>(uiPrefs.sidebarTab)
  const setTab = (t: 'wp' | 'io' | 'routes') => { saveUIPrefs({ sidebarTab: t }); setTabRaw(t) }
  const [showGenDialog, setShowGenDialog] = useState(false)
  const { wps } = path

  const handleAdd = useCallback(() => {
    const last = wps[wps.length - 1] ?? { x: 20, y: 0, z: 0 }
    addWp({ ...last }, selected >= 0 ? selected : undefined)
  }, [wps, selected, addWp])

  return (
    <aside className="sidebar">
      {/* Resize handle — left edge drag makes sidebar wider/narrower */}
      <div className="sidebar-resize-handle"
        onMouseDown={(e) => { e.preventDefault(); onResizeStart(e) }} />
      {/* Tab bar */}
      <div className="sidebar-tabs">
        <button className={`sidebar-tab ${tab === 'wp' ? 'active' : ''}`}
          onClick={() => setTab('wp')}>
          WPs <span className="count">{wps.length}</span>
        </button>
        <button className={`sidebar-tab ${tab === 'routes' ? 'active' : ''}`}
          onClick={() => setTab('routes')}>
          Routes
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
                    <NumInput key={axis} step={1} title={axis.toUpperCase()}
                      value={wp[axis]}
                      commit={(n) => setWp(i, { ...wps[i], [axis]: n })}
                      onClick={(e) => e.stopPropagation()} />
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
              <button title="Generate waypoints from a geometric shape"
                onClick={() => setShowGenDialog(true)}>⬡ Gen</button>
            </div>
          </div>
        </>
      )}

      {tab === 'routes' && <RoutesPanel />}
      {tab === 'io' && <IOPanel />}
      {showGenDialog && <GenerateDialog onClose={() => setShowGenDialog(false)} />}

      {/* Hotkey reference — always visible regardless of active tab */}
      <div className="sidebar-hint">
        <span>Click node</span> → select<br />
        <span>Drag wp</span> → move in view plane<br />
        <span>Alt drag</span> → rotate entire path<br />
        <span>Ctrl drag</span> → translate entire path<br />
        <span>Right drag</span> → pan · <span>Scroll</span> → zoom<br />
        <span>Right-click wp</span> → context menu<br />
        <span>Right-click empty</span> → add here<br />
        <span>Shift+click</span> → add at point<br />
        <span>Del key</span> → remove selected<br />
        <span>←/→ (paused)</span> → step frame<br />
        <span>Ctrl+Z / Ctrl+⇧Z</span> → undo / redo<br />
        <span>Corner wedge / F</span> → maximize / restore
      </div>
    </aside>
  )
}

// ── Status bar ──────────────────────────────────────────────────────────
function StatusBar() {
  const { status } = useStore()
  return <div className="status-bar">{status}</div>
}

// ── Step one frame forward or back while paused ─────────────────────────
function stepFrame(dir: 1 | -1) {
  const { path, animT, playing, setPlayState } = useStore.getState()
  if (playing) return
  const nSegs = path.closed ? path.wps.length : path.wps.length - 1
  if (nSegs < 1) return
  const STEP = 1 / 20   // 1/20 of a segment per arrow key
  let newT = animT + dir * STEP
  if (path.closed) {
    while (newT < 0) newT += nSegs
    while (newT >= nSegs) newT -= nSegs
  } else {
    newT = Math.max(0, Math.min(nSegs, newT))
  }
  const tan = tangentAt(path.wps, newT, path.closed)
  const { R, U } = makeFrame(tan)
  setPlayState(newT, R, U)
}

// ── App ─────────────────────────────────────────────────────────────────
export function App() {
  useAnimLoop()

  const [isLinked,     setIsLinked]     = useState(orthoLinked)
  const [showHelp,     setShowHelp]     = useState(false)
  const [sidebarWidth, setSidebarWidth] = useState(uiPrefs.sidebarWidth)
  // Ref so the drag mouseUp handler can read the latest width without stale closure.
  const sidebarWidthRef = useRef(uiPrefs.sidebarWidth)

  // ── Splash on load ───────────────────────────────────────────────────
  const [splash, setSplash] = useState<'visible' | 'fading' | 'gone'>('visible')
  const dismissSplash = useCallback(() => {
    setSplash(s => s === 'visible' ? 'fading' : s)
  }, [])
  useEffect(() => {
    const t = setTimeout(dismissSplash, 2000)
    const onKey = () => dismissSplash()
    window.addEventListener('keydown', onKey, { once: true })
    return () => { clearTimeout(t); window.removeEventListener('keydown', onKey) }
  }, [dismissSplash])
  const { maximizedPane, setMaximizedPane,
          behaviorsOpen, behaviorsHeight,
          setBehaviorsHeight } = useStore()
  const hoveredPane    = useRef<PaneName | null>(null)
  const bDragStart     = useRef<{ y: number; h: number } | null>(null)
  const sDragStart     = useRef<{ x: number; w: number } | null>(null)

  // Drag-to-resize: behaviors panel (vertical) + sidebar (horizontal)
  useEffect(() => {
    const onMove = (e: MouseEvent) => {
      if (bDragStart.current) {
        const delta = bDragStart.current.y - e.clientY   // drag UP = taller panel
        const newH  = Math.max(80, Math.min(600, bDragStart.current.h + delta))
        setBehaviorsHeight(newH)
      }
      if (sDragStart.current) {
        const delta = sDragStart.current.x - e.clientX   // drag LEFT = wider sidebar
        const newW  = Math.max(160, Math.min(500, sDragStart.current.w + delta))
        setSidebarWidth(newW)
        sidebarWidthRef.current = newW
      }
    }
    const onUp = () => {
      if (sDragStart.current) saveUIPrefs({ sidebarWidth: sidebarWidthRef.current })
      bDragStart.current = null
      sDragStart.current = null
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup',   onUp)
    return () => {
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup',   onUp)
    }
  }, [setBehaviorsHeight])

  const handleToggleLinked = useCallback(() => {
    setIsLinked(toggleLinked())
  }, [])

  // Global keyboard handler — fires regardless of which element has focus.
  // Registry shortcuts (undo/redo, Space, `, Ctrl+A, Shift+D, Home, End, etc.)
  // are dispatched from SHORTCUTS.  Arrow-step and ? live here (local state).
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      const inInput = e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement
      // Dispatch registry shortcuts that have handlers
      for (const s of SHORTCUTS) {
        if (!s.handler || !s.match) continue
        if (!s.fireInInput && inInput) continue
        if (matchesShortcut(e, s.match)) {
          e.preventDefault()
          s.handler()
          return
        }
      }
      // Skip remaining shortcuts when typing in an input
      if (inInput) return
      // Step frame (arrow keys, only when no modifier)
      if (!e.ctrlKey && !e.metaKey && !e.altKey) {
        if (e.key === 'ArrowRight') { e.preventDefault(); stepFrame(1) }
        if (e.key === 'ArrowLeft')  { e.preventDefault(); stepFrame(-1) }
        if (e.key === '?') setShowHelp(h => !h)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  // setShowHelp is stable (useState setter); SHORTCUTS/matchesShortcut are module-level constants
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const toggleMax = useCallback((pane: PaneName) => {
    setMaximizedPane(maximizedPane === pane ? null : pane)
  }, [maximizedPane, setMaximizedPane])

  const onRootKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
    if (e.key === 'l' || e.key === 'L') handleToggleLinked()
    if (e.key === 'Escape' && maximizedPane !== null) setMaximizedPane(null)

    // F — frame selection in hovered ortho pane (industry standard: zoom to fit)
    // Shift+F — maximize / restore hovered pane (old F behavior, now on Shift)
    const hp = hoveredPane.current
    if (e.key.toLowerCase() === 'f' && hp !== null) {
      if (e.shiftKey) {
        toggleMax(hp)
      } else if (hp !== 'persp') {
        const { path, selected, multiSel } = useStore.getState()
        // Frame selection when a selection exists; otherwise frame all waypoints
        const wps =
          multiSel.length > 0 ? multiSel.map(i => path.wps[i]).filter(Boolean)
          : selected >= 0     ? [path.wps[selected]]
          : path.wps
        window.dispatchEvent(new CustomEvent('tf-frame',
          { detail: { pane: hp, wps } }))
      }
    }

    // Period — frame all waypoints in every ortho view
    if (e.key === '.' && hp !== null) {
      const { path } = useStore.getState()
      for (const p of ['top', 'side', 'front'] as const) {
        window.dispatchEvent(new CustomEvent('tf-frame',
          { detail: { pane: p, wps: path.wps } }))
      }
    }
    // ` (backtick) and Space handled by registry window listener
  }, [handleToggleLinked, maximizedPane, setMaximizedPane, toggleMax])

  // Resolve CSS class for each view-cell
  const cellClass = (pane: PaneName) =>
    maximizedPane === pane ? 'view-cell maximized'
    : maximizedPane !== null ? 'view-cell hidden'
    : 'view-cell'

  return (
    <div className="app" onKeyDown={onRootKeyDown} tabIndex={-1} style={{ outline: 'none' }}>
      <Toolbar isLinked={isLinked} onToggleLinked={handleToggleLinked} onHelp={() => setShowHelp(true)} />
      <div className="workspace" style={{ gridTemplateColumns: `1fr 1fr ${sidebarWidth}px` }}>
        <div className={cellClass('top')} onMouseEnter={() => { hoveredPane.current = 'top' }} onMouseLeave={() => { hoveredPane.current = null }}>
          <div className="view-label">TOP · XZ</div>
          <div className={`expand-wedge br${maximizedPane === 'top' ? ' active' : ''}`}
            title={maximizedPane === 'top' ? 'Restore 4-pane view (Esc / F)' : 'Maximize TOP · XZ (F)'}
            onClick={() => toggleMax('top')} />
          <TopView />
        </div>
        <div className={cellClass('side')} onMouseEnter={() => { hoveredPane.current = 'side' }} onMouseLeave={() => { hoveredPane.current = null }}>
          <div className="view-label">SIDE · XY</div>
          <div className={`expand-wedge bl${maximizedPane === 'side' ? ' active' : ''}`}
            title={maximizedPane === 'side' ? 'Restore 4-pane view (Esc / F)' : 'Maximize SIDE · XY (F)'}
            onClick={() => toggleMax('side')} />
          <SideView />
        </div>
        <div className={cellClass('front')} onMouseEnter={() => { hoveredPane.current = 'front' }} onMouseLeave={() => { hoveredPane.current = null }}>
          <div className="view-label">FRONT · YZ</div>
          <div className={`expand-wedge tr${maximizedPane === 'front' ? ' active' : ''}`}
            title={maximizedPane === 'front' ? 'Restore 4-pane view (Esc / F)' : 'Maximize FRONT · YZ (F)'}
            onClick={() => toggleMax('front')} />
          <FrontView />
        </div>
        <div className={cellClass('persp')} onMouseEnter={() => { hoveredPane.current = 'persp' }} onMouseLeave={() => { hoveredPane.current = null }}>
          <div className="view-label">3D · ORBIT</div>
          <div className={`expand-wedge tl${maximizedPane === 'persp' ? ' active' : ''}`}
            title={maximizedPane === 'persp' ? 'Restore 4-pane view (Esc / F)' : 'Maximize 3D · ORBIT (F)'}
            onClick={() => toggleMax('persp')} />
          <PerspView />
        </div>
        <Sidebar onResizeStart={(e) => {
          sDragStart.current = { x: e.clientX, w: sidebarWidth }
        }} />
      </div>

      {/* Behaviors panel — resizable strip below the four views */}
      {behaviorsOpen && (
        <div className="behaviors-panel" style={{ height: behaviorsHeight }}>
          <div className="bpanel-handle"
            onMouseDown={(e) => {
              e.preventDefault()
              bDragStart.current = { y: e.clientY, h: behaviorsHeight }
            }} />
          <BehaviorsPanel />
        </div>
      )}

      <StatusBar />
      {showHelp && <HelpDialog onClose={() => setShowHelp(false)} />}
      <NodeEditDialog />

      {/* ── Load splash — blurred workspace visible behind the overlay ── */}
      {splash !== 'gone' && (
        <div
          className="splash-overlay"
          style={{
            opacity:    splash === 'visible' ? 1 : 0,
            transition: splash === 'fading'  ? 'opacity 600ms ease' : 'none',
          }}
          onClick={dismissSplash}
          onTransitionEnd={() => { if (splash === 'fading') setSplash('gone') }}
        >
          <img src={splashUrl} alt="Trailforge" />
        </div>
      )}
    </div>
  )
}
