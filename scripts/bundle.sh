#!/usr/bin/env bash
# Builds Pip, its hook collector and Sparkle into build/Pip.app (ad-hoc signed).
# Usage: scripts/bundle.sh [debug|release]
# PIP_VERSION (e.g. 0.2.0) and PIP_BUILD (a number that grows every release) stamp the
# bundle's Info.plist; the source Info.plist is left alone.
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
swift build -c "$config" --product Pip
swift build -c "$config" --product pip-hook
bin="$(swift build -c "$config" --show-bin-path)"

app="build/Pip.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$bin/Pip" "$app/Contents/MacOS/Pip"
cp "$bin/pip-hook" "$app/Contents/Helpers/pip-hook"
# ditto keeps the framework's internal symlinks intact.
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

if [[ -n "${PIP_VERSION:-}" ]]; then plutil -replace CFBundleShortVersionString -string "$PIP_VERSION" "$app/Contents/Info.plist"; fi
if [[ -n "${PIP_BUILD:-}" ]]; then plutil -replace CFBundleVersion -string "$PIP_BUILD" "$app/Contents/Info.plist"; fi

# Sign inside out: Sparkle's helpers, the framework, the collector, then the app.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$sparkle"/XPCServices/*.xpc "$sparkle/Autoupdate" "$sparkle/Updater.app"; do
    codesign --force --sign - "$nested"
done
codesign --force --sign - "$app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$app/Contents/Helpers/pip-hook"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

echo "$app"
