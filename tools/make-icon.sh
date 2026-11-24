#!/bin/sh
# Draws the app icon and writes App/AppIcon.icns, and the same drawing as
# a vector file, docs/icon.svg.
set -eu

cd "$(dirname "$0")/.."

SVG="docs/icon.svg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -O tools/make-icon.swift -o "$WORK/make-icon"
mkdir -p "$(dirname "$SVG")"
"$WORK/make-icon" "$WORK/AppIcon.iconset" "$SVG"
iconutil -c icns "$WORK/AppIcon.iconset" -o App/AppIcon.icns
echo "Wrote App/AppIcon.icns and $SVG"
