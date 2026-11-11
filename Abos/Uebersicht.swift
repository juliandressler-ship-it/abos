import Charts
import SwiftUI

// MARK: - Auswertung

struct KategorieSumme: Identifiable {
    let name: String
    /// nil = nur Abos ohne Betrag
    let proMonat: Double?
    let anzahl: Int
    var id: String { name }
}

enum Auswertung {
    static func kategorieName(_ abo: Abo) -> String {
        abo.kategorie.isEmpty ? "Ohne Kategorie" : abo.kategorie
    }

    /// Aktive Abos nach Kategorie, teuerste zuerst
    static func kategorien(_ abos: [Abo]) -> [KategorieSumme] {
        kategorien(von: abos.filter(\.istAktiv))
    }

    /// Kategorien genau der übergebenen Abos (ohne Statusfilter)
    static func kategorien(von abos: [Abo], wert: (Abo) -> Double? = { $0.proMonat }) -> [KategorieSumme] {
        let gruppen = Dictionary(grouping: abos, by: kategorieName)
        var liste: [KategorieSumme] = []
        for (name, eintraege) in gruppen {
            let werte = eintraege.compactMap(wert)
            liste.append(KategorieSumme(name: name,
                                        proMonat: werte.isEmpty ? nil : werte.reduce(0, +),
                                        anzahl: eintraege.count))
        }
        liste.sort { l, r in
            let a = l.proMonat ?? -1, b = r.proMonat ?? -1
            if a != b { return a > b }
            return l.name.localizedStandardCompare(r.name) == .orderedAscending
        }
        return liste
    }

    /// Teuerste zuerst (auf den Monat umgerechnet), Abos ohne Betrag am Ende
    static func nachKosten(_ l: Abo, _ r: Abo) -> Bool {
        let a = l.proMonat ?? -1, b = r.proMonat ?? -1
        if a != b { return a > b }
        return nachName(l, r)
    }

    static func nachName(_ l: Abo, _ r: Abo) -> Bool {
        l.name.localizedStandardCompare(r.name) == .orderedAscending
    }

    /// Alle Kategorien, die bereits mindestens ein Abo hat
    static func vorhandeneKategorien(_ abos: [Abo]) -> [String] {
        Set(abos.map(\.kategorie).filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static let vorschlaege = ["Versicherung", "Software", "Telekommunikation", "Medien",
                              "Streaming", "Mobilität", "Sonstiges"]
}

// MARK: - Kategorie wählen

/// Dropdown mit den vorhandenen Kategorien, Vorschlägen und „Neue Kategorie…“ zum Eintippen
struct KategorieMenue: View {
    @Bindable var abo: Abo
    let alle: [Abo]
    var farbe: Color? = nil
    @State private var neuZeigen = false
    @State private var neuName = ""
    @State private var hover = false

    private var vorhanden: [String] { Auswertung.vorhandeneKategorien(alle) }
    private var vorschlaege: [String] { Auswertung.vorschlaege.filter { !vorhanden.contains($0) } }

    var body: some View {
        Menu {
            Section("Vorhanden") {
                ForEach(vorhanden, id: \.self) { eintrag($0) }
            }
            if !vorschlaege.isEmpty {
                Section("Vorschläge") {
                    ForEach(vorschlaege, id: \.self) { eintrag($0) }
                }
            }
            Divider()
            Button("Neue Kategorie…") {
                neuName = ""
                neuZeigen = true
            }
            if !abo.kategorie.isEmpty {
                Button("Ohne Kategorie") { abo.kategorie = "" }
            }
        } label: {
            HStack(spacing: 8) {
                if let farbe { Farbpunkt(farbe: farbe) }
                Text(abo.kategorie.isEmpty ? "Kategorie wählen" : abo.kategorie)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .opacity(hover ? 1 : 0.6)
            }
            .foregroundStyle(abo.kategorie.isEmpty ? .tertiary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(hover ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, -6)
        .onHover { hover = $0 }
        .help("Kategorie ändern")
        .alert("Neue Kategorie", isPresented: $neuZeigen) {
            TextField("z. B. Fitness", text: $neuName)
            Button("Übernehmen") {
                let name = neuName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { abo.kategorie = name }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Für „\(abo.name)“")
        }
    }

    @ViewBuilder
    private func eintrag(_ name: String) -> some View {
        Button {
            abo.kategorie = name
        } label: {
            if name == abo.kategorie {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }
}

// MARK: - Kontextmenü für ein Abo

struct AboMenue: View {
    let abo: Abo
    var oeffnen: () -> Void
    var loeschen: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Öffnen", action: oeffnen)
        if abo.istAktiv, let url = Format.url(abo.kuendigungsLink) {
            Button("Kündigungsseite öffnen") { openURL(url) }
        }
        if let url = Format.url(abo.websiteLink) {
            Button("Website öffnen") { openURL(url) }
        }
        Divider()
        if abo.istAktiv {
            Button("Als gekündigt markieren") { abo.kuendigen() }
        } else {
            Button("Wieder aktivieren") { abo.reaktivieren() }
        }
        Divider()
        Button("Löschen…", role: .destructive, action: loeschen)
    }
}

/// Hover-Hintergrund für Tabellenzeilen, deren Teile eigene Klickziele sind
struct ZeilenHover: ViewModifier {
    let hoehe: CGFloat
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: hoehe, alignment: .leading)
            .background(Color.primary.opacity(hover ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 8))
            .onHover { hover = $0 }
    }
}

/// Gedämpfte Farben für Kategorien; die Reihenfolge folgt den Kosten
enum Palette {
    static let farben: [Color] = [
        Color(red: 0.27, green: 0.47, blue: 0.84),  // Blau
        Color(red: 0.20, green: 0.60, blue: 0.56),  // Petrol
        Color(red: 0.88, green: 0.62, blue: 0.24),  // Bernstein
        Color(red: 0.79, green: 0.43, blue: 0.45),  // Rosé
        Color(red: 0.49, green: 0.61, blue: 0.40),  // Salbei
    ]

    static func farbe(_ rang: Int) -> Color {
        rang < farben.count ? farben[rang] : Color.primary.opacity(0.28)
    }
}

extension Format {
    static func anzahl(_ n: Int, _ einzahl: String, _ mehrzahl: String) -> String {
        "\(n) \(n == 1 ? einzahl : mehrzahl)"
    }
}

// MARK: - Klickbare Zeile

struct KlickZeile<Inhalt: View>: View {
    let aktiv: Bool
    let hoehe: CGFloat
    let aktion: () -> Void
    let inhalt: Inhalt
    @State private var hover = false

    init(aktiv: Bool = false, hoehe: CGFloat = 32, aktion: @escaping () -> Void, @ViewBuilder inhalt: () -> Inhalt) {
        self.aktiv = aktiv
        self.hoehe = hoehe
        self.aktion = aktion
        self.inhalt = inhalt()
    }

    var body: some View {
        Button(action: aktion) {
            inhalt
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: hoehe, alignment: .leading)
                .background(Color.primary.opacity(aktiv ? 0.08 : (hover ? 0.04 : 0)),
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct Farbpunkt: View {
    let farbe: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(farbe).frame(width: 8, height: 8)
    }
}

// MARK: - Übersicht

struct UebersichtView: View {
    let abos: [Abo]
    @Binding var kategorie: String?
    @Binding var auswahl: Abo?
    /// Gekündigt-Box aufgeklappt? Liegt im Fenster, damit sie offen bleibt, bis man sie schließt; beim App-Start zu
    @Binding var gekuendigtOffen: Bool
    /// Mehrfachauswahl, geteilt mit der Seitenleiste
    @Binding var markiert: Set<Abo>
    let dringlichkeit: Dringlichkeit
    var neu: () -> Void
    var loeschen: (Abo) -> Void
    @AppStorage("zeitraumJahr") private var jahr = false
    @AppStorage("tabelleSortFeld") private var sortFeld: SortFeld = .preis
    @AppStorage("tabelleSortUmgekehrt") private var sortUmgekehrt = false
    @AppStorage("uebersichtStatus") private var status: UebersichtStatus = .aktiv
    /// Kreisdiagramm (Aufteilung nach Kategorie) oder Linie (Kostenentwicklung über die Zeit)
    @AppStorage("uebersichtDiagramm") private var zeigtVerlauf = false
    @AppStorage("kostenZeitraum") private var zeitraumAktiv = false
    @AppStorage("kostenEinheit") private var einheit: KostenEinheit = .monat
    @AppStorage("zeitraumVorgabe") private var vorgabe: ZeitraumVorgabe = .dieserMonat
    @AppStorage("zeitraumVon") private var vonWert: Double = 0
    @AppStorage("zeitraumBis") private var bisWert: Double = 0
    @State private var gekuendigtGross = false
    @State private var tabellenSuche = ""
    /// Ausgangspunkt für ⇧-Klick in der Tabelle
    @State private var tabellenAnker: Abo?

    /// So viele gekündigte Abos zeigt die kleine Box, der Rest ist scrollbar
    private let gekuendigtSichtbar = 3

    /// Die ausgewerteten Abos: aktive, gekündigte oder alle
    private var basis: [Abo] { abos.filter(status.passt) }
    private var kategorien: [KategorieSumme] { Auswertung.kategorien(von: basis, wert: wert) }
    private var gekuendigte: [Abo] { abos.filter { !$0.istAktiv }.sorted(by: Auswertung.nachKosten) }
    /// Summe aller ausgewerteten Abos (Bezug für die Prozentangaben)
    private var gesamt: Double { basis.compactMap(wert).reduce(0, +) }
    private var inKategorie: [Abo] {
        basis.filter { kategorie == nil || Auswertung.kategorieName($0) == kategorie }
    }
    /// Die kleine Gekündigt-Box gibt es nur in der Ansicht „Aktive“; sonst stehen sie in der Tabelle
    /// Die Gekündigt-Box gibt es nur unter „Alle“; bei „Aktive“ sind Gekündigte ganz ausgeblendet
    private var zeigtGekuendigtBox: Bool { status == .alle && !gekuendigte.isEmpty }

    private var titel: String {
        switch status {
        case .aktiv: return kategorie ?? "Alle aktiven Abos"
        case .gekuendigt: return kategorie.map { "\($0) · gekündigt" } ?? "Gekündigte Abos"
        case .alle: return kategorie.map { "\($0) · aktiv und gekündigt" } ?? "Alle Abos"
        }
    }
    private var tabelle: [Abo] {
        let s = tabellenSuche.trimmingCharacters(in: .whitespaces)
        let basis = s.isEmpty ? inKategorie : inKategorie.filter {
            $0.name.localizedCaseInsensitiveContains(s)
                || $0.kategorie.localizedCaseInsensitiveContains(s)
                || $0.notizen.localizedCaseInsensitiveContains(s)
        }
        return Sortierung(feld: sortFeld, umgekehrt: sortUmgekehrt,
                          wertJahr: ansicht == .zeitraum ? wert : nil).sortiert(basis)
    }
    /// Summe der gezeigten Abos
    private var summe: Double { inKategorie.compactMap(wert).reduce(0, +) }
    /// Faktor gegenüber „pro Monat“: Jahr ×12, sonst die gewählte Einheit (Woche, Tag, Stunde)
    private var faktor: Double { jahr ? 12 : einheit.faktor }

    // MARK: Kosten: pro Monat, pro Jahr oder ein bestimmter Zeitraum

    private var ansicht: KostenAnsicht {
        get { zeitraumAktiv ? .zeitraum : (jahr ? .jahr : .monat) }
        nonmutating set {
            zeitraumAktiv = newValue == .zeitraum
            if newValue != .zeitraum { jahr = newValue == .jahr }
        }
    }
    private var ansichtBindung: Binding<KostenAnsicht> { Binding(get: { ansicht }, set: { ansicht = $0 }) }

    private var von: Binding<Date> {
        Binding(get: { vonWert == 0 ? bereich.start : Date(timeIntervalSinceReferenceDate: vonWert) },
                set: { vonWert = $0.timeIntervalSinceReferenceDate })
    }
    private var bis: Binding<Date> {
        Binding(get: { bisWert == 0 ? bereich.ende : Date(timeIntervalSinceReferenceDate: bisWert) },
                set: { bisWert = $0.timeIntervalSinceReferenceDate })
    }
    private var bereich: (start: Date, ende: Date) {
        let standard = ZeitraumVorgabe.dieserMonat.bereich(von: Date(), bis: Date())
        let a = vonWert == 0 ? standard.start : Date(timeIntervalSinceReferenceDate: vonWert)
        let b = bisWert == 0 ? standard.ende : Date(timeIntervalSinceReferenceDate: bisWert)
        return vorgabe.bereich(von: a, bis: b)
    }
    private var zeitraumText: String {
        vorgabe.beschreibung(von: bereich.start, bis: bereich.ende)
    }

    /// Der Wert eines Abos in der gewählten Ansicht
    private func wert(_ abo: Abo) -> Double? {
        switch ansicht {
        case .monat: return abo.proMonat.map { $0 * einheit.faktor }
        case .jahr: return abo.proJahr
        case .zeitraum: return abo.kosten(von: bereich.start, bis: bereich.ende)
        }
    }

    /// „pro Monat“, „pro Jahr“ oder „im November 2026“
    private var zeitraum: String {
        switch ansicht {
        case .monat: return einheit.text
        case .jahr: return "pro Jahr"
        case .zeitraum:
            switch vorgabe {
            case .diesesJahr, .letztesJahr: return "im Jahr \(zeitraumText)"
            case .dieserMonat, .letzterMonat: return "im \(zeitraumText)"
            default: return zeitraumText
            }
        }
    }

    private var anzahlZahlungen: Int {
        inKategorie.map { $0.zahltage(von: bereich.start, bis: bereich.ende).count }.reduce(0, +)
    }

    private func rang(_ name: String) -> Int { kategorien.firstIndex { $0.name == name } ?? 0 }

    private func prozent(_ wert: Double?) -> String {
        guard let wert, gesamt > 0 else { return "–" }
        return "\(Int((wert / gesamt * 100).rounded())) %"
    }

    /// Ein Klick auf dieselbe Kategorie hebt den Filter wieder auf
    private func waehlen(_ name: String) {
        kategorie = kategorie == name ? nil : name
    }

    var body: some View {
        if abos.isEmpty { leer } else { inhalt }
    }

    /// Erster Start: noch keine Abos
    private var leer: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Noch keine Abos").font(.title3.weight(.medium))
                Text("Trag deine Abos und Versicherungen ein – die App rechnet Kosten pro Monat und Jahr aus und erinnert dich rechtzeitig an Kündigungsfristen.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            HStack(spacing: 12) {
                Button(action: neu) { Label("Erstes Abo anlegen", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Button("Backup importieren…") { Sicherung.backupImportieren() }
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inhalt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ansichtsleiste
                if zeigtVerlauf {
                    verlaufAnsicht
                } else {
                    HStack(alignment: .top, spacing: 32) {
                        KreisDiagramm(kategorien: kategorien, kategorie: $kategorie,
                                      mitte: Format.euro(summe),
                                      mitteUnten: kategorie ?? (ansicht == .zeitraum ? zeitraumText : zeitraum))
                            .frame(width: 220, height: 220)
                        VStack(alignment: .leading, spacing: 16) {
                            kopf
                            legende
                            if zeigtGekuendigtBox && !gekuendigtGross { gekuendigtBox }
                        }
                        .frame(maxWidth: 440, alignment: .leading)
                    }
                    if zeigtGekuendigtBox && gekuendigtOffen && gekuendigtGross { gekuendigtGrossAnsicht }
                }
                aboListe
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .onChange(of: status) { _, _ in
            // Kategorie gibt es in der neuen Auswahl nicht mehr? Dann alles zeigen
            if let k = kategorie, !kategorien.contains(where: { $0.name == k }) { kategorie = nil }
        }
    }

    /// Was ausgewertet wird und in welchem Zeitraum – gilt für Diagramm, Summen und Tabelle
    private var ansichtsleiste: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 12) {
                Picker("Anzeigen", selection: $status) {
                    ForEach(UebersichtStatus.allCases) { Text($0.titel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Welche Abos ausgewertet werden")
                Spacer(minLength: 12)
                Picker("Diagramm", selection: $zeigtVerlauf) {
                    Label("Aufteilung", systemImage: "chart.pie").tag(false)
                    Label("Verlauf", systemImage: "chart.line.uptrend.xyaxis").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Aufteilung nach Kategorie oder Kostenentwicklung über die Zeit")
            }
            // Zweite Zeile: was das gewählte Diagramm zeigt
            if zeigtVerlauf {
                HStack(spacing: 8) {
                    Text("Prognose").foregroundStyle(.secondary)
                    VerlaufZeitraumPicker()
                }
            } else {
                KostenUmschalter(ansicht: ansichtBindung)
            }
            if !zeigtVerlauf && ansicht == .zeitraum {
                HStack(spacing: 12) {
                    if vorgabe == .eigener {
                        DatePicker("Von", selection: von, displayedComponents: .date)
                            .fixedSize()
                        DatePicker("bis", selection: bis, displayedComponents: .date)
                            .fixedSize()
                    }
                    Picker("Zeitraum", selection: $vorgabe) {
                        ForEach(ZeitraumVorgabe.allCases) { v in
                            if v == .eigener { Divider() }
                            Text(v.titel).tag(v)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    // MARK: Kostenentwicklung

    /// Aufsummierte Kosten der gewählten Abos (Status und Kategorie wie oben gewählt)
    private var verlaufAnsicht: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titel).font(.title3.weight(.medium))
                    Text("aufsummiert ab „Abo seit“, mit Kündigungen und Wiederaufnahmen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Kategorie direkt hier wählen, z. B. nur Versicherungen
                Picker("Kategorie", selection: $kategorie) {
                    Text("Alle Kategorien").tag(String?.none)
                    Divider()
                    ForEach(kategorien.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                            id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("Verlauf für alle oder eine bestimmte Kategorie")
            }
            KostenVerlauf(abos: inKategorie, hoehe: 260)
        }
    }

    // MARK: Kopf mit Monat/Jahr

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text(titel).font(.title3.weight(.medium))
                Spacer()
                if kategorie != nil {
                    Button("Alle Kategorien") { kategorie = nil }
                        .buttonStyle(.link)
                }
            }
            Text(Format.euro(summe))
                .font(.system(size: 28, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: jahr)
            Text(untertitel)
                .foregroundStyle(.secondary)
        }
    }

    private var untertitel: String {
        let ohneBetrag = inKategorie.filter { $0.betrag == nil }.count
        var teile = [status == .gekuendigt && ansicht != .zeitraum ? "\(zeitraum) gespart" : zeitraum]
        if ansicht == .zeitraum {
            teile.append(Format.anzahl(anzahlZahlungen, "Zahlung", "Zahlungen"))
        }
        if kategorie != nil {
            teile.append("\(prozent(summe)) von \(Format.euro(gesamt))")
        }
        switch status {
        case .aktiv:
            teile.append(Format.anzahl(inKategorie.count, "aktives Abo", "aktive Abos"))
        case .gekuendigt:
            teile.append(Format.anzahl(inKategorie.count, "gekündigtes Abo", "gekündigte Abos"))
        case .alle:
            let aktivSumme = inKategorie.filter(\.istAktiv).compactMap(wert).reduce(0, +)
            let gekSumme = inKategorie.filter { !$0.istAktiv }.compactMap(wert).reduce(0, +)
            teile.append("aktiv \(Format.euro(aktivSumme))")
            teile.append("gekündigt \(Format.euro(gekSumme))")
        }
        if ohneBetrag > 0 { teile.append("\(ohneBetrag) ohne Betrag") }
        return teile.joined(separator: " · ")
    }

    private var legende: some View {
        VStack(spacing: 2) {
            ForEach(Array(kategorien.enumerated()), id: \.element.id) { i, k in
                KlickZeile(aktiv: kategorie == k.name, aktion: { waehlen(k.name) }) {
                    HStack(spacing: 8) {
                        Farbpunkt(farbe: k.proMonat == nil ? Color.primary.opacity(0.12) : Palette.farbe(i))
                        Text(k.name).lineLimit(1)
                        Text("\(k.anzahl)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(Format.euro(k.proMonat))
                            .monospacedDigit()
                            .foregroundStyle(k.proMonat == nil ? .secondary : .primary)
                        Text(prozent(k.proMonat))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .opacity(kategorie == nil || kategorie == k.name ? 1 : 0.5)
            }
        }
        .padding(.horizontal, -8)
    }

    // MARK: Gekündigt

    private var gespart: Double { gekuendigte.compactMap(\.proMonat).reduce(0, +) }

    private func gekuendigtKopf(gross: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Klick auf die Überschrift klappt auf und zu
            Button {
                withAnimation(.easeOut(duration: 0.2)) { gekuendigtOffen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(gekuendigtOffen ? 90 : 0))
                    Text("Gekündigt").font(.headline.weight(.medium))
                    Text("\(gekuendigte.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if gespart > 0 {
                        Text(ansicht == .zeitraum ? "spart \(Format.euro(gespart)) pro Monat"
                                                  : "spart \(Format.euro(gespart * faktor)) \(zeitraum)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(gekuendigtOffen ? "Zuklappen" : "Gekündigte Abos zeigen")
            if gekuendigtOffen {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { gekuendigtGross.toggle() }
            } label: {
                Image(systemName: gross ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.callout.weight(.medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(gross ? "Verkleinern" : "Vergrößern: alle gekündigten Abos mit Details")
            }
        }
    }

    /// Kleine Box neben dem Diagramm: höchstens drei Zeilen, darunter scrollen
    private var gekuendigtBox: some View {
        let zeilenHoehe: CGFloat = 28
        let ueberlauf = gekuendigte.count > gekuendigtSichtbar
        return VStack(alignment: .leading, spacing: 8) {
            gekuendigtKopf(gross: false)
            if gekuendigtOffen {
            Group {
                if ueberlauf {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(gekuendigte) { gekuendigtZeile($0, hoehe: zeilenHoehe) }
                        }
                        .padding(.trailing, 16)
                        .background(SichtbarerScroller())
                    }
                    .frame(height: zeilenHoehe * CGFloat(gekuendigtSichtbar))
                } else {
                    VStack(spacing: 0) {
                        ForEach(gekuendigte) { gekuendigtZeile($0, hoehe: zeilenHoehe) }
                    }
                }
            }
            .padding(.horizontal, -8)
            if ueberlauf {
                Text("\(gekuendigte.count - gekuendigtSichtbar) weitere – scrollen oder vergrößern")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func gekuendigtZeile(_ abo: Abo, hoehe: CGFloat) -> some View {
        GekuendigtZeile(abo: abo, faktor: faktor, hoehe: hoehe, oeffnen: { auswahl = abo })
            .contextMenu { AboMenue(abo: abo, oeffnen: { auswahl = abo }, loeschen: { loeschen(abo) }) }
    }

    /// Vergrößerte Ansicht über die volle Breite mit Kategorie und Ersparnis
    private var gekuendigtGrossAnsicht: some View {
        VStack(alignment: .leading, spacing: 8) {
            gekuendigtKopf(gross: true)
            HStack(spacing: 12) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Kategorie").frame(width: 160, alignment: .leading)
                Text("spart pro Monat").frame(width: 110, alignment: .trailing)
                Text("spart pro Jahr").frame(width: 110, alignment: .trailing)
                Color.clear.frame(width: 120)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            Divider()
            VStack(spacing: 0) {
                ForEach(gekuendigte) { abo in
                    HStack(spacing: 12) {
                        Button { auswahl = abo } label: {
                            HStack(spacing: 12) {
                                Text(abo.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(Auswertung.kategorieName(abo)).lineLimit(1)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 160, alignment: .leading)
                                Text(Format.euro(abo.proMonat)).frame(width: 110, alignment: .trailing)
                                Text(Format.euro(abo.proJahr)).frame(width: 110, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            abo.reaktivieren()
                        } label: {
                            Label("Aktivieren", systemImage: "arrow.uturn.backward")
                                .fixedSize()
                        }
                        .buttonStyle(.borderless)
                        .help("Wieder zu den aktiven Abos nehmen")
                        .frame(width: 120, alignment: .trailing)
                    }
                    .modifier(ZeilenHover(hoehe: 32))
                    .contextMenu { AboMenue(abo: abo, oeffnen: { auswahl = abo }, loeschen: { loeschen(abo) }) }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    // MARK: Tabelle der aktiven Abos

    private var aboListe: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(titel).font(.headline.weight(.medium))
                Text(Sortierung(feld: sortFeld, umgekehrt: sortUmgekehrt).beschreibung)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SuchFeld(text: $tabellenSuche, platzhalter: kategorie.map { "In \($0) suchen" } ?? "In Tabelle suchen")
                    .frame(width: 200)
                Button(action: neu) {
                    Label(kategorie.map { "Neues Abo in \($0)" } ?? "Neues Abo", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 12) {
                SortSpalte(titel: "Name", feld: .name, aktuell: $sortFeld, umgekehrt: $sortUmgekehrt)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SortSpalte(titel: "Kategorie", feld: .kategorie, aktuell: $sortFeld, umgekehrt: $sortUmgekehrt)
                    .frame(width: Spalte.kategorie, alignment: .leading)
                SortSpalte(titel: "Kündigen bis", feld: .frist, aktuell: $sortFeld, umgekehrt: $sortUmgekehrt,
                           ausrichtung: .trailing)
                    .frame(width: Spalte.frist)
                SortSpalte(titel: "pro Monat", feld: .preis, aktuell: $sortFeld, umgekehrt: $sortUmgekehrt,
                           ausrichtung: .trailing)
                    .frame(width: Spalte.betrag)
                SortSpalte(titel: ansicht == .zeitraum ? "Im Zeitraum" : "pro Jahr", feld: .jahr,
                           aktuell: $sortFeld, umgekehrt: $sortUmgekehrt, ausrichtung: .trailing)
                    .frame(width: Spalte.betrag)
                Color.clear.frame(width: Spalte.oeffnen)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            Divider()
            // Lazy: nur sichtbare Zeilen werden aufgebaut
            LazyVStack(spacing: 0) {
                ForEach(tabelle) { abo in
                    aboZeile(abo)
                }
            }
            if tabelle.isEmpty {
                Text(tabellenSuche.isEmpty ? "Keine Abos in dieser Auswahl" : "Nichts gefunden für „\(tabellenSuche)“")
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                Text("Ein Klick auf den Namen öffnet das Abo – Kategorie, Kündigungsdatum und Preise lassen sich direkt hier ändern, der Stift benennt um")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }
        }
    }

    private enum Spalte {
        static let kategorie: CGFloat = 160
        static let frist: CGFloat = 104
        static let betrag: CGFloat = 100
        static let oeffnen: CGFloat = 24
    }

    /// Jede Zelle ist direkt bearbeitbar; der Pfeil rechts öffnet das ganze Abo
    private func aboZeile(_ abo: Abo) -> some View {
        let name = Auswertung.kategorieName(abo)
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                NameFeld(abo: abo, oeffnen: { klick(abo) })
                if !abo.istAktiv {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                        .help("Gekündigt" + (abo.gekuendigtAm.map { " am \(Format.datum($0))" } ?? ""))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            KategorieMenue(abo: abo, alle: abos,
                           farbe: abo.kategorie.isEmpty ? nil : Palette.farbe(rang(name)))
                .frame(width: Spalte.kategorie, alignment: .leading)

            Group {
                if abo.istAktiv {
                    FristFeld(abo: abo, dringlichkeit: dringlichkeit)
                } else {
                    // Gekündigt: hier interessiert, wann gekündigt wurde
                    Text(abo.gekuendigtAm.map(Format.datum) ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .help("Gekündigt am")
                }
            }
            .frame(width: Spalte.frist, alignment: .trailing)

            BetragFeld(abo: abo, faktor: 1)
                .frame(width: Spalte.betrag, alignment: .trailing)
            Group {
                if ansicht == .zeitraum {
                    // Tatsächliche Zahlungen im gewählten Zeitraum (nur Anzeige)
                    let tage = abo.zahltage(von: bereich.start, bis: bereich.ende)
                    Text(Format.euro(abo.kosten(von: bereich.start, bis: bereich.ende)))
                        .monospacedDigit()
                        .foregroundStyle(tage.isEmpty ? .tertiary : .primary)
                        .padding(.horizontal, 6)
                        .help(tage.isEmpty ? "Keine Zahlung in diesem Zeitraum"
                              : "Zahlungen am " + tage.map(Format.datum).joined(separator: ", "))
                } else {
                    BetragFeld(abo: abo, faktor: 12)
                }
            }
            .frame(width: Spalte.betrag, alignment: .trailing)

            Button { auswahl = abo } label: {
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: Spalte.oeffnen, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Alle Details öffnen")
        }
        .modifier(ZeilenHover(hoehe: 40))
        .background(markiert.count > 1 && markiert.contains(abo) ? Color.accentColor.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        // Ein Klick irgendwo in die Zeile öffnet das Abo; Felder und Menüs darin reagieren weiter selbst
        .contentShape(Rectangle())
        .onTapGesture { klick(abo) }
        .contextMenu { AboMenue(abo: abo, oeffnen: { auswahl = abo }, loeschen: { loeschen(abo) }) }
    }

    /// Klick: öffnen. ⌘ oder ⌥: einzeln dazu/weg. ⇧: Bereich in der Reihenfolge der Tabelle.
    private func klick(_ abo: Abo) {
        let tasten = NSEvent.modifierFlags
        if tasten.contains(.shift) {
            let anker = tabellenAnker ?? markiert.first ?? abo
            if let i = tabelle.firstIndex(of: anker), let j = tabelle.firstIndex(of: abo) {
                markiert = Set(tabelle[min(i, j)...max(i, j)])
            }
            tabellenAnker = anker
        } else if tasten.contains(.command) || tasten.contains(.option) {
            if markiert.contains(abo) { markiert.remove(abo) } else { markiert.insert(abo) }
            tabellenAnker = abo
        } else {
            tabellenAnker = abo
            auswahl = abo
        }
    }
}

// MARK: - Bearbeitbare Zellen

/// Gemeinsamer Look: wirkt wie Text, zeigt beim Überfahren und Bearbeiten ein Feld
private struct ZellenRahmen: ViewModifier {
    let hover: Bool
    let fokus: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(Color(nsColor: .textBackgroundColor).opacity(fokus ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
            .background(Color.primary.opacity(hover && !fokus ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(fokus ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1.5))
    }
}

/// Name: ein Klick öffnet das Abo. Zum Umbenennen erscheint beim Überfahren ein Stift.
/// Das Eingabefeld gibt es erst beim Bearbeiten – das hält die Tabelle schnell.
struct NameFeld: View {
    let abo: Abo
    var oeffnen: () -> Void
    @State private var bearbeiten = false
    @State private var text = ""
    @State private var hover = false
    @FocusState private var fokus: Bool

    var body: some View {
        if bearbeiten {
            TextField("Name", text: $text, prompt: Text("Ohne Namen"))
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($fokus)
                .onSubmit { uebernehmen() }
                .onExitCommand { bearbeiten = false }   // Esc verwirft die Änderung
                .onChange(of: fokus) { _, aktiv in if !aktiv { uebernehmen() } }
                .onAppear { text = abo.name; fokus = true }
                .modifier(ZellenRahmen(hover: false, fokus: true))
                .padding(.leading, -6)
        } else {
            HStack(spacing: 6) {
                Button(action: oeffnen) {
                    Text(abo.name.isEmpty ? "Ohne Namen" : abo.name)
                        .lineLimit(1)
                        .foregroundStyle(abo.name.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Abo öffnen")
                Button { bearbeiten = true } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hover ? 1 : 0)
                .help("Umbenennen")
            }
            .onHover { hover = $0 }
        }
    }

    private func uebernehmen() {
        let neu = text.trimmingCharacters(in: .whitespaces)
        if neu != abo.name { abo.name = neu }
        bearbeiten = false
    }
}

/// Eigene Kosten pro Monat oder Jahr; der Betrag pro Zahlung wird daraus zurückgerechnet.
/// Zeigt Text und wird erst beim Klick zum Eingabefeld.
struct BetragFeld: View {
    let abo: Abo
    let faktor: Double
    @State private var bearbeiten = false
    @State private var hover = false
    @FocusState private var fokus: Bool

    private var wert: Binding<Double?> {
        Binding(get: { abo.proMonat.map { $0 * faktor } },
                set: { abo.eigeneKostenSetzen($0, faktor: faktor) })
    }

    var body: some View {
        Group {
            if bearbeiten {
                HStack(spacing: 2) {
                    TextField(faktor == 1 ? "pro Monat" : "pro Jahr", value: wert,
                              format: .number.precision(.fractionLength(2)).locale(Format.locale),
                              prompt: Text("offen"))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($fokus)
                        .onSubmit { bearbeiten = false }
                        .onExitCommand { bearbeiten = false }
                        .onChange(of: fokus) { _, aktiv in if !aktiv { bearbeiten = false } }
                        .onAppear { fokus = true }
                    Text("€").foregroundStyle(.secondary)
                }
                .modifier(ZellenRahmen(hover: false, fokus: true))
            } else {
                Button { bearbeiten = true } label: {
                    Text(Format.euro(abo.proMonat.map { $0 * faktor }))
                        .monospacedDigit()
                        .foregroundStyle(faktor == 1 && abo.betrag != nil ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .modifier(ZellenRahmen(hover: hover, fokus: false))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 }
            }
        }
        .help(hilfe)
    }

    private var hilfe: String {
        var text = "Klicken zum Ändern – dein Anteil \(faktor == 1 ? "pro Monat" : "pro Jahr"), der Betrag pro Zahlung wird umgerechnet"
        if abo.anteilProzent != 100 { text += " (Anteil \(Int(abo.anteilProzent)) %)" }
        return text
    }
}

/// „Kündigen bis“: ein Klick öffnet einen Kalender
struct FristFeld: View {
    let abo: Abo
    let dringlichkeit: Dringlichkeit
    @State private var offen = false
    @State private var hover = false

    private var datum: Binding<Date> {
        Binding(get: { abo.spaetestensKuendigenBis ?? Date() },
                set: { abo.kuendigenBisSetzen($0) })
    }

    var body: some View {
        Button { offen.toggle() } label: {
            Group {
                if let frist = abo.spaetestensKuendigenBis {
                    Text(Format.datum(frist))
                        .monospacedDigit()
                        .foregroundStyle(dringlichkeit.farbe(abo.tageBisFrist()) ?? Color.secondary)
                } else {
                    Text("festlegen").foregroundStyle(.tertiary)
                }
            }
            .modifier(ZellenRahmen(hover: hover || offen, fokus: false))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Kündigungsdatum ändern")
        .popover(isPresented: $offen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spätestens kündigen bis").font(.headline.weight(.medium))
                DatePicker("Kündigen bis", selection: datum, in: Kalender.de.startOfDay(for: Date())...,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Text(erklaerung)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Fertig") { offen = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 260)
        }
    }

    private var erklaerung: String {
        if abo.kuendigenBisFest != nil {
            return "Fester Termin" + (abo.autoVerlaengerung
                ? ", wiederholt sich \(AboDetailView.wiederholText(abo.verlaengerungsSchritt))" : "")
        }
        let frist = AboDetailView.fristText(abo.fristWert, abo.fristEinheit)
        guard let r = abo.naechstesEnde() else { return "" }
        let letzter = Format.datum(Abo.letzterTag(vor: r))
        let teil = frist.map { "Frist \($0) vor dem letzten Tag (\(letzter))" } ?? "Keine Frist, letzter Tag ist der \(letzter)"
        return teil + (abo.autoVerlaengerung ? "; verlängert sich am \(Format.datum(r))" : "")
    }
}

/// Suchfeld im Stil der Seitenleiste
struct SuchFeld: View {
    @Binding var text: String
    var platzhalter = "Suchen"
    var fokus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Group {
                if let fokus {
                    TextField(platzhalter, text: $text).textFieldStyle(.plain).focused(fokus)
                } else {
                    TextField(platzhalter, text: $text).textFieldStyle(.plain)
                }
            }
            // Esc leert die Suche und verlässt das Feld, wie im Finder
            .onExitCommand { text = ""; Fokus.beenden() }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Suche leeren")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Zeile in der Gekündigt-Box; beim Überfahren erscheint „Aktivieren“
struct GekuendigtZeile: View {
    let abo: Abo
    let faktor: Double
    let hoehe: CGFloat
    var oeffnen: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: oeffnen) {
                HStack {
                    Text(abo.name).lineLimit(1)
                    Spacer()
                    Text(Format.euro(abo.proMonat.map { $0 * faktor }))
                        .monospacedDigit()
                        .strikethrough(abo.betrag != nil)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: hoehe)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hover {
                Button("Aktivieren") { abo.reaktivieren() }
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("„\(abo.name)“ wieder zu den aktiven Abos nehmen")
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: hoehe)
        .background(Color.primary.opacity(hover ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hover = $0 }
    }
}

// MARK: - Kreisdiagramm

struct KreisDiagramm: View {
    let kategorien: [KategorieSumme]
    @Binding var kategorie: String?
    let mitte: String
    let mitteUnten: String

    private let innen: CGFloat = 0.64

    private var teile: [(name: String, wert: Double, rang: Int)] {
        var liste: [(name: String, wert: Double, rang: Int)] = []
        for (i, k) in kategorien.enumerated() {
            if let wert = k.proMonat, wert > 0 { liste.append((name: k.name, wert: wert, rang: i)) }
        }
        return liste
    }

    var body: some View {
        Chart(teile, id: \.name) { t in
            SectorMark(angle: .value("Kosten", t.wert),
                       innerRadius: .ratio(innen),
                       angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(Palette.farbe(t.rang))
                .opacity(kategorie == nil || kategorie == t.name ? 1 : 0.25)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 2) {
                Text(mitte)
                    .font(.system(size: 18, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(mitteUnten)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 120)
        }
        .chartOverlay { _ in
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { punkt in
                        tippen(punkt, groesse: geo.size)
                    }
            }
        }
        .animation(.easeOut(duration: 0.18), value: kategorie)
        .accessibilityLabel("Kosten nach Kategorie")
    }

    /// Ermittelt das angeklickte Kreisstück; Klick in die Mitte zeigt wieder alles
    private func tippen(_ punkt: CGPoint, groesse: CGSize) {
        let dx = punkt.x - groesse.width / 2
        let dy = punkt.y - groesse.height / 2
        let abstand = hypot(dx, dy)
        let aussen = min(groesse.width, groesse.height) / 2
        guard abstand <= aussen else { return }
        guard abstand >= aussen * innen else { kategorie = nil; return }

        // Winkel im Uhrzeigersinn ab 12 Uhr
        var winkel = atan2(dx, -dy)
        if winkel < 0 { winkel += 2 * .pi }
        let gesamt = teile.map(\.wert).reduce(0, +)
        let ziel = winkel / (2 * .pi) * gesamt
        var summe = 0.0
        for t in teile {
            summe += t.wert
            if ziel <= summe {
                kategorie = kategorie == t.name ? nil : t.name
                return
            }
        }
    }
}

/// Die Übersicht nur neu berechnen, wenn sich ihre Eingaben wirklich ändern – nicht bei jedem Klick
/// auf ein Abo. Änderungen an einzelnen Abos kommen über die Beobachtung der Abo-Werte trotzdem an.
extension UebersichtView: Equatable {
    static func == (l: UebersichtView, r: UebersichtView) -> Bool {
        l.abos.map(\.persistentModelID) == r.abos.map(\.persistentModelID)
            && l.kategorie == r.kategorie
            && l.gekuendigtOffen == r.gekuendigtOffen
            && l.dringlichkeit == r.dringlichkeit
            && l.markiert == r.markiert
    }
}
