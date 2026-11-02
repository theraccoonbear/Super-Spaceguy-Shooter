#!/usr/bin/env bash
# Fail if assets/speech_dict.txt differs from what tools/bake_speech_dict just wrote.
#
# Usage: check_speech_dict_fresh.sh
# Run from the repo root right after "bash tools/bake_speech_dict". Compares the working
# tree with the index, so uncommitted local edits to the dict also count as stale.
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0;; esac
set -euo pipefail

git diff --exit-code assets/speech_dict.txt || {
  echo "::error::speech_dict.txt is stale — run tools/bake_speech_dict and commit"
  exit 1
}
