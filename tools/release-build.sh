#!/bin/sh
# Builds the version people download: signed with a Developer ID, with the
# virtual microphone's driver inside. With "notarise" it is also sent to
# Apple to be notarised, and zipped ready to attach to a release.
#
#   tools/release-build.sh            make build/ReleaseExport/CamTwisted.app
#   tools/release-build.sh notarise   make it, notarise it, zip it
set -eu

cd "$(dirname "$0")/.."

APP_NAME="CamTwisted.app"
ARCHIVE="build/CamTwisted-release.xcarchive"
EXPORT_OPTIONS="build/ReleaseExportOptions.plist"
EXPORT_DIR="build/ReleaseExport"
NOTARISED_DIR="build/ReleaseNotarised"
# How long to wait for Apple, and how often to ask.
NOTARY_TRIES=90
NOTARY_PAUSE_SECONDS=20

# Writes the export options for one destination: "export" keeps the app
# here, "upload" sends it to be notarised.
write_options() {
    cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>destination</key>
	<string>$1</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST
}

export_archive() {
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$1" -allowProvisioningUpdates 2>&1 | grep -E "error:|EXPORT (SUCCEEDED|FAILED)" | sort -u
}

xcodegen generate >/dev/null
xcodebuild -project CamTwisted.xcodeproj -scheme CamTwisted -configuration Release \
    -derivedDataPath build/ReleaseDerivedData -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates archive 2>&1 | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" | sort -u
[ -d "$ARCHIVE" ] || { echo "No archive was made"; exit 1; }

if [ "${1:-}" != "notarise" ]; then
    rm -rf "$EXPORT_DIR"
    write_options export
    export_archive "$EXPORT_DIR"
    [ -d "$EXPORT_DIR/$APP_NAME" ] || { echo "No app was exported"; exit 1; }
    echo "Exported $EXPORT_DIR/$APP_NAME"
    exit 0
fi

write_options upload
export_archive "build/ReleaseUpload"
echo "Sent to be notarised, waiting for Apple"

tries=0
until [ -d "$NOTARISED_DIR/$APP_NAME" ]; do
    tries=$((tries + 1))
    [ "$tries" -le "$NOTARY_TRIES" ] || { echo "Apple has not notarised it yet. Run this again later."; exit 1; }
    rm -rf "$NOTARISED_DIR"
    xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$NOTARISED_DIR" >/dev/null 2>&1 \
        || sleep "$NOTARY_PAUSE_SECONDS"
done

xcrun stapler validate "$NOTARISED_DIR/$APP_NAME"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$NOTARISED_DIR/$APP_NAME/Contents/Info.plist")
ZIP="build/CamTwisted-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$NOTARISED_DIR/$APP_NAME" "$ZIP"
echo "Made $ZIP"
