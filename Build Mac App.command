#!/bin/zsh
cd "${0:A:h}"
if ! command -v swiftc >/dev/null; then
  echo 'Building the Mac app needs the Xcode Command Line Tools. Install them with: xcode-select --install'
  read; exit 1
fi
APP="Shadow Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos13.0" mac/*.swift -o "$APP/Contents/MacOS/Shadow Studio" || { echo 'Build failed.'; read; exit 1; }
cp mac/cmudict.dict mac/CMUDICT-LICENSE.txt mac/voice-workshop-head.jpg mac/VOICE-WORKSHOP-LICENSE.txt "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Shadow Studio</string>
<key>CFBundleDisplayName</key><string>Shadow Studio</string>
<key>CFBundleIdentifier</key><string>local.shadowstudio.app</string>
<key>CFBundleExecutable</key><string>Shadow Studio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Shadow Studio records your voice so you can practise phrases. Recordings stay on this Mac.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :ShadowProjectDir string $PWD" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo 'Built "Shadow Studio.app". Drag it to Applications or the Dock; it keeps using this folder for its data.'
