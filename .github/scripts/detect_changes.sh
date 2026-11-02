#!/usr/bin/env bash
# Decide which halves of CI a change needs (#341) and which Build matrix to run.
#
# Usage: detect_changes.sh
# Env in:  EVENT   github.event_name
#          REF     github.ref
#          BEFORE  github.event.before (push events; all-zeros or unknown commit = run everything)
#          GITHUB_OUTPUT  file the outputs are appended to (defaults to /dev/stdout)
# Outputs: game, server (true/false) and build-matrix (JSON) on GITHUB_OUTPUT.
# Needs a checkout deep enough to diff: HEAD^1 for pull_request, BEFORE for push.
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0;; esac
set -euo pipefail

EVENT="${EVENT:-}"
REF="${REF:-}"
BEFORE="${BEFORE:-}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"

all=1 files=""
if [ "$EVENT" = pull_request ]; then
  # HEAD is the PR merged into master; its first parent is master
  files="$(git diff --name-only HEAD^1 HEAD)" && all=0
elif [ "$EVENT" = push ] && [[ "$REF" == refs/heads/* ]] && ! [[ "$BEFORE" =~ ^0+$ ]] && git cat-file -e "$BEFORE^{commit}" 2> /dev/null; then
  files="$(git diff --name-only "$BEFORE" HEAD)" && all=0
fi
game=0 server=0
while IFS= read -r f; do
  case "$f" in
    '') ;;
    .github/*) game=1 server=1 ;;
    tests/input/leaderboard.json|tests/input/telemetry_rows.txt) game=1 server=1 ;;
    server/*) server=1 ;;
    assets/*) game=1 ;;
    docs/*|*.md) ;;
    *) game=1 ;;
  esac
done <<< "$files"
if [ "$all" = 1 ]; then game=1 server=1; fi
echo "changed files:"; printf '  %s\n' $files
tf() { if [ "$1" = 1 ]; then echo true; else echo false; fi; }
echo "game=$(tf $game)" >> "$OUT"
echo "server=$(tf $server)" >> "$OUT"
echo "game=$(tf $game) server=$(tf $server)"
mac='{"os":"macos-latest","name":"Build macOS","artifact-name":"sss-macos","artifact-path":"builds/sss","release-asset-name":"sss-macos"}'
win='{"os":"windows-latest","name":"Build Windows","artifact-name":"sss-windows","artifact-path":"builds/sss.exe","release-asset-name":"sss-windows.exe"}'
lnx='{"os":"ubuntu-22.04","cache-suffix":"-ubuntu2204","name":"Build Linux","artifact-name":"sss-linux","artifact-path":"builds/sss","release-asset-name":"sss-linux"}'
# PRs: build-dev covers Linux, so only master, tags and dispatch build the credentialed binary
if [ "$EVENT" = pull_request ] || { [ "$EVENT" = push ] && [ "$REF" != refs/heads/master ] && [[ "$REF" != refs/tags/v* ]]; }; then
  echo "build-matrix={\"include\":[$mac,$win]}" >> "$OUT"
else
  echo "build-matrix={\"include\":[$lnx,$mac,$win]}" >> "$OUT"
fi
