import { PathData, TriggerEvent, FireMode, ShieldMode, ScalarSegment, SegmentLoopSeam } from '../store'
import { type CraftRollEase } from '../math/craftRoll'
import { Waypoint } from '../math/vec3'

// ── Export ──────────────────────────────────────────────────────────────
function fmt(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(4)
}

function fmtT(t: number): string {
  // Arc-length fraction: always 4 decimal places for readability
  return t.toFixed(4)
}

function serializeTriggerEvent(ev: TriggerEvent): string {
  switch (ev.type) {
    case 'fireMode':   return `fireMode, ${ev.mode}`
    case 'weapon':     return `weapon, ${ev.name}`
    case 'shieldMode': return `shieldMode, ${ev.mode}`
    case 'invuln':     return `invuln, ${ev.value}`
    case 'phase':      return `phase, ${ev.tag}`
    case 'sound':      return `sound, ${ev.name}, ${ev.volume}, ${ev.loop ? 1 : 0}`
    case 'custom':     return `custom, ${ev.tag}, ${ev.value}`
  }
}

export function exportBlock(p: PathData): string {
  const lines: string[] = []
  lines.push(`[${p.name}]`)

  // type= only emitted for non-default; 'craft' is implicit (backward compat)
  if (p.type && p.type !== 'craft') lines.push(`type=${p.type}`)

  lines.push(`speed=${p.speed}`)

  if (p.orient === 'target') {
    lines.push(`orient=target:${fmt(p.target.x)},${fmt(p.target.y)},${fmt(p.target.z)}`)
  } else {
    lines.push(`orient=path`)
  }

  lines.push(`closed=${p.closed ? 1 : 0}`)

  lines.push('')

  // For closed paths: append wps[0] as the last line so the game engine
  // gets the duplicate-endpoint convention it expects (wps[last] === wps[0]).
  const wpsToExport: Waypoint[] = (p.closed && p.wps.length > 0)
    ? [...p.wps, p.wps[0]]
    : p.wps

  for (const wp of wpsToExport) {
    const x = fmt(wp.x).padStart(8)
    const y = fmt(wp.y).padStart(8)
    const z = fmt(wp.z).padStart(8)
    lines.push(`${x}  ${y}  ${z}`)
  }

  // Segment tracks — one line per segment, tracks in sorted-name order
  const trackNames = Object.keys(p.segmentTracks ?? {}).sort()
  if (trackNames.length > 0) {
    lines.push('')
    for (const name of trackNames) {
      for (const seg of p.segmentTracks[name]) {
        lines.push(`segment: ${name}, ${fmtT(seg.t)}, ${fmtT(seg.duration)}, ${fmt(seg.value)}, ${seg.mode}, ${seg.ease}`)
      }
    }
    for (const name of trackNames) {
      const seam = p.segmentLoopSeams?.[name]
      if (seam) {
        lines.push(`segseam: ${name}, ${fmtT(seam.tailFrac)}, ${fmtT(seam.headFrac)}, ${fmt(seam.targetValue)}, ${seam.ease}`)
      }
    }
  }

  // Trigger events — sorted by t
  const triggers = [...(p.triggers ?? [])].sort((a, b) => a.t - b.t)
  if (triggers.length > 0) {
    lines.push('')
    for (const tr of triggers) {
      lines.push(`trigger: ${fmtT(tr.t)}, ${serializeTriggerEvent(tr.event)}`)
    }
  }

  // Craft roll segments — sorted by t
  const crSegs = [...(p.craftRollSegments ?? [])].sort((a, b) => a.t - b.t)
  if (crSegs.length > 0) {
    lines.push('')
    for (const seg of crSegs) {
      lines.push(`craftroll: ${fmtT(seg.t)}, ${fmtT(seg.duration)}, ${seg.degrees}, ${seg.direction}, ${seg.mode}, ${seg.ease}`)
    }
  }

  // Loop seam — only emit when non-null
  if (p.craftRollLoopSeam) {
    const s = p.craftRollLoopSeam
    lines.push('')
    lines.push(`loopseam: ${fmtT(s.tailFrac)}, ${fmtT(s.headFrac)}, ${fmt(s.targetAngle)}, ${s.ease}`)
  }

  return lines.join('\n')
}

// ── Import ──────────────────────────────────────────────────────────────
function parseTriggerEvent(parts: string[]): TriggerEvent | null {
  const type = parts[0]
  switch (type) {
    case 'fireMode':
      return { type: 'fireMode', mode: parts[1] as FireMode }
    case 'weapon':
      return { type: 'weapon', name: parts[1] ?? '' }
    case 'shieldMode':
      return { type: 'shieldMode', mode: parts[1] as ShieldMode }
    case 'invuln':
      return { type: 'invuln', value: (parseInt(parts[1] ?? '0') === 1 ? 1 : 0) }
    case 'phase':
      return { type: 'phase', tag: parts[1] ?? '' }
    case 'custom':
      return { type: 'custom', tag: parts[1] ?? '', value: parts[2] ?? '' }
    default:
      return null
  }
}

export function parseBlocks(text: string): Map<string, PathData> {
  const result = new Map<string, PathData>()
  const lines  = text.split(/\r?\n/)
  let cur: PathData | null = null

  for (const rawLine of lines) {
    const line = rawLine.trim()

    // Section header: [name]
    const header = line.match(/^\[([^\]]+)\]$/)
    if (header) {
      if (cur) result.set(cur.name, stripDuplicateEndpoint(cur))
      cur = {
        name:              header[1],
        type:              'craft',
        speed:             0.025,
        orient:            'path',
        target:            { x: 0, y: 0, z: 0 },
        closed:            true,
        wps:               [],
        triggers:          [],
        craftRollSegments: [],
        craftRollLoopSeam: null,
        segmentTracks:     {},
        segmentLoopSeams:  {},
      }
      continue
    }

    if (!cur || line.startsWith('#') || line === '') continue

    // Segment track: "segment: name, t, duration, value, mode, ease"
    if (line.startsWith('segment:')) {
      const parts = line.slice(8).split(',').map(s => s.trim())
      if (parts.length >= 6) {
        const name     = parts[0]
        const t        = parseFloat(parts[1])
        const duration = parseFloat(parts[2])
        const value    = parseFloat(parts[3])
        const mode     = parts[4] as 'relative' | 'absolute'
        const ease     = parts[5] as CraftRollEase
        if (!isNaN(t) && !isNaN(duration) && !isNaN(value)) {
          const seg: ScalarSegment = {
            id: Math.random().toString(36).slice(2, 9),
            t, duration, value, mode, ease,
          }
          if (!cur.segmentTracks[name]) cur.segmentTracks[name] = []
          cur.segmentTracks[name].push(seg)
        }
      }
      continue
    }

    // Segment track loop seam: "segseam: name, tailFrac, headFrac, targetValue, ease"
    if (line.startsWith('segseam:')) {
      const parts = line.slice(8).split(',').map(s => s.trim())
      if (parts.length >= 5) {
        const name        = parts[0]
        const tailFrac    = parseFloat(parts[1])
        const headFrac    = parseFloat(parts[2])
        const targetValue = parseFloat(parts[3])
        const ease        = parts[4] as CraftRollEase
        if (!isNaN(tailFrac) && !isNaN(headFrac) && !isNaN(targetValue)) {
          const seam: SegmentLoopSeam = { tailFrac, headFrac, targetValue, ease: ease || 'in-out' }
          cur.segmentLoopSeams[name] = seam
        }
      }
      continue
    }

    // Craft roll segment: "craftroll: t, duration, degrees, direction, mode, ease"
    if (line.startsWith('craftroll:')) {
      const parts = line.slice(10).split(',').map(s => s.trim())
      if (parts.length >= 6) {
        const t         = parseFloat(parts[0])
        const duration  = parseFloat(parts[1])
        const degrees   = parseInt(parts[2], 10)
        const direction = parts[3] as 'cw' | 'ccw'
        const mode      = parts[4] as 'relative' | 'absolute'
        const ease      = parts[5] as CraftRollEase
        if (!isNaN(t) && !isNaN(duration) && !isNaN(degrees)) {
          cur.craftRollSegments.push({
            id: Math.random().toString(36).slice(2, 9),
            t, duration, degrees, direction, mode, ease,
          })
        }
      }
      continue
    }

    // Loop seam: "loopseam: tailFrac, headFrac, targetAngle, ease"
    if (line.startsWith('loopseam:')) {
      const parts = line.slice(9).split(',').map(s => s.trim())
      if (parts.length >= 4) {
        const tailFrac    = parseFloat(parts[0])
        const headFrac    = parseFloat(parts[1])
        const targetAngle = parseFloat(parts[2])
        const ease        = parts[3] as CraftRollEase
        if (!isNaN(tailFrac) && !isNaN(headFrac) && !isNaN(targetAngle)) {
          cur.craftRollLoopSeam = { tailFrac, headFrac, targetAngle, ease: ease || 'in-out' }
        }
      }
      continue
    }

    // Trigger event: "trigger: t, type, ...args"
    if (line.startsWith('trigger:')) {
      const parts = line.slice(8).split(',').map(s => s.trim())
      if (parts.length >= 2) {
        const t = parseFloat(parts[0])
        const event = parseTriggerEvent(parts.slice(1))
        if (!isNaN(t) && event) {
          cur.triggers.push({ t, event })
        }
      }
      continue
    }

    // key=value
    const kv = line.match(/^(\w+)=(.+)$/)
    if (kv) {
      const [, key, val] = kv
      switch (key) {
        case 'type':
          cur.type = (val.trim() === 'camera') ? 'camera' : 'craft'
          break
        case 'speed':  cur.speed  = parseFloat(val); break
        case 'closed': cur.closed = val.trim() === '1'; break
        // Legacy: old files had a global 'roll' — ignore it (per-node rolls are on waypoint lines)
        case 'roll': break
        case 'orient':
          if (val.startsWith('target:')) {
            cur.orient = 'target'
            const parts = val.slice(7).split(',').map(Number)
            cur.target = { x: parts[0] ?? 0, y: parts[1] ?? 0, z: parts[2] ?? 0 }
          } else {
            cur.orient = 'path'
          }
          break
      }
      continue
    }

    // Waypoint: X Y Z (extra columns ignored)
    const nums = line.split(/\s+/).filter(Boolean).map(Number)
    if (nums.length >= 3 && nums.slice(0, 3).every((n) => !isNaN(n))) {
      cur.wps.push({ x: nums[0], y: nums[1], z: nums[2] })
    }
  }

  if (cur) result.set(cur.name, stripDuplicateEndpoint(cur))
  return result
}

// ── Per-file helpers ────────────────────────────────────────────────────

// Convert a route name to a safe kebab-case filename stem (no .mvr extension).
// Must stay in sync with the same function in tools/migrate-maneuvers.js.
export function nameToFilename(name: string): string {
  return name.trim()
    .toLowerCase()
    .replace(/[\s_]+/g, '-')      // spaces and underscores → hyphens
    .replace(/[^a-z0-9-]/g, '')   // strip anything else
    .replace(/-{2,}/g, '-')       // collapse runs of hyphens
    .replace(/^-+|-+$/g, '')      // trim leading/trailing hyphens
    || 'unnamed'
}

// Parse a single .mvr file's text. Returns the PathData or null on failure.
export function parseFile(text: string): PathData | null {
  const map   = parseBlocks(text)
  const first = map.values().next().value
  return (first as PathData | undefined) ?? null
}

// Strip duplicate endpoint from old-format files where wps[last] === wps[0].
function stripDuplicateEndpoint(p: PathData): PathData {
  if (!p.closed || p.wps.length < 2) return p
  const first = p.wps[0], last = p.wps[p.wps.length - 1]
  const eps = 0.001
  if (Math.abs(first.x - last.x) < eps &&
      Math.abs(first.y - last.y) < eps &&
      Math.abs(first.z - last.z) < eps) {
    return { ...p, wps: p.wps.slice(0, -1) }
  }
  return p
}
