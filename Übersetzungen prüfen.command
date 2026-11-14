#!/bin/bash
# Sammelt alle Oberflächentexte in Abos/Localizable.xcstrings und meldet,
# welche noch keine englische Übersetzung haben. Danach im Katalog ergänzen
# (Xcode: Localizable.xcstrings öffnen) und erneut bauen.

set -euo pipefail
cd "$(dirname "$0")"
BAU="$HOME/Library/Caches/Abos-Build"

echo "Baue, um die Texte einzusammeln …"
xcodebuild -project Abos.xcodeproj -scheme Abos -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BAU" build -quiet

# Texte des Claude-Servers bleiben deutsch und kommen nicht in den Katalog
xcrun xcstringstool sync Abos/Localizable.xcstrings --stringsdata \
  $(find "$BAU/Build/Intermediates.noindex" -name "*.stringsdata" \
    ! -name "MCPServer*" ! -name "Generated*" ! -name "Extracted*")

/usr/bin/python3 - <<'PY'
import json
p = 'Abos/Localizable.xcstrings'
d = json.load(open(p))
fehlt = []
for k, v in d['strings'].items():
    loc = v.setdefault('localizations', {})
    # Deutsch ausdrücklich eintragen, damit es einen eigenen de.lproj-Ordner gibt
    loc.setdefault('de', {'stringUnit': {'state': 'translated', 'value': k}})
    loc['de']['stringUnit']['state'] = 'translated'
    if 'en' not in loc:
        fehlt.append(k)
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print(f"{len(d['strings'])} Texte im Katalog.")
if fehlt:
    print(f"Ohne englische Übersetzung ({len(fehlt)}):")
    for k in fehlt:
        print("  •", k)
else:
    print("Alle Texte sind übersetzt.")
PY
