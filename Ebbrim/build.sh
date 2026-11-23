#!/bin/bash
# Builds Ebbrim.app into ../build.noindex (kept out of Spotlight).
set -e
source "$(dirname "$0")/buildlib.sh"
APP="$OUT/Ebbrim.app"

compile_zstd
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "compiling (SDK: $SDK)…"
swiftc -O -sdk "$SDK" -target "$TARGET" \
  -framework Cocoa -framework SwiftUI \
  -import-objc-header "$ROOT/Vendor/zstd/zstd.h" \
  -o "$APP/Contents/MacOS/Ebbrim" \
  "$ROOT"/Sources/*.swift "$ROOT"/Sources/Data/*.swift "${ZSTD_OBJS[@]}"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
[ -d "$ROOT/Resources" ] && cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "built $APP"
