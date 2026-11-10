import SwiftUI

/// Wie ein Segment-Schalter, aber das erste Segment hat einen Dropdown-Pfeil:
/// Klick auf den Text wählt die Ansicht, der Pfeil öffnet Monat / Woche / Tag / Stunde.
struct KostenUmschalter: View {
    @Binding var ansicht: KostenAnsicht
    /// Kompakt für die Gesamt-Karte: nur „Monat ⌄ | Jahr“
    var kompakt = false
    @AppStorage("kostenEinheit") private var einheit: KostenEinheit = .monat

    var body: some View {
        HStack(spacing: 2) {
            segment(gewaehlt: ansicht == .monat) {
                Menu {
                    Picker("Einheit", selection: einheitWaehlen) {
                        ForEach(KostenEinheit.allCases) { Text($0.titel).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Text(kompakt ? einheit.kurz : einheit.titel)
                } primaryAction: {
                    ansicht = .monat
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Durchschnitt \(einheit.text) – der Pfeil wechselt zu Woche, Tag oder Stunde")
            }
            knopf(kompakt ? "Jahr" : "Pro Jahr", .jahr)
            if !kompakt { knopf("Zeitraum", .zeitraum) }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }

    /// Einheit wählen schaltet auch auf diese Ansicht um
    private var einheitWaehlen: Binding<KostenEinheit> {
        Binding(get: { einheit }, set: { einheit = $0; ansicht = .monat })
    }

    private func knopf(_ titel: String, _ ziel: KostenAnsicht) -> some View {
        segment(gewaehlt: ansicht == ziel) {
            Button(titel) { ansicht = ziel }
                .buttonStyle(.plain)
        }
    }

    private func segment<Inhalt: View>(gewaehlt: Bool, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        inhalt()
            .padding(.horizontal, 10)
            .frame(height: 20)
            .background {
                if gewaehlt {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
                }
            }
            .contentShape(Rectangle())
    }
}
