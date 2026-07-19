#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
HOOKS_DIR="$REPO/.git/hooks"

cp "$SCRIPT_DIR/pre-push" "$HOOKS_DIR/pre-push"
chmod +x "$HOOKS_DIR/pre-push"
echo "Installed pre-push hook."
