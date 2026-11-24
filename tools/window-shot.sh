#!/bin/sh
# Opens the app on a setup file, with any launch options, and saves a
# picture of each of its windows. The setup is handed over as OpenSetup, so
# it is open before the other options are applied to it. Nothing is
# clicked: the launch options (see the README) put the window in the state
# wanted.
#
#   tools/window-shot.sh <name> <setup.camtwisted> <folder for pictures> [launch options...]
#   tools/window-shot.sh outputs "docs/demo/Demo show.camtwisted" /tmp/shots -OpenOnPane Output
set -eu

NAME="$1"; SETUP="$2"; OUT="$3"; shift 3
# The app's name and where install.sh puts it.
APP_NAME="CamTwisted"
INSTALL_DIR="/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"
# Long enough for the window to open and the picture to settle.
: "${SETTLE_SECONDS:=7}"
# Long enough for the old copy of the app to finish quitting.
: "${QUIT_SECONDS:=1}"
# What a window with no title (a sheet) is called in the picture's file name.
UNTITLED_WINDOW_NAME="sheet"
LISTER="$(mktemp -t camtwisted-windows).swift"
trap 'rm -f "$LISTER"' EXIT

cat > "$LISTER" <<'SWIFT'
import CoreGraphics
import Foundation
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
// The app's name and the name for an untitled window come in as arguments.
let appName = CommandLine.arguments[1]
let untitledName = CommandLine.arguments[2]
for info in list where (info[kCGWindowOwnerName as String] as? String) == appName {
    let number = info[kCGWindowNumber as String] as? Int ?? 0
    let title = (info[kCGWindowName as String] as? String ?? "").filter { $0.isLetter || $0.isNumber }
    print(number, title.isEmpty ? untitledName : title)
}
SWIFT

mkdir -p "$OUT"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep "$QUIT_SECONDS"
open -a "$APP" --args -OpenSetup "$(cd "$(dirname "$SETUP")" && pwd)/$(basename "$SETUP")" "$@"
sleep "$SETTLE_SECONDS"
# Brought to the front, so the windows are drawn as active ones are.
open -a "$APP"
sleep "$QUIT_SECONDS"
swift "$LISTER" "$APP_NAME" "$UNTITLED_WINDOW_NAME" | while read -r NUMBER TITLE; do
    screencapture -x -o -l "$NUMBER" "$OUT/$NAME-$TITLE.png"
    echo "$OUT/$NAME-$TITLE.png"
done
