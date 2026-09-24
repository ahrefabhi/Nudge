#!/usr/bin/env bash
# Builds Pip and its hook collector, and wraps them in build/Pip.app (ad-hoc signed).
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
swift build -c "$config" --product Pip
swift build -c "$config" --product pip-hook
bin="$(swift build -c "$config" --show-bin-path)"

app="build/Pip.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
cp "$bin/Pip" "$app/Contents/MacOS/Pip"
cp "$bin/pip-hook" "$app/Contents/Helpers/pip-hook"
cp Resources/Info.plist "$app/Contents/Info.plist"

# Nested code is signed before the bundle that contains it.
codesign --force --sign - "$app/Contents/Helpers/pip-hook"
codesign --force --sign - "$app"

echo "$app"
