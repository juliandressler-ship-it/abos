import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Abo.name) private var abos: [Abo]
    @State private var auswahl: Abo?
    @State private var kategorieFilter: String?
    @State private var suche = ""
    @State private var zuLoeschen: Abo?
    /// Gekündigt-Box in der Übersicht: beim Start zu, bleibt offen bis man sie schließt
    @State private var gekuendigtOffen = false
    /// Frisch angelegtes Abo: Namensfeld bekommt den Fokus
    @State private var neuAngelegt: PersistentIdentifier?
    @FocusState private var sucheAktiv: Bool
    @AppStorage(StandardErinnerung.ersteSchluessel) private var standard1 = 0
    @AppStorage(StandardErinnerung.zweiteSchluessel) private var standard2 = -1
    @AppStorage("sortFeld") private var sortFeld: SortFeld = .name
    @AppStorage("sortUmgekehrt") private var sortUmgekehrt = false

    /// Farben der Fristen: orange ab 14 Tagen, rot ab 3 Tagen (unabhängig von den Mitteilungen)
    private var dringlichkeit: Dringlichkeit { Dringlichkeit(14, 3) }

    private var gefiltert: [Abo] {
        let s = suche.trimmingCharacters(in: .whitespaces)
        let basis = s.isEmpty ? abos : abos.filter {
            $0.name.localizedCaseInsensitiveContains(s)
                || $0.kategorie.localizedCaseInsensitiveContains(s)
                || $0.notizen.localizedCaseInsensitiveContains(s)
        }
        return Sortierung(feld: sortFeld, umgekehrt: sortUmgekehrt).sortiert(basis)
    }

    /// Ändert sich, sobald Erinnerungen neu geplant werden müssen
    private var planSignatur: String {
        let teile = abos.map { a in
            "\(a.uuid)|\(a.name)|\(a.kuendigenBisFest?.timeIntervalSince1970 ?? 0)|\(a.statusRaw)|\(a.spaetestensKuendigenBis?.timeIntervalSince1970 ?? 0)|"
                + "\(a.erledigtFuerFrist?.timeIntervalSince1970 ?? 0)|\(a.erneutErinnernAm?.timeIntervalSince1970 ?? 0)"
        }
        return teile.joined(separator: ";") + "#\(standard1)#\(standard2)"
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardView(abos: abos, auswahl: $auswahl, kategorie: $kategorieFilter, dringlichkeit: dringlichkeit)
            Divider()
            HSplitView {
                seitenleiste
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
                Group {
                    if let abo = auswahl {
                        AboDetailView(abo: abo, dringlichkeit: dringlichkeit,
                                      zurueckTitel: kategorieFilter ?? "Übersicht",
                                      fokusName: neuAngelegt == abo.persistentModelID,
                                      zurueck: { auswahl = nil },
                                      loeschen: { zuLoeschen = abo })
                            .id(abo.persistentModelID)
                    } else {
                        UebersichtView(abos: abos, kategorie: $kategorieFilter, auswahl: $auswahl,
                                       gekuendigtOffen: $gekuendigtOffen,
                                       dringlichkeit: dringlichkeit, neu: neu,
                                       loeschen: { zuLoeschen = $0 })
                    }
                }
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(fensterTitel)
        .toolbar {
            ToolbarItemGroup {
                Button(action: neu) { Label("Neues Abo", systemImage: "plus") }
                    .help("Neues Abo anlegen (⌘N)")
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .onDeleteCommand { if let a = auswahl { zuLoeschen = a } }
        .confirmationDialog("„\(zuLoeschen?.name ?? "")“ löschen?",
                            isPresented: Binding(get: { zuLoeschen != nil }, set: { if !$0 { zuLoeschen = nil } })) {
            Button("Löschen", role: .destructive) {
                if let a = zuLoeschen { loeschen(a) }
            }
            Button("Abbrechen", role: .cancel) { zuLoeschen = nil }
        } message: {
            Text("Statt zu löschen kannst du ein Abo auch auf „Gekündigt“ setzen.")
        }
        // ⌘Z / ⇧⌘Z / ⌘Y: Änderungen an Abos über das Widerrufen-Menü des Fensters
        // Für die Menüs: ⌘N, ⌘F, ⌘K, ⌘⌫, ⌘[
        .focusedSceneValue(\.aboAuswahl, $auswahl)
        .focusedSceneValue(\.fensterAktionen, FensterAktionen(neu: neu,
                                                              suchen: { sucheAktiv = true },
                                                              loeschen: { zuLoeschen = $0 }))
        .onAppear { context.undoManager = undoManager }
        .onChange(of: undoManager) { _, neu in context.undoManager = neu }
        .task { await Mitteilungen.berechtigungAnfragen() }
        .task(id: planSignatur) { Mitteilungen.planen(context: context) }
        .onChange(of: scenePhase) { _, neu in
            if neu == .active { Mitteilungen.planen(context: context) }
        }
    }

    private var fensterTitel: String {
        if let abo = auswahl { return abo.name.isEmpty ? "Abo" : abo.name }
        return kategorieFilter ?? "Übersicht"
    }

    private var seitenleiste: some View {
        VStack(spacing: 8) {
            SuchFeld(text: $suche, fokus: $sucheAktiv)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            SortierLeiste(feld: $sortFeld, umgekehrt: $sortUmgekehrt)
                .padding(.horizontal, 12)

            liste
        }
    }

    private var liste: some View {
        let aktive = gefiltert.filter(\.istAktiv)
        let gekuendigte = gefiltert.filter { !$0.istAktiv }
        return List(selection: $auswahl) {
            if !aktive.isEmpty {
                Section {
                    ForEach(aktive) { zeile($0) }
                } header: {
                    HStack {
                        Text("Aktiv")
                        Spacer()
                        Text("pro Monat").fontWeight(.regular)
                    }
                }
            }
            if !gekuendigte.isEmpty {
                Section("Gekündigt") {
                    ForEach(gekuendigte) { zeile($0) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func zeile(_ abo: Abo) -> some View {
        AboZeile(abo: abo, dringlichkeit: dringlichkeit)
            .tag(abo)
            .contextMenu {
                AboMenue(abo: abo, oeffnen: { auswahl = abo }, loeschen: { zuLoeschen = abo })
            }
    }

    private func neu() {
        // In einer gefilterten Kategorie landet das neue Abo direkt dort
        let kategorie = kategorieFilter == "Ohne Kategorie" ? "" : (kategorieFilter ?? "")
        let abo = Abo(name: "", kategorie: kategorie)
        abo.protokollieren(VerlaufEintrag(art: .angelegt, quelle: .app))
        context.insert(abo)
        try? context.save()
        suche = ""
        neuAngelegt = abo.persistentModelID
        auswahl = abo
    }

    private func loeschen(_ abo: Abo) {
        if auswahl == abo { auswahl = nil }
        zuLoeschen = nil
        context.delete(abo)
        try? context.save()
    }
}

// MARK: - Dringlichkeit

/// Farbe einer Frist richtet sich nach den eingestellten Erinnerungen:
/// innerhalb des längeren Vorlaufs orange, innerhalb des kürzeren rot, sonst neutral.
struct Dringlichkeit {
    let bald: Int
    let akut: Int

    init(_ v1: Int, _ v2: Int) {
        let aktiv = [v1, v2].filter { $0 > 0 }
        bald = aktiv.max() ?? 14
        akut = aktiv.count > 1 ? (aktiv.min() ?? 3) : min(3, bald)
    }

    func farbe(_ tage: Int?) -> Color? {
        guard let tage else { return nil }
        if tage <= akut { return .red }
        if tage <= bald { return .orange }
        return nil
    }
}

// MARK: - Listenzeile

struct AboZeile: View {
    let abo: Abo
    let dringlichkeit: Dringlichkeit

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(abo.name.isEmpty ? "Ohne Namen" : abo.name)
                    .lineLimit(1)
                if !abo.kategorie.isEmpty {
                    Text(abo.kategorie)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if abo.istAktiv, let tage = abo.tageBisFrist(), tage >= 0, let farbe = dringlichkeit.farbe(tage) {
                Text(tage == 0 ? "heute" : "\(tage) T")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(farbe)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(farbe.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                    .help("Kündigungsfrist \(Format.inTagen(tage))")
            }
            Text(Format.euro(abo.proMonat))
                .monospacedDigit()
                .foregroundStyle(abo.betrag == nil || !abo.istAktiv ? .secondary : .primary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Kalenderblatt (Signatur)

/// Ein kleines Abreißkalender-Blatt für Kündigungsdaten.
/// Der Kopf färbt sich nur, wenn die Frist in den Erinnerungs-Vorlauf fällt.
struct Kalenderblatt: View {
    let datum: Date
    var farbe: Color?

    var body: some View {
        VStack(spacing: 0) {
            Text(datum.formatted(.dateTime.month(.abbreviated).locale(Format.locale)))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(farbe ?? Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .background((farbe ?? Color.primary).opacity(farbe == nil ? 0.06 : 0.16))
            Text(datum.formatted(.dateTime.day().locale(Format.locale)))
                .font(.system(size: 18, weight: .medium))
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 40, height: 44)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.datum(datum))
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    let abos: [Abo]
    @Binding var auswahl: Abo?
    @Binding var kategorie: String?
    let dringlichkeit: Dringlichkeit
    @AppStorage("zeitraumJahr") private var jahr = false
    @AppStorage("kostenEinheit") private var einheit: KostenEinheit = .monat

    private var aktive: [Abo] { abos.filter(\.istAktiv) }
    private var faktor: Double { jahr ? 12 : einheit.faktor }
    private var monatOderJahr: Binding<KostenAnsicht> {
        Binding(get: { jahr ? .jahr : .monat }, set: { jahr = $0 == .jahr })
    }
    private var summe: Double { aktive.compactMap(\.proMonat).reduce(0, +) * faktor }
    private var ohneBetrag: Int { aktive.filter { $0.betrag == nil }.count }
    private var kategorien: [KategorieSumme] { Auswertung.kategorien(abos) }
    private var zeigtGesamt: Bool { auswahl == nil && kategorie == nil }

    private var naechsteFristen: [(abo: Abo, frist: Date)] {
        var liste: [(abo: Abo, frist: Date)] = []
        for a in aktive {
            if let frist = a.spaetestensKuendigenBis { liste.append((abo: a, frist: frist)) }
        }
        liste.sort { l, r in
            if l.frist != r.frist { return l.frist < r.frist }
            return l.abo.name < r.abo.name
        }
        return liste
    }

    /// Erstes sichtbares Kalenderblatt für die Pfeil-Knöpfe
    @State private var fristStart = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            gesamt.frame(width: 300)
            fristen.frame(maxWidth: .infinity)
            kategorieListe.frame(width: 260)
        }
        .padding(16)
        .frame(height: 200)
    }

    // Gesamtsumme; ein Klick öffnet die Übersicht
    private var gesamt: some View {
        Karte(hervorgehoben: zeigtGesamt) {
            HStack(spacing: 4) {
                Text("Gesamt").font(.headline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                KostenUmschalter(ansicht: monatOderJahr, kompakt: true)
            }
            Spacer(minLength: 0)
            Text(Format.euro(summe))
                .font(.system(size: 32, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: jahr)
            Text((jahr ? "pro Jahr" : einheit.text) + " · \(Format.anzahl(aktive.count, "aktives Abo", "aktive Abos"))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            stapelBalken
            if ohneBetrag > 0 {
                Text(Format.anzahl(ohneBetrag, "Abo", "Abos") + " ohne Betrag")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            auswahl = nil
            kategorie = nil
        }
        .help("Übersicht öffnen")
    }

    private var stapelBalken: some View {
        var teile: [(rang: Int, wert: Double)] = []
        for (i, k) in kategorien.enumerated() {
            if let w = k.proMonat, w > 0 { teile.append((rang: i, wert: w)) }
        }
        let gesamt = teile.map(\.wert).reduce(0, +)
        return GeometryReader { geo in
            let luecke: CGFloat = 2
            let breite = geo.size.width - luecke * CGFloat(max(teile.count - 1, 0))
            HStack(spacing: luecke) {
                ForEach(teile, id: \.rang) { t in
                    Rectangle()
                        .fill(Palette.farbe(t.rang))
                        .frame(width: gesamt > 0 ? max(2, breite * t.wert / gesamt) : 0)
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }

    // Nächste Fristen wie Blätter eines Wandkalenders
    /// Alle anstehenden Fristen; nach rechts scrollen (Trackpad) oder mit den Pfeilen blättern
    private var fristen: some View {
        let liste = naechsteFristen
        return Karte {
            HStack(spacing: 8) {
                Text("Nächste Kündigungsfristen").font(.headline.weight(.medium))
                if liste.count > 0 {
                    Text("\(liste.count)").font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                }
                Spacer()
                if liste.count > 4 {
                    Button { fristStart = max(0, fristStart - 3) } label: { Image(systemName: "chevron.left") }
                        .disabled(fristStart == 0)
                        .help("Frühere Fristen")
                    Button { fristStart = min(liste.count - 1, fristStart + 3) } label: { Image(systemName: "chevron.right") }
                        .disabled(fristStart >= liste.count - 4)
                        .help("Spätere Fristen")
                }
            }
            .buttonStyle(.borderless)
            if liste.isEmpty {
                Spacer(minLength: 0)
                Text("Keine Fristen hinterlegt").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                ScrollViewReader { leser in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(Array(liste.enumerated()), id: \.offset) { i, eintrag in
                                fristBlatt(eintrag.abo, eintrag.frist)
                                    .frame(width: 128)
                                    .id(i)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: fristStart) { _, neu in
                        withAnimation(.easeOut(duration: 0.25)) { leser.scrollTo(neu, anchor: .leading) }
                    }
                }
                .padding(.horizontal, -8)
                .padding(.bottom, -8)
            }
        }
    }

    private func fristBlatt(_ abo: Abo, _ frist: Date) -> some View {
        let tage = abo.tageBisFrist() ?? 0
        let farbe = dringlichkeit.farbe(tage)
        return Button {
            auswahl = abo
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Kalenderblatt(datum: frist, farbe: farbe)
                    .padding(.bottom, 4)
                Text(abo.name)
                    .lineLimit(1)
                Text(Format.inTagen(tage))
                    .font(.caption)
                    .foregroundStyle(farbe ?? Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .contentShape(Rectangle())
            .background(auswahl == abo ? Color.primary.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Spätestens kündigen bis \(Format.datum(frist))")
    }

    // Rangliste der Kategorien; ein Klick zeigt die Kategorie in der Übersicht
    private var kategorieListe: some View {
        Karte {
            Text("Kosten pro Kategorie").font(.headline.weight(.medium))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(kategorien.enumerated()), id: \.element.id) { i, k in
                        KlickZeile(aktiv: auswahl == nil && kategorie == k.name, hoehe: 24,
                                   aktion: {
                                       auswahl = nil
                                       kategorie = kategorie == k.name ? nil : k.name
                                   }) {
                            HStack(spacing: 8) {
                                Farbpunkt(farbe: k.proMonat == nil ? Color.primary.opacity(0.12) : Palette.farbe(i))
                                Text(k.name).lineLimit(1)
                                Spacer()
                                Text(Format.euro(k.proMonat.map { $0 * faktor }))
                                    .monospacedDigit()
                                    .foregroundStyle(k.proMonat == nil ? .secondary : .primary)
                            }
                            .font(.callout)
                        }
                    }
                }
                .padding(.horizontal, -8)
            }
            .scrollIndicators(.never)
        }
    }
}

struct Karte<Inhalt: View>: View {
    let hervorgehoben: Bool
    let inhalt: Inhalt

    init(hervorgehoben: Bool = false, @ViewBuilder inhalt: () -> Inhalt) {
        self.hervorgehoben = hervorgehoben
        self.inhalt = inhalt()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { inhalt }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(hervorgehoben ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08)))
    }
}
