#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/release .build/module-cache
swiftc -O -module-cache-path .build/module-cache -target arm64-apple-macosx13.0 Sources/*.swift -o .build/release/HarborFTP
mkdir -p build/HarborFTP.app/Contents/MacOS build/HarborFTP.app/Contents/Resources
cp Resources/AppIcon.icns build/HarborFTP.app/Contents/Resources/
cp .build/release/HarborFTP build/HarborFTP.app/Contents/MacOS/
cat > build/HarborFTP.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HarborFTP</string>
<key>CFBundleIdentifier</key><string>local.harbor.ftp</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>HarborFTP</string>
<key>CFBundleShortVersionString</key><string>0.5.5</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - build/HarborFTP.app
