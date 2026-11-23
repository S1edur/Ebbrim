#!/bin/bash
# Ebbrim statusLine command for Claude Code. Saves the `rate_limits` that
# Claude Code passes on stdin to Ebbrim's own folder, then runs the
# previous statusLine command (if any) with the same input so its output stays.
input=$(cat)
dir="${EBBRIM_DIR:-$HOME/Library/Application Support/Ebbrim}"
limits=$(printf '%s' "$input" | /usr/bin/plutil -extract rate_limits json -o - - 2>/dev/null)
if [ -n "$limits" ]; then
  mkdir -p "$dir"
  tmp="$dir/.statusline-usage.json.$$"
  printf '{"rate_limits":%s,"captured_at":%s}\n' "$limits" "$(date +%s)" > "$tmp" \
    && mv -f "$tmp" "$dir/statusline-usage.json"
fi
if [ -n "${EBBRIM_PREV_STATUSLINE:-}" ]; then
  printf '%s' "$input" | /bin/bash -c "$EBBRIM_PREV_STATUSLINE"
fi
