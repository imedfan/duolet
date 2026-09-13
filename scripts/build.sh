#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Duolet.xcodeproj -scheme Duolet -configuration Release \
  -derivedDataPath build build "$@"
echo "Built: $PWD/build/Build/Products/Release/Duolet.app"
