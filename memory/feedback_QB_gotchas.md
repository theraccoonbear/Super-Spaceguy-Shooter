---
name: feedback_qb64pe_gotchas
description: QB64PE reserved identifiers, parser bugs, include syntax, scoping rules, and array-passing constraints
metadata:
  type: feedback
---

## Dim SHARED required for module-level variables accessed inside Subs
In QB64PE (classic BASIC scoping), module-level `Dim` variables are NOT visible inside Subs/Functions. Without `SHARED`, each Sub that references the name creates its own implicit zero-size local, causing "Unused variable" warnings for the real one and "Subscript out of range" at runtime.

**Rule:** Any module-level variable (especially arrays) that Subs need to read or write must be declared `Dim Shared`.

**How to apply:** Every engine module that holds state used by its own Subs (e.g., scene.bas, starfield.bas) must use `Dim Shared` for all module-level variables. Variables only used at module level (not inside any Sub) can use plain `Dim`.

---

## Reserved identifiers
`pos` and `rot` are reserved in QB64PE. Sub/Function parameters named `pos` or `rot` cause "Name already in use" compile errors. Use `objPos`, `objRot`, etc.

**Why:** Parser treats them as built-in keywords in some contexts.
**How to apply:** Never name Sub/Function parameters `pos` or `rot`.

---

## Include syntax
`'$INCLUDE:'filename'` — the leading single quote is REQUIRED. Without it the directive is treated as a comment.

---

## Case insensitivity
QB64PE is fully case-insensitive. `MyVar`, `myvar`, `MYVAR` are the same identifier.

---

## Function + UDT return type bug
`Function` that returns a UDT type fails in included files. Use a `Sub` with an output parameter instead.

**Why:** QB64PE cannot return UDTs from Functions in included `.bas` files.
**How to apply:** Any engine function that produces a UDT result → `Sub E3D_Foo(..., result As MyType)`.

---

## UDT array member index bug (zero-divide parser bug)
`udtVar.arrayField(udtVar.scalarField)` — using a scalar field of the same UDT to index one of its array fields causes a parser/zero-divide error.

**Why:** QB64PE evaluates the index expression incorrectly when both the array and the index come from the same UDT variable.
**How to apply:** Extract the index to a local variable first: `Dim idx As Integer : idx = udtVar.scalarField : udtVar.arrayField(idx)`.

---

## And / Or do NOT short-circuit
Both sides of `And`/`Or` are always evaluated. This matters when one side has side effects or can produce a runtime error (e.g., array out-of-bounds, division by zero).

**How to apply:** Never rely on short-circuit evaluation. Guard each condition separately with `If`/`ElseIf` if the right-hand side could error.

---

## Global UDT arrays are unusable inside Subs in included files

All three access patterns fail when the array is declared at module level in an included `.bas` file and accessed from within a Sub:

1. **Passing as array parameter** (`globalUdtArr()`) → "Incorrect array type passed to sub"
2. **Assigning to an element** (`globalUdtArr(n) = val`) → "User defined types in expressions are invalid"
3. **Passing an element as a parameter** (`MySub globalUdtArr(n)`) → "2nd sub argument requires TYPE …"

**Fix:** Don't store UDT types in global arrays in engine modules. Decompose them into parallel scalar arrays (Single, Integer, Long) which have none of these restrictions. For example, instead of `E3D_scnPolys(1 To 450) As E3D_Polygon`, store `E3D_scnVX(1 To 450, 1 To 8) As Single` etc. Scalar global arrays can be read and written freely inside Subs.

**What IS allowed inside Subs in included files:**
- Local UDT variables (`Dim facePoly As E3D_Polygon`) — full read/write
- Local UDT arrays (`Dim tmpPolys(1 To 32) As E3D_Polygon`) — can be passed as array params to other Subs
- Reading fields of local UDT array elements (`tmpPolys(i).coords(v).x`) — fine if index is a separate local var
- Global scalar arrays (Single, Integer, Long) — full read/write
- UDT parameter-to-parameter assignment inside a Sub — fine

**Why:** QB64PE's C++ backend doesn't correctly resolve global UDT array references when inside a Sub in an included compilation unit.

---

## Const declarations must appear before first use

QB64PE processes the file top-to-bottom. If an identifier is encountered before any `Const` declaration for it, QB64PE creates an implicit variable for it. When the `Const` declaration is reached later, the compiler errors with "Name already in use (CONSTNAME)".

**Why:** Classic BASIC scoping — no forward-declaration of constants. The implicit-variable creation on first sight pre-claims the name.

**How to apply:** Place all `Const` blocks at the very top of the file, immediately after any `'$INCLUDE` directives, before any code or `Dim` statements that might reference them. This is safe because `Const` values are all literals and don't depend on types or variables being declared first.

---

## UDT instance + field name collides with Const names

QB64PE's C++ backend flattens UDT member access into `instancename_fieldname`. This means a constant named `CAM_FOV` conflicts with `cam.fov` (the `fov` field of the `cam` variable), because QB64PE sees them as the same identifier (case-insensitive). The compiler error is "Name already in use (CONSTNAME)".

**Why:** The C++ codegen joins the variable name and field name with an underscore, and QB64PE's identifier table is case-insensitive, so `cam_fov` == `CAM_FOV`.

**How to apply:** Never name a `Const` with the pattern `<varname>_<fieldname>` where `varname` is a live UDT instance and `fieldname` is one of its fields. For example, with `Dim cam As E3D_Camera` (which has a `fov` field), `CAM_FOV` is a forbidden constant name — use `GAME_FOV` or any other prefix that doesn't match an existing variable.

---

## `'$INCLUDE` order matters
Types must be defined before they are used. engine3d.bi includes `types.bi` first, then the subs that reference those types.

---

## `Shared x` inside a Sub conflicts with `Dim x` at module level

Using `Shared varname` inside a Sub causes QB64PE to emit a C++ global declaration that double-conflicts with the existing module-level `Dim varname`. The compiler errors with a duplicate symbol.

**Correct pattern:** Declare module-level variables that Subs in included files need as `Dim Shared` at declaration. Subs then access them directly — no `Shared` statement inside the Sub is needed or correct.

**How to apply:** Any variable that a Sub in an included `.bas` file must read or write: declare it `Dim Shared varname As Type` in the file where it lives. Single UDT instances (`Dim Shared boss As GameObj`) work; UDT *arrays* remain off-limits as Sub parameters per the earlier array gotcha.

---

## Function return type must use suffix, not `As Type`

`Function Foo(x As String) As Integer` is invalid in QB64-PE — the return type must be declared via name suffix: `Function Foo%(x As String)` for Integer, `Function Foo$(...)` for String, `Function Foo!(...)` for Single. The `As Type` form on a Function signature causes "Expected )" at the declaration line.

**How to apply:** Always use suffix notation on Function names for return type. `As Type` in the parameter list is fine; `As Type` on the Function name itself is not.

---

## `$EMBED` and `_LoadImage` paths resolve from the compiler's CWD, not the source file

Both `$EMBED:'path'` and `_LoadImage("path")` resolve relative to the **working directory where the compiler is invoked**, not the directory of the `.bas` file being compiled. So when building with `buildqb.sh code/3d/sss.bas` from the qb64pe root, asset paths must include the full prefix: `code/3d/assets/file.png`, not just `assets/file.png`.
