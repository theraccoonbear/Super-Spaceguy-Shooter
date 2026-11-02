#!/usr/bin/env bash
# The "All checks pass" gate: every needed job must have succeeded, except a job the
# change filter skipped on purpose.
#
# Usage: ci_gate.sh <job>=<result>:<wanted> ...
#   <result>  the job's needs.<job>.result (success, failure, cancelled, skipped)
#   <wanted>  true if the change filter wanted the job to run, false if it skipped it
#             on purpose (a skipped job then counts as passed)
# Example: ci_gate.sh changes=success:true render=skipped:false
# Exits 1 if any job fails the rule, after printing one line per job.
case "${1:-}" in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0;; esac
set -euo pipefail

fail=0
# <job> <result> <whether the change filter wanted it to run>
check() {
  if [ "$2" = success ] || { [ "$2" = skipped ] && [ "$3" = false ]; }; then
    printf 'ok   %-14s %s\n' "$1" "$2"
  else
    printf 'FAIL %-14s %s\n' "$1" "$2"; fail=1
  fi
}
for arg in "$@"; do
  job="${arg%%=*}"
  rest="${arg#*=}"
  check "$job" "${rest%%:*}" "${rest#*:}"
done
[[ $fail -eq 0 ]] && echo "All checks passed." || exit 1
