// math/spline-frame.js
// ALL boss-flight spline math lives here as exprforge DSL.
// This file is the single source of truth — pure JS, no QB64, no TypeScript.
//
// QB64-PE SCOPE RULE: All Dim statements inside Subs share a module-wide namespace.
// Every letIn name below uses a function-specific prefix to prevent collisions:
//   mf = SpEfMkFrame     ap = SpEfActualPos    rf = SpEfRollFrame
//   cw = SpEfCrWeights   dw = SpEfCrDerivWeights
//   fn = SpEfFacingNorm  aa = SpEfArcAdvance
//
// Downstream generated files (never hand-edit):
//   src/gameplay/spline_path_gen.bi           QB64
//   tools/path_editor/src/math/spline_gen.ts  TypeScript
//
// Regenerate both with:  node tools/emit-spline.js

'use strict';

const EF = require('exprforge');
const { num, v, call, add, mul, sub, div, neg, letIn, select, cmp, outputs } = EF;

// ── Helpers ───────────────────────────────────────────────────────────────

const PI       = num(3.141592653589793);
const degToRad = (degVar) => mul(degVar, div(PI, num(180)));
const dot3     = (ax, ay, az, bx, by, bz) => add(mul(ax, bx), mul(ay, by), mul(az, bz));
const len3     = (x, y, z) => call("sqrt", dot3(x, y, z, x, y, z));

const EPS = num(0.000001);
function safeDiv(component, lenVar, fallback) {
    const isSafe = cmp(v(lenVar), ">", EPS);
    const safeLen = select(isSafe, v(lenVar), num(1));
    return select(isSafe, div(component, safeLen), fallback);
}

// worldUp branch shared across MkFrame and ActualPos helpers
const nearVert = cmp(call("abs", v("ty")), ">", num(0.98));

// ── SpEfMkFrame ───────────────────────────────────────────────────────────
// Gram-Schmidt frame from normalized tangent (tx, ty, tz).
// worldUp = (0,0,1) when |ty|>0.98, else (0,1,0).
// R = normalize(T × worldUp),  U = R × T
// Outputs: rx, ry, rz, ux, uy, uz

function mfChain(body) {
    return letIn("mfWy",     select(nearVert, num(0), num(1)),
           letIn("mfWz",     select(nearVert, num(1), num(0)),
           letIn("mfCrossX", sub(mul(v("ty"), v("mfWz")), mul(v("tz"), v("mfWy"))),
           letIn("mfCrossY", neg(mul(v("tx"), v("mfWz"))),
           letIn("mfCrossZ", mul(v("tx"), v("mfWy")),
           letIn("mfRLen",   len3(v("mfCrossX"), v("mfCrossY"), v("mfCrossZ")),
           letIn("mfRxN",    safeDiv(v("mfCrossX"), "mfRLen", num(0)),
           letIn("mfRyN",    safeDiv(v("mfCrossY"), "mfRLen", num(0)),
           letIn("mfRzN",    safeDiv(v("mfCrossZ"), "mfRLen", num(1)),
               body
           )))))))));
}

const SpEfMkFrame = {
    name: "SpEfMkFrame",
    params: ["tx", "ty", "tz"],
    body: mfChain(outputs({
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

function apChain(body) {
    return letIn("apWy",     select(nearVert, num(0), num(1)),
           letIn("apWz",     select(nearVert, num(1), num(0)),
           letIn("apCrossX", sub(mul(v("ty"), v("apWz")), mul(v("tz"), v("apWy"))),
           letIn("apCrossY", neg(mul(v("tx"), v("apWz"))),
           letIn("apCrossZ", mul(v("tx"), v("apWy")),
           letIn("apRLen",   len3(v("apCrossX"), v("apCrossY"), v("apCrossZ")),
           letIn("apRxN",    safeDiv(v("apCrossX"), "apRLen", num(0)),
           letIn("apRyN",    safeDiv(v("apCrossY"), "apRLen", num(0)),
           letIn("apRzN",    safeDiv(v("apCrossZ"), "apRLen", num(1)),
           letIn("apUx",     sub(mul(v("apRyN"), v("tz")), mul(v("apRzN"), v("ty"))),
           letIn("apUy",     sub(mul(v("apRzN"), v("tx")), mul(v("apRxN"), v("tz"))),
           letIn("apUz",     sub(mul(v("apRxN"), v("ty")), mul(v("apRyN"), v("tx"))),
           letIn("apRad",    degToRad(v("prDeg")),
           letIn("apC",      call("cos", v("apRad")),
           letIn("apS",      call("sin", v("apRad")),
               body
           )))))))))))))));
}

const SpEfActualPos = {
    name: "SpEfActualPos",
    params: ["wx", "wy_wire", "wz_wire", "tx", "ty", "tz", "prDeg", "so"],
    body: apChain(outputs({
        x: add(v("wx"),       mul(v("so"), add(mul(v("apC"), v("apUx")), mul(v("apS"), v("apRxN"))))),
        y: add(v("wy_wire"),  mul(v("so"), add(mul(v("apC"), v("apUy")), mul(v("apS"), v("apRyN"))))),
        z: add(v("wz_wire"),  mul(v("so"), add(mul(v("apC"), v("apUz")), mul(v("apS"), v("apRzN"))))),
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
    body: letIn("rfRad", degToRad(v("crDeg")),
          letIn("rfC",   call("cos", v("rfRad")),
          letIn("rfS",   call("sin", v("rfRad")),
              outputs({
                  rolledUx: sub(mul(v("rfC"), v("ux")), mul(v("rfS"), v("rx"))),
                  rolledUy: sub(mul(v("rfC"), v("uy")), mul(v("rfS"), v("ry"))),
                  rolledUz: sub(mul(v("rfC"), v("uz")), mul(v("rfS"), v("rz"))),
                  rolledRx: add(mul(v("rfS"), v("ux")), mul(v("rfC"), v("rx"))),
                  rolledRy: add(mul(v("rfS"), v("uy")), mul(v("rfC"), v("ry"))),
                  rolledRz: add(mul(v("rfS"), v("uz")), mul(v("rfC"), v("rz"))),
              })
          ))),
};

// ── SpEfCrWeights ─────────────────────────────────────────────────────────
// CR basis weights for position interpolation.
// w0..w3 from t (standard Catmull-Rom matrix, pre-multiplied by 0.5).
// Outputs: w0, w1, w2, w3

const SpEfCrWeights = {
    name: "SpEfCrWeights",
    params: ["t"],
    body: letIn("cwT2", mul(v("t"), v("t")),
          letIn("cwT3", mul(v("cwT2"), v("t")),
              outputs({
                  w0: mul(num(0.5), add(neg(v("cwT3")), mul(num(2), v("cwT2")), neg(v("t")))),
                  w1: mul(num(0.5), add(mul(num(3), v("cwT3")), mul(num(-5), v("cwT2")), num(2))),
                  w2: mul(num(0.5), add(mul(num(-3), v("cwT3")), mul(num(4), v("cwT2")), v("t"))),
                  w3: mul(num(0.5), add(v("cwT3"), neg(v("cwT2")))),
              })
          )),
};

// ── SpEfCrDerivWeights ────────────────────────────────────────────────────
// CR derivative (tangent) basis weights.
// dw0..dw3 from t — multiply against 4 ghost CPs to get the unnormalized tangent.
// Mirrors SpTangentAt in spline_path.bi and the inline tangent in behavior.bas Case 6.
// Outputs: dw0, dw1, dw2, dw3

const SpEfCrDerivWeights = {
    name: "SpEfCrDerivWeights",
    params: ["t"],
    body: letIn("dwT2", mul(v("t"), v("t")),
        outputs({
            dw0: mul(num(0.5), add(mul(num(-3), v("dwT2")), mul(num(4),   v("t")), num(-1))),
            dw1: mul(num(0.5), add(mul(num(9),  v("dwT2")), mul(num(-10), v("t")))),
            dw2: mul(num(0.5), add(mul(num(-9), v("dwT2")), mul(num(8),   v("t")), num(1))),
            dw3: mul(num(0.5), add(mul(num(3),  v("dwT2")), mul(num(-2),  v("t")))),
        })
    ),
};

// ── SpEfFacingNorm ────────────────────────────────────────────────────────
// Safe-normalize direction vector (dx, dy, dz).
// Fallback (0,1,0) when len < EPS so callers always receive a unit vector.
// The orient-mode switch (path vs target) is caller infrastructure, not DSL.
// Outputs: fx, fy, fz

const SpEfFacingNorm = {
    name: "SpEfFacingNorm",
    params: ["dx", "dy", "dz"],
    body: letIn("fnFLen", len3(v("dx"), v("dy"), v("dz")),
        outputs({
            fx: safeDiv(v("dx"), "fnFLen", num(0)),
            fy: safeDiv(v("dy"), "fnFLen", num(1)),
            fz: safeDiv(v("dz"), "fnFLen", num(0)),
        })
    ),
};

// ── SpEfArcAdvance ────────────────────────────────────────────────────────
// Arc-length reparameterization: advance = speed / |tangent|
// Falls back to speed when the tangent is near-zero (degenerate segment).
// Mirrors the inline advance in behavior.bas Case 6.
// Outputs: advance

const SpEfArcAdvance = {
    name: "SpEfArcAdvance",
    params: ["tx", "ty", "tz", "speed"],
    body: letIn("aaTanLen", len3(v("tx"), v("ty"), v("tz")),
        outputs({
            advance: safeDiv(v("speed"), "aaTanLen", v("speed")),
        })
    ),
};

// ── Export all ────────────────────────────────────────────────────────────

const splineFrameAsts = [
    SpEfMkFrame,
    SpEfActualPos,
    SpEfRollFrame,
    SpEfCrWeights,
    SpEfCrDerivWeights,
    SpEfFacingNorm,
    SpEfArcAdvance,
];

module.exports = { splineFrameAsts };
