#!/bin/zsh
# Builds LinkRouter.app and installs it to ~/Applications. No Xcode required.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LinkRouter"

APP="build/LinkRouter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/LinkRouter"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: render every size macOS wants from the 1024px master, then pack into .icns.
if [[ -f Resources/AppIcon-1024.png ]]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET" "$APP/Contents/Resources"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature: enough for an app that only runs on this machine.
codesign --force --sign - "$APP"

DEST="$HOME/Applications/LinkRouter.app"
mkdir -p "$HOME/Applications"
pkill -x LinkRouter 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"

# Tell LaunchServices about the (new) app so it shows up as a browser option immediately.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
echo "Installed $DEST"
