import AppKit
import SwiftUI

// MARK: - Fokus wie in anderen Mac-Apps

/// Ein Klick neben ein Textfeld beendet die Eingabe; Esc und Return verlassen das Feld
@MainActor
enum Fokus {
    private static var beobachter: Any?
    private static var tastenBeobachter: Any?

    static func einrichten() {
        tastenEinrichten()
        guard beobachter == nil else { return }
        beobachter = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { ereignis in
            guard let fenster = ereignis.window, let inhalt = fenster.contentView,
                  fenster.firstResponder is NSText else { return ereignis }
            let punkt = inhalt.superview?.convert(ereignis.locationInWindow, from: nil) ?? ereignis.locationInWindow
            if !istEingabe(inhalt.hitTest(punkt)) {
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
                  !(umschalt && (richtung == .links || richtung == .rechts)),
                  let fenster = ereignis.window, !(fenster is NSPanel),
                  !String(describing: type(of: fenster)).contains("Popover") else { return ereignis }
            let fokus = fenster.firstResponder
            // Im Suchfeld: ↑ ↓ gehen durch die Treffer, ← → bleiben beim Text
            if let editor = fokus as? NSTextView, let feld = editor.delegate as? NSTextField {
                let istSuche = (feld.placeholderString ?? "").localizedCaseInsensitiveContains("suchen")
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
            Button("Abo löschen…") { if let abo { aktionen?.loeschen(abo) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(abo == nil)
        }
    }
}

/// Welche Abos die Übersicht auswertet
enum UebersichtStatus: String, CaseIterable, Identifiable {
    case aktiv, gekuendigt, alle
    var id: String { rawValue }

    var titel: String {
        switch self {
        case .aktiv: return "Aktive"
        case .gekuendigt: return "Gekündigte"
        case .alle: return "Alle"
        }
    }

    var menuTitel: String {
        switch self {
        case .aktiv: return "Nur aktive Abos"
        case .gekuendigt: return "Nur gekündigte Abos"
        case .alle: return "Aktive und gekündigte Abos"
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
