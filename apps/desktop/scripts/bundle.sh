#!/bin/sh
# Builds build/Voice.app.
#
#   scripts/bundle.sh [debug|release]
#
# VERSION sets the app version. CODESIGN_IDENTITY picks the signing identity; by default
# the first Apple Development identity in the keychain is used, or an ad-hoc signature.
set -eu
cd "$(dirname "$0")/.."

configuration="${1:-debug}"
app="build/Voice.app"

if ! command -v swift >/dev/null; then
  echo "error: Swift is not installed. Install Xcode, then run: xcode-select --install" >&2
  exit 1
fi

echo "Building Voice ($configuration)"
swift build -c "$configuration" --product Voice

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c "$configuration" --show-bin-path)/Voice" "$app/Contents/MacOS/Voice"
cp Support/Info.plist "$app/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "${VERSION#v}" "$app/Contents/Info.plist"
fi

identity="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -n 1)}"
if [ -z "$identity" ]; then
  identity="-"
  echo "No signing identity found: signing ad hoc. macOS asks for the app's permissions again after every build."
fi
codesign --force --sign "$identity" "$app"

echo "Built $app"
