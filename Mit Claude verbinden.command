#!/bin/bash
# Trägt die Abos-App als lokalen MCP-Server in die Claude-Desktop-App ein.
# Einfacher ist meist die Claude-Erweiterung Abos.mcpb (Doppelklick); dieses Skript ist die Alternative ohne Erweiterung.
# Claude schreibt seine Konfigurationsdatei aus dem Speicher zurück, solange es läuft.
# Deshalb wartet dieses Skript, bis Claude beendet ist, trägt dann ein und startet Claude neu.

KONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
# Installierte App suchen: /Applications, sonst ~/Applications
APP="/Applications/Abos.app/Contents/MacOS/Abos"
[ -x "$APP" ] || APP="$HOME/Applications/Abos.app/Contents/MacOS/Abos"

# Läuft die Claude-App? (Hauptprozess, nicht die Helfer)
claude_laeuft() {
  ps -axo comm= | grep -qx "/Applications/Claude.app/Contents/MacOS/Claude"
}

if [ ! -x "$APP" ]; then
  echo "Abos.app nicht gefunden unter: $APP"
  read -n 1 -s -r -p "Taste drücken zum Schließen"; exit 1
fi

if claude_laeuft; then
  echo "Bitte jetzt die Claude-App mit ⌘Q beenden – ich warte …"
  while claude_laeuft; do sleep 1; done
fi
sleep 2

mkdir -p "$(dirname "$KONFIG")"
[ -f "$KONFIG" ] && cp -p "$KONFIG" "$KONFIG.backup-$(date +%Y%m%d-%H%M%S)"

/usr/bin/python3 - "$KONFIG" "$APP" <<'PY'
import json, os, sys
pfad, app = sys.argv[1], sys.argv[2]
daten = json.load(open(pfad)) if os.path.exists(pfad) else {}
daten.setdefault("mcpServers", {})["abos"] = {"command": app, "args": ["--mcp"]}
with open(pfad, "w") as f:
    json.dump(daten, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("Eingetragen: abos →", app, "--mcp")
PY

echo "Starte Claude …"
open -a Claude
echo "Fertig. Dieses Fenster kannst du schließen."
