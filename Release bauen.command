#!/bin/bash
# Baut die Download-Dateien für eine neue Version:
#   Release/Abos.zip   – die App für Apple-Silicon- und Intel-Macs
#   Release/Abos.mcpb  – die Claude-Erweiterung
# Beide Dateien kommen danach als Anhang in ein GitHub-Release.

set -euo pipefail
cd "$(dirname "$0")"
BAU="$HOME/Library/Caches/Abos-Release"
AUS="Release"
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "Baue Abos für Apple Silicon und Intel …"
xcodebuild -project Abos.xcodeproj -scheme Abos -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BAU" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet
APP="$BAU/Build/Products/Release/Abos.app"
"$LS" -u "$APP" 2>/dev/null || true   # keine zweite Abos-App in der App-Liste

rm -rf "$AUS" && mkdir -p "$AUS"
ditto -c -k --keepParent "$APP" "$AUS/Abos.zip"

echo "Packe die Claude-Erweiterung …"
chmod +x claude-erweiterung/server/start.sh
(cd claude-erweiterung && zip -q -r -X "../$AUS/Abos.mcpb" manifest.json icon.png server)

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo
echo "Fertig – Version $VERSION:"
ls -lh "$AUS"
echo
lipo -archs "$APP/Contents/MacOS/Abos" | sed 's/^/Architekturen: /'
