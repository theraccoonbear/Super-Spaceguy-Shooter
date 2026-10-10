// Regression coverage for the .e3d parser and its "axisfix" per-model
// correction -- the single declared fact that keeps this parser and the
// game's E3D_LoadMesh (src/3d/mesh.bas) applying the same mesh-orientation
// correction instead of independently re-deriving it (issue #181's
// follow-up: this class of drift is exactly what caused the boss orientation
// saga in the first place).
import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { parseE3DBlock } from './e3d'

const withAxisFix = `o TESTSHIP
aabb 1 1 1
axisfix -1 1 -1
v 1 2 3
v -1 -2 -3
f 1 2 1 10 20 30
end`

const withoutAxisFix = `o TESTSHIP
aabb 1 1 1
v 1 2 3
f 1 1 1 10 20 30
end`

const withQuad = `o TESTSHIP
aabb 1 1 1
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
q 1 2 3 4 200 200 200
end`

describe('parseE3DBlock', () => {
  it('defaults axisFix to [1,1,1] and leaves vertices unchanged when absent', () => {
    const mesh = parseE3DBlock(withoutAxisFix)!
    expect(mesh.axisFix).toEqual([1, 1, 1])
    expect(mesh.vertices[0]).toEqual([1, 2, 3])
  })

  it('applies a declared axisfix to every vertex as it is parsed', () => {
    const mesh = parseE3DBlock(withAxisFix)!
    expect(mesh.axisFix).toEqual([-1, 1, -1])
    // v 1 2 3 -> (-1, 2, -3); v -1 -2 -3 -> (1, -2, 3)
    expect(mesh.vertices[0]).toEqual([-1, 2, -3])
    expect(mesh.vertices[1]).toEqual([1, -2, 3])
  })

  it('parses face color and 1-based indices', () => {
    const mesh = parseE3DBlock(withoutAxisFix)!
    expect(mesh.faces[0].indices).toEqual([1, 1, 1])
    expect(mesh.faces[0].color).toEqual([10, 20, 30])
  })

  it('keeps quad faces as 4 indices (triangulation is the renderer\'s job)', () => {
    const mesh = parseE3DBlock(withQuad)!
    expect(mesh.faces[0].indices).toEqual([1, 2, 3, 4])
    expect(mesh.vertices).toHaveLength(4)
  })

  it('returns null for text that is not an object block', () => {
    expect(parseE3DBlock('not a block')).toBeNull()
  })
})

// Ground-truth orientation checks against the REAL asset file, not synthetic
// fixtures -- the point of "axisfix rollout beyond BOSS" (see the .e3d
// header's axisfix comment) is verifying each candidate cutscene-actor
// model's actual mesh geometry, the same way BOSS's belly-at-negative-Y
// fact was confirmed from real vertex/face-color data rather than guessed.
// PLAYER is the only other model TrailForge currently loads (PerspView's
// playerShipRef); a future actor gets the same treatment before being
// trusted to path-follow.
function readRealBlock(name: string): string {
  const path = resolve(__dirname, '../../../../assets/models.e3d')
  const text = readFileSync(path, 'utf-8')
  const start = text.indexOf(`o ${name}\n`)
  if (start < 0) throw new Error(`readRealBlock: no "o ${name}" block in assets/models.e3d`)
  const end = text.indexOf('\nend', start)
  return text.slice(start, end + 4)
}

describe('PLAYER mesh orientation (ground truth from the real asset)', () => {
  it('has no declared axisfix -- its source .obj already matches the X=forward convention', () => {
    const mesh = parseE3DBlock(readRealBlock('PLAYER'))!
    expect(mesh.axisFix).toEqual([1, 1, 1])
  })

  it('nose points toward +X: the +X end is a narrow tip, the -X end is the wide wing/tail cluster', () => {
    // Confirmed by hand once (mesh.vertices count, spread near each X
    // extreme) when this test was written -- pinned here so a future
    // re-export of PLAYER's source .obj can't silently flip its facing
    // without a test noticing, the same class of drift that hid in BOSS
    // until someone actually looked at the mesh data.
    const mesh = parseE3DBlock(readRealBlock('PLAYER'))!
    const xs = mesh.vertices.map(v => v[0])
    const minX = Math.min(...xs), maxX = Math.max(...xs)

    const spreadNear = (targetX: number) => {
      const near = mesh.vertices.filter(v => Math.abs(v[0] - targetX) < 0.1)
      const ys = near.map(v => v[1]), zs = near.map(v => v[2])
      return {
        count: near.length,
        ySpread: ys.length ? Math.max(...ys) - Math.min(...ys) : 0,
        zSpread: zs.length ? Math.max(...zs) - Math.min(...zs) : 0,
      }
    }
    const nose = spreadNear(maxX)   // +X end -- should be the pointed tip
    const tail = spreadNear(minX)   // -X end -- should be the wide body/wings

    expect(nose.count).toBeLessThan(tail.count)
    expect(nose.ySpread).toBeLessThan(tail.ySpread)
    expect(nose.zSpread).toBeLessThan(tail.zSpread)
  })
})
