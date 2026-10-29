#!/bin/zsh
# SPDX-License-Identifier: MIT
set -euo pipefail
cd -- "${0:A:h}"
task_app="$PWD/dist/Scan Connector for Mac.app"
task_sdk="${MAC_NATIVE_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources" build
if [[ ! -f build/AppIcon.icns ]]; then
    xcrun swift Icon.swift "$PWD/build/AppIcon.iconset"
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx13.0 -sdk "$task_sdk" Sources/Protocol.swift Sources/Appearance.swift Sources/Receiver.swift Sources/Model.swift Sources/Views.swift Sources/Tests.swift Sources/main.swift -framework SwiftUI -framework AppKit -framework Foundation -framework Network -framework CryptoKit -framework Security -framework ServiceManagement -framework CoreGraphics -framework ImageIO -framework PDFKit -o "$task_app/Contents/MacOS/Scan Connector for Mac"
cp Info.plist "$task_app/Contents/Info.plist"
cp LICENSE "$task_app/Contents/Resources/LICENSE.txt"
cp NOTICE "$task_app/Contents/Resources/NOTICE.txt"
if [[ -f build/AppIcon.icns ]]; then cp build/AppIcon.icns "$task_app/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - --identifier local.mac-native-scan.app "$task_app"
echo "$task_app"
