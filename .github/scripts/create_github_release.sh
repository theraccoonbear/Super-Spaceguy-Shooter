#!/usr/bin/env bash
# Create the GitHub release for a tag, attaching every file in the assets directory.
# A tag with a '-' (v0.1.0-rc1) is a pre-release, never "latest".
#
# Usage: create_github_release.sh [--dry-run] <tag> [assets dir]
#   --dry-run  print the gh command instead of running it (no token or network needed)
#   assets dir defaults to release-assets
# Env in:  GH_TOKEN  token with contents: write (not needed for --dry-run)
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0;; esac
set -euo pipefail

dry=0
if [ "${1:-}" = --dry-run ]; then dry=1; shift; fi
TAG="${1:?usage: create_github_release.sh [--dry-run] <tag> [assets dir]}"
dir="${2:-release-assets}"
cmd=(gh release create "$TAG" "$dir"/* --title "$TAG" --generate-notes)
[[ "$TAG" == *-* ]] && cmd+=(--prerelease)
if [ "$dry" = 1 ]; then
  printf '%q ' "${cmd[@]}"; echo
else
  "${cmd[@]}"
fi
