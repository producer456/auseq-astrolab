#!/usr/bin/env bash
# Compile-check against the iOS Simulator (no code signing required).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/generate.sh

xcodebuild \
  -project AUSeq.xcodeproj \
  -scheme AUSeq \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build "$@"
