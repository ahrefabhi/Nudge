#!/usr/bin/env bash
# Builds a Peeku release: Peeku-<version>.zip, signed with your Sparkle EdDSA key, and the
# appcast.xml Sparkle reads. Without --publish it stops there (a dry run); with --publish it
# tags the release and uploads both files to GitHub.
#
# Usage: scripts/release.sh <version> [--publish]      e.g. scripts/release.sh 0.2.0
#
# The feed lives at releases/latest/download/appcast.xml, so every published release must
# attach its own appcast.xml. The private signing key stays in your login Keychain
# (made once with Sparkle's generate_keys).
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }

version="${1:-}"
publish="${2:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "give a version like 0.2.0"
[[ -z "$publish" || "$publish" == "--publish" ]] || die "unknown option $publish"
tag="v$version"

git diff --quiet && git diff --cached --quiet || die "commit or stash your changes first"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "$tag already exists"

# The repository comes from the feed URL, so the app and the releases can't disagree.
feed="$(plutil -extract SUFeedURL raw Resources/Info.plist)"
repo="$(sed -E 's|https://github.com/([^/]+/[^/]+)/releases/.*|\1|' <<<"$feed")"
[[ "$repo" != "$feed" ]] || die "SUFeedURL isn't a GitHub releases URL: $feed"

# Sparkle compares CFBundleVersion; the commit count only ever grows on main.
build="$(git rev-list --count HEAD)"
PEEKU_VERSION="$version" PEEKU_BUILD="$build" scripts/bundle.sh release

out="build/release/$tag"
rm -rf "$out"
mkdir -p "$out"
zip="$out/Peeku-$version.zip"
ditto -c -k --keepParent build/Peeku.app "$zip"

# Sparkle only installs an app named like the one it's replacing, and the feed only lists the
# latest release, so every update archive also carries the app under Peeku's old names. An app
# updated from Nudge or Pip renames itself to Peeku.app on first launch (BundleRename).
# The bundle's name isn't part of its signature, so the copies stay validly signed.
update_zip="$out/Peeku-$version-update.zip"
staging="$out/update"
mkdir -p "$staging"
for name in Peeku Nudge Pip; do ditto build/Peeku.app "$staging/$name.app"; done
ditto -c -k "$staging" "$update_zip"
rm -rf "$staging"

sign_update=".build/artifacts/sparkle/Sparkle/bin/sign_update"
# Prints: sparkle:edSignature="…" length="…"
enclosure="$("$sign_update" "$update_zip")"
[[ "$enclosure" == *edSignature* ]] || die "signing failed: $enclosure"

minimum="$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist)"
cat > "$out/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Peeku</title>
    <link>https://github.com/$repo</link>
    <item>
      <title>Peeku $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$repo/releases/tag/$tag</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$repo/releases/download/$tag/Peeku-$version-update.zip" type="application/octet-stream" $enclosure />
    </item>
  </channel>
</rss>
XML

echo "built $zip, $update_zip (build $build) and $out/appcast.xml"

if [[ "$publish" != "--publish" ]]; then
    echo "dry run: nothing uploaded. To publish: scripts/release.sh $version --publish"
    exit 0
fi

git push origin HEAD
gh release create "$tag" "$zip" "$update_zip" "$out/appcast.xml" --repo "$repo" --target "$(git rev-parse HEAD)" \
    --title "Peeku $version" --generate-notes
echo "published https://github.com/$repo/releases/tag/$tag"
