#!/bin/bash
# Regenerates Resources/AppIcon.icns from the vector logo (Sources/Logo.swift).
set -euo pipefail
source "$(dirname "$0")/../buildlib.sh"
TMP="$(mktemp -d)"
swiftc -sdk "$SDK" -target "$TARGET" -framework SwiftUI -framework AppKit \
  -o "$TMP/render" "$ROOT/Sources/Logo.swift" "$ROOT/Icon/main.swift"
"$TMP/render" "$TMP/icon-1024.png"
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
cp "$TMP/icon-1024.png" "$ROOT/Icon/icon-1024.png"
rm -rf "$TMP"
echo "wrote $ROOT/Resources/AppIcon.icns"
