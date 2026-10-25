# ADR-0001: SSS1 stays a rail shooter; splines are cinematics-only

- **Status:** Accepted
- **Date:** 2026-10-25
- **Related:** #181, #197, #214, #216

## Context

SSS was designed as a pseudo-3D rail shooter. Its camera path is fixed, depth is mostly a scrolling Z axis, and enemies, aiming and collision are all framed around the player's lane.

PR #197 (`feat/boss-multi-axis-181`) tried to give the boss full 3D movement along authored paths. It added:

- **ExprForge spline math.** `math/formula.expr` holds 21 functions. `tools/emit-spline.js` generates `src/gameplay/spline_path_gen.bi` and `tools/TrailForge/src/math/spline_gen.ts` from it.
- **TrailForge.** `tools/TrailForge/` is a React/Three route editor. It writes `.mvr` maneuver files to `assets/maneuvers/`.
- **A game-side maneuver engine.** `src/gameplay/maneuvers.bas` loads the routes, and boss states 5 and 6 in `src/gameplay/behavior.bas` would fly them.

The authored paths never fit well with the actual fight. #197 ended by shelving the integration, and #214 tracks how that might be revisited. This is how things stand on master:

- The boss uses only its original hunt/evade movement (states 0 and 1). The only thing that calls `BOSS_PickMode`, the way into states 5 and 6, is `tests/mnv_transition_test.bas`.
- `sss.bas` embeds three `.mvr` routes. `assets/sequence.txt` names maneuvers, and the names are parsed into `bossManeuverList$`, but nothing uses that list.
- The game doesn't use ExprForge for anything outside spline math, so no other system depends on it.
- The cost of keeping it is small:
  - about 1.1k lines of BASIC that compile but never run
  - three `mnv_*` tests in CI
  - a step that regenerates the spline code on every build
  - the BOSS mesh `axisfix`, undone every frame in `combat.bas`

Making gameplay fully 3D would mean reworking collision, aim-assist, readability and difficulty tuning around movement the engine wasn't built for. A rail shooter's strength is a camera path the designer controls.

## Decision

1. **SSS1 stays a pseudo-3D rail shooter.** Gameplay movement, for the boss and for enemies, will not use authored spline routes.
2. **ExprForge, TrailForge and the maneuver engine stay in the repo, unused by gameplay.** They aren't deleted or moved out, because the upkeep is small and the work is reusable.
3. **Spline routes may be used for cinematics**, such as boss entrances and exits, level transitions and flybys. Cinematics don't need collision, aim or player input to agree with the path, and those conflicts are what made gameplay integration hard.
4. **Full 3D movement is deferred to a possible SSS2** that is designed for 3D from the start. Any reuse of this tooling there is a question for SSS2's design, not this codebase.

This settles #214's open question, "what should authored paths be *for*": intro, outro and set-piece cinematics, not fight choreography.

## Consequences

- The unused code and its tests stay as an accepted cost. The `mnv_*` tests keep the engine working in case cinematics use it.
- The ExprForge rule in `CLAUDE.md` still applies to any change to spline math. That math is currently used only by tools and possible cinematics.
- `CONTEXT.md` and `README.md` no longer describe spline paths as live boss movement.
- **If cinematics are built on the maneuver engine**, deal with the following first. Until then they cause no harm.
  - **Mesh axisfix.** `assets/models.e3d` gives BOSS `axisfix -1 1 -1`, and the Euler render path in `combat.bas` undoes it every frame. A path-driven pose would need that undo applied only to the Euler branch (see #214).
  - **ExprForge version drift.** `math/package.json` uses `^0.9.0` and `tools/TrailForge/package.json` uses `^0.6.1`.
  - **Phase ownership.** `.mvr` phase triggers and the HP thresholds in `boss.bas` both try to set `boss.phase`. A cinematic should not touch phase at all.
  - **`E3D_BuildObjectMatBasis`** (`src/3d/object.bas`) has to be wired back into the render path.
- Gameplay ideas that need free 3D movement go to SSS2 instead of being retrofitted here.
