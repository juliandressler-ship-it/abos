import AppKit
import SwiftUI

// MARK: - Fokus wie in anderen Mac-Apps

/// Ein Klick neben ein Textfeld beendet die Eingabe; Esc und Return verlassen das Feld
@MainActor
enum Fokus {
    private static var beobachter: Any?
    private static var tastenBeobachter: Any?
    /// EXPERIMENT Kacheln: true, solange die Kachel-Übersicht zu sehen ist – dann gehören Pfeile, Return und ⌫ dem Raster
    static var kachelnAktiv = false

    static func einrichten() {
        tastenEinrichten()
        guard beobachter == nil else { return }
        beobachter = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { ereignis in
            guard let fenster = ereignis.window, let inhalt = fenster.contentView else { return ereignis }
            let punkt = inhalt.superview?.convert(ereignis.locationInWindow, from: nil) ?? ereignis.locationInWindow
            let ziel = inhalt.hitTest(punkt)

            // ⌥-Klick in einer Liste wirkt wie ⌘-Klick: einzelne Einträge dazu- oder abwählen
            if ereignis.modifierFlags.contains(.option), istInListe(ziel),
               let umgebaut = NSEvent.mouseEvent(
                   with: ereignis.type, location: ereignis.locationInWindow,
                   modifierFlags: ereignis.modifierFlags.subtracting(.option).union(.command),
                   timestamp: ereignis.timestamp, windowNumber: ereignis.windowNumber, context: nil,
                   eventNumber: ereignis.eventNumber, clickCount: ereignis.clickCount, pressure: ereignis.pressure) {
                return umgebaut
            }

            if ereignis.type == .leftMouseDown, fenster.firstResponder is NSText, !istEingabe(ziel) {
                fenster.makeFirstResponder(nil)
            }
            return ereignis
        }
    }

    /// Beim Start soll kein Textfeld (z. B. die Suche) den Tastaturfokus haben
    static func startFokusLoesen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            for fenster in NSApp.windows where fenster.isVisible && !(fenster is NSPanel) {
                if fenster.firstResponder is NSText { fenster.makeFirstResponder(nil) }
            }
        }
    }

    /// Beendet eine laufende Texteingabe; true, wenn es eine gab
    @discardableResult
    static func beenden() -> Bool {
        guard let fenster = NSApp.keyWindow, fenster.firstResponder is NSText else { return false }
        fenster.makeFirstResponder(nil)
        return true
    }

    /// Pfeiltasten im Hauptfenster: ↑ ↓ wechseln das Abo, ← → blättern in den Fristen.
    /// Beim Tippen, in Listen und in Menüs/Popovers bleiben die Tasten, wie sie sind.
    private static func tastenEinrichten() {
        guard tastenBeobachter == nil else { return }
        tastenBeobachter = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ereignis in
            // EXPERIMENT Kacheln: Return öffnet, ⌫ löscht, ⌘A wählt alle Kacheln
            if kachelnAktiv, let taste = kachelTaste(ereignis) {
                NotificationCenter.default.post(name: Taste.gedrueckt, object: taste)
                return nil
            }
            let richtung: Pfeil?
            switch ereignis.keyCode {
            case 126: richtung = .hoch
            case 125: richtung = .runter
            case 123: richtung = .links
            case 124: richtung = .rechts
            default: richtung = nil
            }
            let umschalt = ereignis.modifierFlags.contains(.shift)
            guard let richtung,
                  ereignis.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  !(umschalt && (richtung == .links || richtung == .rechts) && !kachelnAktiv), // EXPERIMENT Kacheln: && !kachelnAktiv
                  let fenster = ereignis.window, !(fenster is NSPanel),
                  !String(describing: type(of: fenster)).contains("Popover") else { return ereignis }
            let fokus = fenster.firstResponder
            // Im Suchfeld: ↑ ↓ gehen durch die Treffer, ← → bleiben beim Text
            if let editor = fokus as? NSTextView, let feld = editor.delegate as? NSTextField {
                let istSuche = (feld.placeholderString ?? "").localizedCaseInsensitiveContains(String(localized: "suchen"))
                guard istSuche, richtung == .hoch || richtung == .runter else { return ereignis }
                NotificationCenter.default.post(name: Pfeil.gedrueckt, object: richtung, userInfo: ["erweitern": umschalt])
                return nil
            }
            // In der Seitenleiste gehen ↑ ↓ wie gewohnt durch die Liste; ← → braucht sie nicht – die blättern die Fristen
            if (fokus is NSTableView || fokus is NSOutlineView) && (richtung == .links || richtung == .rechts) {
                NotificationCenter.default.post(name: Pfeil.gedrueckt, object: richtung)
                return nil
            }
            if fokus is NSText || fokus is NSTableView || fokus is NSOutlineView
                || fokus is NSDatePicker || fokus is NSSegmentedControl || fokus is NSPopUpButton
                || fokus is NSStepper || fokus is NSSlider {
                return ereignis
            }
            NotificationCenter.default.post(name: Pfeil.gedrueckt, object: richtung, userInfo: ["erweitern": umschalt])
            return nil
        }
    }

    enum Pfeil {
        case hoch, runter, links, rechts
        static let gedrueckt = Notification.Name("AbosPfeiltaste")
    }

    // EXPERIMENT Kacheln (Anfang)
    enum Taste {
        case oeffnen, loeschen, alle
        static let gedrueckt = Notification.Name("AbosKachelTaste")
    }

    /// Nur im Hauptfenster, ohne offenes Blatt und wenn kein Textfeld oder keine Liste den Fokus hat
    private static func kachelTaste(_ e: NSEvent) -> Taste? {
        guard let fenster = e.window, !(fenster is NSPanel), fenster.attachedSheet == nil, fenster.sheetParent == nil,
              !String(describing: type(of: fenster)).contains("Popover") else { return nil }
        let fokus = fenster.firstResponder
        if fokus is NSText || fokus is NSTableView || fokus is NSOutlineView || fokus is NSDatePicker { return nil }
        let mod = e.modifierFlags.intersection([.command, .option, .control, .shift])
        switch e.keyCode {
        case 36, 76: return mod.isEmpty ? .oeffnen : nil            // Return, Enter
        case 51, 117: return (mod.isEmpty || mod == .command) ? .loeschen : nil   // ⌫, ⌦, ⌘⌫
        case 0: return mod == .command ? .alle : nil                // ⌘A
        default: return nil
        }
    }
    // EXPERIMENT Kacheln (Ende)

    private static func istInListe(_ ansicht: NSView?) -> Bool {
        var v = ansicht
        while let x = v {
            if x is NSTableView || x is NSOutlineView { return true }
            v = x.superview
        }
        return false
    }

    private static func istEingabe(_ ansicht: NSView?) -> Bool {
        var v = ansicht
        while let x = v {
            if x is NSText || x is NSTextField || x is NSDatePicker { return true }
            v = x.superview
        }
        return false
    }
}

// MARK: - Menüs und Tastaturkürzel

/// Was das Hauptfenster den Menüs zur Verfügung stellt
struct FensterAktionen {
    var neu: () -> Void
    var suchen: () -> Void
    var loeschen: (Abo) -> Void
    /// EXPERIMENT Kacheln: mehrere markierte Abos auf einmal löschen
    var markiertAnzahl = 0
    var markiertLoeschen: () -> Void = {}
}

private struct AuswahlSchluessel: FocusedValueKey { typealias Value = Binding<Abo?> }
private struct AktionenSchluessel: FocusedValueKey { typealias Value = FensterAktionen }

extension FocusedValues {
    var aboAuswahl: Binding<Abo?>? {
        get { self[AuswahlSchluessel.self] }
        set { self[AuswahlSchluessel.self] = newValue }
    }
    var fensterAktionen: FensterAktionen? {
        get { self[AktionenSchluessel.self] }
        set { self[AktionenSchluessel.self] = newValue }
    }
}

struct AboBefehle: Commands {
    @FocusedValue(\.aboAuswahl) private var auswahl
    @FocusedValue(\.fensterAktionen) private var aktionen
    @AppStorage("zeitraumJahr") private var jahr = false
    @AppStorage("kostenZeitraum") private var zeitraumAktiv = false
    @AppStorage("uebersichtDiagramm") private var zeigtVerlauf = false
    @AppStorage("seitenleisteSichtbar") private var seitenleisteSichtbar = true   // EXPERIMENT Kacheln
    @AppStorage("uebersichtLayout") private var layout: UebersichtLayout = .diagramme   // EXPERIMENT Kacheln

    private var kosten: Binding<KostenAnsicht> {
        Binding(get: { zeitraumAktiv ? .zeitraum : (jahr ? .jahr : .monat) },
                set: { neu in
                    zeitraumAktiv = neu == .zeitraum
                    if neu != .zeitraum { jahr = neu == .jahr }
                })
    }
    @AppStorage("uebersichtStatus") private var status = UebersichtStatus.aktiv

    private var abo: Abo? { auswahl?.wrappedValue }

    var body: some Commands {
        // Ablage
        CommandGroup(replacing: .newItem) {
            Button("Neues Abo") { aktionen?.neu() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(aktionen == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("Backup exportieren…") { Sicherung.backupExportieren() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Backup importieren…") { Sicherung.backupImportieren() }
            Divider()
            Button("Als Tabelle (CSV) exportieren…") { Sicherung.csvExportieren() }
        }

        // Bearbeiten
        CommandGroup(after: .undoRedo) {
            // Zusätzlich zu ⇧⌘Z wie unter Windows gewohnt
            Button("Wiederholen") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("y", modifiers: .command)
        }
        CommandGroup(after: .textEditing) {
            Button("Suchen") { aktionen?.suchen() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(aktionen == nil)
        }

        // Darstellung
        CommandGroup(before: .toolbar) {
            // EXPERIMENT Kacheln (Anfang)
            Button(seitenleisteSichtbar ? "Seitenleiste ausblenden" : "Seitenleiste einblenden") {
                withAnimation(.easeOut(duration: 0.2)) { seitenleisteSichtbar.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Picker("Übersicht als", selection: $layout) {
                Text("Diagramm und Tabelle").tag(UebersichtLayout.diagramme)
                Text("Kacheln").tag(UebersichtLayout.kacheln)
            }
            .pickerStyle(.inline)
            Divider()
            // EXPERIMENT Kacheln (Ende)
            Picker("Übersicht zeigt", selection: $status) {
                ForEach(UebersichtStatus.allCases) { Text($0.menuTitel).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Diagramm", selection: $zeigtVerlauf) {
                Text("Aufteilung nach Kategorie").tag(false)
                Text("Kostenverlauf").tag(true)
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Kosten", selection: kosten) {
                Text("Kosten pro Monat").tag(KostenAnsicht.monat)
                Text("Kosten pro Jahr").tag(KostenAnsicht.jahr)
                Text("Zahlungen im Zeitraum").tag(KostenAnsicht.zeitraum)
            }
            .pickerStyle(.inline)
            Divider()
            Button("Zur Übersicht") { auswahl?.wrappedValue = nil }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(abo == nil)
            Divider()
        }

        // Abo
        CommandMenu("Abo") {
            if let abo, !abo.istAktiv {
                Button("Wieder aktivieren") { abo.reaktivieren() }
                    .keyboardShortcut("k", modifiers: .command)
            } else {
                Button("Als gekündigt markieren") { abo?.kuendigen() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(abo == nil)
            }
            Button("Kündigungsseite öffnen") {
                if let url = abo.flatMap({ Format.url($0.kuendigungsLink) }) { NSWorkspace.shared.open(url) }
            }
            .disabled(abo.flatMap { Format.url($0.kuendigungsLink) } == nil)
            Button("Website öffnen") {
                if let url = abo.flatMap({ Format.url($0.websiteLink) }) { NSWorkspace.shared.open(url) }
            }
            .disabled(abo.flatMap { Format.url($0.websiteLink) } == nil)
            Divider()
            // EXPERIMENT Kacheln: ohne geöffnetes Abo löscht ⌘⌫ alle markierten
            if abo == nil, let n = aktionen?.markiertAnzahl, n > 1 {
                Button("\(n) Abos löschen…") { aktionen?.markiertLoeschen() }
                    .keyboardShortcut(.delete, modifiers: .command)
            } else if abo == nil, aktionen?.markiertAnzahl == 1 {
                Button("Abo löschen…") { aktionen?.markiertLoeschen() }
                    .keyboardShortcut(.delete, modifiers: .command)
            } else {
            Button("Abo löschen…") { if let abo { aktionen?.loeschen(abo) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(abo == nil)
            }
        }
    }
}

/// Welche Abos die Übersicht auswertet
enum UebersichtStatus: String, CaseIterable, Identifiable {
    case aktiv, gekuendigt, alle
    var id: String { rawValue }

    var titel: String {
        switch self {
        case .aktiv: return String(localized: "Aktive")
        case .gekuendigt: return String(localized: "Gekündigte")
        case .alle: return String(localized: "Alle")
        }
    }

    var menuTitel: String {
        switch self {
        case .aktiv: return String(localized: "Nur aktive Abos")
        case .gekuendigt: return String(localized: "Nur gekündigte Abos")
        case .alle: return String(localized: "Aktive und gekündigte Abos")
        }
    }

    func passt(_ abo: Abo) -> Bool {
        switch self {
        case .aktiv: return abo.istAktiv
        case .gekuendigt: return !abo.istAktiv
        case .alle: return true
        }
    }
}
