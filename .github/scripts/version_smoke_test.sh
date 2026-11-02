#!/usr/bin/env bash
# Smoke test: the binary's --version output is well formed and matches VERSION.
#
# Usage: version_smoke_test.sh [--ignore-tag] <sss binary>
#   --ignore-tag  treat a tag ref like any other: expect the dev version format
#                 (used for the credential-free dev build, which is never a release)
# Env in:  RUNNER_OS       Linux, macOS or Windows (default: from uname)
#          GITHUB_REF      refs/tags/vX.Y.Z[-suffix] makes the tag's version the expected output
#          GITHUB_REF_NAME the tag name
# Run from the repo root (reads ./VERSION). On Linux with xvfb-run available the binary
# runs under it, so a headless box works.
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0;; esac
set -euo pipefail

ignore_tag=0
if [ "${1:-}" = --ignore-tag ]; then ignore_tag=1; shift; fi
BIN="${1:?usage: version_smoke_test.sh [--ignore-tag] <sss binary>}"
GITHUB_REF="${GITHUB_REF:-}"
GITHUB_REF_NAME="${GITHUB_REF_NAME:-}"
if [ -z "${RUNNER_OS:-}" ]; then
  case "$(uname -s)" in
    Linux) RUNNER_OS=Linux ;;
    Darwin) RUNNER_OS=macOS ;;
    *) RUNNER_OS=Windows ;;
  esac
fi

if [ "$RUNNER_OS" = "Linux" ] && command -v xvfb-run &>/dev/null; then
  OUT=$(xvfb-run -a "$BIN" --version)
else
  OUT=$("$BIN" --version)
fi
echo "$OUT"
if [ "$RUNNER_OS" != "Windows" ] && [[ "$OUT" == *$'\r'* ]]; then
  echo "::error::--version output contains a carriage return on $RUNNER_OS (#252)"
  exit 1
fi
OUT="${OUT//$'\r'/}"
BASE_VERSION="$(tr -d '[:space:]' < VERSION)"
# A tag build must print exactly the tag's version (v0.1.0-rc1 -> 0.1.0-rc1), and
# the tag must be a release of VERSION. Taken from the ref, not git, so a checkout
# that lost the tag (make-version.sh falls back to VERSION) fails here.
if [ "$ignore_tag" = 0 ] && [[ "$GITHUB_REF" == refs/tags/v* ]]; then
  TAG_VERSION="${GITHUB_REF_NAME#v}"
  if [ "${TAG_VERSION%%-*}" != "$BASE_VERSION" ]; then
    echo "::error::tag $GITHUB_REF_NAME doesn't match VERSION ($BASE_VERSION)"
    exit 1
  fi
  if [ "$OUT" != "Super Spaceguy Shooter $TAG_VERSION" ]; then
    echo "::error::--version smoke test failed: expected 'Super Spaceguy Shooter $TAG_VERSION', got: $OUT"
    exit 1
  fi
  exit 0
fi
echo "$OUT" | grep -qE "Super Spaceguy Shooter ${BASE_VERSION}(-dev\+[0-9a-f]+(-dirty)?)?$" || {
  echo "::error::--version smoke test failed: expected a version starting with '${BASE_VERSION}', got: $OUT"
  exit 1
}
