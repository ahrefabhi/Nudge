#!/usr/bin/env bash
# Renders Peeku's app icon from the real PeekuView into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

iconset="build/AppIcon.iconset"
rm -rf "$iconset"
swift run Peeku --icon "$iconset"
iconutil -c icns -o Resources/AppIcon.icns "$iconset"
echo "Resources/AppIcon.icns"
