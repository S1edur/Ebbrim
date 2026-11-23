#!/bin/bash
# Builds Ebbrim.dmg (drag-to-Applications disk image) into build.noindex/.
# The app is ad-hoc signed, not notarized: see README › Download.
set -euo pipefail
source "$(dirname "$0")/buildlib.sh"
"$ROOT/build.sh" >/dev/null
STAGE="$OUT/dmg"
rm -rf "$STAGE" "$OUT/Ebbrim.dmg"
mkdir -p "$STAGE"
cp -R "$OUT/Ebbrim.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Ebbrim" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Ebbrim.dmg"
rm -rf "$STAGE"
echo "built $OUT/Ebbrim.dmg ($(du -h "$OUT/Ebbrim.dmg" | cut -f1))"
