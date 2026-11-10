import Charts
import SwiftUI

// MARK: - Daten

/// Ein Monat im Kostenverlauf
struct VerlaufPunkt: Identifiable {
    let monat: Date
    /// Zahlungen in diesem Monat
    let imMonat: Double
    /// Alle Zahlungen vom Beginn bis einschließlich dieses Monats
    let kumuliert: Double
    var id: Date { monat }
}

enum Verlauf {
    static func monatsAnfang(_ d: Date) -> Date {
        let cal = Kalender.de
        return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }

    /// Monatswerte vom ersten „Abo seit“ bis zum Ende des Prognosezeitraums
    static func punkte(_ abos: [Abo], bis ende: Date) -> [VerlaufPunkt] {
        let cal = Kalender.de
        let mitBetrag = abos.filter { $0.betrag != nil }
        guard let erster = mitBetrag.map(\.startdatum).min() else { return [] }
        let start = monatsAnfang(erster)
        let letzterMonat = monatsAnfang(ende)
        let letzterTag = cal.date(byAdding: DateComponents(month: 1, day: -1), to: letzterMonat) ?? ende

        var proMonat: [Date: Double] = [:]
        for abo in mitBetrag {
            guard let betrag = abo.anteilProZahlung else { continue }
            for tag in abo.zahltage(von: start, bis: letzterTag) {
                proMonat[monatsAnfang(tag), default: 0] += betrag
            }
        }

        var punkte: [VerlaufPunkt] = []
        var summe = 0.0
        var monat = start
        while monat <= letzterMonat && punkte.count < 1500 {
            let wert = proMonat[monat] ?? 0
            summe += wert
            punkte.append(VerlaufPunkt(monat: monat, imMonat: wert, kumuliert: summe))
            monat = cal.date(byAdding: .month, value: 1, to: monat) ?? letzterMonat.addingTimeInterval(1)
        }
        return punkte
    }

    /// Tatsächlich gezahlt bis heute (einschließlich)
    static func bisHeute(_ abos: [Abo]) -> Double {
        abos.compactMap { abo in abo.kosten(von: .distantPast, bis: Date()) }.reduce(0, +)
    }
}

// MARK: - Prognosezeitraum

/// Wie weit der Verlauf in die Zukunft reicht; gilt für Übersicht und Abo-Karten gemeinsam
struct VerlaufZeitraumPicker: View {
    @AppStorage("verlaufJahre") private var jahre = 3
    @AppStorage("verlaufEigen") private var eigen = false
    @AppStorage("verlaufEigeneJahre") private var eigeneJahre = 20

    /// 0 steht für „Eigene“
    private var auswahl: Binding<Int> {
        Binding(get: { eigen ? 0 : jahre },
                set: { neu in
                    if neu == 0 { eigen = true } else { eigen = false; jahre = neu }
                })
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Prognose", selection: auswahl) {
                Text("1 Jahr").tag(1)
                Text("3 Jahre").tag(3)
                Text("5 Jahre").tag(5)
                Text("10 Jahre").tag(10)
                Text("Eigene").tag(0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Wie weit der Verlauf in die Zukunft reicht")
            if eigen {
                HStack(spacing: 4) {
                    TextField("Jahre", value: $eigeneJahre, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48)
                        .onSubmit { eigeneJahre = min(100, max(1, eigeneJahre)) }
                    Stepper("Jahre", value: $eigeneJahre, in: 1...100).labelsHidden()
                    Text("Jahre").foregroundStyle(.secondary)
                }
                .fixedSize()
                .help("1 bis 100 Jahre in die Zukunft")
            }
        }
    }

}

// MARK: - Diagramm

/// Aufsummierte Kosten über die Zeit; Maus darüber zeigt Monat, Zahlung im Monat und Summe bis dahin
struct KostenVerlauf: View {
    let abos: [Abo]
    var hoehe: CGFloat = 240
    var zeigtSummen = true
    // Beobachtet, damit das Diagramm bei jeder Änderung neu rechnet
    @AppStorage("verlaufJahre") private var jahre = 3
    @AppStorage("verlaufEigen") private var eigen = false
    @AppStorage("verlaufEigeneJahre") private var eigeneJahre = 20
    @State private var auswahl: Date?

    private var ende: Date {
        let n = eigen ? min(100, max(1, eigeneJahre)) : jahre
        return Kalender.de.date(byAdding: .year, value: n, to: Date()) ?? Date()
    }

    var body: some View {
        let punkte = Verlauf.punkte(abos, bis: ende)
        VStack(alignment: .leading, spacing: 12) {
            if punkte.isEmpty || (punkte.last?.kumuliert ?? 0) == 0 {
                Text("Noch nichts zu zeigen – dafür braucht es einen Betrag und „Abo seit“")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: hoehe * 0.5)
            } else {
                if zeigtSummen { summen(punkte) }
                diagramm(punkte)
            }
        }
    }

    // Zwei Zahlen über dem Diagramm: bisher und bis zum Ende des Zeitraums
    private func summen(_ punkte: [VerlaufPunkt]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            kennzahl("Bisher ausgegeben", Format.euro(Verlauf.bisHeute(abos)))
            kennzahl("Bis \(monatJahr(punkte.last?.monat ?? ende))", Format.euro(punkte.last?.kumuliert))
        }
    }

    private func kennzahl(_ titel: String, _ wert: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titel).font(.caption).foregroundStyle(.secondary)
            Text(wert).font(.system(size: 18, weight: .medium)).monospacedDigit()
        }
    }

    private func diagramm(_ punkte: [VerlaufPunkt]) -> some View {
        let heute = Verlauf.monatsAnfang(Date())
        // Bisher durchgezogen, Prognose gestrichelt; der aktuelle Monat gehört zu beiden, damit die Linie zusammenhängt
        let bisher = punkte.filter { $0.monat <= heute }
        let prognose = punkte.filter { $0.monat >= heute }
        let gewaehlt = auswahl.flatMap { a in punkte.min { abs($0.monat.timeIntervalSince(a)) < abs($1.monat.timeIntervalSince(a)) } }
        let jahreSpanne = (punkte.last?.monat.timeIntervalSince(punkte.first?.monat ?? Date()) ?? 0) / (365 * 86400)

        return Chart {
            ForEach(bisher) { p in
                AreaMark(x: .value("Monat", p.monat), y: .value("Summe", p.kumuliert))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.accentColor.opacity(0.12))
                LineMark(x: .value("Monat", p.monat), y: .value("Summe", p.kumuliert), series: .value("Teil", "Bisher"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(prognose) { p in
                AreaMark(x: .value("Monat", p.monat), y: .value("Summe", p.kumuliert))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.accentColor.opacity(0.05))
                LineMark(x: .value("Monat", p.monat), y: .value("Summe", p.kumuliert), series: .value("Teil", "Prognose"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.accentColor.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            RuleMark(x: .value("Heute", Date()))
                .foregroundStyle(Color.primary.opacity(0.2))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("heute").font(.caption2).foregroundStyle(.secondary)
                }
            if let g = gewaehlt {
                RuleMark(x: .value("Monat", g.monat))
                    .foregroundStyle(Color.primary.opacity(0.25))
                // Das Fenster sitzt am Punkt und bleibt immer innerhalb des Diagramms
                PointMark(x: .value("Monat", g.monat), y: .value("Summe", g.kumuliert))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(40)
                    .annotation(position: .topLeading, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        infoFenster(g, zukunft: g.monat > heute)
                    }
            }
        }
        .chartXAxis {
            if jahreSpanne > 2 {
                // Bei langen Zeiträumen nur alle 2, 5 oder 10 Jahre beschriften
                let schritt = jahreSpanne > 40 ? 10 : jahreSpanne > 15 ? 5 : jahreSpanne > 7 ? 2 : 1
                AxisMarks(values: .stride(by: .year, count: schritt)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel(format: .dateTime.year().locale(Format.locale))
                }
            } else {
                AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits).locale(Format.locale))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { wert in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let v = wert.as(Double.self) {
                        Text(v.formatted(.currency(code: "EUR").precision(.fractionLength(0)).locale(Format.locale)))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let ort):
                            guard let rahmen = proxy.plotFrame else { return }
                            let x = ort.x - geo[rahmen].origin.x
                            auswahl = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            auswahl = nil
                        }
                    }
            }
        }
        .frame(height: hoehe)
        .padding(.top, 12) // Platz für „heute“
        .accessibilityLabel("Aufsummierte Kosten über die Zeit")
    }

    /// Das kleine Fenster beim Überfahren
    private func infoFenster(_ p: VerlaufPunkt, zukunft: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(monatJahr(p.monat)).fontWeight(.medium)
                if zukunft {
                    Text("Prognose").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("In diesem Monat").foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(Format.euro(p.imMonat)).monospacedDigit()
            }
            HStack {
                Text("Insgesamt bis dahin").foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(Format.euro(p.kumuliert)).monospacedDigit().fontWeight(.medium)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(width: 230)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
    }

    private func monatJahr(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide).year().locale(Format.locale))
    }
}
