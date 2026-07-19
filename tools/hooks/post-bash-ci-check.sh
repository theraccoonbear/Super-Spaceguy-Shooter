#!/bin/bash
# Claude Code PostToolUse hook: after git push, launch a background CI watcher.
# Outputs the log path so Claude can Monitor it and send a PushNotification on completion.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
" 2>/dev/null)

echo "$COMMAND" | grep -qE "git(\s+-C\s+\S+)?\s+push" || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)
BRANCH=$(git -C "$REPO" branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] || [ "$BRANCH" = "master" ] && exit 0

PR=$(gh pr list --repo theraccoonbear/Super-Spaceguy-Shooter --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)
[ -z "$PR" ] || [ "$PR" = "null" ] && exit 0

LOGFILE="/tmp/ci-watch-pr${PR}.log"
rm -f "$LOGFILE"

# Background: poll until all checks leave pending, then write terminal marker
(
  while true; do
    STATUS_JSON=$(gh pr checks "$PR" --repo theraccoonbear/Super-Spaceguy-Shooter --json name,bucket 2>/dev/null)
    if [ -z "$STATUS_JSON" ]; then
      sleep 15
      continue
    fi
    echo "$STATUS_JSON" | python3 -c "
import sys, json
checks = json.load(sys.stdin)
for c in checks:
    print(f\"{c['name']}: {c['bucket']}\")
" >> "$LOGFILE" 2>/dev/null
    ALL_DONE=$(echo "$STATUS_JSON" | python3 -c "
import sys, json
checks = json.load(sys.stdin)
print('yes' if all(c['bucket'] != 'pending' for c in checks) else 'no')
" 2>/dev/null)
    if [ "$ALL_DONE" = "yes" ]; then
      FAILED=$(echo "$STATUS_JSON" | python3 -c "
import sys, json
checks = json.load(sys.stdin)
failed = [c['name'] for c in checks if c['bucket'] == 'fail']
print(','.join(failed))
" 2>/dev/null)
      if [ -z "$FAILED" ]; then
        echo "CI_RESULT:PASS:PR #${PR} all checks green" >> "$LOGFILE"
      else
        echo "CI_RESULT:FAIL:PR #${PR} failed: $FAILED" >> "$LOGFILE"
      fi
      break
    fi
    sleep 30
  done
) &

echo ""
echo "=== CI: PR #$PR ($BRANCH) — watching in background ==="
echo "CI_WATCH_LOG=$LOGFILE"
echo ""
