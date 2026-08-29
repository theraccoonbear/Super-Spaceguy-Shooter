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
- After any change to `assets/gametext.txt` or `assets/gamevalues.ini`: run `bash tools/bake_speech_dict` from the repo root and commit the updated `assets/speech_dict.txt`. CI will fail otherwise.

## QB64-PE gotchas
- Plain `Dim x` (non-Shared) at module scope in `$INCLUDE` files is invisible to Subs — use `Dim Shared`. `Dim Shared x As String` works correctly; no `$` suffix needed.
- `_COMMAND$(n)` subscript form is not supported in QB64-PE v4.5.0 — use `COMMAND$` (full string)
- All `Dim` inside Subs are module-scope in QB64-PE; variable names must be unique across all Subs in a compilation unit
- Short names like `pos`, `val` are built-in keywords — prefix vars with context (e.g. `objPos`, `sndVal`)
- `Not` is bitwise, not logical: `Not 1 = -2` (truthy), so `If Not flag` misbehaves when `flag` is `1` instead of `-1`. Use `If flag = 0` to guard a disabled feature, or define boolean consts as `0`/`-1`

## Scope of work
- Fix only what was asked. Don't refactor, clean up, or fix adjacent things unless asked.
- No comments unless the WHY is non-obvious.
- No new files unless the task requires them.

## Pull requests
- Every PR body must include `Closes #N` (or `Fixes #N`) for each GitHub issue the PR resolves. Without it the issue will not auto-close on merge.
- After every commit on a PR branch, push immediately. The user tests from a separate working copy and cannot see local commits.

## Commit hygiene
- No AI attribution trailers in commit messages or PR bodies -- no `Co-Authored-By: Claude ...`, no `Claude-Session:`, nothing similar. `.claude/settings.json`'s `attribution` block disables these at the source; `tools/git-hooks/commit-msg` is a backstop that rejects a commit containing one.
- One-time per clone: `git config core.hooksPath tools/git-hooks` (git does not auto-discover a tracked hooks directory).

## Pre-commit checklist — run ALL of these locally before every commit/push
1. **Build**: `./tools/buildqb sss.bas` — must complete with no errors
2. **Smoke test**: `builds/sss --version` — must print the version and exit 0
3. **All automated tests**: build and run every test binary in `tests/` (mirrors `.github/scripts/qb64test.sh`, which runs this same suite in CI on Linux, macOS, and Windows):
   ```
   ./tools/buildqb tests/seq_trace_test.bas         && builds/seq_trace_test
   ./tools/buildqb tests/seq_dispatch_test.bas      && builds/seq_dispatch_test
   ./tools/buildqb tests/scene_jump_planet_test.bas && builds/scene_jump_planet_test
   ./tools/buildqb tests/snd_init_test.bas          && builds/snd_init_test
   ./tools/buildqb tests/telem_creds_test.bas       && builds/telem_creds_test
   ./tools/buildqb tests/dbg_output_test.bas        && builds/dbg_output_test
   tools/http_queue_test   # builds + runs http_queue_test.bas against a local mock server
   ```
   All tests must pass (exit 0) before committing. No exceptions.
4. **Speech dict**: if `assets/gametext.txt` or `assets/gamevalues.ini` changed, run `bash tools/bake_speech_dict` and commit `assets/speech_dict.txt`.

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