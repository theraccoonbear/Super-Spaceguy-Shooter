# Flight path math

**All spline flight-path math lives in [`math/formula.expr`](../math/formula.expr)**, written in the [exprforge](https://www.npmjs.com/package/exprforge) DSL. It is the single source of truth for every flight-path calculation.

Gameplay doesn't use it today. The boss uses hand-coded hunt/evade movement, and spline routes are kept for possible cinematics. See [ADR-0001](adr/0001-rail-shooter-scope.md).

Do not hand-edit the generated files. `node tools/emit-spline.js` (run from the repo root, after `npm install` in `math/`) regenerates both downstream targets from the DSL:

| Generated file | Language | Consumer |
|---|---|---|
| `src/gameplay/spline_path_gen.bi` | QB64-PE | Game runtime (`behavior.bas` flyover states; not used by gameplay) |
| `tools/TrailForge/src/math/spline_gen.ts` | TypeScript | TrailForge preview |

`tools/buildqb sss.bas` runs the emit script on every build (locally and in CI), and the test runner regenerates `spline_path_gen.bi` when it is missing or older than its inputs, so the QB64 output is always fresh. `spline_path_gen.bi` is gitignored: never commit it. `spline_gen.ts` is tracked: if you add or change a function in the DSL, run the emit script (or `tools/dev emit`) and commit the regenerated `spline_gen.ts` with your `formula.expr` change.

Implemented algorithms: Catmull-Rom position/tangent weights, Gram-Schmidt frame, standoff offset, arc-length reparameterization, and Rodrigues parallel transport for smooth ship-body orientation.
