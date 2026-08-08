// math/spline-frame.js
// ALL boss-flight spline math lives here as exprforge DSL.
// This file is the single source of truth — pure JS, no QB64, no TypeScript.
//
// QB64-PE SCOPE RULE: All Dim statements inside Subs share a module-wide namespace.
// Every letChain name below uses a function-specific prefix to prevent collisions:
//   mf = SpEfMkFrame     ap = SpEfActualPos    rf = SpEfRollFrame
//   cw = SpEfCrWeights   dw = SpEfCrDerivWeights
//   fn = SpEfFacingNorm  aa = SpEfArcAdvance    tf = SpEfTransportFrame
//
// NOTE: normalize3 (exprforge/math) injects a fixed binding __exprforgeMathNrmLen2.
// Only one Sub in the compilation unit may use it — that is SpEfFacingNorm.
// All other normalizations use explicit safeDiv letChain pairs to avoid collision.
//
// Downstream generated files (never hand-edit):
//   src/gameplay/spline_path_gen.bi           QB64
//   tools/path_editor/src/math/spline_gen.ts  TypeScript
//
// Regenerate both with:  node tools/emit-spline.js

'use strict';

const { num, v, add, mul, sub, div, neg, letChain, select, cmp, outputs, call } = require('exprforge');
const { safeDiv, dot3, len3, cross3, normalize3 } = require('exprforge/math');

// ── Project-local helpers (not generic enough for exprforge/math) ─────────

const PI       = num(3.141592653589793);
const degToRad = (degVar) => mul(degVar, div(PI, num(180)));

// worldUp branch: (0,0,1) when |ty|>0.98, else (0,1,0).
// References the param named "ty" — valid for any Sub that uses this param name.
const nearVert = cmp(call("abs", v("ty")), ">", num(0.98));

// Gram-Schmidt letChain pairs: T × worldUp → right vector, then normalize.
// Returns array of [name, expr] pairs for use in letChain([...pairs], body).
// `prefix` namespaces all bindings so mf/ap never collide in QB64 scope.
function gramSchmidtPairs(prefix) {
    return [
        [prefix+'Wy',     select(nearVert, num(0), num(1))],
        [prefix+'Wz',     select(nearVert, num(1), num(0))],
        // T × worldUp (worldUp.x = 0, so CrossY simplifies to -tx*Wz)
        [prefix+'CrossX', sub(mul(v("ty"), v(prefix+"Wz")), mul(v("tz"), v(prefix+"Wy")))],
        [prefix+'CrossY', neg(mul(v("tx"), v(prefix+"Wz")))],
        [prefix+'CrossZ', mul(v("tx"), v(prefix+"Wy"))],
        [prefix+'RLen',   len3(v(prefix+"CrossX"), v(prefix+"CrossY"), v(prefix+"CrossZ"))],
        [prefix+'RxN', safeDiv(v(prefix+"CrossX"), v(prefix+"RLen"), num(0))],
        [prefix+'RyN', safeDiv(v(prefix+"CrossY"), v(prefix+"RLen"), num(0))],
        [prefix+'RzN', safeDiv(v(prefix+"CrossZ"), v(prefix+"RLen"), num(1))],
    ];
}

// ── SpEfMkFrame ───────────────────────────────────────────────────────────
// Gram-Schmidt frame from normalized tangent (tx, ty, tz).
// worldUp = (0,0,1) when |ty|>0.98, else (0,1,0).
// R = normalize(T × worldUp),  U = R × T
// Outputs: rx, ry, rz, ux, uy, uz

const SpEfMkFrame = {
    name: "SpEfMkFrame",
    params: ["tx", "ty", "tz"],
    body: letChain(gramSchmidtPairs("mf"), outputs({
        rx: v("mfRxN"),
        ry: v("mfRyN"),
        rz: v("mfRzN"),
        ux: sub(mul(v("mfRyN"), v("tz")), mul(v("mfRzN"), v("ty"))),
        uy: sub(mul(v("mfRzN"), v("tx")), mul(v("mfRxN"), v("tz"))),
        uz: sub(mul(v("mfRxN"), v("ty")), mul(v("mfRyN"), v("tx"))),
    })),
};

// ── SpEfActualPos ─────────────────────────────────────────────────────────
// actual = wire + standoff*(cos(pathRoll)*U + sin(pathRoll)*R)
// Params: wx, wy_wire, wz_wire, tx, ty, tz, prDeg, so
// (wy_wire avoids collision with the local apWy binding)
// Outputs: x, y, z

const SpEfActualPos = {
    name: "SpEfActualPos",
    params: ["wx", "wy_wire", "wz_wire", "tx", "ty", "tz", "prDeg", "so"],
    body: letChain([
        ...gramSchmidtPairs("ap"),
        ["apUx", sub(mul(v("apRyN"), v("tz")), mul(v("apRzN"), v("ty")))],
        ["apUy", sub(mul(v("apRzN"), v("tx")), mul(v("apRxN"), v("tz")))],
        ["apUz", sub(mul(v("apRxN"), v("ty")), mul(v("apRyN"), v("tx")))],
        ["apRad", degToRad(v("prDeg"))],
        ["apC",   call("cos", v("apRad"))],
        ["apS",   call("sin", v("apRad"))],
    ], outputs({
        x: add(v("wx"),      mul(v("so"), add(mul(v("apC"), v("apUx")), mul(v("apS"), v("apRxN"))))),
        y: add(v("wy_wire"), mul(v("so"), add(mul(v("apC"), v("apUy")), mul(v("apS"), v("apRyN"))))),
        z: add(v("wz_wire"), mul(v("so"), add(mul(v("apC"), v("apUz")), mul(v("apS"), v("apRzN"))))),
    })),
};

// ── SpEfRollFrame ─────────────────────────────────────────────────────────
// rolledU = cos(rad)*U - sin(rad)*R
// rolledR = sin(rad)*U + cos(rad)*R
// Params: ux, uy, uz, rx, ry, rz, crDeg
// Outputs: rolledUx, rolledUy, rolledUz, rolledRx, rolledRy, rolledRz

const SpEfRollFrame = {
    name: "SpEfRollFrame",
    params: ["ux", "uy", "uz", "rx", "ry", "rz", "crDeg"],
    body: letChain([
        ["rfRad", degToRad(v("crDeg"))],
        ["rfC",   call("cos", v("rfRad"))],
        ["rfS",   call("sin", v("rfRad"))],
    ], outputs({
        rolledUx: sub(mul(v("rfC"), v("ux")), mul(v("rfS"), v("rx"))),
        rolledUy: sub(mul(v("rfC"), v("uy")), mul(v("rfS"), v("ry"))),
        rolledUz: sub(mul(v("rfC"), v("uz")), mul(v("rfS"), v("rz"))),
        rolledRx: add(mul(v("rfS"), v("ux")), mul(v("rfC"), v("rx"))),
        rolledRy: add(mul(v("rfS"), v("uy")), mul(v("rfC"), v("ry"))),
        rolledRz: add(mul(v("rfS"), v("uz")), mul(v("rfC"), v("rz"))),
    })),
};

// ── SpEfCrWeights ─────────────────────────────────────────────────────────
// CR basis weights for position interpolation.
// w0..w3 from t (standard Catmull-Rom matrix, pre-multiplied by 0.5).
// Outputs: w0, w1, w2, w3

const SpEfCrWeights = {
    name: "SpEfCrWeights",
    params: ["t"],
    body: letChain([
        ["cwT2", mul(v("t"), v("t"))],
        ["cwT3", mul(v("cwT2"), v("t"))],
    ], outputs({
        w0: mul(num(0.5), add(neg(v("cwT3")), mul(num(2),   v("cwT2")), neg(v("t")))),
        w1: mul(num(0.5), add(mul(num(3),  v("cwT3")), mul(num(-5),  v("cwT2")), num(2))),
        w2: mul(num(0.5), add(mul(num(-3), v("cwT3")), mul(num(4),   v("cwT2")), v("t"))),
        w3: mul(num(0.5), add(v("cwT3"), neg(v("cwT2")))),
    })),
};

// ── SpEfCrDerivWeights ────────────────────────────────────────────────────
// CR derivative (tangent) basis weights.
// dw0..dw3 from t — multiply against 4 ghost CPs to get the unnormalized tangent.
// Mirrors SpTangentAt in spline_path.bi and the inline tangent in behavior.bas Case 6.
// Outputs: dw0, dw1, dw2, dw3

const SpEfCrDerivWeights = {
    name: "SpEfCrDerivWeights",
    params: ["t"],
    body: letChain([
        ["dwT2", mul(v("t"), v("t"))],
    ], outputs({
        dw0: mul(num(0.5), add(mul(num(-3), v("dwT2")), mul(num(4),   v("t")), num(-1))),
        dw1: mul(num(0.5), add(mul(num(9),  v("dwT2")), mul(num(-10), v("t")))),
        dw2: mul(num(0.5), add(mul(num(-9), v("dwT2")), mul(num(8),   v("t")), num(1))),
        dw3: mul(num(0.5), add(mul(num(3),  v("dwT2")), mul(num(-2),  v("t")))),
    })),
};

// ── SpEfFacingNorm ────────────────────────────────────────────────────────
// Safe-normalize direction vector (dx, dy, dz).
// Fallback (0,1,0) when len < EPS so callers always receive a unit vector.
// Uses normalize3 from exprforge/math — injects __exprforgeMathNrmLen2.
// CONSTRAINT: only one Sub in this file may use normalize3 (QB64 Dim scope).
// Outputs: fx, fy, fz

const SpEfFacingNorm = (() => {
    const { x, y, z } = normalize3(v("dx"), v("dy"), v("dz"), num(0), num(1), num(0));
    return {
        name: "SpEfFacingNorm",
        params: ["dx", "dy", "dz"],
        body: outputs({ fx: x, fy: y, fz: z }),
    };
})();

// ── SpEfArcAdvance ────────────────────────────────────────────────────────
// Arc-length reparameterization: advance = speed / |tangent|
// Falls back to speed when the tangent is near-zero (degenerate segment).
// Mirrors the inline advance in behavior.bas Case 6.
// Outputs: advance

const SpEfArcAdvance = {
    name: "SpEfArcAdvance",
    params: ["tx", "ty", "tz", "speed"],
    body: letChain([
        ["aaTanLen", len3(v("tx"), v("ty"), v("tz"))],
    ], outputs({
        advance: safeDiv(v("speed"), v("aaTanLen"), v("speed")),
    })),
};

// ── SpEfTransportFrame ────────────────────────────────────────────────────
// Rodrigues parallel-transport: rotates frame (rx,ry,rz, ux,uy,uz) from
// unit tangent T0 to unit tangent T1, preserving orientation with no twist.
//
// Rotation axis  b  = T0 × T1  (|b| = sinA for unit tangents)
// Rodrigues:  v' = v*cosA + (b×v)*sinA + k*(k·v)*(1-cosA)
//             where k = b/|b| (unit axis), sinA = |b|, cosA = T0·T1
//
// Falls back to identity (frame unchanged) when T0 ≈ T1 (|b| < EPS).
// Prefix: tf
// Outputs: newRx, newRy, newRz, newUx, newUy, newUz

const SpEfTransportFrame = (() => {
    // Build cross-product expressions (AST nodes only — no let injection)
    const b   = cross3(v("tx0"), v("ty0"), v("tz0"), v("tx1"), v("ty1"), v("tz1"));
    const kXr = cross3(v("tfKx"), v("tfKy"), v("tfKz"), v("rx"), v("ry"), v("rz"));
    const kXu = cross3(v("tfKx"), v("tfKy"), v("tfKz"), v("ux"), v("uy"), v("uz"));
    const guard = cmp(v("tfBLen"), ">", num(0.000001));

    // Rodrigues output for one vector component (v=vx/vy/vz, kd=k·v, ckc=k×v component, ki=k component)
    const rod = (vComp, kdV, kc, ki) =>
        select(guard,
            add(mul(vComp, v("tfCosA")), mul(kc, v("tfBLen")), mul(ki, mul(kdV, v("tf1mC")))),
            vComp);

    return {
        name: "SpEfTransportFrame",
        params: ["tx0", "ty0", "tz0", "tx1", "ty1", "tz1", "rx", "ry", "rz", "ux", "uy", "uz"],
        body: letChain([
            ["tfBx",   b.x],
            ["tfBy",   b.y],
            ["tfBz",   b.z],
            ["tfBLen", len3(v("tfBx"), v("tfBy"), v("tfBz"))],
            ["tfCosA", dot3(v("tx0"), v("ty0"), v("tz0"), v("tx1"), v("ty1"), v("tz1"))],
            ["tfKx",   safeDiv(v("tfBx"), v("tfBLen"), num(0))],
            ["tfKy",   safeDiv(v("tfBy"), v("tfBLen"), num(0))],
            ["tfKz",   safeDiv(v("tfBz"), v("tfBLen"), num(1))],
            ["tf1mC",  sub(num(1), v("tfCosA"))],
            ["tfKdR",  dot3(v("tfKx"), v("tfKy"), v("tfKz"), v("rx"), v("ry"), v("rz"))],
            ["tfCKRx", kXr.x],
            ["tfCKRy", kXr.y],
            ["tfCKRz", kXr.z],
            ["tfKdU",  dot3(v("tfKx"), v("tfKy"), v("tfKz"), v("ux"), v("uy"), v("uz"))],
            ["tfCKUx", kXu.x],
            ["tfCKUy", kXu.y],
            ["tfCKUz", kXu.z],
        ], outputs({
            newRx: rod(v("rx"), v("tfKdR"), v("tfCKRx"), v("tfKx")),
            newRy: rod(v("ry"), v("tfKdR"), v("tfCKRy"), v("tfKy")),
            newRz: rod(v("rz"), v("tfKdR"), v("tfCKRz"), v("tfKz")),
            newUx: rod(v("ux"), v("tfKdU"), v("tfCKUx"), v("tfKx")),
            newUy: rod(v("uy"), v("tfKdU"), v("tfCKUy"), v("tfKy")),
            newUz: rod(v("uz"), v("tfKdU"), v("tfCKUz"), v("tfKz")),
        })),
    };
})();

// ── Export all ────────────────────────────────────────────────────────────

const splineFrameAsts = [
    SpEfMkFrame,
    SpEfActualPos,
    SpEfRollFrame,
    SpEfCrWeights,
    SpEfCrDerivWeights,
    SpEfFacingNorm,
    SpEfArcAdvance,
    SpEfTransportFrame,
];

module.exports = { splineFrameAsts };
