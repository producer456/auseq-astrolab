#!/bin/bash
# AUSeq (AstroLab v2.1) — build, ad-hoc sign, publish to local Tailscale serve.
#
# No TestFlight, no quota, no local network needed — the Mac serves the IPA +
# manifest over its tailnet HTTPS endpoint. Open the install page in Safari on
# any iOS device on the tailnet and tap Install.
#
# Prereqs (one-time, already set up on this Mac):
#   - ~/Sites/ios-ota served by launchd job com.user.ios-ota-serve (127.0.0.1:8765)
#   - tailscale serve --bg http://127.0.0.1:8765
#   - target device UDID registered (handled by -allowProvisioningUpdates).

set -e
export PATH="/opt/homebrew/bin:$PATH"

REPO_DIR="/Users/admin/auseq-astrolab"
TEAM_ID="9TUXM4MBAV"
SCHEME="AUSeq"
PROJECT="AUSeq.xcodeproj"
BUNDLE_ID="com.producer456.auseq2"
APP_TITLE="AUSeq (AstroLab 2.1)"
ARCHIVE_PATH="/tmp/AUSeqAstroLab.xcarchive"
EXPORT_PATH="/tmp/AUSeqAstroLabAdHocExport"
API_KEY="FV5WR6A335"
API_ISSUER="063d077f-1dbb-4904-8ead-515fe477da68"
KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY}.p8"

SERVE_ROOT="$HOME/Sites/ios-ota"
SERVE_DIR="$SERVE_ROOT/$BUNDLE_ID"
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
TAILNET_HOST=$("$TS" status --json | jq -r '.Self.DNSName' | sed 's/\.$//')

cd "$REPO_DIR"
BUILD_NUMBER=$(date +%s)

echo ">> Regenerating Xcode project (xcodegen)..."
xcodegen generate

echo ">> Archiving (build $BUILD_NUMBER)..."
rm -rf "$ARCHIVE_PATH"
xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    -allowProvisioningUpdates \
    -authenticationKeyID "$API_KEY" \
    -authenticationKeyIssuerID "$API_ISSUER" \
    -authenticationKeyPath "$KEY_FILE" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -quiet

echo ">> Exporting ad-hoc IPA..."
cat > /tmp/AUSeqAstroLabAdHocExportOptions.plist <<'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>9TUXM4MBAV</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <false/>
    <key>compileBitcode</key>
    <false/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
PLISTEOF

rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist /tmp/AUSeqAstroLabAdHocExportOptions.plist \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyID "$API_KEY" \
    -authenticationKeyIssuerID "$API_ISSUER" \
    -authenticationKeyPath "$KEY_FILE"

IPA_SRC=$(ls "$EXPORT_PATH"/*.ipa | head -1)
[ -f "$IPA_SRC" ] || { echo "ERR: no IPA produced in $EXPORT_PATH"; exit 1; }

echo ">> Publishing to tailnet serve dir..."
mkdir -p "$SERVE_DIR"
cp "$IPA_SRC" "$SERVE_DIR/app.ipa"

IPA_URL="https://$TAILNET_HOST/$BUNDLE_ID/app.ipa"
MANIFEST_URL="https://$TAILNET_HOST/$BUNDLE_ID/manifest.plist"
INSTALL_LINK="itms-services://?action=download-manifest&url=$MANIFEST_URL"
INSTALL_PAGE="https://$TAILNET_HOST/$BUNDLE_ID/install.html"

cat > "$SERVE_DIR/manifest.plist" <<MANIFESTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>$IPA_URL</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>$BUNDLE_ID</string>
        <key>bundle-version</key><string>$BUILD_NUMBER</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>$APP_TITLE</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
MANIFESTEOF

cat > "$SERVE_DIR/meta.json" <<METAEOF
{
  "bundle_id": "$BUNDLE_ID",
  "title": "$APP_TITLE",
  "build": "$BUILD_NUMBER",
  "updated": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
METAEOF

cat > "$SERVE_DIR/install.html" <<HTMLEOF
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Install $APP_TITLE</title>
<style>
  body{font:16px/1.4 -apple-system,system-ui,sans-serif;display:grid;place-items:center;min-height:100vh;margin:0;background:#111;color:#eee}
  .card{padding:2rem;text-align:center;max-width:24rem}
  h1{margin:.25rem 0 .75rem;font-size:1.5rem}
  a.btn{display:inline-block;padding:1rem 2rem;background:#1aa39a;color:#fff;border-radius:.75rem;text-decoration:none;font-weight:600;font-size:1.125rem;margin-top:1rem}
  p.meta{color:#888;font-size:.875rem;margin:.25rem 0}
  small{display:block;margin-top:1.25rem;color:#666;font-size:.75rem}
</style>
<div class="card">
  <h1>$APP_TITLE</h1>
  <p class="meta">build $BUILD_NUMBER</p>
  <p class="meta">$(date '+%Y-%m-%d %H:%M')</p>
  <a class="btn" href="$INSTALL_LINK">Install on this device</a>
  <small>Open in Safari on the target iPhone/iPad, on the tailnet.</small>
</div>
HTMLEOF

[ -x /Users/admin/Sites/refresh-ota-hub.sh ] && /Users/admin/Sites/refresh-ota-hub.sh || true

echo ""
echo "=========================================================="
echo "Build $BUILD_NUMBER published."
echo ""
echo "Hub (all projects):  https://$TAILNET_HOST/"
echo "This build:          $INSTALL_PAGE"
echo "=========================================================="
