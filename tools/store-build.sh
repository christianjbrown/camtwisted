#!/bin/sh
# Builds the Mac App Store and TestFlight version: sandboxed, without the
# virtual microphone's driver. Makes an archive, and with "upload" sends it
# to App Store Connect, which needs an Apple Distribution certificate and
# an app record there.
#
#   tools/store-build.sh          make build/CamTwisted.xcarchive
#   tools/store-build.sh upload   make it, then upload it
set -eu

cd "$(dirname "$0")/.."

ARCHIVE="build/CamTwisted.xcarchive"
EXPORT_OPTIONS="build/StoreExportOptions.plist"

xcodegen generate >/dev/null
xcodebuild -project CamTwisted.xcodeproj -scheme CamTwisted -configuration Store \
    -derivedDataPath build/StoreDerivedData -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates archive 2>&1 | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" | sort -u
[ -d "$ARCHIVE" ] || { echo "No archive was made"; exit 1; }
echo "Archived $ARCHIVE"

if [ "${1:-}" = "upload" ]; then
    cat > "$EXPORT_OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath build/StoreExport -allowProvisioningUpdates 2>&1 | grep -E "error:|EXPORT (SUCCEEDED|FAILED)|Upload" | sort -u
fi
