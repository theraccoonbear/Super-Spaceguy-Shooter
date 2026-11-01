# Building from source

You need:

- [QB64-PE](https://github.com/QB64-Phoenix-Edition/QB64pe) installed and on your `PATH` as `qb64pe`.
- [Node.js](https://nodejs.org/) with `npm` on your `PATH`. `tools/buildqb sss.bas` runs `npm install` in `math/` and then `node tools/emit-spline.js` to generate the spline math (see [Flight path math](flight-path-math.md)).
- Network access on the first build, so `npm install` can fetch [exprforge](https://www.npmjs.com/package/exprforge) into `math/node_modules/`. Later builds use the installed copy.

```bash
# recommended -- run from the repo root
tools/buildqb sss.bas
```

This generates the spline math, bakes the speech phoneme dictionary, regenerates `src/sys/version.bas` from the `VERSION` file and the current git commit, links QB64-PE's asset directory to this repo's `assets/` (so `$EMBED:'assets/...'` resolves), and compiles. The binary lands in `builds/sss` (`builds/sss.exe` on Windows), or wherever `SSS_BUILD_OUT=<path>` says.

```bash
# smoke test
builds/sss --version
```

Pre-built binaries for Linux, macOS, and Windows are produced by CI on every merge to `master` and attached to tagged releases.

**Release builds.** A plain build is a dev build. `tools/buildqb --release sss.bas` (or `SSS_RELEASE=1`; `.github/scripts/qb64build.sh --release` in CI; `tools/dev build --release` in the container) makes a release build: `--version` prints the bare version, and the dev-only flags (everything below except `--version`, `--help`, `--no-telem` and `--debug`) are compiled out, so passing one is an `unknown option` error. `--debug` still works, for bug reports, but `--help` doesn't list it. `tools/make-version.sh` switches it with `$LET RELEASEBUILD` in the generated `src/sys/version.bas`. Tagged (`v*`) releases ship release builds; every other CI build is a dev build, plus one Linux release build checked by `tests/release_build_test.sh`. A release build overwrites `builds/sss`, so rebuild without `--release` before using the dev flags again.
