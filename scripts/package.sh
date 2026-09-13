#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Override CODE_SIGN_IDENTITY and related Xcode settings through arguments.
bash scripts/build.sh ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO "$@"
app="$PWD/build/Build/Products/Release/Duolet.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
mkdir -p dist
stage=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Duolet.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/License.txt"
cat > "$stage/Read Me.txt" <<'TXT'
Duolet — power & connection, at a glance.

Drag Duolet.app into Applications, eject this disk, then open Duolet.
Duolet appears in the menu bar and shows a movable desktop widget.
Use its menu to hide/resize the widget or enable Launch at Login.
For the system widget: right-click desktop → Edit Widgets → Duolet.

This local build is ad-hoc signed, not notarized by Apple. If macOS blocks it,
review System Settings → Privacy & Security → Open Anyway after attempting
launch. Only approve software whose source you trust. Managed Macs may prohibit
this exception. No system security setting needs to be disabled.

The WidgetKit extension is included. Some macOS installations require an
Apple Development/Developer ID signature before showing it in the gallery;
the live desktop widget remains available in the app.

MIT license. No analytics, accounts, or external services.
TXT
codesign --verify --deep --strict "$stage/Duolet.app"
output="$PWD/dist/Duolet-$version-universal.dmg"
hdiutil create -volname Duolet -srcfolder "$stage" -format UDZO -ov "$output"
hdiutil verify "$output"
(cd dist && shasum -a 256 "Duolet-$version-universal.dmg" > SHA256SUMS)
echo "Packaged: $output"
