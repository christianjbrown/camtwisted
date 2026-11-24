#!/bin/sh
# Builds a signed copy and puts it in /Applications, where macOS requires an
# app to live before it may install a camera extension.
set -eu

cd "$(dirname "$0")/.."

INSTALL_DIR="/Applications"
APP_NAME="CamTwisted.app"
PRODUCT="build/DerivedData/Build/Products/Debug/$APP_NAME"

xcodegen generate >/dev/null
xcodebuild -project CamTwisted.xcodeproj -scheme CamTwisted -configuration Debug \
    -derivedDataPath build/DerivedData -allowProvisioningUpdates build 2>&1 \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
pkill -x "${APP_NAME%.app}" 2>/dev/null || true
rm -rf "${INSTALL_DIR:?}/$APP_NAME"
ditto "$PRODUCT" "$INSTALL_DIR/$APP_NAME"
# Replacing the app in place can leave the Dock showing a blank icon:
# registering it afresh makes the system read the icon again.
touch "$INSTALL_DIR/$APP_NAME"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALL_DIR/$APP_NAME" || true
echo "Installed $INSTALL_DIR/$APP_NAME"
