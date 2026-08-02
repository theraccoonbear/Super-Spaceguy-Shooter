# 3D engine (`src/engine3d.bi` and `src/3d/`)

## What problem it solves

The things the player directly interacts with — ships, asteroids, pickups — are true 3D-modeled geometry, rendered with no GPU access (QB64-PE's `SCREEN`/`_NEWIMAGE` is a plain 2D pixel buffer). `src/3d/` is a from-scratch software 3D pipeline for exactly that: matrix transforms, perspective projection, backface culling, depth sorting, and scanline polygon rasterization, all in QBasic.

Not everything on screen goes through this pipeline. Planets are 2D sprite images (`assets/planet-*.png`), not modeled geometry, and the starfield backdrop (`starfield.bas`) is a parallax effect — scrolling points at different speeds to fake depth — rather than a true 3D environment. Only the objects the player actually pilots, shoots, and collides with are real 3D meshes.

`src/engine3d.bi` is the include manifest — `$INCLUDE` this one file (as `sss.bas` does) and it pulls in every module below in the right dependency order:

```
3d/types.bi      shared struct definitions (must come first — everything else depends on these)
3d/poly.bas       Z-buffer, polygon rasterizer, debug print helpers
3d/matrix.bas     4x4 matrix math
3d/camera.bas     view/projection matrices, screen-space projection
3d/mesh.bas       mesh storage, .e3d loading, mesh-to-screen drawing
3d/object.bas     per-object model matrix builder
3d/input.bas      keyboard input with edge detection (not 3D-specific, but small enough to live here)
3d/collision.bas  AABB overlap test
3d/scene.bas      cross-mesh face batching and depth sort
3d/starfield.bas  parallax star background
3d/obj.bas        Wavefront OBJ + MTL loader (for the offline obj2e3d conversion tool, not the game itself)
```

## Coordinate system

Stated directly in `assets/models.e3d`'s header comment and `obj.bas`:

```
X = forward, Y = up, Z = left. Camera sits behind (-X) and above (+Y) the subject.
```

This is a left-handed-feeling convention chosen to match how the game's camera trails behind the player ship. Model authors need to orient meshes to this convention before conversion — `obj.bas`'s loader does **not** remap axes (though the separate `obj2e3d.bas` conversion tool does support a `remap` argument for models authored in Blender's +Z-up convention).

## Core types (`3d/types.bi`)

```basic
Type E3D_Coord        ' a 3D point or vector: x, y, z As Single
Type E3D_Polygon       ' a projected/world-space polygon: count, coords(1 To 8) As E3D_Coord
Type E3D_Matrix4       ' 4x4 transform: m(0 To 3, 0 To 3) As Single
Type E3D_Camera        ' pos, target, up As E3D_Coord; fov, nearZ, farZ As Single
Type E3D_Face          ' a mesh face: up to 8 vert indices, baked normal, base color
Type E3D_Mesh          ' up to 8192 verts / 8192 faces
Type E3D_AABB          ' axis-aligned bounding box half-extents: hx, hy, hz As Single
```

## Pipeline, in order

The actual per-frame path (used by both the game and `viewer.bas`) pools every visible object's faces from *every* mesh into one shared batch before sorting and drawing, so depth ordering is correct across objects, not just within one mesh:

1. **Load meshes once at startup** — `E3D_LoadMesh(objData$, name$, mesh, aabb)` parses one named mesh out of the embedded `assets/models.e3d` text blob (format: `o NAME`, `aabb hx hy hz`, `v x y z`, `f i1 i2 i3 r g b`, `q i1 i2 i3 i4 r g b`, `end`), followed by `E3D_BakeMeshNormals` to precompute per-face normals once rather than recomputing them every frame.
2. **`E3D_SceneBegin`** resets the shared per-frame face pool (`scene.bas`'s `E3D_scn*` arrays).
3. **Per visible object**: build its model matrix (`E3D_BuildObjectMat(pos, rot, scale, mat)` — rotation X, then Y, then Z, then scale, then translation), then call `E3D_SceneAddMeshLit(mesh, modelMat, camPos, tt, lightDir)` (or `...LitTinted` for a color-tinted variant, used for e.g. asteroid damage flash). This transforms the mesh's vertices into world space, backface-culls (dot product of face normal against the camera-facing vector), computes flat directional-light shading from the mesh's baked normals rotated into world space, computes per-face depth, and appends the results — still in world space, not yet projected — into the shared pool.
4. **Build the view-projection matrix** once per frame from the camera — `E3D_MatLookAt` (view) and `E3D_MatPerspective` (projection), combined with `E3D_MatMul`.
5. **`E3D_SceneFlush(vpMat, scrW, scrH)`**, called once after every object for the frame has been added: clears the Z-buffer, insertion-sorts the *entire* pooled batch back-to-front by depth (insertion sort because between-frame ordering is usually nearly-sorted already), then for each pooled face in order: `E3D_ProjectPoly` (multiply by the view-projection matrix, perspective-divide, map NDC `[-1, 1]` to pixel coordinates — a vertex behind the near plane aborts that polygon) followed immediately by `E3D_DrawPoly` (scanline rasterize into the framebuffer, tracking a per-scanline Z-buffer so overlapping polygons within the sorted order still resolve correctly at the pixel level).

`E3D_DrawMesh` and unlit `E3D_GetMeshFaces` (in `mesh.bas`) implement an older, self-contained single-mesh version of this same idea — cull, sort, project, and draw one mesh's faces standalone, no lighting, hue-cycled face colors. Neither has any call sites left anywhere in the game, tools, or tests; treat them as dead code unless you're reviving them for something new.

## Mesh authoring workflow

Meshes are hand-written or converted, not modeled directly in this text format:

```bash
# convert a Wavefront OBJ (e.g. exported from Blender) into an .e3d block
./builds/obj2e3d model.obj <remap> <scale> SLOT_NAME
#   remap: 0 = none, 1 = Blender (-Z forward), 2 = (+Z forward)
#   scale: e.g. 0.00225 for cm-range Blender exports
```

This emits an `o SLOT_NAME ... end` block (see the format comment at the top of `assets/models.e3d`) to append into that file. `viewer.bas` (repo root) is a standalone tool for previewing a single mesh in isolation without running the whole game — useful for checking a conversion before committing it.

## Known limitations and gotchas

- **Fixed-size arrays, not dynamic.** `E3D_Mesh` caps at 8192 verts/faces; `E3D_SCENE_MAX` caps the per-frame batched face pool at 8192; `E3D_ZBUF_W`/`E3D_ZBUF_H` cap the Z-buffer at 1280×960. Exceeding any of these silently drops data rather than erroring — there's no bounds-check warning.
- **No perspective-correct texture mapping or textures at all.** Faces are flat-colored (either a baked base color or a hue-cycle fallback), optionally lit with simple directional flat shading. There's no texture sampling anywhere in this pipeline.
- **Backface culling assumes consistent winding order.** A face with vertices wound the wrong way culls (or fails to cull) incorrectly — this is a common mistake when hand-authoring `f`/`q` lines in `.e3d` directly rather than via `obj2e3d`.
- **Dead code still present**: `E3D_DrawMesh` and unlit `E3D_GetMeshFaces` (`mesh.bas`) are an older, self-contained single-mesh render path with no remaining callers — don't assume either is in use without checking call sites first, and consider removing them (separately from a docs change) if that's confirmed still true.
- **`E3D_SceneAddMeshLit`/`...Flush` must be paired correctly per frame** — `E3D_SceneBegin` has to run before any `E3D_SceneAddMeshLit*` calls, and `E3D_SceneFlush` after all of them, or you'll draw a stale or partial batch. There's no assertion enforcing the order.

## Testing in isolation

There's no automated test for the rendering pipeline itself (pixel output isn't practically assertable in this codebase's test style). To verify a mesh or rendering change:

```bash
tools/buildqb viewer.bas
builds/viewer   # or obj2e3d.bas for conversion-time checks
```

`viewer.bas` loads and displays a single named mesh with camera controls, letting you inspect a model or a rendering change without booting the full game. Beyond that, run the game itself (`--scene <name>` to jump straight to a stage — see [`src/sys/README-sequence.md`](sys/README-sequence.md)) and look at it.
