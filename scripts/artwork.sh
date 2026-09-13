#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
build/Build/Products/Release/Duolet.app/Contents/MacOS/Duolet --render-previews build/artwork
mkdir -p Resources/AppIcon.iconset docs/images
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" build/artwork/app-icon.png --out "Resources/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" build/artwork/app-icon.png --out "Resources/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
cp build/artwork/indicator-states.png docs/images/indicator-states.png
echo 'Artwork updated. Rebuild to include the regenerated application icon.'
