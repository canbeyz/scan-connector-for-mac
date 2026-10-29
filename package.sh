#!/bin/zsh
# SPDX-License-Identifier: MIT
set -euo pipefail
cd -- "${0:A:h}"
task_app="$PWD/dist/Scan Connector for Mac.app"
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")"
mkdir -p "$PWD/build"
task_stage="$(mktemp -d "$PWD/build/installer.XXXXXX")"
trap '/bin/rm -rf "$task_stage"' EXIT
ditto "$task_app" "$task_stage/Scan Connector for Mac.app"
if [[ ! -L "$task_stage/Applications" ]]; then ln -s /Applications "$task_stage/Applications"; fi
cp README.md "$task_stage/Read Me.txt"
cp LICENSE "$task_stage/LICENSE.txt"
cp NOTICE "$task_stage/NOTICE.txt"
codesign --verify --deep --strict "$task_stage/Scan Connector for Mac.app"
hdiutil create -volname "Scan Connector for Mac" -srcfolder "$task_stage" -format UDZO -ov "$PWD/dist/Scan-Connector-for-Mac-$task_version-Apple-Silicon.dmg"
ditto -c -k --sequesterRsrc --keepParent "$task_app" "$PWD/dist/Scan-Connector-for-Mac-$task_version-Apple-Silicon.zip"
echo "$PWD/dist/Scan-Connector-for-Mac-$task_version-Apple-Silicon.dmg"
