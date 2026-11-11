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
                Text(abos.count == 1 ? "1 Abo ausgewählt" : "\(abos.count) Abos ausgewählt").fontWeight(.medium)
                Text(abos.map { $0.name.isEmpty ? "Ohne Namen" : $0.name }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            zahl("pro Monat", proMonat, betont: true)
            zahl("pro Jahr", proMonat * 12)
            if einheit != .monat { zahl(einheit.text, proMonat * einheit.faktor) }
            zahl("bisher bezahlt", Verlauf.bisHeute(abos))

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
