#!/bin/bash
# Builds ClaudeTokenBar and assembles an ad-hoc-signed app bundle at dist/ClaudeTokenBar.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/ClaudeTokenBar.app
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeTokenBar "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>ClaudeTokenBar</string>
	<key>CFBundleIdentifier</key><string>io.dreamus.claudetokenbar</string>
	<key>CFBundleName</key><string>ClaudeTokenBar</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Packaged: $APP  (run: open $APP)"
