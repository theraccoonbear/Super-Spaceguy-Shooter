// Generate waypoints from a geometric shape.
// Replaces the current waypoint list on confirm.

import { useState, useCallback, type CSSProperties } from 'react'
import { useStore } from '../store'
import type { Waypoint } from '../math/vec3'

type Shape = 'blank' | 'circle' | 'ellipse' | 'figure8' | 'helix' | 'arc'
type Plane = 'XZ' | 'XY' | 'YZ'
type HelixAxis = 'X' | 'Y' | 'Z'

// ── Persist generator settings across sessions ──────────────────────────────
const STORAGE_KEY = 'trailforge:gen-settings'

interface GenSettings {
  shape: Shape; n: number; r: number; ra: number; rb: number
  helixLen: number; helixTurns: number; arcDeg: number
  cx: number; cy: number; cz: number; plane: Plane; helixAxis: HelixAxis; closed: boolean
}

const DEFAULTS: GenSettings = {
  shape: 'circle', n: 16, r: 12, ra: 16, rb: 8,
  helixLen: 20, helixTurns: 2, arcDeg: 180,
  cx: 10, cy: 0, cz: 0, plane: 'XZ', helixAxis: 'X', closed: true,
}

function loadSettings(): GenSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return DEFAULTS
    return { ...DEFAULTS, ...JSON.parse(raw) }
  } catch { return DEFAULTS }
}

function saveSettings(s: GenSettings): void {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(s)) } catch { /* ignore */ }
}

// Deferred-commit numeric input — only commits on blur or Enter,
// so typing "12" doesn't get clobbered after typing "1".
function DeferredNumInput({ value, setter, step = 1, min, style }: {
  value:  number
  setter: (v: number) => void
  step?:  number
  min?:   number
  style?: CSSProperties
}) {
  const [text, setText] = useState<string | null>(null)
  const display = text !== null ? text : String(value)

  function commit(raw: string) {
    const n = parseFloat(raw)
    if (!isNaN(n)) setter(min !== undefined ? Math.max(min, n) : n)
    setText(null)
  }

  return (
    <input type="number" value={display} step={step} min={min} style={style}
      onChange={e => setText(e.target.value)}
      onFocus={e => { setText(String(value)); e.target.select() }}
      onBlur={e => commit(e.target.value)}
      onKeyDown={e => { if (e.key === 'Enter') e.currentTarget.blur() }} />
  )
}

const TAU = 2 * Math.PI

function wp(x: number, y: number, z: number): Waypoint {
  return { x, y, z, pathRoll: 0, craftRoll: 0 }
}

function genCircle(n: number, r: number, cx: number, cy: number, cz: number, plane: Plane): Waypoint[] {
  return Array.from({ length: n }, (_, i) => {
    const t = TAU * i / n
    const a = r * Math.cos(t), b = r * Math.sin(t)
    if (plane === 'XZ') return wp(cx + a, cy,     cz + b)
    if (plane === 'XY') return wp(cx + a, cy + b, cz)
    /* YZ */             return wp(cx,     cy + a, cz + b)
  })
}

function genEllipse(n: number, ra: number, rb: number, cx: number, cy: number, cz: number, plane: Plane): Waypoint[] {
  return Array.from({ length: n }, (_, i) => {
    const t = TAU * i / n
    const a = ra * Math.cos(t), b = rb * Math.sin(t)
    if (plane === 'XZ') return wp(cx + a, cy,     cz + b)
    if (plane === 'XY') return wp(cx + a, cy + b, cz)
    /* YZ */             return wp(cx,     cy + a, cz + b)
  })
}

function genFigure8(n: number, r: number, cx: number, cy: number, cz: number, plane: Plane): Waypoint[] {
  // Lemniscate of Gerono: a = r*sin(t),  b = r*sin(t)*cos(t)
  return Array.from({ length: n }, (_, i) => {
    const t = TAU * i / n
    const a = r * Math.sin(t)
    const b = r * Math.sin(t) * Math.cos(t)
    if (plane === 'XZ') return wp(cx + a, cy,     cz + b)
    if (plane === 'XY') return wp(cx + a, cy + b, cz)
    /* YZ */             return wp(cx,     cy + a, cz + b)
  })
}

function genHelix(n: number, r: number, len: number, turns: number,
                  cx: number, cy: number, cz: number, axis: HelixAxis): Waypoint[] {
  return Array.from({ length: n }, (_, i) => {
    const t     = i / (n - 1)
    const theta = TAU * turns * t
    const cos   = r * Math.cos(theta)
    const sin   = r * Math.sin(theta)
    // Progress along chosen axis; circle in the perpendicular plane
    if (axis === 'X') return wp(cx + len * t, cy + cos,       cz + sin)
    if (axis === 'Y') return wp(cx + cos,       cy + len * t, cz + sin)
    /* Z */            return wp(cx + cos,       cy + sin,       cz + len * t)
  })
}

function genArc(n: number, r: number, angleDeg: number, cx: number, cy: number, cz: number, plane: Plane): Waypoint[] {
  const arcRad = angleDeg * Math.PI / 180
  return Array.from({ length: n }, (_, i) => {
    const t = (i / (n - 1)) * arcRad - arcRad / 2
    const a = r * Math.cos(t), b = r * Math.sin(t)
    if (plane === 'XZ') return wp(cx + a, cy,     cz + b)
    if (plane === 'XY') return wp(cx + a, cy + b, cz)
    /* YZ */             return wp(cx,     cy + a, cz + b)
  })
}

interface Props {
  onClose: () => void
  /** When true: creates a brand-new route (name='untitled', speed=0.25)
   *  instead of replacing the current path's waypoints. */
  newRoute?: boolean
}

export function GenerateDialog({ onClose, newRoute }: Props) {
  const { replaceWps, patchPath, setPath } = useStore()

  const saved = loadSettings()
  const [shape,      setShape]      = useState<Shape>(saved.shape)
  const [n,          setN]          = useState(saved.n)
  const [r,          setR]          = useState(saved.r)
  const [ra,         setRa]         = useState(saved.ra)
  const [rb,         setRb]         = useState(saved.rb)
  const [helixLen,   setHelixLen]   = useState(saved.helixLen)
  const [helixTurns, setHelixTurns] = useState(saved.helixTurns)
  const [arcDeg,     setArcDeg]     = useState(saved.arcDeg)
  const [cx,         setCx]         = useState(saved.cx)
  const [cy,         setCy]         = useState(saved.cy)
  const [cz,         setCz]         = useState(saved.cz)
  const [plane,      setPlane]      = useState<Plane>(saved.plane)
  const [helixAxis,  setHelixAxis]  = useState<HelixAxis>(saved.helixAxis)
  const [closed,     setClosed]     = useState(saved.closed)

  const generate = useCallback(() => {
    saveSettings({ shape, n, r, ra, rb, helixLen, helixTurns, arcDeg, cx, cy, cz, plane, helixAxis, closed })
    let wps: Waypoint[]
    const nClamped = Math.max(3, n)
    switch (shape) {
      case 'blank':   wps = [{ x: 10, y: 0, z: 0, pathRoll: 0, craftRoll: 0 }];                  break
      case 'circle':  wps = genCircle(nClamped, r, cx, cy, cz, plane);                           break
      case 'ellipse': wps = genEllipse(nClamped, ra, rb, cx, cy, cz, plane);                     break
      case 'figure8': wps = genFigure8(nClamped, r, cx, cy, cz, plane);                          break
      case 'helix':   wps = genHelix(Math.max(3, nClamped), r, helixLen, helixTurns, cx, cy, cz, helixAxis); break
      case 'arc':     wps = genArc(Math.max(2, nClamped), r, arcDeg, cx, cy, cz, plane);         break
    }
    const isClosed = shape !== 'helix' && shape !== 'arc' && shape !== 'blank' ? closed : false
    if (newRoute) {
      setPath({
        name:     'untitled',
        type:     'craft',
        speed:    0.25,
        orient:   'path',
        target:   { x: 0, y: 6, z: 0 },
        standoff: 0,
        closed:   isClosed,
        wps:      wps!,
        tracks:            {},
        triggers:          [],
        craftRollSegments: [],
        craftRollLoopSeam: null,
      })
    } else {
      replaceWps(wps!)
      patchPath('closed', isClosed)
    }
    onClose()
  }, [shape, n, r, ra, rb, helixLen, helixTurns, arcDeg, cx, cy, cz, plane, helixAxis, closed,
      newRoute, setPath, replaceWps, patchPath, onClose])

  const numInput = (label: string, value: number, setter: (v: number) => void, step = 1, min?: number) => (
    <div className="modal-row" key={label}>
      <span className="modal-label">{label}</span>
      <DeferredNumInput value={value} setter={setter} step={step} min={min} />
    </div>
  )

  const shapeHasPlane = shape !== 'helix' && shape !== 'blank'
  const shapeHasParams = shape !== 'blank'

  const SHAPE_LABELS: Record<Shape, string> = {
    blank: 'Blank', circle: 'Circle', ellipse: 'Ellipse',
    figure8: 'Fig-8', helix: 'Helix', arc: 'Arc',
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="modal-header">{newRoute ? 'New Route — Choose Shape' : 'Generate Path from Shape'}</div>

        {/* Shape picker */}
        <div className="modal-row">
          <span className="modal-label">Shape</span>
          <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
            {(['blank', 'circle', 'ellipse', 'figure8', 'helix', 'arc'] as Shape[]).map(s => (
              <button key={s} className={shape === s ? 'primary' : ''}
                onClick={() => setShape(s)}
                style={{ fontSize: 10, padding: '2px 7px' }}>
                {SHAPE_LABELS[s]}
              </button>
            ))}
          </div>
        </div>

        {/* Blank: no params needed */}
        {shape === 'blank' && (
          <div style={{ fontSize: 11, color: 'var(--text-faint)', margin: '6px 0 2px', lineHeight: 1.5 }}>
            Starts with a single waypoint at (10, 0, 0).<br />
            Double-click in any ortho view to add more nodes.
          </div>
        )}

        {/* Plane (not for helix or blank) */}
        {shapeHasPlane && (
          <div className="modal-row">
            <span className="modal-label">Plane</span>
            <div style={{ display: 'flex', gap: 4 }}>
              {(['XZ', 'XY', 'YZ'] as Plane[]).map(p => (
                <button key={p} className={plane === p ? 'primary' : ''}
                  onClick={() => setPlane(p)}
                  style={{ fontSize: 10, padding: '2px 10px' }}>
                  {p}
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Points */}
        {shapeHasParams && numInput('Points', n, v => setN(Math.max(3, Math.round(v))), 1, 3)}

        {/* Shape-specific params */}
        {shape === 'ellipse' && <>
          {numInput('Radius A', ra, setRa, 0.5)}
          {numInput('Radius B', rb, setRb, 0.5)}
        </>}

        {(shape === 'circle' || shape === 'figure8') && numInput('Radius', r, setR, 0.5)}

        {shape === 'helix' && <>
          <div className="modal-row">
            <span className="modal-label">Along axis</span>
            <div style={{ display: 'flex', gap: 4 }}>
              {(['X', 'Y', 'Z'] as HelixAxis[]).map(a => (
                <button key={a} className={helixAxis === a ? 'primary' : ''}
                  onClick={() => setHelixAxis(a)}
                  style={{ fontSize: 10, padding: '2px 12px' }}>{a}</button>
              ))}
            </div>
          </div>
          {numInput('Radius',  r,          setR,          0.5)}
          {numInput('Length',  helixLen,   setHelixLen,   1)}
          {numInput('Turns',   helixTurns, setHelixTurns, 0.5)}
        </>}

        {shape === 'arc' && <>
          {numInput('Radius', r,      setR,      0.5)}
          {numInput('Arc °',  arcDeg, setArcDeg, 15)}
        </>}

        {/* Center */}
        {shapeHasParams && (
          <div className="modal-row">
            <span className="modal-label">Center</span>
            <div style={{ display: 'flex', gap: 4 }}>
              {([['X', cx, setCx], ['Y', cy, setCy], ['Z', cz, setCz]] as [string, number, (v:number)=>void][]).map(([lbl, val, setter]) => (
                <label key={lbl} style={{ display:'flex', alignItems:'center', gap:2, fontSize:10, color:'var(--text-dim)' }}>
                  {lbl}
                  <DeferredNumInput value={val} setter={setter} step={1} style={{ width:48 }} />
                </label>
              ))}
            </div>
          </div>
        )}

        {/* Closed */}
        {shapeHasParams && shape !== 'helix' && shape !== 'arc' && (
          <div className="modal-row">
            <label style={{ display:'flex', alignItems:'center', gap:5, cursor:'pointer' }}>
              <input type="checkbox" checked={closed} onChange={e => setClosed(e.target.checked)} />
              <span className="modal-label">Closed loop</span>
            </label>
          </div>
        )}

        <div className="modal-footer">
          <button onClick={onClose}>Cancel</button>
          <button className="primary" onClick={generate}>
            {shape === 'blank' ? 'Create' : 'Generate'}
          </button>
        </div>
      </div>
    </div>
  )
}
