#!/bin/bash
# Builds a universal (Apple Silicon + Intel), ad-hoc signed build/LightSnap.app.
#   --install  copy it to /Applications and launch it
#   --zip      also produce build/LightSnap.zip + .sha256 for a release
set -euo pipefail
cd "$(dirname "$0")"

APP=build/LightSnap.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" \
        Sources/*.swift -o "build/LightSnap-$arch"
done
lipo -create build/LightSnap-arm64 build/LightSnap-x86_64 -output "$APP/Contents/MacOS/LightSnap"
rm build/LightSnap-arm64 build/LightSnap-x86_64
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature with the hardened runtime (no Developer ID needed).
codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"

for arg in "$@"; do
    case "$arg" in
        --zip)
            ditto -c -k --keepParent "$APP" build/LightSnap.zip
            (cd build && shasum -a 256 LightSnap.zip > LightSnap.zip.sha256)
            echo "Packaged build/LightSnap.zip"
            ;;
        --install)
            pkill -x LightSnap || true
            rm -rf /Applications/LightSnap.app
            cp -R "$APP" /Applications/
            open /Applications/LightSnap.app
            echo "Installed to /Applications/LightSnap.app"
            ;;
    esac
done
