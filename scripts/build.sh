#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LOCALPORTS_BUILD_DIR:-$PROJECT_ROOT/.build}"
OUTPUT_DIR="${LOCALPORTS_OUTPUT_DIR:-$PROJECT_ROOT/dist}"
APP="$OUTPUT_DIR/Yolk.app"
SIGN_IDENTITY="${YOLK_SIGN_IDENTITY:--}"
BUILD_ARGS=(--package-path "$PROJECT_ROOT" --scratch-path "$BUILD_DIR" -c release)
if [[ "${YOLK_UNIVERSAL:-0}" == "1" ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
mkdir -p "$BUILD_DIR/module-cache" "$OUTPUT_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
STAGING="$(mktemp -d "$OUTPUT_DIR/.yolk-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="$STAGING/Yolk.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/LocalPorts" "$STAGED_APP/Contents/MacOS/LocalPorts"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
# SwiftPM's accessor checks Bundle.main.resourceURL on macOS.
ditto "$BIN_DIR/LocalPorts_LocalPorts.bundle" "$STAGED_APP/Contents/Resources/LocalPorts_LocalPorts.bundle"
ICONSET="$STAGING/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$PROJECT_ROOT/Sources/LocalPorts/Assets/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$PROJECT_ROOT/Sources/LocalPorts/Assets/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$STAGED_APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGED_APP"
fi
codesign --verify --strict "$STAGED_APP"
# Do not overwrite a mapped executable in place. Keep one recoverable previous build.
if [[ -e "$APP" ]]; then
    BACKUP_DIR="$(mktemp -d "$OUTPUT_DIR/.yolk-previous.XXXXXX")"
    mv "$APP" "$BACKUP_DIR/Yolk.app"
fi
mv "$STAGED_APP" "$APP"
printf '\nApplication ready: %s\n' "$APP"
