#!/usr/bin/env bash
# Renders Pip's app icon from the real PipView into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

iconset="build/AppIcon.iconset"
rm -rf "$iconset"
swift run Pip --icon "$iconset"
iconutil -c icns -o Resources/AppIcon.icns "$iconset"
echo "Resources/AppIcon.icns"
