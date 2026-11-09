import AppKit
import SwiftUI

// MARK: - Sortierung

enum SortFeld: String, CaseIterable, Identifiable {
    case name, kategorie, preis, jahr, frist
    var id: String { rawValue }
    var titel: String {
        switch self {
        case .name: return "Name"
        case .kategorie: return "Kategorie"
        case .preis: return "Preis"
        case .jahr: return "Preis pro Jahr"
        case .frist: return "Frist"
        }
    }

    /// Die Felder der Seitenleiste; Kategorie und Jahr gibt es nur als Tabellenspalte
    static let seitenleiste: [SortFeld] = [.name, .preis, .frist]
}

/// Feld plus Richtung. `umgekehrt == false` ist die naheliegende Richtung:
/// Name A–Z, Preis höchster zuerst, Frist nächste zuerst.
struct Sortierung {
    var feld: SortFeld
    var umgekehrt: Bool
    /// Eigener Wert für die Spalte „pro Jahr“ (z. B. Zahlungen im gewählten Zeitraum)
    var wertJahr: ((Abo) -> Double?)? = nil

    var richtung: String {
        switch feld {
        case .name, .kategorie: return umgekehrt ? "Z–A" : "A–Z"
        case .preis, .jahr: return umgekehrt ? "Niedrigster" : "Höchster"
        case .frist: return umgekehrt ? "Späteste" : "Nächste"
        }
    }

    /// z. B. „Preis, höchster zuerst“
    var beschreibung: String {
        switch feld {
        case .name: return "Name \(richtung)"
        case .kategorie: return "Kategorie \(richtung)"
        case .preis, .jahr: return "Preis, \(richtung.lowercased()) zuerst"
        case .frist: return "Frist, \(richtung.lowercased()) zuerst"
        }
    }

    /// Abos ohne Betrag bzw. ohne Frist stehen immer am Ende
    func sortiert(_ abos: [Abo]) -> [Abo] {
        let schluessel = abos.map { abo -> (abo: Abo, preis: Double?, frist: Date?) in
            (abo, feld == .jahr ? (wertJahr?(abo) ?? abo.proMonat) : abo.proMonat,
             feld == .frist ? abo.spaetestensKuendigenBis : nil)
        }
        let sortiert = schluessel.sorted { l, r in
            switch feld {
            case .name:
                let ergebnis = l.abo.name.localizedStandardCompare(r.abo.name)
                if ergebnis != .orderedSame { return umgekehrt ? ergebnis == .orderedDescending : ergebnis == .orderedAscending }
            case .kategorie:
                // „Ohne Kategorie“ immer am Ende, innerhalb einer Kategorie nach Name
                switch (l.abo.kategorie.isEmpty, r.abo.kategorie.isEmpty) {
                case (false, true): return true
                case (true, false): return false
                default: break
                }
                let ergebnis = l.abo.kategorie.localizedStandardCompare(r.abo.kategorie)
                if ergebnis != .orderedSame { return umgekehrt ? ergebnis == .orderedDescending : ergebnis == .orderedAscending }
            case .preis, .jahr:
                switch (l.preis, r.preis) {
                case let (a?, b?) where a != b: return umgekehrt ? a < b : a > b
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            case .frist:
                switch (l.frist, r.frist) {
                case let (a?, b?) where a != b: return umgekehrt ? a > b : a < b
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            }
            return Auswertung.nachName(l.abo, r.abo)
        }
        return sortiert.map(\.abo)
    }
}

/// Segmente für das Feld und daneben ein Knopf, der die Richtung umdreht
struct SortierLeiste: View {
    @Binding var feld: SortFeld
    @Binding var umgekehrt: Bool

    var body: some View {
        HStack(spacing: 8) {
            Picker("Sortieren nach", selection: $feld) {
                ForEach(SortFeld.seitenleiste) { Text($0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: feld) { _, _ in umgekehrt = false }

            Button {
                umgekehrt.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(Sortierung(feld: feld, umgekehrt: umgekehrt).richtung)
                        .lineLimit(1)
                }
                .frame(minWidth: 84)
            }
            .help("Reihenfolge umdrehen")
        }
    }
}

/// Spaltenkopf zum Sortieren: Klick wählt die Spalte, ein zweiter Klick dreht die Richtung um
struct SortSpalte: View {
    let titel: String
    let feld: SortFeld
    @Binding var aktuell: SortFeld
    @Binding var umgekehrt: Bool
    var ausrichtung: Alignment = .leading

    private var aktiv: Bool { aktuell == feld }

    var body: some View {
        Button {
            if aktiv { umgekehrt.toggle() } else { aktuell = feld; umgekehrt = false }
        } label: {
            HStack(spacing: 4) {
                if ausrichtung == .trailing { Spacer(minLength: 0) }
                Text(titel)
                if aktiv {
                    Image(systemName: pfeilNachUnten ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .medium))
                }
                if ausrichtung == .leading { Spacer(minLength: 0) }
            }
            .foregroundStyle(aktiv ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Nach \(titel) sortieren")
    }

    /// Pfeil zeigt die Leserichtung der Werte: absteigend = nach unten
    private var pfeilNachUnten: Bool {
        switch feld {
        case .name, .kategorie, .frist: return umgekehrt
        case .preis, .jahr: return !umgekehrt
        }
    }
}

// MARK: - Immer sichtbarer Scrollbalken

/// Schaltet die umgebende NSScrollView auf einen dauerhaft sichtbaren Scrollbalken mit Spur
struct SichtbarerScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Fuehler() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Fuehler)?.einstellen()
    }

    final class Fuehler: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            einstellen()
        }

        func einstellen() {
            DispatchQueue.main.async { [weak self] in
                guard let scroll = self?.enclosingScrollView else { return }
                scroll.scrollerStyle = .legacy
                scroll.hasVerticalScroller = true
                scroll.autohidesScrollers = false
            }
        }
    }
}
