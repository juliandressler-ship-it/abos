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
            for tag in abo.zahltage(von: start, bis: letzterTag) {
                proMonat[monatsAnfang(tag), default: 0] += abo.anteil(am: tag) ?? 0
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

    /// Für lange Zeiträume nur jeden n-ten Monat zeichnen (Summen bleiben exakt); der aktuelle und
    /// der letzte Monat sind immer dabei
    static func ausgeduennt(_ punkte: [VerlaufPunkt], hoechstens: Int = 240) -> [VerlaufPunkt] {
        guard punkte.count > hoechstens else { return punkte }
        let schritt = Int((Double(punkte.count) / Double(hoechstens)).rounded(.up))
        let heute = monatsAnfang(Date())
        return punkte.enumerated().filter { i, p in
            i % schritt == 0 || i == punkte.count - 1 || p.monat == heute
        }.map(\.element)
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
                // Eigene Ansicht: Mausbewegungen zeichnen nur das Diagramm neu, gerechnet wird nicht noch einmal
                VerlaufDiagramm(punkte: Verlauf.ausgeduennt(punkte), hoehe: hoehe)
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

    private func monatJahr(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide).year().locale(Format.locale))
    }
}

/// Das eigentliche Diagramm, selbst gezeichnet (deutlich schneller als Swift Charts).
/// Hält den Maus-Zustand selbst, damit Mausbewegungen nichts neu berechnen.
struct VerlaufDiagramm: View {
    let punkte: [VerlaufPunkt]
    let hoehe: CGFloat
    @State private var gewaehlt: Int?

    // Ränder für die Achsenbeschriftung
    private let links: CGFloat = 64
    private let unten: CGFloat = 20
    private let oben: CGFloat = 14

    var body: some View {
        let skala = Skala(punkte: punkte)
        GeometryReader { geo in
            let flaeche = CGRect(x: links, y: oben, width: max(1, geo.size.width - links - 4),
                                 height: max(1, geo.size.height - oben - unten))
            let lage = Lage(skala: skala, flaeche: flaeche)
            ZStack(alignment: .topLeading) {
                gitter(skala, lage, flaeche)
                linien(skala, lage, flaeche)
                heuteLinie(skala, lage, flaeche)
                if let i = gewaehlt, punkte.indices.contains(i) {
                    markierung(i, lage, flaeche, breite: geo.size.width)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let ort): gewaehlt = lage.index(beiX: ort.x, punkte: punkte)
                case .ended: gewaehlt = nil
                }
            }
        }
        .frame(height: hoehe)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aufsummierte Kosten über die Zeit, bis \(Format.euro(punkte.last?.kumuliert))")
    }

    // MARK: Maßstab

    struct Skala {
        let start: Date
        let ende: Date
        let maxWert: Double
        let ticks: [Double]
        let heute: Date

        init(punkte: [VerlaufPunkt]) {
            start = punkte.first?.monat ?? Date()
            ende = punkte.last?.monat ?? Date()
            heute = Date()
            let roh = max(punkte.last?.kumuliert ?? 1, 1)
            // „Schöne“ Teilung: 1, 2, 2,5 oder 5 × 10^n
            let grob = roh / 4
            let basis = pow(10, floor(log10(grob)))
            let stufe = [1, 2, 2.5, 5, 10].map { $0 * basis }.first { $0 >= grob } ?? grob
            maxWert = ceil(roh / stufe) * stufe
            ticks = stride(from: 0, through: maxWert + stufe / 2, by: stufe).map { $0 }
        }
    }

    struct Lage {
        let skala: Skala
        let flaeche: CGRect

        func x(_ d: Date) -> CGFloat {
            let spanne = max(1, skala.ende.timeIntervalSince(skala.start))
            return flaeche.minX + CGFloat(d.timeIntervalSince(skala.start) / spanne) * flaeche.width
        }

        func y(_ v: Double) -> CGFloat {
            flaeche.maxY - CGFloat(v / max(skala.maxWert, 1)) * flaeche.height
        }

        /// Nächster Punkt zur Mausposition (binäre Suche über die Zeit)
        func index(beiX px: CGFloat, punkte: [VerlaufPunkt]) -> Int? {
            guard !punkte.isEmpty, px >= flaeche.minX - 8, px <= flaeche.maxX + 8 else { return nil }
            var lo = 0, hi = punkte.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if x(punkte[mid].monat) < px { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 && abs(x(punkte[lo - 1].monat) - px) < abs(x(punkte[lo].monat) - px) { return lo - 1 }
            return lo
        }
    }

    // MARK: Zeichnen

    private func gitter(_ skala: Skala, _ lage: Lage, _ f: CGRect) -> some View {
        let cal = Kalender.de
        let jahre = max(0, cal.dateComponents([.year], from: skala.start, to: skala.ende).year ?? 0)
        let schritt = jahre > 40 ? 10 : jahre > 15 ? 5 : jahre > 7 ? 2 : 1
        let ersteJahr = cal.component(.year, from: skala.start) + 1
        let jahresMarken: [Date] = jahre >= 2
            ? stride(from: ersteJahr, through: cal.component(.year, from: skala.ende), by: schritt)
                .compactMap { cal.date(from: DateComponents(year: $0, month: 1, day: 1)) }
            : stride(from: 0, through: max(0, cal.dateComponents([.month], from: skala.start, to: skala.ende).month ?? 0), by: 3)
                .compactMap { cal.date(byAdding: .month, value: $0, to: skala.start) }
        let format: Date.FormatStyle = jahre >= 2
            ? .dateTime.year().locale(Format.locale)
            : .dateTime.month(.abbreviated).year(.twoDigits).locale(Format.locale)

        return ZStack(alignment: .topLeading) {
            // Waagrechte Linien mit Beträgen
            ForEach(skala.ticks, id: \.self) { t in
                Path { p in
                    p.move(to: CGPoint(x: f.minX, y: lage.y(t)))
                    p.addLine(to: CGPoint(x: f.maxX, y: lage.y(t)))
                }
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                Text(t.formatted(.currency(code: "EUR").precision(.fractionLength(0)).locale(Format.locale)))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: links - 8, alignment: .trailing)
                    .position(x: (links - 8) / 2, y: lage.y(t))
            }
            // Senkrechte Linien mit Jahren bzw. Monaten
            ForEach(jahresMarken, id: \.self) { d in
                if d >= skala.start && d <= skala.ende {
                    Path { p in
                        p.move(to: CGPoint(x: lage.x(d), y: f.minY))
                        p.addLine(to: CGPoint(x: lage.x(d), y: f.maxY))
                    }
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    Text(d.formatted(format))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: lage.x(d), y: f.maxY + unten / 2 + 2)
                }
            }
        }
    }

    /// Treppenlinie: der Wert gilt bis zum nächsten Monat; bisher kräftig, Prognose heller
    private func linien(_ skala: Skala, _ lage: Lage, _ f: CGRect) -> some View {
        let heute = Verlauf.monatsAnfang(skala.heute)
        let grenze = punkte.lastIndex { $0.monat <= heute } ?? 0
        let bisher = Array(punkte[0...grenze])
        let prognose = Array(punkte[grenze...])
        return ZStack {
            flaeche(bisher, lage, f).fill(Color.accentColor.opacity(0.14))
            flaeche(prognose, lage, f).fill(Color.accentColor.opacity(0.06))
            treppe(prognose, lage).stroke(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            treppe(bisher, lage).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    private func treppe(_ teil: [VerlaufPunkt], _ lage: Lage) -> Path {
        Path { p in
            guard let erster = teil.first else { return }
            p.move(to: CGPoint(x: lage.x(erster.monat), y: lage.y(erster.kumuliert)))
            var vorher = erster.kumuliert
            for pkt in teil.dropFirst() {
                let x = lage.x(pkt.monat)
                p.addLine(to: CGPoint(x: x, y: lage.y(vorher)))
                p.addLine(to: CGPoint(x: x, y: lage.y(pkt.kumuliert)))
                vorher = pkt.kumuliert
            }
        }
    }

    private func flaeche(_ teil: [VerlaufPunkt], _ lage: Lage, _ f: CGRect) -> Path {
        var p = treppe(teil, lage)
        guard let erster = teil.first, let letzter = teil.last else { return p }
        p.addLine(to: CGPoint(x: lage.x(letzter.monat), y: f.maxY))
        p.addLine(to: CGPoint(x: lage.x(erster.monat), y: f.maxY))
        p.closeSubpath()
        return p
    }

    private func heuteLinie(_ skala: Skala, _ lage: Lage, _ f: CGRect) -> some View {
        let x = lage.x(skala.heute)
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: x, y: f.minY))
                p.addLine(to: CGPoint(x: x, y: f.maxY))
            }
            .stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            Text("heute")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
                .position(x: x + 16, y: f.minY - 7)
        }
    }

    /// Senkrechte Linie, Punkt und das kleine Fenster beim Überfahren
    private func markierung(_ i: Int, _ lage: Lage, _ f: CGRect, breite: CGFloat) -> some View {
        let p = punkte[i]
        let x = lage.x(p.monat), y = lage.y(p.kumuliert)
        let fensterBreite: CGFloat = 230
        // Fenster links vom Punkt; ist dort kein Platz, rechts davon
        let linksDavon = x - fensterBreite - 10
        let fx = linksDavon >= f.minX ? linksDavon : min(x + 10, breite - fensterBreite)
        let fy = min(max(f.minY, y - 92), f.maxY - 84)
        return ZStack(alignment: .topLeading) {
            Path { pfad in
                pfad.move(to: CGPoint(x: x, y: f.minY))
                pfad.addLine(to: CGPoint(x: x, y: f.maxY))
            }
            .stroke(Color.primary.opacity(0.25), lineWidth: 1)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .position(x: x, y: y)
            infoFenster(p, zukunft: p.monat > Verlauf.monatsAnfang(Date()))
                .frame(width: fensterBreite)
                .offset(x: fx, y: fy)
        }
        .allowsHitTesting(false)
    }

    private func infoFenster(_ p: VerlaufPunkt, zukunft: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(p.monat.formatted(.dateTime.month(.wide).year().locale(Format.locale))).fontWeight(.medium)
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
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
