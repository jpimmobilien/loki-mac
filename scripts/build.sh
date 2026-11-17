#!/bin/bash
# Baut LOKI.app (Apple Silicon, ad-hoc signiert) nach build/LOKI.app.
#   VERSION=0.1.0 BUILD_NUMBER=1 scripts/build.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
mkdir -p build

command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate

echo "▸ xcodebuild (Release, arm64)"
if ! xcodebuild -project LOKI.xcodeproj -scheme LOKI -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/dd \
    -skipMacroValidation -skipPackagePluginValidation \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build > build/xcodebuild.log 2>&1; then
    echo "✗ Build fehlgeschlagen. Fehler:"
    grep -E "error:|fatal error|Undefined symbol|ld: " build/xcodebuild.log | sort -u | head -150 || true
    echo "--- Ende des Protokolls ---"
    tail -40 build/xcodebuild.log
    exit 1
fi
grep -E "warning:" build/xcodebuild.log | grep "/Sources/LOKI/" | sort -u | head -60 || true

APP="build/dd/Build/Products/Release/LOKI.app"
test -d "$APP" || { echo "✗ $APP fehlt"; exit 1; }
rm -rf build/LOKI.app
ditto "$APP" build/LOKI.app
codesign --force --deep --sign - build/LOKI.app
codesign --verify --deep --strict --verbose=2 build/LOKI.app
echo "✓ build/LOKI.app ($(du -sh build/LOKI.app | cut -f1))"
