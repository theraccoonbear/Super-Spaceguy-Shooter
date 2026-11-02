#!/usr/bin/env bash
# Verify the downloaded release assets are exactly the expected, non-empty files.
#
# Usage: check_release_assets.sh [dir] [asset ...]
#   dir     defaults to release-assets
#   asset   defaults to sss-linux sss-macos sss-windows.exe
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0;; esac
set -euo pipefail

dir="${1:-release-assets}"
if [ "$#" -gt 0 ]; then shift; fi
if [ "$#" -eq 0 ]; then set -- sss-linux sss-macos sss-windows.exe; fi
ls -l "$dir"
for f in "$@"; do
  [ -s "$dir/$f" ] || { echo "::error::missing release asset $f"; exit 1; }
done
[ "$(ls "$dir" | wc -l)" -eq "$#" ] || { echo "::error::expected exactly $# release assets"; exit 1; }
