// Behaviors panel — two-mode design.
//
// COMPACT (default): thin bar, passive dots at keyframe t-positions, no editing.
//   Click row → switch to ACTIVE.
//
// ACTIVE: panel expands below the compact row:
//   [edit strip]  — kf controls or hint
//   [graph]       — interactive SVG: diamonds at (t, value); drag to move both axes;
//                   click empty area to add; right-click diamond to delete/replicate.
//   The bar stays compact in active mode — passive reference only.
//   Graph handles ALL keyframe interaction in active mode.
//
// Alignment guarantee: ruler and track rows use the same CSS grid columns
//   (--bpanel-label-w | 1fr | --bpanel-right-w). No arithmetic, no drift.

import React, { useRef, useState, useEffect, useCallback, useMemo, type CSSProperties } from 'react'
import { useStore, EaseType, TriggerEvent, FireMode, ShieldMode, TrackKeyframe } from '../store'
import { trackColor, triggerColor, evalTrack } from '../views/behaviorMarkers'
import { pauseAfterCheckpoint, resumeTemporal } from '../views/undoHelpers'
import { buildSpline } from '../math/spline'
import type { PathData } from '../store'

// ── Constants ─────────────────────────────────────────────────────────────

const KNOWN_TRACKS = ['craftRoll', 'standoff', 'offsetAngle', 'speed', 'visible', 'engineBrightness']
const EASE_OPTIONS: EaseType[] = ['linear', 'smooth', 'ease-in', 'ease-out', 'instant']

const TRIGGER_TYPES = ['fireMode', 'weapon', 'shieldMode', 'invuln', 'phase', 'sound', 'custom'] as const
type TriggerType = typeof TRIGGER_TYPES[number]

/** Sensible default value for a new keyframe in a named track.
 *  Tracks that are multipliers (speed, visible, brightness) default to 1 = no change.
 *  Angular/offset tracks default to 0 = neutral. */
function defaultTrackValue(name: string): number {
  switch (name) {
    case 'speed':            return 1   // 1× multiplier — ship moves at path speed
    case 'visible':          return 1   // 1 = visible
    case 'engineBrightness': return 1   // 1 = full brightness
    default:                 return 0   // craftRoll, standoff, offsetAngle → neutral
  }
}

function defaultEvent(type: TriggerType): TriggerEvent {
  switch (type) {
    case 'fireMode':   return { type: 'fireMode',   mode: 'on' }
    case 'weapon':     return { type: 'weapon',      name: '' }
    case 'shieldMode': return { type: 'shieldMode',  mode: 'on' }
    case 'invuln':     return { type: 'invuln',      value: 1 }
    case 'phase':      return { type: 'phase',       tag: '' }
    case 'sound':      return { type: 'sound',       name: '', volume: 1, loop: false }
    case 'custom':     return { type: 'custom',      tag: '', value: '' }
  }
}

function triggerSummary(ev: TriggerEvent): string {
  switch (ev.type) {
    case 'fireMode':   return ev.mode
    case 'weapon':     return ev.name || '—'
    case 'shieldMode': return ev.mode
    case 'invuln':     return ev.value === 1 ? 'on' : 'off'
    case 'phase':      return ev.tag || '—'
    case 'sound':      return ev.name || '—'
    case 'custom':     return ev.tag ? `${ev.tag}=${ev.value}` : '—'
  }
}

/** Default easing for a new keyframe in a named track.
 *  Instant for hard-toggle tracks; smooth for analog tracks that benefit from
 *  gradual transitions; linear left as explicit fallback. */
function defaultTrackEasing(name: string): EaseType {
  switch (name) {
    case 'visible':          return 'instant'   // hard toggle — no fade
    case 'engineBrightness': return 'smooth'    // ramp looks better eased
    case 'craftRoll':        return 'smooth'    // roll transitions feel natural smooth
    case 'offsetAngle':      return 'smooth'    // lateral drift same
    case 'standoff':         return 'smooth'    // distance ramps same
    case 'speed':            return 'smooth'    // avoids jarring acceleration kinks
    default:                 return 'linear'
  }
}

/** Short unit/description shown in graph value labels */
function trackUnit(name: string): string {
  switch (name) {
    case 'craftRoll':  return '°'
    case 'offsetAngle': return '°'
    case 'standoff':   return 'u'
    case 'speed':      return '×'
    default:           return ''
  }
}

/** Per-track value clamps — prevents runaway values from drag overshoots. */
function trackValueLimits(name: string): { min: number; max: number } {
  switch (name) {
    // craftRoll uses "accumulated degrees" authoring: values beyond ±360 mean
    // multiple full rotations (720° = two rolls).  Cap at ±3600 (10 full rotations).
    case 'craftRoll':        return { min: -3600, max: 3600 }
    case 'offsetAngle':      return { min: -180,  max: 180  }
    case 'standoff':         return { min: -200,  max: 200  }
    case 'speed':            return { min: 0,     max: 10   }
    case 'visible':          return { min: 0,     max: 1    }
    case 'engineBrightness': return { min: 0,     max: 5    }
    default:                 return { min: -1000, max: 1000 }
  }
}

/** Per-tick wheel step for value editing. Shift multiplies by 10. */
function wheelStep(name: string): number {
  switch (name) {
    case 'craftRoll':        return 5    // 5° per tick; Shift = 50° (near a quarter-turn)
    case 'offsetAngle':      return 1
    case 'standoff':         return 0.5
    case 'speed':            return 0.05
    case 'visible':          return 0.05
    case 'engineBrightness': return 0.1
    default:                 return 1
  }
}

// ── NumInput ──────────────────────────────────────────────────────────────
interface NumInputProps {
  value: number; step?: number; min?: number; max?: number
  className?: string; title?: string; style?: CSSProperties
  commit: (n: number) => void
}
function NumInput({ value, step, min, max, className, title, style, commit }: NumInputProps) {
  const [text, setText] = useState<string | null>(null)
  const display = text !== null ? text : String(value)
  function tryCommit(raw: string) {
    const n = parseFloat(raw)
    if (isNaN(n)) { setText(String(value)); return }
    let v = min !== undefined ? Math.max(min, n) : n
    if (max !== undefined) v = Math.min(max, v)
    commit(v); setText(null)
  }
  return (
    <input type="number" className={className} title={title} style={style}
      step={step} min={min} max={max} value={display}
      onChange={e => setText(e.target.value)}
      onFocus={e => { setText(String(value)); e.target.select() }}
      onBlur={e => tryCommit(e.target.value)}
      onKeyDown={e => { if (e.key === 'Enter') e.currentTarget.blur() }} />
  )
}

// ── Trigger value editor ──────────────────────────────────────────────────
function TriggerValueEditor({ event, onChange }: {
  event: TriggerEvent; onChange: (ev: TriggerEvent) => void
}) {
  switch (event.type) {
    case 'fireMode':
      return (
        <select className="bp-select" value={event.mode}
          onChange={e => onChange({ ...event, mode: e.target.value as FireMode })}>
          {(['off', 'on', 'target', 'willful'] as FireMode[]).map(m => <option key={m}>{m}</option>)}
        </select>
      )
    case 'weapon':
      return <input className="bp-text" placeholder="weapon name" value={event.name}
        onChange={e => onChange({ ...event, name: e.target.value })} />
    case 'shieldMode':
      return (
        <select className="bp-select" value={event.mode}
          onChange={e => onChange({ ...event, mode: e.target.value as ShieldMode })}>
          {(['off', 'on', 'partial'] as ShieldMode[]).map(m => <option key={m}>{m}</option>)}
        </select>
      )
    case 'invuln':
      return (
        <select className="bp-select" value={event.value}
          onChange={e => onChange({ ...event, value: parseInt(e.target.value) as 0|1 })}>
          <option value={1}>on</option><option value={0}>off</option>
        </select>
      )
    case 'phase':
      return <input className="bp-text" placeholder="phase tag" value={event.tag}
        onChange={e => onChange({ ...event, tag: e.target.value })} />
    case 'sound':
      return (
        <>
          <input className="bp-text" placeholder="sound name" value={event.name}
            onChange={e => onChange({ ...event, name: e.target.value })} />
          <span className="bp-label">vol</span>
          <NumInput value={event.volume} step={0.1} min={0} max={1}
            commit={v => onChange({ ...event, volume: v })}
            className="bp-num" style={{ width: 42 }} />
          <label className="bp-chk-label">
            <input type="checkbox" checked={event.loop}
              onChange={e => onChange({ ...event, loop: e.target.checked })} />
            loop
          </label>
        </>
      )
    case 'custom':
      return (
        <>
          <input className="bp-text bp-text-sm" placeholder="tag" value={event.tag}
            onChange={e => onChange({ ...event, tag: e.target.value })} />
          <input className="bp-text bp-text-sm" placeholder="value" value={event.value}
            onChange={e => onChange({ ...event, value: e.target.value })} />
        </>
      )
  }
}

// ── Arc-length lookup table ────────────────────────────────────────────────
// Both PathRuler (playback ruler) and TrackGraph (graph editor) must show
// keyframe positions in the SAME coordinate system so dragging a diamond in
// the graph bar moves the corresponding tick on the ruler by exactly the same
// number of pixels — no lurching, no racing.
//
// kf.t is stored as parameter fraction [0..1]. Playback uses arc-length
// normalization (arcAdvanceAt), so 0.5 parameter fraction ≠ 0.5 of the way
// through the animation. This table converts between the two spaces so both
// components display in arc-length fraction space while still storing in
// parameter fraction space.
interface ArcTable {
  paramToArc(pf: number): number   // parameter fraction [0..1] → arc-length fraction [0..1]
  arcToParam(af: number): number   // arc-length fraction [0..1] → parameter fraction [0..1]
}

const IDENTITY_ARC: ArcTable = { paramToArc: p => p, arcToParam: a => a }

function makeArcTable(path: PathData): ArcTable {
  if (path.wps.length < 2) return IDENTITY_ARC

  const samples = buildSpline({ wps: path.wps, closed: path.closed, standoff: path.standoff })
  if (samples.length < 2) return IDENTITY_ARC

  // Cumulative arc lengths and matching parameter fractions for each sample
  // SplineSample.frac is rawAt[i]/nSegs — already parameter fraction [0..1]
  const paramFracs: number[] = [samples[0].frac]
  const cumArc: number[]     = [0]
  for (let i = 1; i < samples.length; i++) {
    const s = samples[i], p = samples[i - 1]
    const dx = s.wire.x - p.wire.x, dy = s.wire.y - p.wire.y, dz = s.wire.z - p.wire.z
    cumArc.push(cumArc[i - 1] + Math.sqrt(dx * dx + dy * dy + dz * dz))
    paramFracs.push(s.frac)
  }
  const totalArc = cumArc[cumArc.length - 1]
  if (totalArc === 0) return IDENTITY_ARC

  // Largest index where arr[i] <= val
  function lb(arr: number[], val: number): number {
    let lo = 0, hi = arr.length - 1
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (arr[mid] <= val) lo = mid; else hi = mid - 1 }
    return lo
  }

  function paramToArc(pf: number): number {
    pf = Math.max(0, Math.min(1, pf))
    const i = lb(paramFracs, pf)
    if (i >= paramFracs.length - 1) return 1
    const span = paramFracs[i + 1] - paramFracs[i]
    const t    = span < 1e-10 ? 0 : (pf - paramFracs[i]) / span
    return (cumArc[i] + t * (cumArc[i + 1] - cumArc[i])) / totalArc
  }

  function arcToParam(af: number): number {
    af = Math.max(0, Math.min(1, af))
    const arcVal = af * totalArc
    const i = lb(cumArc, arcVal)
    if (i >= cumArc.length - 1) return 1
    const span = cumArc[i + 1] - cumArc[i]
    const t    = span < 1e-10 ? 0 : (arcVal - cumArc[i]) / span
    return paramFracs[i] + t * (paramFracs[i + 1] - paramFracs[i])
  }

  return { paramToArc, arcToParam }
}

// ── PathRuler ─────────────────────────────────────────────────────────────
// Uses same grid columns as track rows via class .bpanel-ruler-row.
// Positions are displayed in arc-length fraction space so they match the
// graph editor diamonds pixel-for-pixel.
function PathRuler() {
  const { path, animT, setAnimT } = useStore()
  const barRef    = useRef<HTMLDivElement>(null)
  const scrubbing = useRef(false)

  const nSegs    = path.closed ? path.wps.length : Math.max(path.wps.length - 1, 1)
  const arcTable = useMemo(() => makeArcTable(path), [path])
  const { paramToArc, arcToParam } = arcTable

  // Playhead in arc-length fraction space
  const paramFrac = nSegs > 0 ? Math.max(0, Math.min(1, (animT % nSegs) / nSegs)) : 0
  const animFrac  = paramToArc(paramFrac)

  const scrubAt = (clientX: number) => {
    if (!barRef.current) return
    const rect    = barRef.current.getBoundingClientRect()
    const arcFrac = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width))
    setAnimT(arcToParam(arcFrac) * nSegs)
  }

  const handlePointer = (e: React.PointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId)
    scrubbing.current = true
    scrubAt(e.clientX)
  }
  const handleMove = (e: React.PointerEvent) => {
    if (!scrubbing.current) return
    scrubAt(e.clientX)
  }

  const trackNames = Object.keys(path.tracks).sort()

  return (
    <div className="bpanel-ruler-wrap">
      <div className="bpanel-ruler-row">
        <div>{/* left spacer — grid col 1 */}</div>
        <div ref={barRef} className="bpanel-ruler-bar"
          onPointerDown={handlePointer} onPointerMove={handleMove}
          onPointerUp={() => { scrubbing.current = false }}>
          <div className="bpanel-ruler-labels">
            <span>0</span>
            <span className="bpanel-ruler-t">{paramFrac.toFixed(3)}</span>
            <span>1</span>
          </div>
          <div className="bpanel-scrubber" style={{ left: `${animFrac * 100}%` }} />
          {/* Keyframe ticks — converted to arc-length fraction to match graph diamonds */}
          {trackNames.flatMap(name =>
            (path.tracks[name] ?? []).map((kf, i) => (
              <div key={`${name}-${i}`} className="bpanel-ruler-kf"
                style={{ left: `${paramToArc(kf.t) * 100}%`, background: trackColor(name) }}
                title={`${name}  t=${kf.t.toFixed(3)}  ${kf.value}  ${kf.ease}`} />
            ))
          )}
          {path.triggers.map((tr, i) => (
            <div key={`tr-${i}`} className="bpanel-ruler-trigger"
              style={{ left: `${paramToArc(tr.t) * 100}%`, background: triggerColor(tr.event.type) }}
              title={`${tr.event.type}  t=${tr.t.toFixed(3)}  ${triggerSummary(tr.event)}`} />
          ))}
        </div>
        <div>{/* right spacer — grid col 3 */}</div>
      </div>
    </div>
  )
}

// ── TrackGraph ────────────────────────────────────────────────────────────
// Interactive graph inside .bpanel-active-graph (position:relative, height:52px).
//
// VALUE RANGE: pinned to trackValueLimits — no auto-scaling runaway.
//
// INTERACTION MODEL (simplified):
//   • Click empty area → adds keyframe at that t position with default value
//   • Drag diamond horizontally → moves t only (1D)
//   • Value is always edited via the NumInput in the edit strip above, never by dragging
//
// RENDERING:
//   • SVG (preserveAspectRatio="none") draws the curve/area fill — distortion OK for curves
//   • Diamond handles are absolutely-positioned CSS divs (rotated squares) → always exact
//     pixel size regardless of the SVG's aspect ratio, no compensation math needed
interface CtxMenuState { x: number; y: number; kfIdx: number }
interface GraphDrag { startClientX: number; startArcFrac: number; startT: number; currentT: number }

function TrackGraph({ name, frames, color, selIdx, onSelKf, onCtxMenu, containerRef }: {
  name:         string
  frames:       TrackKeyframe[]
  color:        string
  selIdx:       number
  onSelKf:      (v: { track: string; idx: number } | null) => void
  onCtxMenu:    (s: CtxMenuState) => void
  containerRef: React.RefObject<HTMLDivElement>
}) {
  const { path, addKeyframe, updateKeyframe } = useStore()
  const arcTable = useMemo(() => makeArcTable(path), [path])
  const { paramToArc, arcToParam } = arcTable
  const drag        = useRef<GraphDrag | null>(null)
  const justDragged = useRef(false)

  // ── Stable value range from track limits ─────────────────────────────
  const VW = 200; const VH = 100; const PAD = 8
  const { min: vMin, max: vMax } = trackValueLimits(name)
  const vRange = vMax - vMin

  // toX maps arc-length fraction [0..1] → SVG x coordinate
  const toX = (arcFrac: number) => arcFrac * VW
  const toY = (v: number) => {
    const c = Math.max(vMin, Math.min(vMax, v))
    return VH - PAD - ((c - vMin) / vRange) * (VH - PAD * 2)
  }
  // Y position as a fraction [0..1] for CSS top positioning (0=top, 1=bottom)
  const toTopFrac = (v: number) => toY(v) / VH

  // ── Sparkline (SVG) ───────────────────────────────────────────────────
  const STEPS = 80
  let linePoints = ''; let areaD = ''
  if (frames.length >= 1) {
    const pts = Array.from({ length: STEPS + 1 }, (_, i) => {
      const arcFrac  = i / STEPS
      const paramFrac = arcToParam(arcFrac)
      return `${toX(arcFrac).toFixed(1)},${toY(evalTrack(frames, paramFrac)).toFixed(1)}`
    })
    linePoints = pts.join(' ')
    areaD = pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${p}`).join(' ') + ` L${VW},${VH} L0,${VH} Z`
  }

  // ── Click → add keyframe at t with default value ──────────────────────
  function handleSvgClick(e: React.MouseEvent<SVGSVGElement>) {
    if (justDragged.current || !containerRef.current) return
    const r = containerRef.current.getBoundingClientRect()
    const arcFrac = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width))
    const t = arcToParam(arcFrac)
    if (frames.some(kf => Math.abs(paramToArc(kf.t) - arcFrac) < 0.02)) return
    const val    = defaultTrackValue(name)
    const newKf: TrackKeyframe = { t, value: val, ease: defaultTrackEasing(name) }
    addKeyframe(name, newKf)
    const sorted = [...frames, newKf].sort((a, b) => a.t - b.t)
    const idx = sorted.findIndex(kf => Math.abs(kf.t - t) < 0.001)
    onSelKf({ track: name, idx })
  }

  // ── Diamond drag — horizontal (t) only ────────────────────────────────
  function handleDiamondPointerDown(e: React.PointerEvent<HTMLDivElement>, idx: number) {
    e.stopPropagation()
    e.currentTarget.setPointerCapture(e.pointerId)
    pauseAfterCheckpoint()
    drag.current = { startClientX: e.clientX, startArcFrac: paramToArc(frames[idx].t), startT: frames[idx].t, currentT: frames[idx].t }
    onSelKf({ track: name, idx })
  }
  function handleDiamondPointerMove(e: React.PointerEvent<HTMLDivElement>) {
    if (!drag.current || !containerRef.current) return
    const r     = containerRef.current.getBoundingClientRect()
    const dArc  = (e.clientX - drag.current.startClientX) / r.width
    const newT  = arcToParam(Math.max(0, Math.min(1, drag.current.startArcFrac + dArc)))
    const cur  = useStore.getState().path.tracks[name] ?? []
    const ai   = cur.findIndex(kf => Math.abs(kf.t - drag.current!.currentT) < 0.0005)
    if (ai >= 0) {
      updateKeyframe(name, ai, { ...cur[ai], t: newT })
      drag.current.currentT = newT
    }
  }
  function handleDiamondPointerUp() {
    if (!drag.current) return
    const moved = Math.abs(drag.current.currentT - drag.current.startT) > 0.001
    drag.current = null
    if (moved) { justDragged.current = true; setTimeout(() => { justDragged.current = false }, 0) }
    resumeTemporal()
  }

  // ── Mouse-wheel → change selected keyframe VALUE (not t) ─────────────
  // Attached as a native (non-passive) wheel listener on the graph container so
  // preventDefault() and stopPropagation() work at the DOM level, preventing:
  //   1. The event from scrolling any ancestor container.
  //   2. Focused <input type="range"> elements (scrubber) from capturing the event
  //      in Firefox, which routes wheel to the focused element regardless of cursor.
  const isWheeling   = useRef(false)
  const wheelTimer   = useRef<ReturnType<typeof setTimeout> | null>(null)
  const selIdxRef    = useRef(selIdx)
  selIdxRef.current  = selIdx

  const nativeWheelRef = useRef<(e: WheelEvent) => void>(() => {})
  nativeWheelRef.current = (e: WheelEvent) => {
    const si = selIdxRef.current
    if (si < 0) return
    e.preventDefault()
    e.stopPropagation()
    // Blur any focused range input (scrubber) so it stops capturing wheel events
    if (document.activeElement instanceof HTMLInputElement && document.activeElement.type === 'range') {
      document.activeElement.blur()
    }
    const { min, max } = trackValueLimits(name)
    const step  = wheelStep(name) * (e.shiftKey ? 10 : 1)
    const delta = e.deltaY < 0 ? step : -step   // scroll up → increase value
    if (!isWheeling.current) { pauseAfterCheckpoint(); isWheeling.current = true }
    if (wheelTimer.current) clearTimeout(wheelTimer.current)
    wheelTimer.current = setTimeout(() => {
      resumeTemporal(); isWheeling.current = false; wheelTimer.current = null
    }, 400)
    const cur = useStore.getState().path.tracks[name] ?? []
    const kf  = cur[si]
    if (!kf) return
    updateKeyframe(name, si, { ...kf, value: Math.max(min, Math.min(max, kf.value + delta)) })
  }

  useEffect(() => {
    const el = containerRef.current
    if (!el) return
    const fn = (e: WheelEvent) => nativeWheelRef.current(e)
    el.addEventListener('wheel', fn, { passive: false })
    return () => el.removeEventListener('wheel', fn)
  // containerRef is stable — only needs to run on mount/unmount
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Diamond size: always 8px — never changes on select.
  const D = 8

  return (
    <>
      {/* Background SVG — curve + area fill only (pointer-events:none) */}
      <svg
        style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', cursor: 'crosshair', pointerEvents: 'none' }}
        viewBox={`0 0 ${VW} ${VH}`} preserveAspectRatio="none">

        {/* Zero-guide */}
        {vMin < 0 && vMax > 0 && (
          <line x1={0} y1={toY(0).toFixed(1)} x2={VW} y2={toY(0).toFixed(1)}
            stroke="rgba(255,255,255,0.12)" strokeWidth="1" strokeDasharray="3 4" />
        )}

        {/* Area fill */}
        {areaD && <path d={areaD} fill={color} opacity="0.12" stroke="none" />}

        {/* Curve */}
        {linePoints && (
          <polyline points={linePoints} fill="none" stroke={color} strokeWidth="2" opacity="0.65" />
        )}

        {/* Vertical stems — visual only, interaction handled by stem divs below */}
        {frames.map((kf, i) => (
          <line key={i}
            x1={(paramToArc(kf.t) * VW).toFixed(1)} y1={toY(kf.value).toFixed(1)}
            x2={(paramToArc(kf.t) * VW).toFixed(1)} y2={VH}
            stroke={color} strokeWidth={i === selIdx ? '1.5' : '1'} opacity="0.25" />
        ))}
      </svg>

      {/* Transparent click-catcher (background, below stems+diamonds) */}
      <div style={{ position: 'absolute', inset: 0, cursor: 'crosshair' }}
        onClick={e => { e.stopPropagation(); handleSvgClick(e as unknown as React.MouseEvent<SVGSVGElement>) }} />

      {/* Per-keyframe: stem drag handle + diamond */}
      {frames.map((kf, i) => {
        const isSel   = i === selIdx
        const topFrac = toTopFrac(kf.value)
        const stemW   = 12   // px — wide invisible hit target for the stem
        const sharedHandlers = {
          onPointerDown: (ev: React.PointerEvent<HTMLDivElement>) => handleDiamondPointerDown(ev, i),
          onPointerMove: handleDiamondPointerMove,
          onPointerUp:   handleDiamondPointerUp,
          // onWheel handled by native listener on containerRef — no React prop needed
          onContextMenu: (ev: React.MouseEvent) => { ev.preventDefault(); ev.stopPropagation(); onCtxMenu({ x: ev.clientX, y: ev.clientY, kfIdx: i }) },
        }
        return (
          <React.Fragment key={i}>
            {/* Stem drag zone — covers the full vertical line from diamond to baseline */}
            <div
              title={`t=${kf.t.toFixed(3)}  val=${kf.value.toFixed(3)}  ease=${kf.ease}\nDrag ← → to move in time · wheel to change value`}
              style={{
                position: 'absolute',
                left:   `calc(${paramToArc(kf.t) * 100}% - ${stemW / 2}px)`,
                top:    `${topFrac * 100}%`,
                width:  stemW,
                height: `${(1 - topFrac) * 100}%`,
                cursor: 'ew-resize',
                zIndex: 1,
              }}
              onClick={ev => { ev.stopPropagation(); if (!justDragged.current) onSelKf({ track: name, idx: i }) }}
              {...sharedHandlers}
            />
            {/* Diamond — fixed 8px, filled interior when selected */}
            <div
              style={{
                position:  'absolute',
                left:      `calc(${paramToArc(kf.t) * 100}% - ${D / 2}px)`,
                top:       `calc(${topFrac * 100}% - ${D / 2}px)`,
                width:     D, height: D,
                transform: 'rotate(45deg)',
                background: isSel ? color : 'var(--bg)',
                border:    `1.5px solid ${color}`,
                cursor:    'ew-resize',
                zIndex:    2,
                boxSizing: 'border-box',
              }}
              onClick={ev => ev.stopPropagation()}
              {...sharedHandlers}
            />
          </React.Fragment>
        )
      })}

      {/* Empty-state hint */}
      {frames.length === 0 && (
        <div style={{
          position: 'absolute', inset: 0, display: 'flex',
          alignItems: 'center', justifyContent: 'center',
          fontSize: 10, color: 'rgba(255,255,255,0.25)',
          pointerEvents: 'none', userSelect: 'none',
        }}>
          click to add keyframe
        </div>
      )}
    </>
  )
}

// ── KfContextMenu ─────────────────────────────────────────────────────────
function KfContextMenu({ x, y, kf, trackName, kfIdx, onClose }: {
  x: number; y: number; kf: TrackKeyframe; kfIdx: number; trackName: string; onClose: () => void
}) {
  const { path, addKeyframe, removeKeyframe } = useStore()
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const h = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) onClose() }
    setTimeout(() => document.addEventListener('mousedown', h), 0)
    return () => document.removeEventListener('mousedown', h)
  }, [onClose])
  const others = Object.keys(path.tracks).filter(n => n !== trackName)
  return (
    <div ref={ref} className="bp-ctx-menu" style={{ left: x, top: y }}>
      <div className="bp-ctx-section">t={kf.t.toFixed(3)} · val={kf.value}</div>
      <button className="bp-ctx-item bp-ctx-danger"
        onClick={() => { removeKeyframe(trackName, kfIdx); onClose() }}>Delete keyframe</button>
      {others.length > 0 && <>
        <div className="bp-ctx-sep" />
        <div className="bp-ctx-section">Replicate t to:</div>
        {others.map(n => (
          <button key={n} className="bp-ctx-item" style={{ color: trackColor(n) }}
            onClick={() => {
              const fs = path.tracks[n] ?? []
              if (!fs.some(f => Math.abs(f.t - kf.t) < 0.005))
                addKeyframe(n, { t: kf.t, value: kf.value, ease: kf.ease })
              onClose()
            }}>{n}</button>
        ))}
      </>}
      <div className="bp-ctx-sep" />
      <div className="bp-ctx-note">Lock: coming soon</div>
    </div>
  )
}

// ── TrackRow ──────────────────────────────────────────────────────────────
function TrackRow({ name, selKf, onSelKf, isExpanded, onExpand }: {
  name: string
  selKf: { track: string; idx: number } | null
  onSelKf: (v: { track: string; idx: number } | null) => void
  isExpanded: boolean
  onExpand: () => void
}) {
  const { path, updateKeyframe, removeKeyframe, setTrack,
          hoveredBehavior, setHoveredBehavior,
          mutedTracks, toggleMutedTrack } = useStore()
  const isMuted    = !!mutedTracks[name]
  const graphRef   = useRef<HTMLDivElement>(null)
  const frames     = path.tracks[name] ?? []
  const color      = trackColor(name)
  const isSelTrack = selKf?.track === name
  const selIdx     = isSelTrack ? selKf!.idx : -1
  const isHovered  = hoveredBehavior?.type === 'track' && hoveredBehavior.name === name
  const sel        = selIdx >= 0 ? frames[selIdx] : null
  const [ctxMenu, setCtxMenu] = useState<CtxMenuState | null>(null)

  function commitT(t: number) {
    if (!sel) return; updateKeyframe(name, selIdx, { ...sel, t: Math.max(0, Math.min(1, t)) })
  }
  function commitValue(v: number) {
    if (!sel) return; updateKeyframe(name, selIdx, { ...sel, value: v })
  }
  function commitEase(ease: EaseType) {
    if (!sel) return; updateKeyframe(name, selIdx, { ...sel, ease })
  }
  function deleteKf() { removeKeyframe(name, selIdx); onSelKf(null) }

  const unit = trackUnit(name)

  return (
    <div
      className={`bpanel-track-group${isHovered ? ' hovered' : ''}${isExpanded ? ' active' : ''}${isMuted ? ' muted' : ''}`}
      onMouseEnter={() => setHoveredBehavior({ type: 'track', name })}
      onMouseLeave={() => setHoveredBehavior(null)}>

      {/* ── Compact row — always visible ── */}
      <div className="bpanel-track-row"
        style={{ cursor: isExpanded ? 'default' : 'pointer' }}
        onClick={isExpanded ? undefined : onExpand}>

        {/* Col 1: label with mode indicator */}
        <span className="bpanel-track-label" style={{ color }}
          title={isExpanded ? 'Click to collapse' : 'Click to expand'}
          onClick={e => { e.stopPropagation(); onExpand() }}>
          <span className="bpanel-mode-ind">{isExpanded ? '▼' : '▶'}</span>
          {name}
        </span>

        {/* Col 2: thin bar — passive position dots in compact, clean in active */}
        <div className="bpanel-track-bar" style={{ cursor: isExpanded ? 'default' : 'pointer' }}>
          <div className="bpanel-track-baseline" />
          {!isExpanded && frames.map((kf, i) => (
            <div key={i}
              className={`bpanel-kf-diamond${i === selIdx ? ' selected' : ''}`}
              style={{ left: `${kf.t * 100}%`, background: color, borderColor: color }}
              title={`t=${kf.t.toFixed(3)}  val=${kf.value}${unit} — click to expand`}
              onClick={e => { e.stopPropagation(); onSelKf({ track: name, idx: i }); onExpand() }} />
          ))}
        </div>

        {/* Col 3: right panel — eye-mute + meta + delete-track button */}
        <div className="bpanel-track-right">
          <button className="bp-eye-btn"
            title={isMuted ? 'Unmute — re-enable in preview' : 'Mute — suppress in preview'}
            style={{ color: isMuted ? 'var(--text-faint)' : color, opacity: isMuted ? 0.45 : 0.75 }}
            onClick={e => { e.stopPropagation(); toggleMutedTrack(name) }}>
            {isMuted ? '○' : '◉'}
          </button>
          <span className="bpanel-track-meta">{frames.length} kf</span>
          <button className="bp-icon-btn danger" title="Remove entire track (discards all keyframes)"
            onClick={e => {
              e.stopPropagation()
              const n = frames.length
              if (n > 0 && !window.confirm(
                `Delete the "${name}" track?\n\nThis will permanently discard ${n} keyframe${n !== 1 ? 's' : ''}.\nThis action can be undone with Ctrl+Z.`
              )) return
              setTrack(name, []); onSelKf(null)
            }}>×</button>
        </div>
      </div>

      {/* ── Active panel — edit controls then interactive graph ── */}
      {isExpanded && (
        <div className="bpanel-active-panel">
          <div className="bpanel-active-edit">
            {sel ? (
              <>
                <span className="bp-label">t</span>
                <NumInput value={sel.t} step={0.001} min={0} max={1} commit={commitT}
                  className="bp-num bp-num-t"
                  title="Arc-length position (0–1). Also drag diamond ← → on graph." />
                <span className="bp-label">val</span>
                <NumInput value={sel.value}
                  step={name === 'craftRoll' || name === 'offsetAngle' ? 5 : 0.1}
                  min={trackValueLimits(name).min} max={trackValueLimits(name).max}
                  commit={commitValue} className="bp-num"
                  title={name === 'craftRoll' ? 'Roll in degrees: positive=CW, negative=CCW'
                        : name === 'speed'    ? 'Speed multiplier (1 = path default speed)'
                        : undefined} />
                {name === 'craftRoll' && (
                  <button className="bp-icon-btn" title="Flip roll sign"
                    onClick={() => commitValue(-sel.value)}>
                    {sel.value >= 0 ? '↻' : '↺'}
                  </button>
                )}
                <span className="bp-label">ease</span>
                <select className="bp-select" value={sel.ease}
                  onChange={e => commitEase(e.target.value as EaseType)}>
                  {EASE_OPTIONS.map(o => <option key={o}>{o}</option>)}
                </select>
                <button className="bp-icon-btn danger" onClick={deleteKf}>Del kf</button>
              </>
            ) : (
              <span className="bp-hint">
                {frames.length === 0
                  ? `Click graph to add — then set value above${name === 'craftRoll' ? ' (degrees)' : name === 'speed' ? ' (1=default)' : ''}`
                  : 'Click ◆ or compact dot to select · drag ◆ ← → to reposition · right-click to delete'}
              </span>
            )}
          </div>
          <div ref={graphRef} className="bpanel-active-graph">
            <TrackGraph name={name} frames={frames} color={color}
              selIdx={selIdx} onSelKf={onSelKf} onCtxMenu={setCtxMenu}
              containerRef={graphRef as React.RefObject<HTMLDivElement>} />
          </div>
        </div>
      )}

      {ctxMenu && frames[ctxMenu.kfIdx] && (
        <KfContextMenu x={ctxMenu.x} y={ctxMenu.y}
          kf={frames[ctxMenu.kfIdx]} kfIdx={ctxMenu.kfIdx}
          trackName={name} onClose={() => setCtxMenu(null)} />
      )}
    </div>
  )
}

// ── TriggerRow ────────────────────────────────────────────────────────────
function TriggerRow({ index, selTrig, onSelTrig }: {
  index: number; selTrig: number | null; onSelTrig: (i: number | null) => void
}) {
  const { path, updateTrigger, removeTrigger, hoveredBehavior, setHoveredBehavior } = useStore()
  const tr        = path.triggers[index]
  const color     = triggerColor(tr.event.type)
  const isSel     = selTrig === index
  const isHovered = hoveredBehavior?.type === 'trigger' && hoveredBehavior.index === index

  function setT(t: number) { updateTrigger(index, { ...tr, t: Math.max(0, Math.min(1, t)) }) }
  function setType(type: TriggerType) { updateTrigger(index, { ...tr, event: defaultEvent(type) }) }

  return (
    <div className={`bpanel-trigger-group${isHovered ? ' hovered' : ''}`}
      onMouseEnter={() => setHoveredBehavior({ type: 'trigger', index })}
      onMouseLeave={() => setHoveredBehavior(null)}>
      <div className={`bpanel-trigger-row${isSel ? ' selected' : ''}`}
        onClick={() => onSelTrig(isSel ? null : index)}>
        <span className="bpanel-trigger-t" style={{ color }}>{tr.t.toFixed(3)}</span>
        <span className="bpanel-trigger-type">{tr.event.type}</span>
        <span className="bpanel-trigger-val">{triggerSummary(tr.event)}</span>
        <button className="bp-icon-btn" title="Remove trigger"
          onClick={e => { e.stopPropagation(); removeTrigger(index); onSelTrig(null) }}>×</button>
      </div>
      {isSel && (
        <div className="bpanel-active-edit" style={{ borderTop: '1px solid var(--border2)', flexWrap: 'wrap' }}>
          <span className="bp-label">pos</span>
          <input type="range" className="bp-range" min={0} max={1} step={0.001}
            value={tr.t} onChange={e => setT(parseFloat(e.target.value))} />
          <NumInput value={tr.t} step={0.01} min={0} max={1} commit={setT}
            className="bp-num bp-num-t" />
          <span className="bp-label">type</span>
          <select className="bp-select" value={tr.event.type}
            onChange={e => setType(e.target.value as TriggerType)}>
            {TRIGGER_TYPES.map(t => <option key={t}>{t}</option>)}
          </select>
          <TriggerValueEditor event={tr.event}
            onChange={ev => updateTrigger(index, { ...tr, event: ev })} />
        </div>
      )}
    </div>
  )
}

// ── AddMenu ───────────────────────────────────────────────────────────────
function AddMenu({ onClose, animFrac }: { onClose: () => void; animFrac: number }) {
  const { path, addKeyframe, addTrigger } = useStore()
  const [customName, setCustomName] = useState('')
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const h = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) onClose() }
    setTimeout(() => document.addEventListener('mousedown', h), 0)
    return () => document.removeEventListener('mousedown', h)
  }, [onClose])

  function addTrack(name: string) {
    if (!name.trim()) return
    const existing = path.tracks[name] ?? []
    if (!existing.some(kf => Math.abs(kf.t - animFrac) < 0.01))
      addKeyframe(name, { t: animFrac, value: defaultTrackValue(name), ease: defaultTrackEasing(name) })
    onClose()
  }

  return (
    <div ref={ref} className="bp-add-menu">
      <div className="bp-add-section">TRACKS</div>
      {KNOWN_TRACKS.map(name => (
        <button key={name} className="bp-add-item"
          style={{ color: trackColor(name) }} onClick={() => addTrack(name)}>{name}</button>
      ))}
      <div className="bp-add-custom">
        <input className="bp-text" placeholder="custom name…" value={customName}
          onChange={e => setCustomName(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') addTrack(customName) }} />
        <button className="bp-add-item" onClick={() => addTrack(customName)}>+</button>
      </div>
      <div className="bp-add-section" style={{ marginTop: 6 }}>EVENTS</div>
      {TRIGGER_TYPES.map(type => (
        <button key={type} className="bp-add-item"
          style={{ color: triggerColor(type) }}
          onClick={() => { addTrigger({ t: animFrac, event: defaultEvent(type) }); onClose() }}>
          {type}
        </button>
      ))}
    </div>
  )
}

// ── BehaviorsPanel ────────────────────────────────────────────────────────
export function BehaviorsPanel() {
  const { path, animT, setActiveBehaviorTrack } = useStore()
  const [selKf,    setSelKf]    = useState<{ track: string; idx: number } | null>(null)
  const [selTrig,  setSelTrig]  = useState<number | null>(null)
  const [selTrack, setSelTrack] = useState<string | null>(null)
  const [addOpen,  setAddOpen]  = useState(false)

  const nSegs    = path.closed ? path.wps.length : Math.max(path.wps.length - 1, 1)
  const animFrac = nSegs > 0 ? Math.max(0, Math.min(1, (animT % nSegs) / nSegs)) : 0

  // Stable ref so J/K/I handler always sees current selKf without re-binding the listener
  const selKfRef = useRef(selKf)
  selKfRef.current = selKf

  // ── J / K / I — keyframe navigation and insert (After Effects convention) ──
  // Mounted only while BehaviorsPanel is on screen, so no behaviorsOpen guard needed.
  useEffect(() => {
    const fn = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
      const s   = useStore.getState()
      const ns  = s.path.closed ? s.path.wps.length : Math.max(s.path.wps.length - 1, 1)

      if (e.key === 'j' || e.key === 'J') {
        e.preventDefault()
        // Collect all unique keyframe parameter fractions across every track + trigger
        const allT = [...new Set([
          ...Object.values(s.path.tracks).flatMap(tr => tr.map(kf => kf.t)),
          ...s.path.triggers.map(tr => tr.t),
        ])].sort((a, b) => a - b)
        const cur  = Math.max(0, Math.min(1, s.animT / ns))
        const prev = [...allT].reverse().find(t => t < cur - 0.0005)
        if (prev !== undefined) s.setAnimT(prev * ns)

      } else if (e.key === 'k' || e.key === 'K') {
        e.preventDefault()
        const allT = [...new Set([
          ...Object.values(s.path.tracks).flatMap(tr => tr.map(kf => kf.t)),
          ...s.path.triggers.map(tr => tr.t),
        ])].sort((a, b) => a - b)
        const cur  = Math.max(0, Math.min(1, s.animT / ns))
        const next = allT.find(t => t > cur + 0.0005)
        if (next !== undefined) s.setAnimT(next * ns)

      } else if (e.key === 'i' || e.key === 'I') {
        e.preventDefault()
        const sk = selKfRef.current
        if (!sk) return  // no active track → nothing to insert into
        const frames = s.path.tracks[sk.track] ?? []
        const t      = Math.max(0, Math.min(1, s.animT / ns))
        if (frames.some(kf => Math.abs(kf.t - t) < 0.01)) return  // already a kf nearby
        const val    = frames.length > 0 ? evalTrack(frames, t) : defaultTrackValue(sk.track)
        s.addKeyframe(sk.track, { t, value: val, ease: defaultTrackEasing(sk.track) })
      }
    }
    window.addEventListener('keydown', fn)
    return () => window.removeEventListener('keydown', fn)
  }, [])  // mount/unmount only — reads live state via getState() and selKfRef

  const handleSelKf = useCallback((v: { track: string; idx: number } | null) => {
    setSelKf(v); if (v) setSelTrack(v.track)
  }, [])

  function handleExpand(name: string) {
    setSelTrack(prev => {
      const next = prev === name ? null : name
      setActiveBehaviorTrack(next)
      return next
    })
    if (selKf?.track !== name) setSelKf(null)
  }

  useEffect(() => {
    if (selKf    && (!path.tracks[selKf.track] || !path.tracks[selKf.track][selKf.idx])) setSelKf(null)
    if (selTrig  !== null && !path.triggers[selTrig]) setSelTrig(null)
    if (selTrack !== null && !path.tracks[selTrack])  setSelTrack(null)
  }, [path.tracks, path.triggers, selKf, selTrig, selTrack])

  const trackNames  = Object.keys(path.tracks).sort()
  const hasTracks   = trackNames.length > 0
  const hasTriggers = path.triggers.length > 0

  return (
    <div className="bpanel-inner">
      <div className="bpanel-header">
        <span className="bpanel-title">BEHAVIORS</span>
        <div style={{ position: 'relative' }}>
          <button className="bp-add-btn" title="Add track or trigger"
            onClick={() => setAddOpen(o => !o)}>+ Add</button>
          {addOpen && <AddMenu animFrac={animFrac} onClose={() => setAddOpen(false)} />}
        </div>
      </div>

      <PathRuler />

      {!hasTracks && !hasTriggers && (
        <div className="bpanel-empty">
          No behaviors — click <strong>+ Add</strong> to create a track or trigger
        </div>
      )}

      {hasTracks && (
        <div className="bpanel-tracks">
          {trackNames.map(name => (
            <TrackRow key={name} name={name}
              selKf={selKf} onSelKf={handleSelKf}
              isExpanded={selTrack === name}
              onExpand={() => handleExpand(name)} />
          ))}
        </div>
      )}

      {hasTriggers && (
        <div className="bpanel-triggers">
          <div className="bpanel-section-header">EVENTS</div>
          {path.triggers.map((_, i) => (
            <TriggerRow key={i} index={i} selTrig={selTrig} onSelTrig={setSelTrig} />
          ))}
        </div>
      )}
    </div>
  )
}
