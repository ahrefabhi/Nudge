#!/usr/bin/env bash
# Renders Nudge's app icon from the real NudgeView into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

iconset="build/AppIcon.iconset"
rm -rf "$iconset"
swift run Nudge --icon "$iconset"
iconutil -c icns -o Resources/AppIcon.icns "$iconset"
echo "Resources/AppIcon.icns"
