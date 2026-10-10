# ExprForge wishlist: array/sequence support for shared indexing logic

Status: exploratory. Nothing here is scheduled or approved. Grounded in the actual
ExprForge source at `/var/home/don/code/exprforge` and its actual usage in this repo
(`math/formula.expr`, `tools/emit-spline.js`, `src/gameplay/spline_path.bi`,
`tools/TrailForge/src/math/spline.ts`) as of this writing.

## 1. The concrete problem

ExprForge's AST (`ast.js`) has exactly these node types: `num`, `var`, `bin`, `call`,
`let`, `cmp`, `select`, `outputs`, `field`. Every one of them operates on scalars
(JS `number`) or, via `outputs`, a fixed fanout of named scalars. There is no array
type anywhere in the codebase — confirmed by grep: the only hits for "array" in
`ast.js`/`expr.js`/`fn.js`/`macros.js`/`evaluate.js`/`load-expr.js`/`emitters/base.js`
are JS-level plumbing (`Array.isArray(fn.params)`, an `argStrs` array passed to an
extern template) — never a DSL-level array value.

That's fine for every function actually in `math/formula.expr` today —
`SpEfCrWeights`, `SpEfMkFrame`, `SpEfTransportFrame`, etc. are all pure
scalar-in/scalar-or-tuple-out. But the logic that wraps an array of waypoints and
picks out the 4 Catmull-Rom control points for a segment — with different index
math for open vs. closed paths, and special-cased wraparound at the two boundary
segments of a closed loop — could not be expressed in the DSL, because it needs
array indexing conditioned on array length. So it was hand-written twice:

- QB64: `SpCrGhosts` in `src/gameplay/spline_path.bi` (lines 27-41), plus
  `seaNS = seaNW - 1` / `staNS = staNW - 1` / `sraNS = sraNW - 1` duplicated across
  `SpEvalAt`, `SpTangentAt`, `SpEvalRollAt` in the same file, plus a fourth
  independent copy — `bsmFlNS = bsmWpCount - 1` — in `src/gameplay/behavior.bas`
  (line 173).
- TypeScript: `ghosts()` and `segCount()` in `tools/TrailForge/src/math/spline.ts`
  (lines 49-72), formerly inlined as `wps.length - 1` at 5+ call sites across
  `spline.ts` itself, `App.tsx` (3 places), `shortcuts.ts` (1 place), and
  `BehaviorsPanel.tsx` (5 places) before this session's `segCount()` refactor
  consolidated the TS side onto one function.

Two real bugs came directly out of this duplication:

1. **Issue #211**: independently-introduced, independently-shaped off-by-one at
   the closed-loop seam, producing a zero-length degenerate segment and a visible
   tangent flip.
2. **The "teleport from last waypoint to node 0" bug**: `store.ts`'s
   `normalizePath()` (line 205) strips a closed path's duplicate closing waypoint
   from the live in-memory array once first/last coincide within `eps = 0.001`.
   The QB64 loader has no equivalent step — it always sees the on-disk convention
   (an explicit duplicate). TS's hand-written `ghosts()`/segment-count logic
   assumed the duplicate was always present; when the store had already stripped
   it, `nSegs` undercounted by one and the final segment was silently skipped
   during playback. QB64 was structurally immune (never sees a deduped array) —
   but per this project's own stated philosophy ("shared math, single source of
   truth"), the algorithm wasn't actually shared at the point where the bug lived.
   It was two separately-typed encodings of the same *intent* that happened to
   agree until one side's environment changed.

The current fix (`tools/TrailForge/src/math/spline.ts`'s `hasDuplicateClosingPoint()`
+ `segCount()`) is a real, working fix, but it's still hand-duplication risk with a
test-detection safety net (`tests/mnv_conformance_test.bas`,
`tools/TrailForge/src/math/loop-seam.test.ts`) bolted on after the fact, not
elimination of the duplication at the root. This document is about what ExprForge
itself would need in order to let this class of logic be written once.

## 2. Array/sequence as a first-class type

**What's needed:** a parameter/return type annotation beyond bare scalar — e.g.
`fn ghostIndices(waypoints: number[], seg, closed): ...` — and an `index` AST node
(`{ type: "index", target: Node, at: Node }`) plus array-typed `var`/`param` nodes.

**QB64 emitter implications.** QB64-PE arrays are fixed-dimension and passed by
reference using bare `()` in the parameter list — this is exactly the convention
`spline_path.bi` already uses by hand:

```
Sub SpEvalAt (seaWps() As E3D_Coord, seaNW As Integer, seaAt As Single, seaCl As Integer, ...)
```

Note the array arrives **with no length of its own** — QB64 arrays don't carry
their bound at the call boundary the way a TS `array.length` does, which is why
every hand-written sub above also takes an explicit `seaNW As Integer` count
parameter alongside the array. An ExprForge array parameter would need to lower to
this same *(array, explicit count)* pair in the QB64 emitter — there's no way to
avoid it; QB64 has no runtime-queryable array length across a Sub boundary in the
general case (`UBOUND` only works if the array was dimensioned in a way the callee
can see, which isn't guaranteed for a passed-in array in a `.bi`-included Sub). The
emitter would also need `checkReservedNames`-style validation extended to whatever
naming convention it picks for the synthesized count parameter, and a decision
about element type — the existing `formatFunction`/`formatSuite` machinery in
`emitters/qb64.js` hard-codes `AS DOUBLE` for every scalar; an array parameter of
`E3D_Coord` (a struct, not a DOUBLE) is a second, harder problem (see §7 — likely
out of scope for a first cut, which should probably support only arrays of the
DSL's own scalar type, i.e. `DOUBLE`/`number[]` — not arbitrary structs).

**TypeScript emitter implications.** Much closer to a non-issue: `formatFunction`
in `emitters/typescript.js` already builds `fn.params.map(p => \`${p}: number\`)`;
an array-typed param just needs `: number[]` instead of `: number` for that one
parameter, and the return, if array-typed, needs either `number[]` or a typed
tuple (`[number, number, number, number]` reads better for a fixed 4-ghost return
than `number[]`, and TS supports it natively).

**Net asymmetry to be honest about:** QB64's "array + explicit length, no bounds
safety" is a fundamentally leakier abstraction than TS's `number[]`. Any DSL-level
array type needs its emitted QB64 form to be exactly as unsafe as
hand-written `spline_path.bi` already is today (out-of-range indexing is a runtime
crash or silent garbage read in both) — ExprForge is not in a position to add
bounds-checking QB64 doesn't have, and pretending otherwise in the DSL's semantics
would create a QB64/TS behavior mismatch on out-of-range input, which is the exact
kind of drift this whole feature exists to eliminate.

## 3. Indexing + wraparound/clamp semantics

This is the actual payload of `SpCrGhosts`/`ghosts()`. Concretely, today's TS
version (`spline.ts` lines 59-72):

```ts
function ghosts<T extends Vec3>(wps: T[], seg: number, closed: boolean): [T, T, T, T] {
  const n = wps.length
  if (closed) {
    const m = hasDuplicateClosingPoint(wps) ? n - 1 : n
    const at = (i: number) => wps[((i % m) + m) % m]
    return [at(seg - 1), at(seg), at(seg + 1), at(seg + 2)]
  }
  return [
    wps[Math.max(0, seg - 1)],
    wps[seg],
    wps[Math.min(n - 1, seg + 1)],
    wps[Math.min(n - 1, seg + 2)],
  ]
}
```

and the QB64 twin (`spline_path.bi` lines 27-40) hand-encodes the identical two
policies (`((i % m) + m) % m` wraparound vs. `Math.max`/`Math.min` clamp) using
QB64's own `If ... Then` idiom.

**What a primitive would need to look like:** two small, composable index
primitives, not a bespoke `ghosts`-shaped macro (a macro that only solves this one
call site is exactly the kind of narrow, single-purpose tool this project's own
`math/index.js`-style helpers (`safeDiv`, `len3`, `dot3`, ...) deliberately avoid
being — see macros.js's own framing of a macro as reusable math, not
call-site-specific logic):

```
wrapIndex(i, m)          -- ((i % m) + m) % m        -- closed-path cyclic index
clampIndex(i, lo, hi)    -- max(lo, min(hi, i))       -- open-path boundary clamp
```

Both are pure scalar-in/scalar-out — they don't themselves need array support,
only `%` (modulo), which ExprForge's `bin` node doesn't have today (`BIN_OPS` in
`ast.js` is `{+, -, *, /}` only) and would need adding, or expressing via
`floor`/`mul`/`sub` (`a - floor(a/m)*m`), which is more Number-format-fragile
(negative-input floor-mod edge cases) than a real `%`/`MOD` op — QB64 has `MOD`
(integer) but no floating modulo built-in, so `wrapIndex` as a *primitive*
(mapped straight to each target's native op, the same "one JSON entry, N language
templates" shape `primitives.js`/`PRIMITIVE_ARITY` already uses for `atan2`/`hypot`)
is likely cleaner than trying to build it purely out of existing `bin`/`call` nodes.

`ghosts()` itself, once array param support (§2) and these two primitives exist,
becomes directly expressible:

```
fn ghosts(wps: number[], n, seg, closed):
  let m = closed ? n - 1 : n;                  # (n already accounts for hasDuplicateClosingPoint at the call site)
  let i0 = closed ? wrapIndex(seg - 1, m) : clampIndex(seg - 1, 0, n - 1);
  let i1 = seg;
  let i2 = closed ? wrapIndex(seg + 1, m) : clampIndex(seg + 1, 0, n - 1);
  let i3 = closed ? wrapIndex(seg + 2, m) : clampIndex(seg + 2, 0, n - 1);
  return { p0: wps[i0], p1: wps[i1], p2: wps[i2], p3: wps[i3] };
```

This is the crux of the wishlist: with array params + `wrapIndex`/`clampIndex` +
the `select`-based conditional ExprForge already has (§4), `ghosts()` is a
straight-line, no-loop function — no new control-flow primitive is required for
this specific case.

## 4. Conditionals — already present; not the actual gap

ExprForge already has a conditional *value* expression: `select(cond, then, else)`
in `ast.js` (line 163), surfaced in `expr.js`'s ternary grammar (`cond ? then :
else`, `parseTernary`, lines 248-267) and used constantly in `formula.expr` — e.g.
`SpEfMkFrame`'s `abs(ty) > 0.98 ? 0 : 1` (line 36) and `SpEfVelocityAttitude`'s
clamp-by-nested-ternary (lines 296-298). Every emitter implements it: the default
is a native ternary (`emitters/base.js`'s `_defaultSelect`), with QB64's
`emitSelect` override (`emitters/qb64.js` lines 73-78) doing the documented
arithmetic trick (`(-1*then)*cond + else*(1+cond)`) since QB64 has no ternary
operator.

So `ghosts()`'s closed/open branch and the boundary-segment special case are **not
blocked by missing conditionals** — `select()` already covers exactly this
"choose between two computed values based on a comparison" shape, including
nested/chained conditionals (`SpEfVelocityAttitude`'s clamp already nests two).
The real gap is squarely §2 (array parameter/index types) and §3 (the wrap/clamp
index math) — not control flow. This is worth stating plainly because "add
if/else to the DSL" is the obvious first guess at what's missing, and it's wrong;
don't scope an implementation around adding conditionals that already exist.

## 5. Struct/tuple return values — already present; extend, don't invent

`ghosts()` needs to return 4 points (or, per the leaner sketch above, 4 indices,
letting the caller do the actual array reads — see §6 for why that framing
matters). ExprForge already has multi-value return via `outputs()` (`ast.js` line
174) — `SpEfCrWeights` is the exact precedent named in the prompt for this:

```
fn SpEfCrWeights(t):
  ...
  return { w0: ..., w1: ..., w2: ..., w3: ... };
```

which every scalar-only emitter already renders as its own idiom: TypeScript gets
a named `interface SpEfCrWeightsResult { w0: number; ...}` plus an object literal
(`emitters/typescript.js` `formatSuite`), QB64 gets a `SUB` with the outputs as
by-reference trailing parameters (`emitters/qb64.js` `formatSuite`, since "QB64 has
no struct/tuple return" per that file's own comment).

**What's precisely missing to extend this to array-typed outputs:** `outputs()`'s
fields are typed as scalar Nodes throughout the pipeline — `collectLets` (`ast.js`),
`checkUnboundVars`, `evalNode`'s `"outputs"` case (`evaluate.js`), and both
`formatSuite` implementations assume every field renders as one number. Returning
`{ p0: wps[i0], p1: wps[i1], ... }` (points, not scalars) requires either (a) the
field values themselves become struct-typed (needs a struct type, a much bigger
addition than array-of-number — see §7), or (b) `ghosts()` returns the 4 *indices*
as a plain 4-scalar `outputs()` (already fully supported, zero new capability
needed) and the caller does `wps[i0]`, `wps[i1]`, etc. itself in ordinary
QB64/TS code, same as `spline_path.bi`'s `SpEvalAt` already does today around its
hand-written `SpCrGhosts` call. **(b) is the pragmatic scope-limiter**: it turns
"ExprForge needs struct-typed multi-output" into "ExprForge needs one array
parameter type, one index primitive pair, and zero new return-value machinery" —
a materially smaller ask than it first looks, at the cost of leaving one line of
hand-written array-read plumbing (`p0 = wps(i0)`) at each of the now-small number
of call sites. Given how narrow that residual really is, it is likely not worth
chasing a struct-array return type at all for this specific bug class.

## 6. Iteration/loop constructs — NOT needed for this bug class

`ghosts()` (both today's hand-written versions and the sketch in §3) does not
loop. It performs 4 fixed, statically-known index computations — `seg-1, seg,
seg+1, seg+2` — each independently wrapped or clamped. A `for i in 0..n` construct
would not simplify this at all; there's nothing here to iterate.

Where a real loop *would* eventually matter, based on what else was read for this
document: `behavior.bas`'s phase-trigger scan —

```basic
For bsmPtI = 0 To bsmPhaseTrigCount - 1
    If bsmPhaseTrigFired(bsmPtI) = 0 And boss.arcAngle >= bsmPhaseTrigT(bsmPtI) * bsmFlNS Then
        bsmPhaseTrigFired(bsmPtI) = 1
        boss.phase = bsmPhaseTrigVal(bsmPtI)
    End If
Next bsmPtI
```

is a genuine bounded scan-with-side-effect over an array — but it currently has
**no TypeScript counterpart that fires/accumulates state**. TrailForge does have
its own `path.triggers` array (including a `'phase'` trigger type — see
`store.ts` line 25, `BehaviorsPanel.tsx`'s `TRIGGER_TYPES`), but the TS side only
*authors and exports* trigger data (`format.ts` serializes it) and *draws* markers
for preview (`behaviorMarkers.ts` line 168 loops over `path.triggers` purely to
render diamonds) — there is no TS walk that fires a trigger once and accumulates
a `phase`-like state the way `behavior.bas`'s `bsmPhaseTrigFired()` flag array
does. So this loop's *fire-once-per-pass state machine* semantics exist in exactly
one language today, not two — no live cross-language drift risk yet. Similarly,
`tools/TrailForge/src/math/segmentTrack.ts`'s `evalGenericSegments()` (the shared
engine behind `craftRoll.ts` and every scalar behavior track) does a real
`sorted.find`-style walk over an array with early-exit (`for (const seg of
sorted) { if (af <= seg.t) break; ... }`) — but this, too, has no QB64 counterpart:
`behavior.bas` never evaluates segment tracks (`craftRollSegments`,
`segmentTracks`) at all; those are TrailForge-editor-only preview/authoring
concepts as far as could be confirmed by reading `behavior.bas` end to end. So
today, neither of these loop-shaped pieces of logic is actually duplicated
cross-language — they're single-language, and out of scope for *this* wishlist,
which is specifically about eliminating hand-duplication. Flagged here only so a
loop construct isn't added speculatively against a duplication risk that doesn't
exist yet; if either of these ever gains a QB64 mirror, that would be the point to
revisit bounded-loop support, not before.

**Conclusion for this section:** don't scope "loop support" into the near-term
ask. It solves a problem this codebase doesn't currently have, at a much larger
design cost (see §7's sizing) than the array-param + index-primitive work that
actually would fix the `ghosts()` class of bug.

## 7. Incremental path and sizing

ExprForge emits to 18 language targets today
(`c, cobol, csharp, exprsyntax, fortran, go, java, js, julia, lua, perl, php,
python, qb64, rust, scheme, typescript, zig` — from `ls emitters/`). A breaking
change to the AST/type system has to either work for, or be explicitly
unsupported-but-non-breaking in, all 18. That constrains every increment below to
be additive: existing scalar-only `fn`/`macro` definitions and every existing
emitter must keep working with zero changes if they never use the new array type.

**Increment A — array parameter + index primitives (small-medium).**
Scope: an array-of-number parameter type; `index` AST node (array `var` + `[i]`);
`wrapIndex`/`clampIndex` as new built-in primitives (extend `PRIMITIVE_ARITY` in
`primitives.js`, `CALLS` in `evaluate.js`, and the `calls` table in every emitter
that should support them — realistically, ship it only for `qb64`+`typescript`
first and let the other 16 emitters throw a clear "array params not supported for
this target" error, the same pattern `formatSuite` already uses for suites
(`emitters/base.js` line 131-133: `if (!this.formatSuiteImpl) throw ...`)).
Covers exactly `ghosts()`, returning 4 indices per §5(b) — this alone is enough to
delete `SpCrGhosts`/`ghosts()`/`hasDuplicateClosingPoint()`'s duplicated logic and
replace both with generated code from one `formula.expr` function. Does NOT cover
`segCount()`'s `hasDuplicateClosingPoint()` array *scan* (checking `wps[0]` against
`wps[wps.length-1]`) — that's one more array-read + one more comparison, still
loop-free, so it fits in this same increment, not the next one. Risk: none of the
other 16 emitters gain anything; this is explicitly QB64+TS-only scope creep
contained to two files.

**Increment B — general bounded iteration (`for i in lo..hi`, or a `reduce`/`scan`
primitive) (large).**
Scope: a real loop/accumulator AST node; QB64 emission as a `FOR...NEXT` (natural
fit — QB64 already has this), TS emission as a `for` loop or `.reduce()` (also a
natural fit); but also needs a decision on side effects (`ast.js`'s whole model
today is "expression tree, no statements, no mutation" — introducing a stateful
loop accumulator is a bigger philosophical shift than array params, closer to
"this is now a small imperative language," which cuts against the project's own
"expression AST, not a program AST" framing (see `expr.js`'s header comment,
explicit about deliberately not having this)); interacts with `collectLets`'s flat,
order-only let-model (a loop body's per-iteration bindings don't fit the current
"one flat list per function" scheme (`ast.js` `collectLets` doc comment) without
real nested scoping, which doesn't exist today either). Not currently justified by
any known duplicated bug (see §6) — speculative work against a risk that hasn't
materialized.

**Genuine risk if A ships without ever doing B:** array support with no
loop/reduce leaves ExprForge able to express "pick N statically-known indices out
of an array" (ghosts-shaped problems) but not "fold over an array of unknown
length" (e.g. if a future shared algorithm needs a running sum/min/max over all
waypoints, or the phase-trigger scan in §6 ever needs to be shared cross-language).
That's an acceptable, explicitly-scoped gap for now — not a hidden trap — as long
as it's written down: Increment A solves the bug class in this document, not
"arrays in ExprForge" as a general capability.

## 8. What this would NOT solve

- **`hasDuplicateClosingPoint()`'s coincidence-epsilon convention** (`DUP_EPS =
  0.001` in `spline.ts`, matching `store.ts`'s own `eps = 0.001` in
  `normalizePath`) is itself shareable scalar math (`abs(a-b) < eps`) and could
  already be written in ExprForge today with zero new features — its duplication
  (`store.ts` and `spline.ts` each hard-code `0.001` independently right now) is
  a pre-existing, *already fixable* small case that this document's proposed
  features don't uniquely unlock. Worth its own tiny fix regardless of anything
  else here.
- **`normalizePath()`'s actual mutation** (slicing the array, saving to
  localStorage, `zundo` undo-stack interaction) is inherently TS/React-store
  specific — no version of ExprForge should or could generate this; it isn't math,
  it's application state management.
- **QB64 `Sub`/`Function` dispatch, `$INCLUDE` ordering, and the whole
  module-wide-Dim-scope namespacing convention** (`formula.expr`'s own header
  comment documents the mf/ap/rf/... prefix scheme that exists solely to work
  around this QB64 quirk) stays exactly as hand-managed as it is today. Array
  support doesn't touch it.
- **React state/hooks, the Vite dev-server `/api/maneuvers` plugin, zustand/zundo
  undo semantics, canvas drawing (`behaviorMarkers.ts`, `useOrthoCanvas`)** — all
  genuinely TS/React-only concerns with no QB64 or cross-language analog at all;
  out of scope for ExprForge by definition, not by current limitation.
- **The phase-trigger scan and `evalGenericSegments()`** (§6) are NOT solved by
  anything in this document, on purpose — they need real loop support (Increment
  B, or whatever supersedes it), and more importantly, neither is actually
  duplicated cross-language today, so there is nothing currently broken for
  ExprForge to fix there. If one of them later grows a second-language
  implementation, that's the trigger to revisit, not a reason to build loop
  support speculatively now.
- **Bounds safety.** As noted in §2, an ExprForge array type would faithfully
  reproduce QB64's lack of bounds checking, not paper over it. Out-of-range
  indexing bugs in generated code remain exactly as possible as they are in today's
  hand-written `spline_path.bi`/`spline.ts` — ExprForge only guarantees the QB64
  and TS *logic* agrees, never that either is safe against bad input on its own.
