// EXPERIMENT Kacheln – diese ganze Datei gehört zum Experiment und kann komplett gelöscht werden.
// Zurück zum alten Stand: `git switch main` und neu installieren (siehe Ende der Datei).

import AppKit
import SwiftUI

/// Wie die Übersicht aufgebaut ist: Diagramm mit Tabelle oder ein Raster aus Kacheln
enum UebersichtLayout: String, CaseIterable, Identifiable {
    case diagramme, kacheln
    var id: String { rawValue }
}

/// Label mit oder ohne Titel – für Knöpfe, die bei wenig Platz nur ihr Symbol zeigen
struct EinfachesLabel: LabelStyle {
    let nurSymbol: Bool
    func makeBody(configuration: Configuration) -> some View {
        if nurSymbol {
            configuration.icon
        } else {
            HStack(spacing: 4) { configuration.icon; configuration.title }
        }
    }
}

extension View {
    /// Beschriftung eines Pickers nur bei Bedarf ausblenden
    @ViewBuilder
    func labelsHidden(_ ausblenden: Bool) -> some View {
        if ausblenden { labelsHidden() } else { self }
    }
}

// MARK: - Raster

/// Alle Abos der Übersicht als Kacheln – Bedienung wie im Finder:
/// Klick wählt aus, Doppelklick oder Return öffnet, ⇧/⌘/⌥ wählen mehrere,
/// Pfeiltasten bewegen die Auswahl, ⌫ löscht nach Rückfrage.
struct KachelRaster: View {
    let abos: [Abo]
    @Binding var markiert: Set<Abo>
    @Binding var auswahl: Abo?
    let dringlichkeit: Dringlichkeit
    /// Betrag in der gewählten Ansicht (pro Monat, Jahr, Zeitraum …)
    let wert: (Abo) -> Double?
    /// „pro Monat“, „pro Jahr“, „im November 2026“ …
    let einheit: String
    let farbe: (Abo) -> Color?
    var loeschen: (Abo) -> Void

    /// Ausgangspunkt und bewegliches Ende für ⇧-Bereiche
    @State private var anker: Int?
    @State private var ende: Int?
    @State private var breite: CGFloat = 800

    private let mindestBreite: CGFloat = 200
    private let abstand: CGFloat = 12

    /// Spaltenzahl aus der Breite – nötig, damit ↑ ↓ genau eine Zeile springen
    private var spalten: Int { max(1, Int((breite + abstand) / (mindestBreite + abstand))) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: abstand), count: spalten),
                          spacing: abstand) {
                    ForEach(Array(abos.enumerated()), id: \.element.persistentModelID) { i, abo in
                        AboKachel(abo: abo, markiert: markiert.contains(abo), dringlichkeit: dringlichkeit,
                                  wert: wert(abo), einheit: einheit, farbe: farbe(abo))
                            .id(abo.persistentModelID)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { klick(abo, index: i) }
                            .contextMenu {
                                AboMenue(abo: abo, oeffnen: { auswahl = abo }, loeschen: { loeschen(abo) })
                            }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                // Platz für die Auswahl-Leiste unten
                .padding(.bottom, 96)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 48 } action: { breite = $0 }
            }
            .onReceive(NotificationCenter.default.publisher(for: Fokus.Pfeil.gedrueckt)) { n in
                pfeil(n, proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: Fokus.Taste.gedrueckt)) { n in
                guard Fokus.kachelnAktiv, (n.object as? Fokus.Taste) == .alle else { return }
                markiert = Set(abos)
                anker = 0
                ende = abos.count - 1
            }
        }
    }

    /// Klick wählt aus, Doppelklick öffnet. ⌘ oder ⌥: einzeln dazu/weg. ⇧: Bereich.
    private func klick(_ abo: Abo, index i: Int) {
        // Tastaturfokus aus Seitenleiste oder Suchfeld holen, damit die Pfeiltasten im Raster wirken
        if let fenster = NSApp.keyWindow, fenster.firstResponder is NSText || fenster.firstResponder is NSTableView {
            fenster.makeFirstResponder(nil)
        }
        let tasten = NSEvent.modifierFlags
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 && tasten.intersection([.shift, .command, .option]).isEmpty {
            auswahl = abo
            return
        }
        if tasten.contains(.shift) {
            let a = anker ?? abos.firstIndex { markiert.contains($0) } ?? i
            anker = a
            ende = i
            markiert = Set(abos[min(a, i)...max(a, i)])
        } else if tasten.contains(.command) || tasten.contains(.option) {
            if markiert.contains(abo) { markiert.remove(abo) } else { markiert.insert(abo) }
            anker = i
            ende = i
        } else {
            markiert = [abo]
            anker = i
            ende = i
        }
    }

    /// ← → eine Kachel, ↑ ↓ eine Zeile; mit ⇧ wird die Auswahl erweitert
    private func pfeil(_ n: Notification, proxy: ScrollViewProxy) {
        guard Fokus.kachelnAktiv, let pfeil = n.object as? Fokus.Pfeil, !abos.isEmpty else { return }
        let erweitern = (n.userInfo?["erweitern"] as? Bool) ?? false
        let position = ende.flatMap { $0 < abos.count && markiert.contains(abos[$0]) ? $0 : nil }
            ?? abos.firstIndex { markiert.contains($0) }
        guard let position else {
            let start = (pfeil == .runter || pfeil == .rechts) ? 0 : abos.count - 1
            markiert = [abos[start]]
            anker = start
            ende = start
            proxy.scrollTo(abos[start].persistentModelID)
            return
        }
        let schritt: Int
        switch pfeil {
        case .links: schritt = -1
        case .rechts: schritt = 1
        case .hoch: schritt = -spalten
        case .runter: schritt = spalten
        }
        var ziel = position + schritt
        // Oben/unten am Rand: in der Spalte bleiben statt umzubrechen
        if ziel < 0 { ziel = pfeil == .hoch ? position : 0 }
        if ziel >= abos.count { ziel = pfeil == .runter ? abos.count - 1 : position }
        if erweitern {
            let a = anker ?? position
            anker = a
            markiert = Set(abos[min(a, ziel)...max(a, ziel)])
        } else {
            markiert = [abos[ziel]]
            anker = ziel
        }
        ende = ziel
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(abos[ziel].persistentModelID) }
    }
}

// MARK: - Eine Kachel

struct AboKachel: View {
    let abo: Abo
    let markiert: Bool
    let dringlichkeit: Dringlichkeit
    let wert: Double?
    let einheit: String
    let farbe: Color?
    @State private var hover = false

    private var name: String { abo.name.isEmpty ? String(localized: "Ohne Namen") : abo.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                symbol
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.euro(wert))
                        .font(.system(size: 17, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(wert == nil || !abo.istAktiv ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(einheit)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(name)
                .font(.body.weight(.medium))
                .foregroundStyle(abo.name.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            unterzeile
                .font(.callout)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .background(Color.accentColor.opacity(markiert ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(markiert ? Color.accentColor.opacity(0.8) : Color.primary.opacity(hover ? 0.16 : 0.08),
                          lineWidth: markiert ? 2 : 1))
        .opacity(abo.istAktiv ? 1 : 0.75)
        .onHover { hover = $0 }
        .help(String(localized: "Doppelklick öffnet das Abo"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(markiert ? .isSelected : [])
    }

    /// Anfangsbuchstabe auf der Farbe der Kategorie
    private var symbol: some View {
        let f = farbe ?? Color.secondary
        return Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(f)
            .frame(width: 36, height: 36)
            .background(f.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private var unterzeile: some View {
        if !abo.istAktiv {
            Text(String(localized: "Gekündigt") + (abo.gekuendigtAm.map { String(localized: " am \(Format.datum($0))") } ?? ""))
                .foregroundStyle(.secondary)
        } else if let frist = abo.spaetestensKuendigenBis, let tage = abo.tageBisFrist() {
            (Text(Format.inTagen(tage)).foregroundStyle(dringlichkeit.farbe(tage) ?? Color.secondary)
                + Text(" · \(Format.datum(frist))").foregroundStyle(.tertiary))
                .help("Spätestens kündigen bis \(Format.datum(frist))")
        } else {
            Text(abo.kategorie.isEmpty ? String(localized: "Keine Frist") : abo.kategorie)
                .foregroundStyle(.tertiary)
        }
    }
}

// Rückgängig machen:
//   cd ~/Desktop/Abo/Abos && git switch main && ./"App aktualisieren.command"
// Alle Stellen des Experiments findet man mit:  grep -rn "EXPERIMENT Kacheln" Abos

// MARK: - Seitenleiste einklappen (EXPERIMENT Kacheln)

/// Kleiner Pfeil: ‹ klappt die Seitenleiste ein, › klappt sie wieder auf
struct EinklappKnopf: View {
    enum Richtung { case zu, auf }
    let richtung: Richtung
    var aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            Image(systemName: richtung == .zu ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hover ? .primary : .secondary)
                .frame(width: 24, height: 28)
                .background(Color.primary.opacity(hover ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(richtung == .zu ? "Seitenleiste ausblenden (⌃⌘S)" : "Seitenleiste einblenden (⌃⌘S)")
        .accessibilityLabel(richtung == .zu ? "Seitenleiste ausblenden" : "Seitenleiste einblenden")
    }
}

/// Bleibt links stehen, wenn die Seitenleiste eingeklappt ist
struct EinklappStreifen: View {
    var aufklappen: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                EinklappKnopf(richtung: .auf, aktion: aufklappen)
                    .padding(.top, 12)
                Spacer()
            }
            .frame(width: 32)
            Divider()
        }
    }
}

/// Trenner zum Ziehen; die Breite bleibt zwischen `minimum` und `maximum`
struct SeitenleistenTrenner: View {
    @Binding var breite: Double
    @State private var start: Double?
    @State private var hover = false

    static let minimum: Double = 290
    static let maximum: Double = 380
    static func begrenzt(_ b: Double) -> CGFloat { CGFloat(min(max(b, minimum), maximum)) }

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(width: 7)
            .contentShape(Rectangle())
            .padding(.horizontal, -3)
            .zIndex(1)
            .onHover { drin in
                if drin, !hover { NSCursor.resizeLeftRight.push() }
                if !drin, hover, start == nil { NSCursor.pop() }
                hover = drin
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { g in
                        let s = start ?? breite
                        start = s
                        breite = Double(Self.begrenzt(s + g.translation.width))
                    }
                    .onEnded { _ in
                        start = nil
                        if !hover { NSCursor.pop() }
                    }
            )
            // Doppelklick: zurück auf die Standardbreite
            .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { breite = 300 } }
    }
}
