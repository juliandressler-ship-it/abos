# Abos

Eine kleine Mac-App, mit der du deine Abos und Versicherungen im Blick behältst: was sie pro Monat und Jahr kosten, bis wann du spätestens kündigen musst – und eine Erinnerung, bevor die Frist abläuft.

Alles bleibt auf deinem Mac. Kein Konto, keine Cloud, kein Netzwerk.

## Was Abos kann

- **Übersicht:** Gesamtkosten pro Monat, pro Jahr oder für einen bestimmten Zeitraum, aufgeteilt nach Kategorie als Kreisdiagramm
- **Kündigungsfristen:** „Kündigen bis“ wird aus Verlängerungstag und Frist berechnet – oder du trägst ein festes Datum ein
- **Erinnerungen:** macOS-Mitteilungen vor der Frist, mit den Knöpfen „Erledigt“, „Gekündigt“ und „In 1 Woche erneut“
- **Kündigungsverlauf:** wann gekündigt, wann wieder aktiviert
- **Kündigen per E-Mail:** öffnet eine fertig formulierte Kündigung in deinem Mailprogramm
- **Auswertung:** aktive, gekündigte oder alle Abos – und was Kündigungen gespart haben
- **Backup:** Export und Import als Datei, Export als Tabelle (CSV) für Excel oder Numbers
- **Claude:** Claude kann deine Abos lesen, neue anlegen und Sparpotenziale finden (siehe unten)

Die App ist auf Deutsch und läuft ab macOS 14 (Sonoma) auf Apple-Silicon- und Intel-Macs.

## Installieren

### Mit einer Zeile im Terminal (empfohlen)

Öffne das Programm **Terminal** und füge diese Zeile ein:

```bash
curl -fsSL https://raw.githubusercontent.com/juliandressler-ship-it/abos/main/install.sh | bash
```

Das Skript lädt die App, legt sie in den Programme-Ordner, startet sie und fragt, ob Claude verbunden werden soll. Was es genau tut, steht oben in [install.sh](install.sh).

### Von Hand

1. Unter [Releases](https://github.com/juliandressler-ship-it/abos/releases/latest) die Datei **Abos.zip** laden und entpacken.
2. **Abos** in den Ordner **Programme** ziehen und öffnen.
3. macOS meldet beim ersten Öffnen, dass die App nicht geprüft werden kann. Das liegt daran, dass sie nicht über ein kostenpflichtiges Apple-Entwicklerkonto signiert ist. Öffne dann **Systemeinstellungen → Datenschutz & Sicherheit**, scrolle nach unten und klicke bei „Abos“ auf **Trotzdem öffnen**.

Danach startet die App ganz normal.

## Mit Claude verbinden

Voraussetzung ist die [Claude-App für den Mac](https://claude.ai/download).

1. Unter [Releases](https://github.com/juliandressler-ship-it/abos/releases/latest) die Datei **Abos.mcpb** laden.
2. Doppelklicken – Claude öffnet sich – auf **Installieren** klicken.

Danach kannst du Claude zum Beispiel fragen:

> Welche Abos habe ich, und wo kann ich am meisten sparen?

> Leg eine Hausratversicherung an: 9,50 € im Monat, Kündigungsfrist 3 Monate.

Claude greift dabei über einen lokalen Server auf die App zu. Löschen kann Claude bewusst nicht – das geht nur in der App. Was du Claude im Chat fragst, wird wie jede Chatnachricht an Claude geschickt; gespeichert bleiben die Abos nur auf deinem Mac.

## Deine Daten

- Die Abos liegen in der App-eigenen Datenbank auf deinem Mac und werden von Time Machine mitgesichert.
- Über **Ablage → Backup exportieren** (⇧⌘E) bekommst du eine Datei, die du z. B. in iCloud Drive ablegen und mit **Backup importieren** wiederherstellen kannst.
- Die App ist in der macOS-Sandbox und hat keinen Netzwerkzugriff.

## Selbst bauen

Mit Xcode 16 oder neuer:

```bash
git clone https://github.com/juliandressler-ship-it/abos.git
cd abos
open Abos.xcodeproj
```

- `App aktualisieren.command` baut die App und installiert sie in `~/Applications`.
- `Release bauen.command` erzeugt `Release/Abos.zip` und `Release/Abos.mcpb` für ein neues GitHub-Release.

## Lizenz

[MIT](LICENSE)
