#!/bin/zsh
# 编译「网页快开管理.app」并安装到 ~/Applications/网页快开/
set -e
SRC="${0:A:h}"
OUT="$HOME/Applications/网页快开"
APP="$OUT/网页快开管理.app"
BUILD=$(mktemp -d)
mkdir -p "$OUT" "$BUILD/网页快开管理.app/Contents/MacOS" "$BUILD/网页快开管理.app/Contents/Resources"
B="$BUILD/网页快开管理.app"

swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 \
  "$SRC/main.swift" -o "$B/Contents/MacOS/WebLinkManager"

cat > "$B/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>WebLinkManager</string>
  <key>CFBundleIdentifier</key><string>local.weblink.manager</string>
  <key>CFBundleName</key><string>网页快开管理</string>
  <key>CFBundleDisplayName</key><string>网页快开管理</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
EOF

# 应用自身图标
"$B/Contents/MacOS/WebLinkManager" --self-icon "$BUILD/icon.png"
mkdir "$BUILD/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$B/Contents/Resources/AppIcon.icns"

codesign --force --deep -s - "$B"
rm -rf "$APP"
mv "$B" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
mdimport "$APP"
rm -rf "$BUILD"
echo "已安装: $APP"
