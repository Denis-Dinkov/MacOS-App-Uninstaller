#!/bin/bash
# Builds AppSweeper.app next to this script (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="AppSweeper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    Sources/*.swift -o "$APP/Contents/MacOS/AppSweeper"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AppSweeper</string>
    <key>CFBundleDisplayName</key><string>AppSweeper</string>
    <key>CFBundleIdentifier</key><string>local.appsweeper</string>
    <key>CFBundleExecutable</key><string>AppSweeper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $(pwd)/$APP"

# `./build.sh install` also copies the app into /Applications.
if [[ "${1:-}" == "install" ]]; then
    pkill -x AppSweeper 2>/dev/null || true
    rm -rf "/Applications/$APP"
    ditto "$APP" "/Applications/$APP"
    echo "Installed /Applications/$APP"
fi
