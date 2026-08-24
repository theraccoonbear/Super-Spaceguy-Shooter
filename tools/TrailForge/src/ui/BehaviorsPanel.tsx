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
import { useStore, EaseType, TriggerEvent, FireMode, ShieldMode, TrackKeyframe, CraftRollSegment, CraftRollLoopSeam } from '../store'
import { trackColor, triggerColor, evalTrack } from '../views/behaviorMarkers'
import { pauseAfterCheckpoint, resumeTemporal } from '../views/undoHelpers'
import { buildSpline } from '../math/spline'
import { evalCraftRoll, makeCraftRollSegment, type CraftRollEase } from '../math/craftRoll'
import type { PathData } from '../store'

// ── Constants ─────────────────────────────────────────────────────────────

const KNOWN_TRACKS = ['standoff', 'offsetAngle', 'speed', 'visible', 'engineBrightness']
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
    default:                 return 0   // standoff, offsetAngle → neutral
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
    case 'offsetAngle':      return 'smooth'    // lateral drift same
    case 'standoff':         return 'smooth'    // distance ramps same
    case 'speed':            return 'smooth'    // avoids jarring acceleration kinks
    default:                 return 'linear'
  }
}

/** Short unit/description shown in graph value labels */
function trackUnit(name: string): string {
  switch (name) {
    case 'offsetAngle': return '°'
    case 'standoff':   return 'u'
    case 'speed':      return '×'
    default:           return ''
  }
}

/** Per-track value clamps — prevents runaway values from drag overshoots. */
function trackValueLimits(name: string): { min: number; max: number } {
  switch (name) {
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
    case 'offsetAngle':      return 1
    case 'standoff':         return 0.5
    case 'speed':            return 0.05
    case 'visible':          return 1
    case 'engineBrightness': return 0.1
    default:                 return 1
  }
}

/** Arrow-button step for the inline value NumInput. */
function trackStep(name: string): number {
  switch (name) {
    case 'offsetAngle':      return 1
    case 'standoff':         return 0.1
    case 'speed':            return 0.01
    case 'visible':          return 1
    case 'engineBrightness': return 0.1
    default:                 return 0.1
  }
}

/** Decimal places to display and round to on commit. */
function trackDecimals(name: string): number {
  switch (name) {
    case 'offsetAngle':      return 0
    case 'standoff':         return 1
    case 'speed':            return 2
    case 'visible':          return 0
    case 'engineBrightness': return 1
    default:                 return 2
  }
}

// ── NumInput ──────────────────────────────────────────────────────────────
interface NumInputProps {
  value: number; step?: number; min?: number; max?: number; decimals?: number
  className?: string; title?: string; style?: CSSProperties
  commit: (n: number) => void
}
function NumInput({ value, step, min, max, decimals, className, title, style, commit }: NumInputProps) {
  const [text, setText] = useState<string | null>(null)
  // When not focused: show rounded display; when focused: raw edit string
  const display = text !== null ? text
    : decimals !== undefined ? value.toFixed(decimals) : String(value)
  function tryCommit(raw: string) {
    const n = parseFloat(raw)
    if (isNaN(n)) { setText(null); return }
    let v = min !== undefined ? Math.max(min, n) : n
    if (max !== undefined) v = Math.min(max, v)
    // Round to declared precision so floating-point noise never accumulates
    if (decimals !== undefined) {
      const f = Math.pow(10, decimals)
      v = Math.round(v * f) / f
    }
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

  const samples = buildSpline({ wps: path.wps, closed: path.closed })
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
          {/* Waypoint bars — thin ticks at each node's arc-length position */}
          {path.wps.map((_, i) => {
            const wpParamFrac = nSegs > 0 ? i / nSegs : 0
            const wpArcFrac   = paramToArc(wpParamFrac)
            // Skip endpoints at the ruler edges (they're redundant with the 0/1 labels)
            if (wpArcFrac < 0.002 || wpArcFrac > 0.998) return null
            return (
              <div key={`wp-${i}`} style={{
                position: 'absolute',
                left: `${wpArcFrac * 100}%`,
                top: 0, bottom: 0, width: 1,
                background: '#94a3b8',
                opacity: 0.35,
                pointerEvents: 'none',
              }} title={`waypoint ${i}  t=${wpParamFrac.toFixed(3)}  arc=${wpArcFrac.toFixed(3)}`} />
            )
          })}
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
          {/* CraftRoll segment spans — arc-length fraction stored directly in seg.t */}
          {(path.craftRollSegments ?? []).map(seg => (
            <div key={`cr-${seg.id}`} style={{
              position: 'absolute',
              left: `${seg.t * 100}%`,
              width: `${Math.max(seg.duration * 100, 0.3)}%`,
              top: 1, bottom: 1,
              background: seg.direction === 'cw' ? '#f97316' : '#38bdf8',
              opacity: 0.45,
              borderRadius: 1,
              pointerEvents: 'none',
            }} title={`craftRoll: ${seg.direction} ${seg.degrees}° ${seg.mode}  t=${seg.t.toFixed(3)}  len=${seg.duration.toFixed(3)}`} />
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

// ── CraftRoll colors (used by PathRuler + CraftRollTrack) ────────────────
const CR_CW  = '#f97316'   // orange — clockwise
const CR_CCW = '#38bdf8'   // blue   — counter-clockwise

// ── CRSegContextMenu ──────────────────────────────────────────────────────
function CRSegContextMenu({ x, y, onClose, onAdd, onDelete }: {
  x: number; y: number; onClose: () => void; onAdd?: () => void; onDelete?: () => void
}) {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const h = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) onClose() }
    setTimeout(() => document.addEventListener('mousedown', h), 0)
    return () => document.removeEventListener('mousedown', h)
  }, [onClose])
  return (
    <div ref={ref} className="bp-ctx-menu" style={{ left: x, top: y }}>
      {onAdd && (
        <button className="bp-ctx-item" onClick={() => { onAdd(); onClose() }}>Add roll segment here</button>
      )}
      {onDelete && (
        <button className="bp-ctx-item bp-ctx-danger" onClick={() => { onDelete(); onClose() }}>Delete segment</button>
      )}
    </div>
  )
}

// ── CraftRollTrack ────────────────────────────────────────────────────────
// Segment-based roll authoring — always shown in the behaviors panel.
// Each segment = one roll action (CW/CCW, relative/absolute, degrees, ease, duration).
// Blocks span t→t+duration; body drag = move; edge drags = resize.

type CRDragMode = 'body' | 'left-edge' | 'right-edge' | 'seam-tail-inner' | 'seam-head-inner'
interface CRDrag {
  id:             string    // segment id, or '__seam__' for seam drags
  mode:           CRDragMode
  startX:         number
  startT:         number    // segment t at drag start
  startDur:       number    // segment duration at drag start
  startTailFrac?: number    // seam tailFrac at drag start
  startHeadFrac?: number    // seam headFrac at drag start
}
type CRCtxMenu =
  | { mode: 'add'; x: number; y: number; t: number }
  | { mode: 'seg'; x: number; y: number; id: string }

function CraftRollTrack({ selSegId, onSelSegId, isExpanded, onExpand }: {
  selSegId:   string | null
  onSelSegId: (id: string | null) => void
  isExpanded: boolean
  onExpand:   () => void
}) {
  const { path, animT, mutedTracks, toggleMutedTrack,
          addCraftRollSegment, updateCraftRollSegment, removeCraftRollSegment,
          setCraftRollSegments, setLoopSeam, updateLoopSeam } = useStore()
  const segments = path.craftRollSegments ?? []
  const loopSeam = path.craftRollLoopSeam
  const isMuted  = !!mutedTracks['craftRoll']
  const arcTable = useMemo(() => makeArcTable(path), [path])
  const rulerRef = useRef<HTMLDivElement>(null)
  const graphRef = useRef<HTMLDivElement>(null)
  const drag     = useRef<CRDrag | null>(null)
  const [crCtxMenu,    setCrCtxMenu]    = useState<CRCtxMenu | null>(null)
  const [seamSelected, setSeamSelected] = useState(false)

  const nSegs    = path.closed ? path.wps.length : Math.max(path.wps.length - 1, 1)
  const animFrac = nSegs > 0 ? Math.max(0, Math.min(1, (animT % nSegs) / nSegs)) : 0
  const sel      = segments.find(s => s.id === selSegId) ?? null

  function rulerFrac(clientX: number): number {
    const r = rulerRef.current?.getBoundingClientRect()
    return r ? Math.max(0, Math.min(1, (clientX - r.left) / r.width)) : 0
  }

  function addSegmentAt(t: number) {
    const seg = makeCraftRollSegment(t)
    addCraftRollSegment(seg)
    onSelSegId(seg.id)
    if (!isExpanded) onExpand()
  }

  // Stable ref so the keydown closure always calls the current addSegmentAt
  const addAtRef = useRef(() => {})
  addAtRef.current = () => addSegmentAt(animFrac)

  // 'N' when this track is expanded → add segment at current playhead
  useEffect(() => {
    if (!isExpanded) return
    const fn = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
      if (e.key === 'n' || e.key === 'N') { e.preventDefault(); addAtRef.current() }
    }
    window.addEventListener('keydown', fn)
    return () => window.removeEventListener('keydown', fn)
  }, [isExpanded])

  function handleBlockPointerDown(e: React.PointerEvent<HTMLDivElement>, seg: CraftRollSegment, mode: CRDragMode) {
    e.stopPropagation()
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    pauseAfterCheckpoint()
    drag.current = { id: seg.id, mode, startX: e.clientX, startT: seg.t, startDur: seg.duration }
    onSelSegId(seg.id); setSeamSelected(false)
    if (!isExpanded) onExpand()
  }

  function handleSeamEdgePointerDown(e: React.PointerEvent<HTMLDivElement>, mode: 'seam-tail-inner' | 'seam-head-inner') {
    if (!loopSeam) return
    e.stopPropagation()
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    pauseAfterCheckpoint()
    drag.current = {
      id: '__seam__', mode, startX: e.clientX, startT: 0, startDur: 0,
      startTailFrac: loopSeam.tailFrac, startHeadFrac: loopSeam.headFrac,
    }
    onSelSegId(null); setSeamSelected(true)
    if (!isExpanded) onExpand()
  }

  function handleRulerPointerMove(e: React.PointerEvent<HTMLDivElement>) {
    const d = drag.current
    if (!d || !rulerRef.current) return
    const r  = rulerRef.current.getBoundingClientRect()
    const df = (e.clientX - d.startX) / r.width

    if (d.mode === 'seam-tail-inner') {
      // tail inner edge is at (1 - tailFrac); drag left → bigger tail → df negative → tailFrac = start - df
      updateLoopSeam({ tailFrac: Math.max(0.01, Math.min(0.45, (d.startTailFrac ?? 0) - df)) })
      return
    }
    if (d.mode === 'seam-head-inner') {
      // head inner edge is at headFrac; drag right → bigger head → df positive → headFrac = start + df
      updateLoopSeam({ headFrac: Math.max(0.01, Math.min(0.45, (d.startHeadFrac ?? 0) + df)) })
      return
    }

    const seg = segments.find(s => s.id === d.id)
    if (!seg) return
    switch (d.mode) {
      case 'body':
        updateCraftRollSegment(d.id, { t: Math.max(0, Math.min(1 - seg.duration, d.startT + df)) })
        break
      case 'right-edge':
        updateCraftRollSegment(d.id, { duration: Math.max(0.01, Math.min(1 - seg.t, d.startDur + df)) })
        break
      case 'left-edge': {
        const newT   = Math.max(0, Math.min(seg.t + seg.duration - 0.01, d.startT + df))
        const newDur = Math.max(0.01, d.startT + d.startDur - newT)
        updateCraftRollSegment(d.id, { t: newT, duration: newDur })
        break
      }
    }
  }

  function handleRulerPointerUp() {
    if (drag.current) { drag.current = null; resumeTemporal() }
  }

  // Graph: sample the accumulated angle curve
  const STEPS = 80; const VW = 200; const VH = 52; const PAD = 4
  const angles = useMemo(
    () => Array.from({ length: STEPS + 1 }, (_, i) => evalCraftRoll(segments, i / STEPS, loopSeam)),
    [segments, loopSeam]
  )
  const maxAbs = Math.max(360, ...angles.map(Math.abs))
  const toGX   = (f: number) => f * VW
  const toGY   = (a: number) => VH / 2 - (a / maxAbs) * (VH / 2 - PAD)
  const linePts = segments.length > 0
    ? angles.map((a, i) => `${toGX(i / STEPS).toFixed(1)},${toGY(a).toFixed(1)}`).join(' ')
    : ''

  function update(patch: Partial<CraftRollSegment>) {
    if (!sel) return
    updateCraftRollSegment(sel.id, patch)
  }

  return (
    <div className={`bpanel-track-group${isExpanded ? ' active' : ''}${isMuted ? ' muted' : ''}`}>

      {/* Compact row */}
      <div className="bpanel-track-row" style={{ cursor: isExpanded ? 'default' : 'pointer' }}
        onClick={isExpanded ? undefined : onExpand}>

        <span className="bpanel-track-label" style={{ color: CR_CW }}
          onClick={e => { e.stopPropagation(); onExpand() }}>
          <span className="bpanel-mode-ind">{isExpanded ? '▼' : '▶'}</span>
          craftRoll
        </span>

        {/* Ruler with draggable blocks — right-click empty area to add */}
        <div ref={rulerRef} className="bpanel-track-bar"
          style={{ position: 'relative', cursor: 'default' }}
          onContextMenu={e => {
            e.preventDefault()
            if (drag.current) return
            const t = rulerFrac(e.clientX)
            const onSeg = segments.some(s => t >= s.t && t <= s.t + s.duration)
            if (!onSeg) setCrCtxMenu({ mode: 'add', x: e.clientX, y: e.clientY, t })
          }}
          onPointerMove={handleRulerPointerMove}
          onPointerUp={handleRulerPointerUp}>
          <div className="bpanel-track-baseline" />
          {segments.map(seg => {
            const col   = seg.direction === 'cw' ? CR_CW : CR_CCW
            const isSel = seg.id === selSegId
            return (
              <React.Fragment key={seg.id}>
                {/* Left resize handle */}
                <div style={{
                  position: 'absolute', left: `${seg.t * 100}%`,
                  top: 1, bottom: 1, width: 6,
                  cursor: 'ew-resize', zIndex: 3,
                  background: 'transparent',
                }}
                  onPointerDown={e => { e.stopPropagation(); handleBlockPointerDown(e, seg, 'left-edge') }}
                  onClick={e => e.stopPropagation()} />
                {/* Block body */}
                <div style={{
                  position: 'absolute',
                  left: `${seg.t * 100}%`,
                  width: `${Math.max(seg.duration * 100, 0.5)}%`,
                  top: 2, bottom: 2,
                  background: col,
                  opacity: isSel ? 0.9 : 0.5,
                  borderRadius: 2,
                  outline: isSel ? `1.5px solid ${col}` : 'none',
                  cursor: 'grab',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  overflow: 'hidden',
                  fontSize: 9, color: '#fff',
                  userSelect: 'none',
                  boxSizing: 'border-box',
                }}
                  onPointerDown={e => { e.stopPropagation(); handleBlockPointerDown(e, seg, 'body') }}
                  onClick={e => { e.stopPropagation(); onSelSegId(seg.id); if (!isExpanded) onExpand() }}
                  onContextMenu={e => { e.preventDefault(); e.stopPropagation(); setCrCtxMenu({ mode: 'seg', x: e.clientX, y: e.clientY, id: seg.id }) }}>
                  {seg.direction === 'cw' ? '↻' : '↺'}
                  {seg.mode === 'absolute' && <span style={{ fontSize: 7, marginLeft: 1, opacity: 0.8 }}>A</span>}
                </div>
                {/* Right resize handle */}
                <div style={{
                  position: 'absolute',
                  left: `calc(${(seg.t + seg.duration) * 100}% - 6px)`,
                  top: 1, bottom: 1, width: 6,
                  cursor: 'ew-resize', zIndex: 3,
                  background: 'transparent',
                }}
                  onPointerDown={e => { e.stopPropagation(); handleBlockPointerDown(e, seg, 'right-edge') }}
                  onClick={e => e.stopPropagation()} />
              </React.Fragment>
            )
          })}
          {segments.length === 0 && !loopSeam && (
            <div style={{
              position: 'absolute', inset: 0, display: 'flex',
              alignItems: 'center', justifyContent: 'center',
              fontSize: 10, color: 'rgba(255,255,255,0.2)',
              pointerEvents: 'none', userSelect: 'none',
            }}>right-click to add · N to add at playhead</div>
          )}

          {/* ── Loop seam bands — two violet spans pinned at the loop point ── */}
          {loopSeam && path.closed && (() => {
            const { tailFrac, headFrac } = loopSeam
            const isSeamSel = seamSelected
            const seamColor = '#a78bfa'
            const seamOpacity = isSeamSel ? 0.85 : 0.5
            return (
              <>
                {/* Tail band: [1−tailFrac, 1] — right end of ruler */}
                {tailFrac > 0 && (
                  <React.Fragment>
                    {/* Body — clickable to select */}
                    <div style={{
                      position: 'absolute',
                      left: `${(1 - tailFrac) * 100}%`, right: 0,
                      top: 2, bottom: 2,
                      background: seamColor, opacity: seamOpacity,
                      borderRadius: '2px 0 0 2px',
                      cursor: 'default',
                      userSelect: 'none',
                      outline: isSeamSel ? `1.5px solid ${seamColor}` : 'none',
                      boxSizing: 'border-box',
                    }}
                      onClick={e => { e.stopPropagation(); setSeamSelected(true); onSelSegId(null); if (!isExpanded) onExpand() }}
                      title={`loop seam tail  arc [${(1 - tailFrac).toFixed(3)} → 1]`} />
                    {/* Draggable inner edge */}
                    <div style={{
                      position: 'absolute',
                      left: `calc(${(1 - tailFrac) * 100}% - 4px)`,
                      top: 0, bottom: 0, width: 8,
                      cursor: 'ew-resize', zIndex: 4,
                      background: 'transparent',
                    }}
                      onPointerDown={e => handleSeamEdgePointerDown(e, 'seam-tail-inner')}
                      onClick={e => e.stopPropagation()} />
                  </React.Fragment>
                )}
                {/* Head band: [0, headFrac] — left end of ruler */}
                {headFrac > 0 && (
                  <React.Fragment>
                    {/* Body — clickable to select */}
                    <div style={{
                      position: 'absolute',
                      left: 0, width: `${headFrac * 100}%`,
                      top: 2, bottom: 2,
                      background: seamColor, opacity: seamOpacity,
                      borderRadius: '0 2px 2px 0',
                      cursor: 'default',
                      userSelect: 'none',
                      outline: isSeamSel ? `1.5px solid ${seamColor}` : 'none',
                      boxSizing: 'border-box',
                    }}
                      onClick={e => { e.stopPropagation(); setSeamSelected(true); onSelSegId(null); if (!isExpanded) onExpand() }}
                      title={`loop seam head  arc [0 → ${headFrac.toFixed(3)}]`} />
                    {/* Draggable inner edge */}
                    <div style={{
                      position: 'absolute',
                      left: `calc(${headFrac * 100}% - 4px)`,
                      top: 0, bottom: 0, width: 8,
                      cursor: 'ew-resize', zIndex: 4,
                      background: 'transparent',
                    }}
                      onPointerDown={e => handleSeamEdgePointerDown(e, 'seam-head-inner')}
                      onClick={e => e.stopPropagation()} />
                  </React.Fragment>
                )}
              </>
            )
          })()}
        </div>

        <div className="bpanel-track-right">
          <button className="bp-eye-btn"
            style={{ color: isMuted ? 'var(--text-faint)' : CR_CW, opacity: isMuted ? 0.45 : 0.75 }}
            title={isMuted ? 'Unmute craft roll' : 'Mute craft roll'}
            onClick={e => { e.stopPropagation(); toggleMutedTrack('craftRoll') }}>
            {isMuted ? '○' : '◉'}
          </button>
          <span className="bpanel-track-meta">{segments.length} seg</span>
          {path.closed && !loopSeam && (
            <button className="bp-seg-btn" title="Add loop seam — smooths the roll angle gap at the loop point"
              style={{ color: '#a78bfa', padding: '0 4px', fontSize: 10 }}
              onClick={e => {
                e.stopPropagation()
                setLoopSeam({ tailFrac: 0.05, headFrac: 0.05, targetAngle: 0, ease: 'in-out' })
                setSeamSelected(true); if (!isExpanded) onExpand()
              }}>⟲</button>
          )}
          {segments.length > 0 && (
            <button className="bp-icon-btn danger" title="Remove all roll segments (Ctrl+Z to undo)"
              onClick={e => {
                e.stopPropagation()
                if (!window.confirm(`Remove all ${segments.length} roll segment${segments.length !== 1 ? 's' : ''}?\nCan be undone with Ctrl+Z.`)) return
                setCraftRollSegments([]); onSelSegId(null)
              }}>×</button>
          )}
        </div>
      </div>

      {crCtxMenu?.mode === 'add' && (
        <CRSegContextMenu x={crCtxMenu.x} y={crCtxMenu.y}
          onClose={() => setCrCtxMenu(null)}
          onAdd={() => { addSegmentAt(crCtxMenu.t) }} />
      )}
      {crCtxMenu?.mode === 'seg' && (
        <CRSegContextMenu x={crCtxMenu.x} y={crCtxMenu.y}
          onClose={() => setCrCtxMenu(null)}
          onDelete={() => { removeCraftRollSegment(crCtxMenu.id); if (selSegId === crCtxMenu.id) onSelSegId(null) }} />
      )}

      {/* Expanded panel */}
      {isExpanded && (
        <div className="bpanel-active-panel">
          <div className="bpanel-active-edit">
            {seamSelected && loopSeam ? (
              // ── Seam selected: show seam controls ──────────────────────────
              <>
                <span style={{ color: '#a78bfa', fontWeight: 600, fontSize: 11 }}>⟲</span>
                <span className="bp-label">tail</span>
                <NumInput value={loopSeam.tailFrac} step={0.005} min={0.005} max={0.45} decimals={3}
                  commit={v => updateLoopSeam({ tailFrac: v })} className="bp-num bp-num-t"
                  title="Tail: arc fraction consumed before the loop point (right band)" />
                <span className="bp-label">head</span>
                <NumInput value={loopSeam.headFrac} step={0.005} min={0.005} max={0.45} decimals={3}
                  commit={v => updateLoopSeam({ headFrac: v })} className="bp-num bp-num-t"
                  title="Head: arc fraction consumed after the loop point (left band)" />
                <span className="bp-label">target°</span>
                <NumInput value={loopSeam.targetAngle} step={1} min={-3600} max={3600} decimals={0}
                  commit={v => updateLoopSeam({ targetAngle: v })} className="bp-num"
                  title="Angle (deg) to ease toward at the loop point" />
                <span className="bp-label">ease</span>
                <select className="bp-select" value={loopSeam.ease}
                  onChange={e => updateLoopSeam({ ease: e.target.value as CraftRollLoopSeam['ease'] })}>
                  <option value="linear">linear</option>
                  <option value="in">ease in</option>
                  <option value="out">ease out</option>
                  <option value="in-out">ease in/out</option>
                </select>
                <button className="bp-icon-btn danger" title="Remove loop seam"
                  onClick={() => { setLoopSeam(null); setSeamSelected(false) }}>Del</button>
              </>
            ) : sel ? (
              // ── Segment selected: show segment controls ─────────────────────
              <>
                <span className="bp-label">dir</span>
                <button className={`bp-seg-btn${sel.direction === 'cw' ? ' active' : ''}`}
                  style={{ color: CR_CW }} onClick={() => update({ direction: 'cw' })}>↻ CW</button>
                <button className={`bp-seg-btn${sel.direction === 'ccw' ? ' active' : ''}`}
                  style={{ color: CR_CCW }} onClick={() => update({ direction: 'ccw' })}>↺ CCW</button>

                <span className="bp-label">mode</span>
                <button className={`bp-seg-btn${sel.mode === 'relative' ? ' active' : ''}`}
                  onClick={() => update({ mode: 'relative' })}>REL</button>
                <button className={`bp-seg-btn${sel.mode === 'absolute' ? ' active' : ''}`}
                  onClick={() => update({ mode: 'absolute' })}>ABS</button>

                <span className="bp-label">°</span>
                <NumInput value={sel.degrees} step={1}
                  min={sel.mode === 'absolute' ? 0 : 1}
                  max={sel.mode === 'absolute' ? 360 : 3600}
                  decimals={0}
                  commit={v => update({ degrees: v })} className="bp-num"
                  title={sel.mode === 'absolute' ? 'Target heading 0–360° in path-following frame' : 'Rotation amount 1–3600° in specified direction'} />

                <span className="bp-label">ease</span>
                <select className="bp-select" value={sel.ease}
                  onChange={e => update({ ease: e.target.value as CraftRollEase })}>
                  <option value="linear">linear</option>
                  <option value="in">ease in</option>
                  <option value="out">ease out</option>
                  <option value="in-out">ease in/out</option>
                </select>

                <span className="bp-label">t</span>
                <NumInput value={sel.t} step={0.005} min={0} max={0.99} decimals={3}
                  commit={v => update({ t: v })} className="bp-num bp-num-t"
                  title="Arc-length fraction where this roll begins (0–1)." />

                <span className="bp-label">len</span>
                <NumInput value={sel.duration} step={0.01} min={0.01} max={1} decimals={2}
                  commit={v => update({ duration: v })} className="bp-num bp-num-t"
                  title="Arc-length duration of this roll." />

                <button className="bp-icon-btn danger"
                  onClick={() => { removeCraftRollSegment(sel.id); onSelSegId(null) }}>Del</button>
              </>
            ) : (
              <span className="bp-hint">
                {segments.length === 0 && !loopSeam
                  ? 'Right-click to add a roll segment'
                  : loopSeam && !segments.length
                  ? 'Click ⟲ seam bands to edit · right-click to add segments'
                  : 'Click a block to select · drag body to move · drag edges to resize'}
              </span>
            )}
          </div>

          {/* Accumulated angle graph */}
          <div ref={graphRef} className="bpanel-active-graph" style={{ position: 'relative' }}>
            <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}
              viewBox={`0 0 ${VW} ${VH}`} preserveAspectRatio="none">
              <line x1={0} y1={VH/2} x2={VW} y2={VH/2}
                stroke="rgba(255,255,255,0.15)" strokeWidth="1" strokeDasharray="3 4" />
              {segments.map(seg => (
                <rect key={seg.id} x={seg.t * VW} y={0}
                  width={Math.max(1, seg.duration * VW)} height={VH}
                  fill={seg.direction === 'cw' ? CR_CW : CR_CCW} opacity={0.07} />
              ))}
              {linePts && (
                <polyline points={linePts} fill="none" stroke={CR_CW} strokeWidth="2" opacity="0.75" />
              )}
              <line x1={arcTable.paramToArc(animFrac) * VW} y1={0}
                x2={arcTable.paramToArc(animFrac) * VW} y2={VH}
                stroke="rgba(255,255,255,0.4)" strokeWidth="1" />
            </svg>
            {segments.length === 0 && (
              <div style={{
                position: 'absolute', inset: 0, display: 'flex',
                alignItems: 'center', justifyContent: 'center',
                fontSize: 10, color: 'rgba(255,255,255,0.2)',
                pointerEvents: 'none',
              }}>accumulated roll angle</div>
            )}
          </div>

        </div>
      )}
    </div>
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
                  step={trackStep(name)} decimals={trackDecimals(name)}
                  min={trackValueLimits(name).min} max={trackValueLimits(name).max}
                  commit={commitValue} className="bp-num"
                  title={name === 'speed' ? 'Speed multiplier (1 = path default speed)' : undefined} />
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
                  ? `Click graph to add — then set value above${name === 'speed' ? ' (1=default)' : ''}`
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
  const { path, addKeyframe, addTrigger, addCraftRollSegment } = useStore()
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
      {/* craftRoll is segment-based — adds a default segment and shows the track */}
      <button className="bp-add-item" style={{ color: CR_CW }}
        onClick={() => { addCraftRollSegment(makeCraftRollSegment(animFrac)); onClose() }}>
        craftRoll
      </button>
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
  const [selKf,      setSelKf]      = useState<{ track: string; idx: number } | null>(null)
  const [selTrig,    setSelTrig]    = useState<number | null>(null)
  const [selTrack,   setSelTrack]   = useState<string | null>(null)
  const [addOpen,    setAddOpen]    = useState(false)
  const [selSegId,   setSelSegId]   = useState<string | null>(null)
  const [crExpanded, setCrExpanded] = useState(false)

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
    if (selSegId !== null && !(path.craftRollSegments ?? []).some(s => s.id === selSegId)) setSelSegId(null)
    // Auto-collapse craftRoll when all segments are removed — hides the row, same as other tracks
    if ((path.craftRollSegments ?? []).length === 0) setCrExpanded(false)
  }, [path.tracks, path.triggers, path.craftRollSegments, selKf, selTrig, selTrack, selSegId])

  const trackNames    = Object.keys(path.tracks).sort()
  const hasTracks     = trackNames.length > 0
  const hasTriggers   = path.triggers.length > 0
  const hasCraftRoll  = (path.craftRollSegments ?? []).length > 0

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

      {/* craftRoll — only shown when segments exist; add via + Add → craftRoll */}
      {hasCraftRoll && (
        <div className="bpanel-tracks">
          <CraftRollTrack
            selSegId={selSegId} onSelSegId={setSelSegId}
            isExpanded={crExpanded} onExpand={() => setCrExpanded(e => !e)} />
        </div>
      )}

      {!hasCraftRoll && !hasTracks && !hasTriggers && (
        <div className="bpanel-empty">
          Click <strong>+ Add</strong> to add behavior tracks or trigger events
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
