#!/bin/bash
# Baut Abos aus diesem Ordner und ersetzt die App in ~/Applications.
# Deine Daten bleiben unberührt: sie liegen getrennt im App-Container von macOS.
# Gebaut wird in ~/Library/Caches, damit keine zweite Abos-App in der App-Liste auftaucht.

cd "$(dirname "$0")" || exit 1
BAU="$HOME/Library/Caches/Abos-Build"
ZIEL="$HOME/Applications/Abos.app"
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "Baue Abos …"
if ! xcodebuild -project Abos.xcodeproj -scheme Abos -configuration Release \
     -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BAU" build -quiet; then
  echo "Bauen fehlgeschlagen – die installierte App bleibt unverändert."
  read -n 1 -s -r -p "Taste drücken zum Schließen"; exit 1
fi
NEU="$BAU/Build/Products/Release/Abos.app"

echo "Installiere nach $ZIEL …"
osascript -e 'tell application id "de.juliandressler.Abos" to quit' 2>/dev/null
sleep 1
mkdir -p "$HOME/Applications"
rm -rf "$ZIEL"
cp -R "$NEU" "$ZIEL"
touch "$ZIEL"
"$LS" -u "$NEU" 2>/dev/null
"$LS" -f "$ZIEL"

if [ "$1" = "--im-hintergrund" ]; then open -g "$ZIEL"; else open "$ZIEL"; fi
echo "Fertig – Abos ist aktualisiert."
