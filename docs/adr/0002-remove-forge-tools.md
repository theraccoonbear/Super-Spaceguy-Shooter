# ADR-0002: ExprForge, TrailForge and the maneuver engine are removed from the repo

- **Status:** Accepted
- **Date:** 2026-11-01
- **Related:** #363, #292, #209, #210, #213, #272, #233
- **Supersedes:** decision 2 of [ADR-0001](0001-rail-shooter-scope.md) (the tools stay in the repo). The rest of ADR-0001 stands.

## Context

ADR-0001 kept ExprForge, TrailForge and the game-side maneuver engine in the repo, unused by gameplay, on the grounds that the upkeep was small. That upkeep turned out to include the build itself:

- `src/gameplay/spline_path_gen.bi` was generated with Node on every `tools/buildqb sss.bas`, in CI and in the test runner, and the game had to compile it although gameplay never runs it.
- That put Node and npm (and network access for `npm install`) on the path of every build, test run and CI job.
- Three `mnv_*` tests, the `maneuver=` key in `assets/sequence.txt`, the BOSS mesh `axisfix` undone each frame in `combat.bas`, and several test stubs existed only to keep the unused engine compiling.

The decisions in ADR-0001 about gameplay are unchanged: SSS1 stays a pseudo-3D rail shooter and bosses use hunt/evade movement (`BOSS_UpdateMovement`, states 0 and 1).

## Decision

1. **Remove the tools and the engine from master.** Removed: `tools/TrailForge/`, `math/` (`formula.expr`), `tools/emit-spline.js`, `tools/migrate-maneuvers.js`, `tools/turn_viz.bas`, `tools/container/in/emit.sh` and `tools/dev emit`, `src/gameplay/spline_path.bi`, `src/gameplay/maneuvers.bas`, boss states 5 and 6 and their helpers in `src/gameplay/behavior.bas`, the `maneuver=` key, `assets/maneuvers/*.mvr`, the `mnv_*` tests, `docs/flight-path-math.md` and `docs/proposals/exprforge-array-support.md`. `behavior.bas` stays, because `BOSS_UpdateMovement` is live.
2. **Keep the removed work findable.** It all lives at the annotated tag `archive/forge-tools`, created on the last master commit that still contains it. Restore from there with `git checkout archive/forge-tools -- <path>`.
3. **Also removed as now-unused:** `E3D_BuildObjectMatBasis` (nothing called it) and the BOSS `axisfix`, together with the per-frame undo in `combat.bas` and the `axisfix` line parser in `mesh.bas`. The flip and its undo cancel exactly, so the boss renders the same.
4. **No Node, npm or Python outside `server/`.** The build, the test suite and CI need none of them. The HTTP mock for `tests/http_queue_test.bas` is now a QB64-PE program (`tools/http_mock_server.bas`, built on `_OPENHOST`), and the remaining Python one-liners that parsed GitHub API JSON use `jq` / `gh --jq`. `server/` stays TypeScript on Cloudflare Workers.
5. **Re-introducing authored paths later is a new decision.** Cinematics on splines (ADR-0001, decision 3) would be designed again, with whatever tooling fits then, starting from the tag if useful.

## Consequences

- `tools/buildqb sss.bas`, `tools/test` and `tools/dev` need only QB64-PE (and a container engine for `tools/dev`). The dev container no longer installs Node.
- The ExprForge-specific rule in `CLAUDE.md` is gone. The general rule against outside languages for verification stays.
- Issues #209, #210, #213 (TrailForge) and #292 (compile the maneuver engine out) are moot or superseded. #272 and #233, which planned to use or track `formula.expr`, need revising.
- Boss flight and rendering are unchanged: render goldens and `tests/playthrough/expected.txt` are untouched by this change.
- The mock's log timestamp `t` is seconds since the mock started, not an epoch time, since QB64-PE has no epoch clock. Nothing reads it.
