import SwiftUI

/// Schwebende Leiste unten, sobald mehrere Abos markiert sind: rechnet sie zusammen.
struct AuswahlLeiste: View {
    let abos: [Abo]
    var aufheben: () -> Void
    @AppStorage("kostenEinheit") private var einheit: KostenEinheit = .monat

    private var proMonat: Double { abos.compactMap(\.proMonat).reduce(0, +) }
    private var ohneBetrag: Int { abos.filter { $0.betrag == nil }.count }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(abos.count == 1 ? String(localized: "1 Abo ausgewählt") : String(localized: "\(abos.count) Abos ausgewählt")).fontWeight(.medium)
                Text(abos.map { $0.name.isEmpty ? String(localized: "Ohne Namen") : $0.name }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            zahl(String(localized: "pro Monat"), proMonat, betont: true)
            zahl(String(localized: "pro Jahr"), proMonat * 12)
            if einheit != .monat { zahl(einheit.text, proMonat * einheit.faktor) }
            zahl(String(localized: "bisher bezahlt"), Verlauf.bisHeute(abos))

            Button { Sicherung.csvExportieren(abos) } label: {
                Label("CSV", systemImage: "square.and.arrow.up")
            }
            .help("Ausgewählte Abos als CSV-Datei exportieren")
            Button("Aufheben", action: aufheben)
                .keyboardShortcut(.cancelAction)
                .help("Auswahl aufheben (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .overlay(alignment: .topLeading) {
            if ohneBetrag > 0 {
                Text("\(ohneBetrag) ohne Betrag nicht mitgerechnet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .offset(x: 12, y: -10)
            }
        }
        .padding(16)
    }

    private func zahl(_ titel: String, _ wert: Double, betont: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(titel).font(.caption).foregroundStyle(.secondary)
            Text(Format.euro(wert))
                .font(.system(size: betont ? 17 : 15, weight: betont ? .semibold : .medium))
                .monospacedDigit()
        }
        .fixedSize()
    }
}

// MARK: - Klick daneben hebt die Auswahl auf

/// Meldet die sichtbare Fläche dieser Ansicht als „gehört zur Auswahl“: Ein Klick hier hebt sie nicht auf.
/// Scrollt die Ansicht teilweise aus dem Bild, zählt nur der sichtbare Teil.
struct AuswahlBereich: ViewModifier {
    @State private var schluessel = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { g in
                let rahmen = g.frame(in: .global)
                guard let sicht = g.bounds(of: .scrollView) else { return rahmen }
                return rahmen.intersection(sicht.offsetBy(dx: rahmen.minX, dy: rahmen.minY))
            } action: { Fokus.auswahlBereiche[schluessel] = $0 }
            .onDisappear { Fokus.auswahlBereiche[schluessel] = nil }
    }
}

extension View {
    func auswahlBereich() -> some View { modifier(AuswahlBereich()) }
}
