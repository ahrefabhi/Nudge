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

# macOS ties Accessibility and Automation permissions to the signature. An ad-hoc signature
# changes with every build, so permissions go stale after each update; a certificate keeps
# them. Use PIP_SIGN_IDENTITY if set, else the "Pip Code Signing" certificate if this Mac has
# it, else ad-hoc (fine for building from source).
identity="${PIP_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"Pip Code Signing"'; then
    identity="Pip Code Signing"
fi
identity="${identity:--}"
sign() { codesign --force --sign "$identity" "$@"; }

# Sign inside out: Sparkle's helpers, the framework, the collector, then the app.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$sparkle"/XPCServices/*.xpc "$sparkle/Autoupdate" "$sparkle/Updater.app"; do
    sign "$nested"
done
sign "$app/Contents/Frameworks/Sparkle.framework"
sign --identifier app.pip.hook "$app/Contents/Helpers/pip-hook"
sign "$app"
codesign --verify --deep --strict "$app"
[[ "$identity" == "-" ]] && echo "note: ad-hoc signed; macOS permissions won't carry over to the next build" >&2

echo "$app"
