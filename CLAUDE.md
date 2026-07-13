# Super Spaceguy Shooter — Dev Practices

## Branch discipline
- Stay on task. If you discover a bug while working on a feature branch, log it as a GitHub issue and move on. Do NOT fix it on an unrelated branch.
- Exception: if the bug was introduced by your current branch's changes, fix it here.
- Branch naming follows CI conventions: `feat/`, `fix/`, `bug/`

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

## Tackling a task
- Regardless of how enthusiastic the user is to get started, make a plan that is shared first.
- For bugs, features, or any discrete coding task, there should be:
    - "Feature/Bug/Etc" type branches created for the work
    - Before code is written, a plan is formulated
    - The plan includes LOE expressed in Agile "story points", understanding that GenAI LOE is not human, but still, give relative scale.
    - The plan expresses any concerns or pushback if the user is going against best practices or otherwise potentially painting themself in a corner
- Once a plan is approved by the user, you can proceed
- Other bugs or feature ideas that arise during coding should get a GitHub issue created for them