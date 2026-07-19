#!/bin/bash
# Claude Code PostToolUse hook: after git push, auto-display PR CI status.
# Receives JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
" 2>/dev/null)

echo "$COMMAND" | grep -qE "git(\s+-C\s+\S+)?\s+push" || exit 0

REPO="/var/home/don/Downloads/_installers/qb64pe/code/3d"
BRANCH=$(git -C "$REPO" branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] || [ "$BRANCH" = "master" ] && exit 0

PR=$(gh pr list --repo theraccoonbear/Super-Spaceguy-Shooter --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)
[ -z "$PR" ] || [ "$PR" = "null" ] && exit 0

echo ""
echo "=== CI: PR #$PR ($BRANCH) ==="
gh pr checks "$PR" --repo theraccoonbear/Super-Spaceguy-Shooter 2>&1 | \
    awk '{printf "  %s\n", $0}'
echo ""
