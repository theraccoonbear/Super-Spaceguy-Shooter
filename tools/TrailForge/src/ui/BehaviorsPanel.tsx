// Behaviors panel — two categories of continuous/discrete behavior, one
// shared interaction contract each:
//
// SEGMENT TRACKS (craftRoll + every scalar track — standoff, speed,
//   offsetAngle, visible, engineBrightness): span-based. Each item is
//   [t, t+duration) with an ease-toward-a-value transition; the value holds
//   between segments. Add via right-click empty ruler OR 'N' when expanded
//   (never click-to-add — accidental clicks must never create segments).
//   Drag body to move, drag edges to resize. Value is edited via NumInput
//   only, never by dragging. CraftRollTrack is the reference implementation;
//   ScalarSegmentTrack is the identical contract generalized over a track
//   name. Both support an optional loop seam (⟲) that eases the value back
//   toward a target across the closed-path wrap point.
//
// DISCRETE TRIGGERS (fireMode, weapon, shieldMode, invuln, phase, sound,
//   custom): instant, fire-once events at a single t. One shared
//   TriggerTypeRow component for every type — only the value-editor widget
//   differs per type.
//
// Alignment guarantee: ruler and track rows use the same CSS grid columns
//   (--bpanel-label-w | 1fr | --bpanel-right-w). No arithmetic, no drift.

import React, { useRef, useState, useEffect, useMemo, type CSSProperties } from 'react'
import { useStore, TriggerEvent, FireMode, ShieldMode, ScalarSegment, CraftRollSegment, CraftRollLoopSeam } from '../store'
import { trackColor, triggerColor } from '../views/behaviorMarkers'
import { pauseAfterCheckpoint, resumeTemporal } from '../views/undoHelpers'
import { makeArcTable } from '../math/spline'
import { evalCraftRoll, makeCraftRollSegment, type CraftRollEase } from '../math/craftRoll'
import { evalScalarSegments, makeScalarSegment, type SegEase } from '../math/segmentTrack'

// ── Constants ─────────────────────────────────────────────────────────────

const SCALAR_TRACK_NAMES = ['standoff', 'offsetAngle', 'speed', 'visible', 'engineBrightness']

const TRIGGER_TYPES = ['fireMode', 'weapon', 'shieldMode', 'invuln', 'phase', 'sound', 'custom'] as const
type TriggerType = typeof TRIGGER_TYPES[number]

/** Sensible default value for a new segment in a named track.
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

/** Default easing for a new segment in a named track — every continuous
 *  track shares craftRoll's ease vocabulary (SegEase). */
function defaultTrackEasing(name: string): SegEase {
  switch (name) {
    case 'visible': return 'linear'   // hard toggle — snappier default
    default:        return 'in-out'   // matches craftRoll's own segment default
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

// ── PathRuler ─────────────────────────────────────────────────────────────
// Uses same grid columns as track rows via class .bpanel-ruler-row.
// Positions are displayed in arc-length fraction space so they match the
// track rows' own rulers pixel-for-pixel. Segment-track t is already
// arc-length (same convention as craftRoll) — no paramToArc conversion.
function PathRuler() {
  const { path, animT, setAnimT, selected } = useStore()
  const barRef    = useRef<HTMLDivElement>(null)
  const scrubbing = useRef(false)

  const nSegs    = path.closed ? path.wps.length : Math.max(path.wps.length - 1, 1)
  const arcTable = useMemo(() => makeArcTable(path.wps, path.closed), [path])
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

  const segmentTrackNames = Object.keys(path.segmentTracks).sort()

  return (
    <div className="bpanel-ruler-wrap">
      <div className="bpanel-ruler-row bpanel-ruler-numbers-row">
        <div>{/* left spacer — grid col 1 */}</div>
        <div className="bpanel-ruler-numbers">
          {path.wps.map((_, i) => {
            const wpParamFrac = nSegs > 0 ? i / nSegs : 0
            const wpArcFrac   = paramToArc(wpParamFrac)
            if (wpArcFrac < 0.002 || wpArcFrac > 0.998) return null
            return (
              <span key={`wpn-${i}`}
                className={i === selected ? 'bpanel-ruler-num sel' : 'bpanel-ruler-num'}
                style={{ left: `${wpArcFrac * 100}%` }}>{i}</span>
            )
          })}
        </div>
        <div>{/* right spacer — grid col 3 */}</div>
      </div>
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
            const isSel = i === selected
            return (
              <div key={`wp-${i}`} style={{
                position: 'absolute',
                left: `${wpArcFrac * 100}%`,
                top: 0, bottom: 0, width: isSel ? 2 : 1,
                background: isSel ? '#fbbf24' : '#94a3b8',
                opacity: isSel ? 1 : 0.35,
                pointerEvents: 'none',
              }} title={`waypoint ${i}  t=${wpParamFrac.toFixed(3)}  arc=${wpArcFrac.toFixed(3)}`} />
            )
          })}
          {/* Segment-track spans — arc-length fraction stored directly in seg.t, same as craftRoll */}
          {segmentTrackNames.flatMap(name =>
            (path.segmentTracks[name] ?? []).map(seg => (
              <div key={`${name}-${seg.id}`} style={{
                position: 'absolute',
                left: `${seg.t * 100}%`,
                width: `${Math.max(seg.duration * 100, 0.3)}%`,
                top: 1, bottom: 1,
                background: trackColor(name),
                opacity: 0.45,
                borderRadius: 1,
                pointerEvents: 'none',
              }} title={`${name}: ${seg.mode}  t=${seg.t.toFixed(3)}  len=${seg.duration.toFixed(3)}  val=${seg.value}`} />
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

// ── CraftRoll colors (used by PathRuler + CraftRollTrack) ────────────────
const CR_CW  = '#f97316'   // orange — clockwise
const CR_CCW = '#38bdf8'   // blue   — counter-clockwise

// ── CRSegContextMenu ──────────────────────────────────────────────────────
// Shared right-click menu for both craftRoll segments and generic scalar
// track segments — "Add segment here" / "Delete segment".
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
        <button className="bp-ctx-item" onClick={() => { onAdd(); onClose() }}>Add segment here</button>
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
//
// This is the REFERENCE interaction contract for every segment track —
// ScalarSegmentTrack below mirrors it exactly, generalized over a track
// name. Do not change one without checking the other.

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
  const arcTable = useMemo(() => makeArcTable(path.wps, path.closed), [path])
  const rulerRef = useRef<HTMLDivElement>(null)
  const graphRef = useRef<HTMLDivElement>(null)
  const drag     = useRef<CRDrag | null>(null)
  const [crCtxMenu,    setCrCtxMenu]    = useState<CRCtxMenu | null>(null)
  const [seamSelected, setSeamSelected] = useState(false)

  const nSegs    = path.closed ? path.wps.length : Math.max(path.wps.length - 1, 1)
  const animFrac = nSegs > 0 ? Math.max(0, Math.min(1, (animT % nSegs) / nSegs)) : 0
  const liveRoll = evalCraftRoll(segments, arcTable.paramToArc(animFrac), loopSeam)
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
          <span className="bpanel-live-val">{liveRoll.toFixed(1)}°</span>
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

// ── ScalarSegmentTrack ───────────────────────────────────────────────────
// Generic segment-based track editor — same span/ease/hold/seam model and
// interaction contract as CraftRollTrack above, parameterized by track
// name. This is what makes every continuous track (standoff, speed,
// offsetAngle, visible, engineBrightness) behave identically to craftRoll
// and to each other. See CraftRollTrack's header comment for the contract;
// keep this in sync with it rather than diverging.

type SegDragMode = 'body' | 'left-edge' | 'right-edge' | 'seam-tail-inner' | 'seam-head-inner'
interface SegDrag {
  id:             string
  mode:           SegDragMode
  startX:         number
  startT:         number
  startDur:       number
  startTailFrac?: number
  startHeadFrac?: number
}
type SegCtxMenu =
  | { mode: 'add'; x: number; y: number; t: number }
  | { mode: 'seg'; x: number; y: number; id: string }

function ScalarSegmentTrack({ name, selSegId, onSelSegId, isExpanded, onExpand }: {
  name:       string
  selSegId:   string | null
  onSelSegId: (id: string | null) => void
  isExpanded: boolean
  onExpand:   () => void
}) {
  const { path, animT, mutedTracks, toggleMutedTrack,
          addSegment, updateSegment, removeSegment,
          setSegmentTrack, setSegmentLoopSeam, updateSegmentLoopSeam } = useStore()
  const segments = path.segmentTracks[name] ?? []
  const loopSeam = path.segmentLoopSeams[name] ?? null
  const isMuted  = !!mutedTracks[name]
  const color    = trackColor(name)
  const unit     = trackUnit(name)
  const { min: vMin, max: vMax } = trackValueLimits(name)
  const arcTable = useMemo(() => makeArcTable(path.wps, path.closed), [path])
  const rulerRef = useRef<HTMLDivElement>(null)
  const graphRef = useRef<HTMLDivElement>(null)
  const drag     = useRef<SegDrag | null>(null)
  const [segCtxMenu,   setSegCtxMenu]   = useState<SegCtxMenu | null>(null)
  const [seamSelected, setSeamSelected] = useState(false)

  const nSegs    = path.closed ? path.wps.length : Math.max(path.wps.length - 1, 1)
  const animFrac = nSegs > 0 ? Math.max(0, Math.min(1, (animT % nSegs) / nSegs)) : 0
  const liveVal  = evalScalarSegments(segments, arcTable.paramToArc(animFrac), loopSeam)
  const sel      = segments.find(s => s.id === selSegId) ?? null

  function rulerFrac(clientX: number): number {
    const r = rulerRef.current?.getBoundingClientRect()
    return r ? Math.max(0, Math.min(1, (clientX - r.left) / r.width)) : 0
  }

  function addSegmentAt(t: number) {
    const seg = makeScalarSegment(t, defaultTrackValue(name))
    seg.ease = defaultTrackEasing(name)
    addSegment(name, seg)
    onSelSegId(seg.id)
    if (!isExpanded) onExpand()
  }

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

  function handleBlockPointerDown(e: React.PointerEvent<HTMLDivElement>, seg: ScalarSegment, mode: SegDragMode) {
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
      updateSegmentLoopSeam(name, { tailFrac: Math.max(0.01, Math.min(0.45, (d.startTailFrac ?? 0) - df)) })
      return
    }
    if (d.mode === 'seam-head-inner') {
      updateSegmentLoopSeam(name, { headFrac: Math.max(0.01, Math.min(0.45, (d.startHeadFrac ?? 0) + df)) })
      return
    }

    const seg = segments.find(s => s.id === d.id)
    if (!seg) return
    switch (d.mode) {
      case 'body':
        updateSegment(name, d.id, { t: Math.max(0, Math.min(1 - seg.duration, d.startT + df)) })
        break
      case 'right-edge':
        updateSegment(name, d.id, { duration: Math.max(0.01, Math.min(1 - seg.t, d.startDur + df)) })
        break
      case 'left-edge': {
        const newT   = Math.max(0, Math.min(seg.t + seg.duration - 0.01, d.startT + df))
        const newDur = Math.max(0.01, d.startT + d.startDur - newT)
        updateSegment(name, d.id, { t: newT, duration: newDur })
        break
      }
    }
  }

  function handleRulerPointerUp() {
    if (drag.current) { drag.current = null; resumeTemporal() }
  }

  // Graph: sample the eased value curve
  const STEPS = 80; const VW = 200; const VH = 52; const PAD = 4
  const values = useMemo(
    () => Array.from({ length: STEPS + 1 }, (_, i) => evalScalarSegments(segments, i / STEPS, loopSeam)),
    [segments, loopSeam]
  )
  const maxAbs = Math.max(Math.abs(vMax), Math.abs(vMin), ...values.map(Math.abs), 1e-6)
  const toGX   = (f: number) => f * VW
  const toGY   = (v: number) => VH / 2 - (v / maxAbs) * (VH / 2 - PAD)
  const linePts = segments.length > 0
    ? values.map((v, i) => `${toGX(i / STEPS).toFixed(1)},${toGY(v).toFixed(1)}`).join(' ')
    : ''

  function update(patch: Partial<ScalarSegment>) {
    if (!sel) return
    updateSegment(name, sel.id, patch)
  }

  return (
    <div className={`bpanel-track-group${isExpanded ? ' active' : ''}${isMuted ? ' muted' : ''}`}>

      {/* Compact row */}
      <div className="bpanel-track-row" style={{ cursor: isExpanded ? 'default' : 'pointer' }}
        onClick={isExpanded ? undefined : onExpand}>

        <span className="bpanel-track-label" style={{ color }}
          onClick={e => { e.stopPropagation(); onExpand() }}>
          <span className="bpanel-mode-ind">{isExpanded ? '▼' : '▶'}</span>
          {name}
          <span className="bpanel-live-val">{liveVal.toFixed(trackDecimals(name))}{unit}</span>
        </span>

        {/* Ruler with draggable blocks — right-click empty area to add */}
        <div ref={rulerRef} className="bpanel-track-bar"
          style={{ position: 'relative', cursor: 'default' }}
          onContextMenu={e => {
            e.preventDefault()
            if (drag.current) return
            const t = rulerFrac(e.clientX)
            const onSeg = segments.some(s => t >= s.t && t <= s.t + s.duration)
            if (!onSeg) setSegCtxMenu({ mode: 'add', x: e.clientX, y: e.clientY, t })
          }}
          onPointerMove={handleRulerPointerMove}
          onPointerUp={handleRulerPointerUp}>
          <div className="bpanel-track-baseline" />
          {segments.map(seg => {
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
                  background: color,
                  opacity: isSel ? 0.9 : 0.5,
                  borderRadius: 2,
                  outline: isSel ? `1.5px solid ${color}` : 'none',
                  cursor: 'grab',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  overflow: 'hidden',
                  fontSize: 9, color: '#fff',
                  userSelect: 'none',
                  boxSizing: 'border-box',
                }}
                  onPointerDown={e => { e.stopPropagation(); handleBlockPointerDown(e, seg, 'body') }}
                  onClick={e => { e.stopPropagation(); onSelSegId(seg.id); if (!isExpanded) onExpand() }}
                  onContextMenu={e => { e.preventDefault(); e.stopPropagation(); setSegCtxMenu({ mode: 'seg', x: e.clientX, y: e.clientY, id: seg.id }) }}>
                  {seg.mode === 'absolute' && <span style={{ fontSize: 7, opacity: 0.8 }}>A</span>}
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
                {tailFrac > 0 && (
                  <React.Fragment>
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
                {headFrac > 0 && (
                  <React.Fragment>
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
            style={{ color: isMuted ? 'var(--text-faint)' : color, opacity: isMuted ? 0.45 : 0.75 }}
            title={isMuted ? `Unmute ${name}` : `Mute ${name}`}
            onClick={e => { e.stopPropagation(); toggleMutedTrack(name) }}>
            {isMuted ? '○' : '◉'}
          </button>
          <span className="bpanel-track-meta">{segments.length} seg</span>
          {path.closed && !loopSeam && (
            <button className="bp-seg-btn" title="Add loop seam — smooths the value gap at the loop point"
              style={{ color: '#a78bfa', padding: '0 4px', fontSize: 10 }}
              onClick={e => {
                e.stopPropagation()
                setSegmentLoopSeam(name, { tailFrac: 0.05, headFrac: 0.05, targetValue: defaultTrackValue(name), ease: 'in-out' })
                setSeamSelected(true); if (!isExpanded) onExpand()
              }}>⟲</button>
          )}
          <button className="bp-icon-btn danger" title={`Remove entire ${name} track (discards all segments)`}
            onClick={e => {
              e.stopPropagation()
              const n = segments.length
              if (n > 0 && !window.confirm(
                `Delete the "${name}" track?\n\nThis will permanently discard ${n} segment${n !== 1 ? 's' : ''}.\nThis action can be undone with Ctrl+Z.`
              )) return
              setSegmentTrack(name, []); onSelSegId(null)
            }}>×</button>
        </div>
      </div>

      {segCtxMenu?.mode === 'add' && (
        <CRSegContextMenu x={segCtxMenu.x} y={segCtxMenu.y}
          onClose={() => setSegCtxMenu(null)}
          onAdd={() => { addSegmentAt(segCtxMenu.t) }} />
      )}
      {segCtxMenu?.mode === 'seg' && (
        <CRSegContextMenu x={segCtxMenu.x} y={segCtxMenu.y}
          onClose={() => setSegCtxMenu(null)}
          onDelete={() => { removeSegment(name, segCtxMenu.id); if (selSegId === segCtxMenu.id) onSelSegId(null) }} />
      )}

      {/* Expanded panel */}
      {isExpanded && (
        <div className="bpanel-active-panel">
          <div className="bpanel-active-edit">
            {seamSelected && loopSeam ? (
              <>
                <span style={{ color: '#a78bfa', fontWeight: 600, fontSize: 11 }}>⟲</span>
                <span className="bp-label">tail</span>
                <NumInput value={loopSeam.tailFrac} step={0.005} min={0.005} max={0.45} decimals={3}
                  commit={v => updateSegmentLoopSeam(name, { tailFrac: v })} className="bp-num bp-num-t"
                  title="Tail: arc fraction consumed before the loop point (right band)" />
                <span className="bp-label">head</span>
                <NumInput value={loopSeam.headFrac} step={0.005} min={0.005} max={0.45} decimals={3}
                  commit={v => updateSegmentLoopSeam(name, { headFrac: v })} className="bp-num bp-num-t"
                  title="Head: arc fraction consumed after the loop point (left band)" />
                <span className="bp-label">target{unit}</span>
                <NumInput value={loopSeam.targetValue}
                  step={trackStep(name)} decimals={trackDecimals(name)}
                  min={vMin} max={vMax}
                  commit={v => updateSegmentLoopSeam(name, { targetValue: v })} className="bp-num"
                  title="Value to ease toward at the loop point" />
                <span className="bp-label">ease</span>
                <select className="bp-select" value={loopSeam.ease}
                  onChange={e => updateSegmentLoopSeam(name, { ease: e.target.value as SegEase })}>
                  <option value="linear">linear</option>
                  <option value="in">ease in</option>
                  <option value="out">ease out</option>
                  <option value="in-out">ease in/out</option>
                </select>
                <button className="bp-icon-btn danger" title="Remove loop seam"
                  onClick={() => { setSegmentLoopSeam(name, null); setSeamSelected(false) }}>Del</button>
              </>
            ) : sel ? (
              <>
                <span className="bp-label">mode</span>
                <button className={`bp-seg-btn${sel.mode === 'relative' ? ' active' : ''}`}
                  onClick={() => update({ mode: 'relative' })}>REL</button>
                <button className={`bp-seg-btn${sel.mode === 'absolute' ? ' active' : ''}`}
                  onClick={() => update({ mode: 'absolute' })}>ABS</button>

                <span className="bp-label">val{unit}</span>
                <NumInput value={sel.value}
                  step={trackStep(name)} decimals={trackDecimals(name)}
                  min={vMin} max={vMax}
                  commit={v => update({ value: v })} className="bp-num"
                  title={sel.mode === 'absolute' ? 'Target value to ease to' : 'Signed delta to ease by, relative to the value entering this segment'} />

                <span className="bp-label">ease</span>
                <select className="bp-select" value={sel.ease}
                  onChange={e => update({ ease: e.target.value as SegEase })}>
                  <option value="linear">linear</option>
                  <option value="in">ease in</option>
                  <option value="out">ease out</option>
                  <option value="in-out">ease in/out</option>
                </select>

                <span className="bp-label">t</span>
                <NumInput value={sel.t} step={0.005} min={0} max={0.99} decimals={3}
                  commit={v => update({ t: v })} className="bp-num bp-num-t"
                  title="Arc-length fraction where this segment begins (0–1)." />

                <span className="bp-label">len</span>
                <NumInput value={sel.duration} step={0.01} min={0.01} max={1} decimals={2}
                  commit={v => update({ duration: v })} className="bp-num bp-num-t"
                  title="Arc-length duration of this segment." />

                <button className="bp-icon-btn danger"
                  onClick={() => { removeSegment(name, sel.id); onSelSegId(null) }}>Del</button>
              </>
            ) : (
              <span className="bp-hint">
                {segments.length === 0 && !loopSeam
                  ? 'Right-click to add a segment'
                  : loopSeam && !segments.length
                  ? 'Click ⟲ seam bands to edit · right-click to add segments'
                  : 'Click a block to select · drag body to move · drag edges to resize'}
              </span>
            )}
          </div>

          {/* Value graph */}
          <div ref={graphRef} className="bpanel-active-graph" style={{ position: 'relative' }}>
            <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}
              viewBox={`0 0 ${VW} ${VH}`} preserveAspectRatio="none">
              <line x1={0} y1={VH/2} x2={VW} y2={VH/2}
                stroke="rgba(255,255,255,0.15)" strokeWidth="1" strokeDasharray="3 4" />
              {segments.map(seg => (
                <rect key={seg.id} x={seg.t * VW} y={0}
                  width={Math.max(1, seg.duration * VW)} height={VH}
                  fill={color} opacity={0.07} />
              ))}
              {linePts && (
                <polyline points={linePts} fill="none" stroke={color} strokeWidth="2" opacity="0.75" />
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
              }}>{name} value over the path</div>
            )}
          </div>

        </div>
      )}
    </div>
  )
}

// ── TriggerTypeRow ───────────────────────────────────────────────────────
// One row per event TYPE (fireMode, weapon, ...), not per event instance —
// mirrors the segment tracks' rulers: a single row per behavior, markers for
// each instance positioned along it. Right-click the bar to add a new
// instance at that position; click a marker to select it for editing below.
function TriggerTypeRow({ type, selTrig, onSelTrig }: {
  type: TriggerType; selTrig: number | null; onSelTrig: (i: number | null) => void
}) {
  const { path, addTrigger, updateTrigger, removeTrigger, setHoveredBehavior } = useStore()
  const items = path.triggers
    .map((tr, i) => ({ tr, i }))
    .filter(x => x.tr.event.type === type)
  const color  = triggerColor(type)
  const sel    = selTrig !== null ? items.find(x => x.i === selTrig) ?? null : null
  const barRef = useRef<HTMLDivElement>(null)

  function addHere(e: React.MouseEvent<HTMLDivElement>) {
    e.preventDefault()
    const rect = e.currentTarget.getBoundingClientRect()
    const t = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
    addTrigger({ t, event: defaultEvent(type) })
  }

  // Whole row is clickable, not just the tiny diamond — with one event (the common
  // case) any click on the row selects it unambiguously; with several, the click
  // selects whichever marker is closest to it along the bar.
  function selectNearest(clientX: number) {
    if (items.length === 0) return
    let best = items[0].i, bestDist = Infinity
    const rect = barRef.current?.getBoundingClientRect()
    const frac = rect ? Math.max(0, Math.min(1, (clientX - rect.left) / rect.width)) : null
    for (const it of items) {
      const d = frac === null ? 0 : Math.abs(it.tr.t - frac)
      if (d < bestDist) { best = it.i; bestDist = d }
    }
    onSelTrig(best)
  }

  return (
    <div className="bpanel-track-group">
      <div className="bpanel-track-row" style={{ cursor: 'pointer' }} onClick={e => selectNearest(e.clientX)}>
        <span className="bpanel-track-label" style={{ color }}>{type}</span>
        <div ref={barRef} className="bpanel-track-bar" title="Right-click to add an event here" onContextMenu={addHere}>
          <div className="bpanel-track-baseline" />
          {items.map(({ tr, i }) => (
            <div key={i}
              className={`bpanel-kf-diamond${selTrig === i ? ' selected' : ''}`}
              style={{ left: `${tr.t * 100}%`, background: color, borderColor: color }}
              title={`t=${tr.t.toFixed(3)}  ${triggerSummary(tr.event)}`}
              onMouseEnter={() => setHoveredBehavior({ type: 'trigger', index: i })}
              onMouseLeave={() => setHoveredBehavior(null)} />
          ))}
        </div>
        <div className="bpanel-track-right">
          <span className="bpanel-track-meta">{items.length} evt</span>
          <button className="bp-icon-btn danger" title="Remove all events of this type"
            onClick={e => {
              e.stopPropagation()
              const n = items.length
              if (!window.confirm(
                `Delete all ${n} "${type}" event${n !== 1 ? 's' : ''}?\n\nThis action can be undone with Ctrl+Z.`
              )) return
              ;[...items].sort((a, b) => b.i - a.i).forEach(x => removeTrigger(x.i))
              onSelTrig(null)
            }}>×</button>
        </div>
      </div>

      {sel && (
        <div className="bpanel-active-panel">
          {/* Reuses the compact row's own bar classes so this handle sits at the exact
              same pixel x as the diamond above it — both are `left: t*100%` in the same
              width container. A native <input type=range> can NOT be made to match this:
              its thumb insets by half the thumb width at each end, so value*100% never
              equals the thumb's actual pixel position. */}
          <div className="bpanel-track-bar bpanel-pos-scrub"
            onPointerDown={e => {
              e.currentTarget.setPointerCapture(e.pointerId)
              const rect = e.currentTarget.getBoundingClientRect()
              updateTrigger(sel.i, { ...sel.tr, t: Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width)) })
            }}
            onPointerMove={e => {
              if (e.buttons !== 1) return
              const rect = e.currentTarget.getBoundingClientRect()
              updateTrigger(sel.i, { ...sel.tr, t: Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width)) })
            }}>
            <div className="bpanel-track-baseline" />
            <div className="bpanel-kf-diamond selected"
              style={{ left: `${sel.tr.t * 100}%`, background: color, borderColor: color }} />
          </div>
          <div className="bpanel-active-edit">
            <span className="bp-label">pos</span>
            <NumInput value={sel.tr.t} step={0.01} min={0} max={1}
              commit={t => updateTrigger(sel.i, { ...sel.tr, t: Math.max(0, Math.min(1, t)) })}
              className="bp-num bp-num-t" />
            <TriggerValueEditor event={sel.tr.event}
              onChange={ev => updateTrigger(sel.i, { ...sel.tr, event: ev })} />
            <button className="bp-icon-btn danger" onClick={() => { removeTrigger(sel.i); onSelTrig(null) }}>Del evt</button>
          </div>
        </div>
      )}
    </div>
  )
}

// ── AddMenu ───────────────────────────────────────────────────────────────
function AddMenu({ onClose, animFrac }: { onClose: () => void; animFrac: number }) {
  const { path, addSegment, addTrigger, addCraftRollSegment } = useStore()
  const [customName, setCustomName] = useState('')
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const h = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) onClose() }
    setTimeout(() => document.addEventListener('mousedown', h), 0)
    return () => document.removeEventListener('mousedown', h)
  }, [onClose])

  function addSegmentTrack(name: string) {
    if (!name.trim()) return
    const existing = path.segmentTracks[name] ?? []
    if (!existing.some(s => Math.abs(s.t - animFrac) < 0.01)) {
      const seg = makeScalarSegment(animFrac, defaultTrackValue(name))
      seg.ease = defaultTrackEasing(name)
      addSegment(name, seg)
    }
    onClose()
  }

  return (
    <div ref={ref} className="bp-add-menu">
      <div className="bp-add-section">TRACKS</div>
      {/* craftRoll — adds a default segment and shows the track */}
      <button className="bp-add-item" style={{ color: CR_CW }}
        onClick={() => { addCraftRollSegment(makeCraftRollSegment(animFrac)); onClose() }}>
        craftRoll
      </button>
      {SCALAR_TRACK_NAMES.map(name => (
        <button key={name} className="bp-add-item"
          style={{ color: trackColor(name) }} onClick={() => addSegmentTrack(name)}>{name}</button>
      ))}
      <div className="bp-add-custom">
        <input className="bp-text" placeholder="custom name…" value={customName}
          onChange={e => setCustomName(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') addSegmentTrack(customName) }} />
        <button className="bp-add-item" onClick={() => addSegmentTrack(customName)}>+</button>
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
  const [selTrig,      setSelTrig]      = useState<number | null>(null)
  const [selTrack,     setSelTrack]     = useState<string | null>(null)
  const [addOpen,      setAddOpen]      = useState(false)
  const [selSegId,     setSelSegId]     = useState<string | null>(null)   // craftRoll's selected segment
  const [crExpanded,   setCrExpanded]   = useState(false)
  const [selScalarSeg, setSelScalarSeg] = useState<{ track: string; id: string } | null>(null)

  const nSegs    = path.closed ? path.wps.length : Math.max(path.wps.length - 1, 1)
  const animFrac = nSegs > 0 ? Math.max(0, Math.min(1, (animT % nSegs) / nSegs)) : 0

  // ── J / K — jump to previous/next segment or trigger start (After Effects convention) ──
  // Mounted only while BehaviorsPanel is on screen, so no behaviorsOpen guard needed.
  useEffect(() => {
    const fn = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
      const s   = useStore.getState()
      const ns  = s.path.closed ? s.path.wps.length : Math.max(s.path.wps.length - 1, 1)

      if (e.key === 'j' || e.key === 'J') {
        e.preventDefault()
        const allT = [...new Set([
          ...Object.values(s.path.segmentTracks).flatMap(segs => segs.map(sg => sg.t)),
          ...s.path.craftRollSegments.map(sg => sg.t),
          ...s.path.triggers.map(tr => tr.t),
        ])].sort((a, b) => a - b)
        const cur  = Math.max(0, Math.min(1, s.animT / ns))
        const prev = [...allT].reverse().find(t => t < cur - 0.0005)
        if (prev !== undefined) s.setAnimT(prev * ns)

      } else if (e.key === 'k' || e.key === 'K') {
        e.preventDefault()
        const allT = [...new Set([
          ...Object.values(s.path.segmentTracks).flatMap(segs => segs.map(sg => sg.t)),
          ...s.path.craftRollSegments.map(sg => sg.t),
          ...s.path.triggers.map(tr => tr.t),
        ])].sort((a, b) => a - b)
        const cur  = Math.max(0, Math.min(1, s.animT / ns))
        const next = allT.find(t => t > cur + 0.0005)
        if (next !== undefined) s.setAnimT(next * ns)
      }
    }
    window.addEventListener('keydown', fn)
    return () => window.removeEventListener('keydown', fn)
  }, [])

  function handleExpand(name: string) {
    setSelTrack(prev => {
      const next = prev === name ? null : name
      setActiveBehaviorTrack(next)
      return next
    })
    if (selScalarSeg?.track !== name) setSelScalarSeg(null)
  }

  useEffect(() => {
    if (selTrig  !== null && !path.triggers[selTrig]) setSelTrig(null)
    if (selTrack !== null && !path.segmentTracks[selTrack]) setSelTrack(null)
    if (selSegId !== null && !(path.craftRollSegments ?? []).some(s => s.id === selSegId)) setSelSegId(null)
    if (selScalarSeg && !(path.segmentTracks[selScalarSeg.track] ?? []).some(s => s.id === selScalarSeg.id)) setSelScalarSeg(null)
    // Auto-collapse craftRoll when all segments are removed — hides the row, same as other tracks
    if ((path.craftRollSegments ?? []).length === 0) setCrExpanded(false)
  }, [path.segmentTracks, path.triggers, path.craftRollSegments, selTrig, selTrack, selSegId, selScalarSeg])

  const trackNames    = Object.keys(path.segmentTracks).sort()
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
            <ScalarSegmentTrack key={name} name={name}
              selSegId={selScalarSeg?.track === name ? selScalarSeg.id : null}
              onSelSegId={id => setSelScalarSeg(id ? { track: name, id } : null)}
              isExpanded={selTrack === name}
              onExpand={() => handleExpand(name)} />
          ))}
        </div>
      )}

      {hasTriggers && (
        <div className="bpanel-triggers">
          <div className="bpanel-section-header">EVENTS</div>
          {TRIGGER_TYPES.filter(type => path.triggers.some(tr => tr.event.type === type)).map(type => (
            <TriggerTypeRow key={type} type={type} selTrig={selTrig} onSelTrig={setSelTrig} />
          ))}
        </div>
      )}
    </div>
  )
}
