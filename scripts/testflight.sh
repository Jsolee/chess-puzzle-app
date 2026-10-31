#!/bin/bash
# Archives in Release and uploads the build to App Store Connect (TestFlight).
# Usage: scripts/testflight.sh             archive and upload
#        scripts/testflight.sh --no-upload archive and export the .ipa to build/export
# Signs with the Xcode account (Settings > Accounts) of DEVELOPMENT_TEAM in project.yml.
# GPL: every shipped build needs its exact source public. Tag and push before uploading to external testers.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=$(awk '/DEVELOPMENT_TEAM:/ {print $2; exit}' project.yml)
BUILD="$(date +%Y%m%d).$(date +%H%M)"     # always grows; nothing to edit
DESTINATION=$([[ "${1:-}" == "--no-upload" ]] && echo export || echo upload)

[[ -f Scachs/Resources/nn-1a298aa575a0.nnue ]] || { echo "Missing the Stockfish net in Scachs/Resources (run scripts/setup.sh)"; exit 1; }
[[ "$(shasum -a 256 Scachs/Resources/nn-1a298aa575a0.nnue | cut -c1-12)" == "1a298aa575a0" ]] || { echo "Net hash mismatch"; exit 1; }

xcodegen generate
xcodebuild archive -project Scachs.xcodeproj -scheme Scachs -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Scachs.xcarchive \
  CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$DESTINATION</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath build/Scachs.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
echo "Build $BUILD ready ($DESTINATION)."
