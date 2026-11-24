import SwiftUI

/// Upgrade oder Downgrade eines Abos, z. B. Claude Pro → Claude Max.
/// Neuer Tarif, neuer Preis und ab wann – der Verlauf hält den Wechsel fest,
/// der Kostenverlauf rechnet ab diesem Tag mit dem neuen Preis. Liegt „Ab“ in der
/// Zukunft (z. B. Downgrade zum Ende der Laufzeit), wird der Wechsel geplant.
struct TarifWechselBlatt: View {
    @Bindable var abo: Abo
    @Environment(\.dismiss) private var dismiss

    @State private var bisher: String
    @State private var neu = ""
    @State private var preis: Double?
    @State private var ab = Date()
    @State private var nameAnpassen = true
    @FocusState private var neuFokus: Bool

    init(abo: Abo) {
        self.abo = abo
        _bisher = State(initialValue: abo.vermuteterTarif)
    }

    private var bisherFest: Bool { !abo.tarif.isEmpty }
    /// „Ab“ liegt nach heute: Wechsel wird nur geplant
    private var istGeplant: Bool { Kalender.de.startOfDay(for: ab) > Kalender.de.startOfDay(for: Date()) }
    /// Tag der nächsten Verlängerung – typischer Termin für ein Downgrade
    private var naechsteVerlaengerung: Date? {
        abo.naechstesEnde().flatMap { $0 > Date() ? Kalender.de.startOfDay(for: $0) : nil }
    }
    private var neuBereinigt: String { neu.trimmingCharacters(in: .whitespaces) }
    private var intervallText: String { abo.intervall.titel.lowercased() }

    /// „Claude Pro“ → „Claude Max“, wenn der bisherige Tarif im Namen steht
    private var namensVorschlag: String? {
        let alt = bisher.trimmingCharacters(in: .whitespaces)
        guard !alt.isEmpty, !neuBereinigt.isEmpty,
              let bereich = abo.name.range(of: alt, options: [.caseInsensitive, .backwards]) else { return nil }
        let vorschlag = abo.name.replacingCharacters(in: bereich, with: neuBereinigt)
        return vorschlag == abo.name ? nil : vorschlag
    }

    /// Unterschied pro Monat (eigener Anteil, aufs Intervall umgerechnet)
    private var differenzProMonat: Double? {
        guard let neu = preis, let alt = abo.betrag else { return nil }
        return (neu - alt) * max(0, abo.anteilProzent) / 100 / Double(abo.monateProIntervall)
    }

    private var kannWechseln: Bool {
        !neuBereinigt.isEmpty && preis != nil
            && neuBereinigt.caseInsensitiveCompare(bisher.trimmingCharacters(in: .whitespaces)) != .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tarif wechseln").font(.headline)
                Text(abo.name.isEmpty ? String(localized: "Ohne Namen") : abo.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Bisher").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    HStack(spacing: 8) {
                        if bisherFest {
                            Text(bisher).fontWeight(.medium)
                        } else {
                            TextField("Bisher", text: $bisher, prompt: Text("z. B. Pro"))
                                .labelsHidden()
                                .frame(width: 140)
                        }
                        Text("\(Format.euro(abo.betrag)) \(intervallText)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Neu").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Neu", text: $neu, prompt: Text("z. B. Max"))
                            .labelsHidden()
                            .frame(width: 140)
                            .focused($neuFokus)
                        if !abo.fruehereTarife.isEmpty {
                            Menu("Früherer Tarif") {
                                ForEach(abo.fruehereTarife, id: \.name) { t in
                                    Button("\(t.name) · \(Format.euro(t.betrag))") {
                                        neu = t.name
                                        if let b = t.betrag { preis = b }
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
                GridRow {
                    Text("Neuer Preis").foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        TextField("Neuer Preis", value: $preis,
                                  format: .number.precision(.fractionLength(2)).locale(Format.locale),
                                  prompt: Text("0,00"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("€ \(intervallText)")
                    }
                }
                GridRow {
                    Text("Ab").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        DatePicker("Ab", selection: $ab, in: Format.datumsBereich, displayedComponents: .date)
                            .labelsHidden()
                            .fixedSize()
                        if let n = naechsteVerlaengerung, !Kalender.de.isDate(ab, inSameDayAs: n) {
                            Button("Zur nächsten Verlängerung") { ab = n }
                                .buttonStyle(.link)
                                .help("Ab \(Format.datum(n)) – z. B. für ein Downgrade zum Ende der Laufzeit")
                        } else if !Kalender.de.isDateInToday(ab) {
                            Button("Heute") { ab = Date() }
                                .buttonStyle(.link)
                        }
                    }
                }
                if let vorschlag = namensVorschlag {
                    GridRow {
                        Text("Name").foregroundStyle(.secondary)
                        Toggle(istGeplant ? String(localized: "Ab dann „\(vorschlag)“ heißen")
                                          : String(localized: "In „\(vorschlag)“ umbenennen"), isOn: $nameAnpassen)
                    }
                }
            }

            zusammenfassung
                .frame(minHeight: 20, alignment: .leading)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(istGeplant ? String(localized: "Wechsel planen") : String(localized: "Wechseln")) { wechseln() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!kannWechseln)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            neuFokus = true
        }
    }

    /// „↑ Upgrade · +80,42 € pro Monat“ – sofort sichtbar, was der Wechsel bedeutet
    @ViewBuilder
    private var zusammenfassung: some View {
        if let d = differenzProMonat, abs(d) >= 0.005 {
            let hoch = d > 0
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(hoch ? String(localized: "Upgrade") : String(localized: "Downgrade")).fontWeight(.medium)
                        + Text(" · \(hoch ? "+" : "−")\(Format.euro(abs(d))) \(String(localized: "pro Monat"))")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: hoch ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(hoch ? Color.orange : Color.green)
                }
                .monospacedDigit()
                if istGeplant { geplantHinweis }
            }
        } else if istGeplant {
            geplantHinweis
        } else {
            Text("Der Wechsel steht danach mit Datum im Verlauf, der Kostenverlauf rechnet ab dann mit dem neuen Preis.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Erklärt, was bei einem Datum in der Zukunft passiert
    private var geplantHinweis: some View {
        let ersetzt = abo.geplanterWechsel.map { String(localized: " Ersetzt den bisher geplanten Wechsel zu \($0.tarif ?? "") am \(Format.datum($0.datum)).") } ?? ""
        return Text(String(localized: "Bis \(Format.datum(Kalender.de.date(byAdding: .day, value: -1, to: ab) ?? ab)) bleibt alles wie jetzt, ab \(Format.datum(ab)) stellt Abos automatisch um.") + ersetzt)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func wechseln() {
        let cal = Kalender.de
        // Heute: jetziger Zeitpunkt, damit der Eintrag nach allem steht, was heute schon passiert ist
        let zeitpunkt = cal.isDateInToday(ab) ? Date() : cal.startOfDay(for: ab)
        let neuerName = nameAnpassen ? namensVorschlag : nil
        abo.tarifWechseln(von: bisher, zu: neuBereinigt, betrag: preis, ab: zeitpunkt, neuerName: neuerName)
        dismiss()
    }
}
