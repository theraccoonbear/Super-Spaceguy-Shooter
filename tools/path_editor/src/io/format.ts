import { PathData } from '../store'
import { Waypoint } from '../math/vec3'

// ── Export ──────────────────────────────────────────────────────────────
function fmt(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(2)
}

export function exportBlock(p: PathData): string {
  const lines: string[] = []
  lines.push(`[${p.name}]`)
  lines.push(`speed=${p.speed}`)

  if (p.orient === 'target') {
    lines.push(`orient=target:${fmt(p.target.x)},${fmt(p.target.y)},${fmt(p.target.z)}`)
  } else {
    lines.push(`orient=path`)
  }

  if (Math.abs(p.standoff) > 0.01) lines.push(`standoff=${fmt(p.standoff)}`)
  lines.push(`closed=${p.closed ? 1 : 0}`)

  lines.push('')

  // For closed paths: append wps[0] as the last line so the game engine
  // gets the duplicate-endpoint convention it expects (wps[last] === wps[0]).
  const wpsToExport: Waypoint[] = (p.closed && p.wps.length > 0)
    ? [...p.wps, p.wps[0]]
    : p.wps

  for (const wp of wpsToExport) {
    const x  = fmt(wp.x).padStart(5)
    const y  = fmt(wp.y).padStart(5)
    const z  = fmt(wp.z).padStart(5)
    const pr = wp.pathRoll  ?? 0
    const cr = wp.craftRoll ?? 0
    // Write roll fields only when non-zero (backward compatible: old parsers stop at 3 nums)
    if (Math.abs(pr) > 0.01 || Math.abs(cr) > 0.01) {
      lines.push(`${x}  ${y}  ${z}  ${fmt(pr).padStart(7)}  ${fmt(cr).padStart(7)}`)
    } else {
      lines.push(`${x}  ${y}  ${z}`)
    }
  }

  return lines.join('\n')
}

// ── Import ──────────────────────────────────────────────────────────────
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
        name:     header[1],
        speed:    0.025,
        orient:   'path',
        target:   { x: 0, y: 0, z: 0 },
        closed:   true,
        standoff: 0,
        wps:      [],
      }
      continue
    }

    if (!cur || line.startsWith('#') || line === '') continue

    // key=value
    const kv = line.match(/^(\w+)=(.+)$/)
    if (kv) {
      const [, key, val] = kv
      switch (key) {
        case 'speed':    cur.speed    = parseFloat(val); break
        case 'standoff': cur.standoff = parseFloat(val); break
        case 'closed':   cur.closed   = val.trim() === '1'; break
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

    // Waypoint: X Y Z [pathRoll [craftRoll]]
    const nums = line.split(/\s+/).filter(Boolean).map(Number)
    if (nums.length >= 3 && nums.every((n) => !isNaN(n))) {
      cur.wps.push({
        x: nums[0], y: nums[1], z: nums[2],
        pathRoll:  nums[3] ?? 0,
        craftRoll: nums[4] ?? 0,
      })
    }
  }

  if (cur) result.set(cur.name, stripDuplicateEndpoint(cur))
  return result
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
