// Regression coverage for the .e3d parser and its "axisfix" per-model
// correction -- the single declared fact that keeps this parser and the
// game's E3D_LoadMesh (src/3d/mesh.bas) applying the same mesh-orientation
// correction instead of independently re-deriving it (issue #181's
// follow-up: this class of drift is exactly what caused the boss orientation
// saga in the first place).
import { describe, it, expect } from 'vitest'
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
