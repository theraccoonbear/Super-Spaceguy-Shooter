#!/usr/bin/env bash
# Decide whether a push to master touched server/ (so the Worker needs deploying).
#
# Usage: detect_server_changes.sh <before sha> <head sha>
#   <before sha> github.event.before; all-zeros or an unknown commit counts as changed
# Env in:  GITHUB_OUTPUT  file the output is appended to (defaults to /dev/stdout)
# Outputs: changed=true|false on GITHUB_OUTPUT. Needs full history (fetch-depth: 0).
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0;; esac
set -euo pipefail

before="${1:?usage: detect_server_changes.sh <before sha> <head sha>}"
sha="${2:?usage: detect_server_changes.sh <before sha> <head sha>}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"
if [[ "$before" =~ ^0+$ ]] || ! git cat-file -e "$before^{commit}" 2>/dev/null; then
  echo "changed=true" >> "$OUT"
elif [[ -n "$(git diff --name-only "$before" "$sha" -- server/)" ]]; then
  echo "changed=true" >> "$OUT"
else
  echo "changed=false" >> "$OUT"
  echo "No changes under server/; skipping deploy."
fi
