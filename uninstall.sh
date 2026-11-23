#!/bin/bash
# Removes Ebbrim and everything it left on this Mac: puts back your Claude Code
# statusLine (if Ebbrim was connected to it), removes the login item, its
# preferences, its data folder, /Applications/Ebbrim.app and ~/.ebbrim.
# Claude, Codex and your logins are not touched.
set -euo pipefail

main() {
  local app="/Applications/Ebbrim.app" here
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

  pkill -x Ebbrim 2>/dev/null || true
  for _ in $(seq 1 50); do pgrep -x Ebbrim >/dev/null || break; sleep 0.1; done
  pkill -9 -x Ebbrim 2>/dev/null || true

  if [ -x "$app/Contents/MacOS/Ebbrim" ]; then
    "$app/Contents/MacOS/Ebbrim" --uninstall || true
  else
    # The app is already gone, so its login item can't be removed from here.
    if grep -q 'EBBRIM_STATUSLINE=1' "$HOME/.claude/settings.json" 2>/dev/null; then
      echo "✗ Your Claude Code statusLine still points at Ebbrim: reinstall Ebbrim and use Uninstall, or edit ~/.claude/settings.json."
    fi
    rm -rf "$HOME/Library/Application Support/Ebbrim" "$HOME/.ebbrim"
    defaults delete com.denys.ebbrim 2>/dev/null || true
    echo "✓ Removed Ebbrim's data folder and preferences"
  fi
  rm -rf "$app"
  # The preferences service may write an empty file for the removed domain
  # just after; give it a moment, then remove what it left.
  sleep 1
  defaults delete com.denys.ebbrim 2>/dev/null || true
  rm -f "$HOME/Library/Preferences/com.denys.ebbrim.plist"
  echo "✓ Removed $app"
  if [ -n "$here" ] && [ -d "$here/build.noindex" ]; then rm -rf "$here/build.noindex"; fi

  echo ""
  echo "Ebbrim is uninstalled."
  if [ -n "$here" ] && [ -e "$here/.git" ] && [ "$here" != "$HOME/.ebbrim" ]; then
    echo "This source folder is still here, delete it if you no longer need it: $here"
  fi
}

main "$@"
