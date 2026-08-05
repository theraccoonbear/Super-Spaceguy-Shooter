import { PathData } from '../store'
import { Vec3 } from '../math/vec3'

// ── Export ──────────────────────────────────────────────────────────────
function fmt(n: number): string {
  // Use integer if exact, otherwise 2 decimal places
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

  if (Math.abs(p.roll) > 0.01)     lines.push(`roll=${fmt(p.roll)}`)
  if (Math.abs(p.standoff) > 0.01) lines.push(`standoff=${fmt(p.standoff)}`)

  lines.push('')

  // For closed paths: append wps[0] as the last line so the game engine
  // gets the duplicate-endpoint convention it expects (wps[last] === wps[0]).
  const wpsToExport = (p.closed && p.wps.length > 0)
    ? [...p.wps, p.wps[0]]
    : p.wps

  for (const wp of wpsToExport) {
    const x = fmt(wp.x).padStart(5)
    const y = fmt(wp.y).padStart(5)
    const z = fmt(wp.z).padStart(5)
    lines.push(`${x}  ${y}  ${z}`)
  }

  return lines.join('\n')
}

// ── Import ──────────────────────────────────────────────────────────────
export function parseBlocks(text: string): Map<string, PathData> {
  const result = new Map<string, PathData>()
  const lines = text.split(/\r?\n/)
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
        roll:     0,
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
        case 'roll':     cur.roll     = parseFloat(val); break
        case 'standoff': cur.standoff = parseFloat(val); break
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

    // Waypoint: X Y Z
    const nums = line.split(/\s+/).filter(Boolean).map(Number)
    if (nums.length >= 3 && nums.every((n) => !isNaN(n))) {
      cur.wps.push({ x: nums[0], y: nums[1], z: nums[2] } as Vec3)
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
