#!/bin/bash
# Builds and runs the data-layer tests (no XCTest on CLT-only Macs).
set -e
source "$(dirname "$0")/buildlib.sh"
compile_zstd
mkdir -p "$OUT"
swiftc -sdk "$SDK" -target "$TARGET" -framework Cocoa \
  -import-objc-header "$ROOT/Vendor/zstd/zstd.h" \
  -o "$OUT/tests" \
  "$ROOT/Sources/UsageFeed.swift" "$ROOT"/Sources/Data/*.swift "$ROOT"/Tests/*.swift \
  "${ZSTD_OBJS[@]}"
cd "$ROOT/Tests" && "$OUT/tests"
