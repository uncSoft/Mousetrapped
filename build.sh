#!/bin/zsh
# Build Mousetrapped.app into ./dist
# Usage: ./build.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")"

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release "${ARCH_FLAGS[@]}"

BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/Mousetrapped"
APP="dist/Mousetrapped.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mousetrapped"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AboutArt.png "$APP/Contents/Resources/"

# Sign with a stable identity if available so TCC permission grants (Input
# Monitoring) survive rebuilds and match the released build. Prefer Developer
# ID (the identity releases ship with, so a locally built copy shares the same
# designated requirement and TCC treats them as the same app); fall back to
# Apple Development, then ad-hoc.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development/{print $2; exit}')"
fi
codesign --force --options runtime --timestamp --sign "${IDENTITY:--}" "$APP" 2>/dev/null \
    || codesign --force --sign "${IDENTITY:--}" "$APP"

echo "Signed as: ${IDENTITY:-ad-hoc}"

echo "Built $APP"
echo "Install with: cp -R $APP /Applications/"
# fin
