#!/usr/bin/env bash
# Fails if a Linux binary needs a newer glibc than the documented floor (#306).
# Usage: glibc_floor_check.sh <linux sss binary> [floor]
# The floor is the oldest glibc a player needs: 2.34 is RHEL/Rocky 9. Lower or raise
# it deliberately, together with README "Downloading a release" and the ubuntu-22.04
# runners that build the Linux release binary in .github/workflows/build.yml.
set -uo pipefail
BIN="$1"
FLOOR="${2:-2.34}"
NEED=$(objdump -T "$BIN" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -n 1)
NEED="${NEED#GLIBC_}"
if [ -z "$NEED" ]; then
  echo "::error::no GLIBC_ symbol versions found in $BIN"
  exit 1
fi
HIGHEST=$(printf '%s\n%s\n' "$NEED" "$FLOOR" | sort -V | tail -n 1)
if [ "$HIGHEST" != "$FLOOR" ]; then
  echo "::error::$BIN needs glibc $NEED, newer than the documented floor $FLOOR"
  objdump -T "$BIN" | grep "GLIBC_$NEED" | head -n 5
  exit 1
fi
echo "ok: highest glibc requirement is $NEED (floor $FLOOR)"
