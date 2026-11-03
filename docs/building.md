# Building from source

You need:

- [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe) installed and on your `PATH` as `qb64pe`.
- Nothing else for the game and its tests: no Node, npm or Python. (Only the backend in `server/` uses Node.)

```bash
# recommended -- run from the repo root
tools/buildqb sss.bas
```

This bakes the speech phoneme dictionary, regenerates `src/sys/version.bas` from the `VERSION` file and the current git commit, links QB64-PE's asset directory to this repo's `assets/` (so `$EMBED:'assets/...'` resolves), and compiles. The binary lands in `builds/sss` (`builds/sss.exe` on Windows), or wherever `SSS_BUILD_OUT=<path>` says.

```bash
# smoke test
builds/sss --version
```

Pre-built binaries for Linux, macOS, and Windows are produced by CI on every merge to `master` and attached to tagged releases.

**Is the build current?** Every successful build writes `builds/<name>.manifest` (one `path:sha1` line for each input, sorted) and `builds/<name>.sha1` (the hash of that listing) next to the executable. The inputs are the entry file and every `$INCLUDE` it pulls in (recursively, all `$IF` branches), every `$EMBED` asset, `VERSION`, the git HEAD, dirty flag and exact tag that go into the version string, `SSS_RELEASE`, the OS, `tools/buildqb`, `tools/make-version.sh` and the QB64-PE version. Contents are hashed, never timestamps, so `touch` and `git checkout` change nothing. `tools/buildqb --check sss.bas` builds nothing: it exits 0 if `builds/sss` is current and 1 if it is stale (missing, no manifest, or changed inputs, which it lists as `changed:`, `added:` or `removed:`). `tools/build-manifest sss.bas` prints the listing. `tools/dev run`, `headless` and `bench` use the same check, in the container, to decide whether to rebuild. `SSS_BUILD_OUT` builds keep their manifest beside their executable.

**Release builds.** A plain build is a dev build. `tools/buildqb --release sss.bas` (or `SSS_RELEASE=1`; `.github/scripts/qb64build.sh --release` in CI; `tools/dev build --release` in the container) makes a release build: `--version` prints the bare version, and the dev-only flags (everything below except `--version`, `--help`, `--no-telem` and `--debug`) are compiled out, so passing one is an `unknown option` error. `--debug` still works, for bug reports, but `--help` doesn't list it. `tools/make-version.sh` switches it with `$LET RELEASEBUILD` in the generated `src/sys/version.bas`. Tagged (`v*`) releases ship release builds; every other CI build is a dev build, plus one Linux release build checked by `tests/release_build_test.sh`. A release build overwrites `builds/sss`, so rebuild without `--release` before using the dev flags again.
