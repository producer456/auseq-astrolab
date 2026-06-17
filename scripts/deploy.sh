#!/usr/bin/env bash
# Build, sign, and install AUSeq to the iPad ("Paddy").
# Requires an Apple ID logged into Xcode (Settings -> Accounts). See CLAUDE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

# Paddy = iPad Pro 11" (M5). Override via env if the device changes.
DEVICE_ID="${DEVICE_ID:-00008142-0005095E0C23401C}"          # xcodebuild destination id
DEVICECTL_ID="${DEVICECTL_ID:-FB14BC29-FBBC-591F-A000-F988ECC42ABB}"  # devicectl identifier
TEAM="${TEAM:-9TUXM4MBAV}"

scripts/generate.sh

xcodebuild \
  -project AUSeq.xcodeproj \
  -scheme AUSeq \
  -configuration Release \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  build

xcrun devicectl device install app \
  --device "$DEVICECTL_ID" \
  build/Build/Products/Release-iphoneos/AUSeq.app
