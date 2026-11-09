#!/bin/bash
# Installiert die Mac-App „Abos“ von GitHub – und auf Wunsch die Claude-Erweiterung.
#
#   curl -fsSL https://raw.githubusercontent.com/juliandressler-ship-it/abos/main/install.sh | bash
#
# Was dieses Skript tut, Schritt für Schritt:
#   1. lädt die neueste Abos.zip aus den GitHub-Releases in einen temporären Ordner
#   2. legt Abos.app nach /Applications (oder ~/Applications, falls dort keine Schreibrechte)
#   3. startet die App
#   4. fragt, ob Claude verbunden werden soll, und öffnet dann die Claude-Erweiterung
# Es braucht kein Passwort und verändert nichts außerhalb des Programme-Ordners.

set -euo pipefail

REPO="juliandressler-ship-it/abos"
DOWNLOAD="${ABOS_DOWNLOAD:-https://github.com/$REPO/releases/latest/download}"
TEST="${ABOS_TEST:-}"   # nur für Tests: nichts starten oder beenden
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ "$(uname)" != "Darwin" ]; then
  echo "Abos läuft nur auf dem Mac."; exit 1
fi
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
  echo "Abos braucht macOS 14 (Sonoma) oder neuer."; exit 1
fi

ZIEL="${ABOS_ZIEL:-/Applications}"
[ -w "$ZIEL" ] || { ZIEL="$HOME/Applications"; mkdir -p "$ZIEL"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "→ Lade Abos …"
curl -fL --progress-bar "$DOWNLOAD/Abos.zip" -o "$TMP/Abos.zip"
ditto -x -k "$TMP/Abos.zip" "$TMP"

# Eine laufende Abos-App schließen (deine Daten bleiben dabei erhalten)
if [ -z "$TEST" ]; then
  osascript -e 'tell application id "de.juliandressler.Abos" to quit' >/dev/null 2>&1 || true
  sleep 1
fi

echo "→ Installiere nach $ZIEL/Abos.app …"
rm -rf "$ZIEL/Abos.app"
ditto "$TMP/Abos.app" "$ZIEL/Abos.app"
xattr -dr com.apple.quarantine "$ZIEL/Abos.app" 2>/dev/null || true
if [ -z "$TEST" ]; then
  "$LS" -f "$ZIEL/Abos.app" 2>/dev/null || true
  open "$ZIEL/Abos.app"
fi
echo "✓ Abos ist installiert."

# Claude-Erweiterung (nur wenn die Claude-App da ist)
if [ -z "$TEST" ] && { [ -d "/Applications/Claude.app" ] || [ -d "$HOME/Applications/Claude.app" ]; }; then
  echo
  printf "Soll Claude auf deine Abos zugreifen können? [j/N] "
  ANTWORT=""
  read -r ANTWORT < /dev/tty || true
  case "$ANTWORT" in
    j|J|ja|Ja|JA|y|Y)
      ERWEITERUNG="$HOME/Downloads/Abos.mcpb"
      curl -fsSL "$DOWNLOAD/Abos.mcpb" -o "$ERWEITERUNG"
      open -a Claude "$ERWEITERUNG"
      echo "✓ In Claude auf „Installieren“ klicken – fertig."
      ;;
    *)
      echo "Kein Problem. Später geht das mit der Datei Abos.mcpb von der GitHub-Seite."
      ;;
  esac
fi
