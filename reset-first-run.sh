#!/bin/bash
# For testing: makes Ebbrim behave like a fresh install (onboarding again).
# Clears only Ebbrim's preferences and its data folder; the app stays installed.
# Refuses while "Claude Code in Terminal" is connected, so its status line never breaks.
set -euo pipefail
if grep -q 'EBBRIM_STATUSLINE=1' "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "Disconnect \"Claude Code in Terminal\" in Ebbrim's Settings first, then run this again."
  exit 1
fi
pkill -x Ebbrim 2>/dev/null || true
for _ in $(seq 1 50); do pgrep -x Ebbrim >/dev/null || break; sleep 0.1; done
pkill -9 -x Ebbrim 2>/dev/null || true
defaults delete com.denys.ebbrim 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/Ebbrim"
echo "Ebbrim is reset. Open at Login, if you turned it on, stays on."
[ "${1:-}" = "--no-open" ] || open /Applications/Ebbrim.app
