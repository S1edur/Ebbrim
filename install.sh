#!/bin/bash
# Ebbrim installer: builds Ebbrim from source on this Mac and puts it in /Applications.
#
#   One line (keeps the source in ~/.ebbrim):
#     curl -fsSL https://raw.githubusercontent.com/S1edur/Ebbrim/main/install.sh | bash
#   From a clone:
#     ./install.sh
#
# Run the same command again to update. Built locally, so macOS shows no
# "unidentified developer" warning, and no password is needed.
set -euo pipefail

REPO_URL="${EBBRIM_REPO:-https://github.com/S1edur/Ebbrim.git}"
BRANCH="${EBBRIM_BRANCH:-main}"
SRC_DIR="${EBBRIM_SRC:-$HOME/.ebbrim}"
DEST="/Applications/Ebbrim.app"

say()  { printf '%s\n' "$*"; }
fail() { printf 'Ebbrim: %s\n' "$*" >&2; exit 1; }

main() {
  # 1. Requirements
  [ "$(uname -s)" = Darwin ] || fail "Ebbrim runs on macOS only."
  local version major
  version=$(sw_vers -productVersion); major=${version%%.*}
  [ "$major" -ge 26 ] || fail "Ebbrim needs macOS 26 or later (this Mac runs $version)."
  [ "$(uname -m)" = arm64 ] || fail "Ebbrim currently builds for Apple silicon Macs only."
  if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
    say "Ebbrim is built from source and needs Apple's free Command Line Tools."
    say "An installer window is opening now. When it finishes, run this command again."
    xcode-select --install >/dev/null 2>&1 || true
    exit 1
  fi
  command -v git >/dev/null || fail "git is missing (it comes with the Command Line Tools)."

  # 2. Source: the checkout this script lives in, or ~/.ebbrim when piped from curl
  # Run as a file (./install.sh) → build that checkout. Piped (curl … | bash)
  # → always use ~/.ebbrim, whatever folder the terminal happens to be in.
  local here=""
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [ -n "$here" ] && [ -f "$here/Ebbrim/build.sh" ]; then
    cd "$here"
    if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      if [ -n "$(git status --porcelain)" ]; then say "Local changes found: building them as they are (no git pull)."
      else git pull --ff-only --quiet || say "Could not update from GitHub: building the copy that is here."; fi
    fi
  elif [ -d "$SRC_DIR/.git" ]; then
    git -C "$SRC_DIR" pull --ff-only --quiet || say "Could not update from GitHub: building the copy that is here."
    cd "$SRC_DIR"
  else
    say "Downloading Ebbrim's source into ${SRC_DIR}…"
    git clone --quiet --depth 1 --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
    cd "$SRC_DIR"
  fi

  # 3. Build (about a minute the first time)
  say "Building Ebbrim…"
  Ebbrim/build.sh >/dev/null || fail "the build failed. Run Ebbrim/build.sh to see why."

  # 4. Replace /Applications/Ebbrim.app and start it
  quit_app Ebbrim
  rm -rf "/Applications/.Ebbrim.app.new"
  cp -R build.noindex/Ebbrim.app "/Applications/.Ebbrim.app.new"
  rm -rf "$DEST"
  mv "/Applications/.Ebbrim.app.new" "$DEST"
  open "$DEST"

  local v
  v=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DEST/Contents/Info.plist")
  say ""
  say "Ebbrim $v is installed and running: look at the edge of your screen."
  say "Update:    run this command again."
  say "Uninstall: Ebbrim menu → Uninstall Ebbrim…  (or: bash \"$PWD/uninstall.sh\")"
}

# Quit a running copy; it saves and cleans up on SIGTERM, so wait for it.
quit_app() {
  pkill -x "$1" 2>/dev/null || true
  for _ in $(seq 1 50); do pgrep -x "$1" >/dev/null || break; sleep 0.1; done
  pkill -9 -x "$1" 2>/dev/null || true
}

main "$@"
