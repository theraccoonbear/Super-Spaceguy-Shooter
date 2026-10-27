# Super Spaceguy Shooter — Dev Practices

## Branch discipline
- Stay on task. If you discover a bug while working on a feature branch, log it as a GitHub issue and move on. Do NOT fix it on an unrelated branch.
- Exception: if the bug was introduced by your current branch's changes, fix it here.
- Branch naming: **`type/short-description-ISSUENUMBER`** — issue number ALWAYS at the end. Examples: `feat/level-difficulty-120`, `fix/boss-model-82`. NO EXCEPTIONS.
- Before creating or switching to any branch: verify it has an issue number. If it does not, STOP and flag it to the user before touching any code.
- Before writing any plan or code: run `git branch` and confirm the current branch has an issue number in the name.

## Build requirement
- Always do a test build after any code change. Fix all errors before reporting back.
- Build command: from the repo root, run `./tools/buildqb sss.bas`  (script auto-creates `qb64pe-dir/assets → repo/assets` symlink so `$EMBED:'assets/...'` resolves correctly from QB64-PE's binary dir)
- After building, always smoke-test: run `builds/sss --version` and confirm it prints the version and exits cleanly. This catches launch crashes without needing a display.
- No native QB64-PE? `tools/dev build` / `tools/dev test` run the same build, smoke test, and full suite in a Podman/Docker container (see README "Building in a container").
- After any change to `assets/gametext.txt` or `assets/gamevalues.ini`: run `bash tools/bake_speech_dict` from the repo root and commit the updated `assets/speech_dict.txt`. CI will fail otherwise.

## QB64-PE gotchas
- Plain `Dim x` (non-Shared) at module scope in `$INCLUDE` files is invisible to Subs — use `Dim Shared`. `Dim Shared x As String` works correctly; no `$` suffix needed.
- `_COMMAND$(n)` subscript form is not supported in QB64-PE v4.5.0 — use `COMMAND$` (full string)
- All `Dim` inside Subs are module-scope in QB64-PE; variable names must be unique across all Subs in a compilation unit
- Short names like `pos`, `val` are built-in keywords — prefix vars with context (e.g. `objPos`, `sndVal`)
- Without `Option _Explicit`, an undefined function or array compiles silently: `RNG!(RNG_FX)` with `rng.bas` missing becomes an implicit array read with `RNG_FX` an implicit 0, and a missing `Dim Shared` or `Const` becomes a 0-valued local. The game, every test and every CI-compiled tool start with `Option _Explicit` (it covers `$INCLUDE`d files too) — keep it in any new program, and include every module a file depends on (e.g. `src/sys/rng.bas` before `src/engine3d.bi`)
- `Not` is bitwise, not logical: `Not 1 = -2` (truthy), so `If Not flag` misbehaves when `flag` is `1` instead of `-1`. Use `If flag = 0` to guard a disabled feature, or define boolean consts as `0`/`-1`

## Scope of work
- Fix only what was asked. Don't refactor, clean up, or fix adjacent things unless asked.
- No comments unless the WHY is non-obvious.
- No new files unless the task requires them.

## No outside languages for verification
- Scope note: ExprForge spline math is currently used only by tools and possible cinematics, not gameplay (`docs/adr/0001-rail-shooter-scope.md`). The rules below still apply in full whenever you touch it.
- NEVER write Python (or any language outside this project's own stack) to "verify a hypothesis," even as disposable scratch work you don't intend to commit. This includes re-deriving/re-transcribing formulas from `formula.expr`, `.bas`, or `.ts` into a throwaway script to sanity-check them numerically.
- Hand-retyping shared math into yet another language to "just check" is the exact silent-transcription-divergence failure mode this codebase's ExprForge discipline exists to prevent. Doing it as a side-channel scratch tool is not exempt from that risk — it's the same mistake with extra steps.
- Verify TypeScript with TypeScript: write a real Vitest test importing the actual exported functions from the real module (e.g. `tools/TrailForge/src/math/spline.ts`) against real project data. Verify QB64 with QB64: a scratch `.bas` harness or an addition to `tests/`, built and run the normal way.
- If a case ever seems to genuinely require an outside language, do not just do it. Stop, explain specifically and concretely why the project's own stack can't answer the question, and get the user's explicit go-ahead for that specific instance before writing a single line.

## Pull requests
- Every PR body must include `Closes #N` (or `Fixes #N`) for each GitHub issue the PR resolves. Without it the issue will not auto-close on merge.
- After every commit on a PR branch, push immediately. The user tests from a separate working copy and cannot see local commits.

## Commit hygiene
- No AI attribution trailers in commit messages or PR bodies -- no `Co-Authored-By: Claude ...`, no `Claude-Session:`, nothing similar. `.claude/settings.json`'s `attribution` block disables these at the source; `tools/git-hooks/commit-msg` is a backstop that rejects a commit containing one.
- One-time per clone: `git config core.hooksPath tools/git-hooks` (git does not auto-discover a tracked hooks directory).

## Pre-commit checklist — run ALL of these locally before every commit/push
1. **Build**: `./tools/buildqb sss.bas` — must complete with no errors
2. **Smoke test**: `builds/sss --version` — must print the version and exit 0
3. **All automated tests**: `tools/test` (or `tools/dev test` in the container). It builds and runs every test in `tests/` in parallel, exactly as CI does on Linux, macOS and Windows (`.github/scripts/qb64test.sh`), then prints each test's output and a pass/fail summary. All tests must pass (exit 0) before committing. No exceptions.
   - **Adding a test:** add its name to `TESTS` in `.github/scripts/qb64test.sh` and make it print `=== <name> ===` first. The runner rejects a binary that doesn't print its own banner, which is how it catches parallel-build mix-ups.
   - **Never run two native QB64-PE builds at once on one install** (e.g. two agents, or `tools/buildqb` in two terminals). On Linux and macOS qb64pe claims its temp folder without a lock, so concurrent compiles can silently produce each other's binaries (#239). `qb64test.sh` gives each worker its own QB64-PE copy; parallel agents should build through `tools/dev`, which runs each build in its own container.
4. **Speech dict**: if `assets/gametext.txt` or `assets/gamevalues.ini` changed, run `bash tools/bake_speech_dict` and commit `assets/speech_dict.txt`.
5. **Full playthrough**: runs in CI as its own job (`playthrough`). Don't run it locally before committing. Run it locally (`tools/dev build && tools/dev shell tests/playthrough/run.sh`, needs an empty `assets/.env`) only to debug a playthrough failure. If the game flow changes on purpose (`assets/sequence.txt`, game states, stages, bosses, crawls, input, the boot screens), update `tests/playthrough/expected.txt` (see README "Testing").

> Adding a new `$INCLUDE` to sequence.bas, dims.bas, or any file that test stubs replicate
> means updating every test file that declares shared vars. Grep for the variable name in
> `tests/` to find which stubs need it.

## Definition of done — a task is NOT complete until ALL of these are true
1. Pre-commit checklist above is fully satisfied locally
2. All changes are committed and pushed to the PR branch
3. A PR is open against master with `Closes #N`
4. **CI is green** — check with `gh pr checks <number>` and wait for all checks to pass before reporting the task complete to the user

Never tell the user a task is done while CI is still running or red. Silence is better than a premature "done."

## Tackling a task
- Regardless of how enthusiastic the user is to get started, make a plan that is shared first.
- For bugs, features, or any discrete coding task, there should be:
    - "Feature/Bug/Etc" type branches created for the work
    - Before code is written, a plan is formulated
    - The plan includes LOE expressed in Agile "story points", understanding that GenAI LOE is not human, but still, give relative scale.
    - The plan expresses any concerns or pushback if the user is going against best practices or otherwise potentially painting themself in a corner
- Once a plan is approved by the user, you can proceed
- Other bugs or feature ideas that arise during coding should get a GitHub issue created for them

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `theraccoonbear/Super-Spaceguy-Shooter` (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `CONTEXT.md` at repo root is the primary orientation document — load it at the start of any session touching game code. ADRs in `docs/adr/`. See `docs/agents/domain.md`.