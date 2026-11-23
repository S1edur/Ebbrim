# Shared by build.sh and test.sh. Pins the macOS 26 SDK (the default 27 SDK
# mismatches the CLT Swift compiler) and compiles the vendored zstd decoder.
[ -n "$BASH_VERSION" ] && shopt -s nullglob
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/../build.noindex"
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | head -1)"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx26.0"

# Compiles zstd once into $OUT/zstd and sets ZSTD_OBJS.
compile_zstd() {
  local dir="$OUT/zstd"; mkdir -p "$dir"
  ZSTD_OBJS=()
  for c in "$ROOT"/Vendor/zstd/common/*.c "$ROOT"/Vendor/zstd/decompress/*.c; do
    local o="$dir/$(basename "${c%.c}").o"
    if [ ! -f "$o" ] || [ "$c" -nt "$o" ]; then
      clang -c -O2 -DZSTD_DISABLE_ASM -DZSTD_LEGACY_SUPPORT=0 -DNDEBUG \
        -target "$TARGET" -isysroot "$SDK" -o "$o" "$c"
    fi
    ZSTD_OBJS+=("$o")
  done
}
