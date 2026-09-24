#!/usr/bin/env bash
# Builds Nudge, its hook collector and Sparkle into build/Nudge.app (ad-hoc signed).
# Usage: scripts/bundle.sh [debug|release]
# NUDGE_VERSION (e.g. 0.2.0) and NUDGE_BUILD (a number that grows every release) stamp the
# bundle's Info.plist; the source Info.plist is left alone.
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
swift build -c "$config" --product Nudge
swift build -c "$config" --product nudge-hook
bin="$(swift build -c "$config" --show-bin-path)"

app="build/Nudge.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$bin/Nudge" "$app/Contents/MacOS/Nudge"
cp "$bin/nudge-hook" "$app/Contents/Helpers/nudge-hook"
# ditto keeps the framework's internal symlinks intact.
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

if [[ -n "${NUDGE_VERSION:-}" ]]; then plutil -replace CFBundleShortVersionString -string "$NUDGE_VERSION" "$app/Contents/Info.plist"; fi
if [[ -n "${NUDGE_BUILD:-}" ]]; then plutil -replace CFBundleVersion -string "$NUDGE_BUILD" "$app/Contents/Info.plist"; fi

# macOS ties Accessibility and Automation permissions to the signature. An ad-hoc signature
# changes with every build, so permissions go stale after each update; a certificate keeps
# them. Use NUDGE_SIGN_IDENTITY if set, else the "Nudge Code Signing" certificate if this Mac has
# it, else ad-hoc (fine for building from source).
identity="${NUDGE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"Nudge Code Signing"'; then
    identity="Nudge Code Signing"
fi
identity="${identity:--}"
sign() { codesign --force --sign "$identity" "$@"; }

# Sign inside out: Sparkle's helpers, the framework, the collector, then the app.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$sparkle"/XPCServices/*.xpc "$sparkle/Autoupdate" "$sparkle/Updater.app"; do
    sign "$nested"
done
sign "$app/Contents/Frameworks/Sparkle.framework"
sign --identifier app.nudge.hook "$app/Contents/Helpers/nudge-hook"
sign "$app"
codesign --verify --deep --strict "$app"
[[ "$identity" == "-" ]] && echo "note: ad-hoc signed; macOS permissions won't carry over to the next build" >&2

echo "$app"
