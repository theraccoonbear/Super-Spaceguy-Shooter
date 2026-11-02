#!/usr/bin/env bash
# Fail with a workflow error if a secret was not passed through the environment.
#
# Usage: require_secret.sh <ENV VAR NAME>
# Env in:  the variable named by the argument (set from ${{ secrets.NAME }} in the step's env:)
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0;; esac
set -euo pipefail

name="${1:?usage: require_secret.sh <ENV VAR NAME>}"
if [[ -z "${!name:-}" ]]; then
  echo "::error::$name secret is not set"
  exit 1
fi
