// Parser for the game's .e3d mesh format (assets/models.e3d), so TrailForge
// can render the ACTUAL baked asset instead of a generic placeholder ship --
// see issue #181's follow-up: the placeholder never validated real mesh
// orientation, which is exactly where the boss orientation bug hid.
//
// Format (assets/models.e3d header): o NAME, aabb hx hy hz, [axisfix sx sy sz],
// v x y z, f i1 i2 i3 r g b, q i1 i2 i3 i4 r g b, end. Indices are 1-based.
// axisfix is applied to vertices as they're parsed (matching E3D_LoadMesh),
// so downstream code never needs its own per-model correction.
// Mirrors src/3d/mesh.bas's E3D_LoadMesh -- keep in sync by hand (this file
// is not ExprForge-generated; it's a straight parser, not shared math).

export interface E3DFace {
  indices: number[]      // 1-based vertex indices, 3 (tri) or 4 (quad)
  color: [number, number, number]
}

export interface E3DMesh {
  name: string
  aabb: [number, number, number]
  axisFix: [number, number, number]   // per-axis sign correction; [1,1,1] if the block declares none
  vertices: [number, number, number][]
  faces: E3DFace[]
}

export function parseE3DBlock(text: string): E3DMesh | null {
  const lines = text.split('\n').map(l => l.trim()).filter(l => l.length > 0)
  if (lines.length === 0 || !lines[0].startsWith('o ')) return null

  const name = lines[0].slice(2).trim()
  const vertices: [number, number, number][] = []
  const faces: E3DFace[] = []
  let aabb: [number, number, number] = [0, 0, 0]
  // Per-axis sign correction for a model whose source .obj axes don't match
  // this app's convention (forward=+X, up=+Y, right=+Z) -- see the .e3d
  // file's header comment. Declared once in the asset, read by BOTH this
  // parser and the game's E3D_LoadMesh (src/3d/mesh.bas) so the correction
  // is a single fact, not independently re-derived per language.
  let axisFix: [number, number, number] = [1, 1, 1]

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i]
    if (line === 'end') break
    const parts = line.split(/\s+/)
    const tag = parts[0]
    if (tag === 'aabb') {
      aabb = [Number(parts[1]), Number(parts[2]), Number(parts[3])]
    } else if (tag === 'axisfix') {
      axisFix = [Number(parts[1]), Number(parts[2]), Number(parts[3])]
    } else if (tag === 'v') {
      vertices.push([
        Number(parts[1]) * axisFix[0],
        Number(parts[2]) * axisFix[1],
        Number(parts[3]) * axisFix[2],
      ])
    } else if (tag === 'f') {
      faces.push({
        indices: [Number(parts[1]), Number(parts[2]), Number(parts[3])],
        color: [Number(parts[4]), Number(parts[5]), Number(parts[6])],
      })
    } else if (tag === 'q') {
      faces.push({
        indices: [Number(parts[1]), Number(parts[2]), Number(parts[3]), Number(parts[4])],
        color: [Number(parts[5]), Number(parts[6]), Number(parts[7])],
      })
    }
  }

  return { name, aabb, axisFix, vertices, faces }
}

export async function fetchE3DModel(name: string): Promise<E3DMesh | null> {
  try {
    const res = await fetch(`/api/models/${encodeURIComponent(name)}`)
    if (!res.ok) return null
    return parseE3DBlock(await res.text())
  } catch {
    return null
  }
}
