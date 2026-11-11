import AppKit
import SwiftData
import SwiftUI

struct AboDetailView: View {
    @Bindable var abo: Abo
    let dringlichkeit: Dringlichkeit
    /// Wohin der Zurück-Button führt, z. B. "Übersicht" oder "Versicherung"
    let zurueckTitel: String
    var fokusName = false
    var zurueck: () -> Void
    var loeschen: () -> Void
    @Query private var alle: [Abo]
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var nameFokus: Bool
    @State private var verlaufOffen = false
    @State private var eigeneFrist = false
    @State private var eigeneVerlaengerung = false
    @State private var mitteilungen: Mitteilungen.Zustand = .bleibt
    // Beobachtet, damit „Standard: …“ sofort stimmt, wenn die Einstellungen sich ändern
    @AppStorage(StandardErinnerung.ersteSchluessel) private var standard1 = 0
    @AppStorage(StandardErinnerung.zweiteSchluessel) private var standard2 = -1

    var body: some View {
        // Oben bleibt nur eine schmale Leiste; Name, Kennzahlen und Verlauf scrollen mit
        VStack(spacing: 0) {
            leiste
            Divider()
            formular
        }
        .onAppear { if fokusName { nameFokus = true } }
        // Die Karte wird für ein anderes Abo wiederverwendet: kurzlebige Zustände zurücksetzen
        .onChange(of: abo.persistentModelID) { _, _ in
            verlaufOffen = false
            eigeneFrist = false
            eigeneVerlaengerung = false
            if fokusName { nameFokus = true }
        }
        // Esc: erst eine laufende Eingabe beenden, beim nächsten Mal zurück zur Übersicht
        .onExitCommand { if !Fokus.beenden() { zurueck() } }
        .task { mitteilungen = await Mitteilungen.zustand() }
        .onChange(of: scenePhase) { _, neu in
            if neu == .active { Task { mitteilungen = await Mitteilungen.zustand() } }
        }
    }

    // MARK: - Feste Leiste: zurück, Name, nächste Schritte

    private var leiste: some View {
        HStack(spacing: 12) {
            Button(action: zurueck) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").fontWeight(.medium)
                    Text(zurueckTitel)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Zurück zu \(zurueckTitel) (⌘[ oder Esc)")
            Text(abo.name.isEmpty ? "Neues Abo" : abo.name)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            aktionen
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: - Kopf im Formular: Name, Kategorie, Kennzahlen (scrollt mit)

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $abo.name, prompt: Text("Name des Abos"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .font(.system(size: 22, weight: .medium))
                    .focused($nameFokus)
                HStack(spacing: 8) {
                    KategorieMenue(abo: abo, alle: alle)
                    if !abo.istAktiv {
                        Text(abo.gekuendigtAm.map { "Gekündigt am \(Format.datum($0))" } ?? "Gekündigt")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            Divider()
            kennzahlen
        }
        .padding(.vertical, 4)
    }

    /// Der naheliegende nächste Schritt: kündigen (Seite oder E-Mail), als gekündigt markieren oder reaktivieren
    private var aktionen: some View {
        HStack(spacing: 8) {
            if abo.istAktiv {
                if let url = Format.url(abo.kuendigungsLink) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Zur Kündigungsseite", systemImage: "arrow.up.right")
                    }
                    .help(url.absoluteString)
                }
                if let mail = kuendigungsMail {
                    Button {
                        openURL(mail)
                    } label: {
                        Label("Per E-Mail kündigen", systemImage: "envelope")
                    }
                    .help("Öffnet eine fertige Kündigung an \(abo.kontaktEmail) in deinem Mailprogramm")
                }
                Button("Als gekündigt markieren") { abo.kuendigen() }
            } else {
                Button {
                    abo.reaktivieren()
                } label: {
                    Label("Wieder aktivieren", systemImage: "arrow.uturn.backward")
                }
                .help("Das Abo läuft wieder und zählt zu den aktiven Kosten")
            }
        }
    }

    /// Vorformulierte Kündigung; verschickt wird sie erst im Mailprogramm
    private var kuendigungsMail: URL? {
        let nummer = abo.vertragsnummer.trimmingCharacters(in: .whitespaces)
        let betreff = "Kündigung \(abo.name)" + (nummer.isEmpty ? "" : " – Vertragsnr. \(nummer)")
        let text = """
        Sehr geehrte Damen und Herren,

        hiermit kündige ich meinen Vertrag „\(abo.name)“\(nummer.isEmpty ? "" : " (Vertragsnummer \(nummer))") \
        fristgerecht zum nächstmöglichen Zeitpunkt.

        Bitte bestätigen Sie mir die Kündigung und das Vertragsende schriftlich.

        Mit freundlichen Grüßen
        """
        return Format.mail(abo.kontaktEmail, betreff: betreff, text: text)
    }

    private var kennzahlen: some View {
        HStack(alignment: .top, spacing: 0) {
            kennzahl(abo.istAktiv ? "Pro Monat" : "Gespart pro Monat", Format.euro(abo.proMonat))
            trenner
            kennzahl(abo.istAktiv ? "Pro Jahr" : "Gespart pro Jahr", Format.euro(abo.proJahr))
            trenner
            fristKennzahl
        }
    }

    private var trenner: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 44).padding(.horizontal, 16)
    }

    private func kennzahl(_ titel: String, _ wert: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titel).font(.caption).foregroundStyle(.secondary)
            Text(wert)
                .font(.system(size: 18, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(abo.betrag == nil ? .secondary : .primary)
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    private var fristKennzahl: some View {
        HStack(alignment: .center, spacing: 12) {
            fristText
            Spacer(minLength: 0)
            if abo.istAktiv, let frist = abo.spaetestensKuendigenBis {
                let tage = abo.tageBisFrist() ?? 0
                Kalenderblatt(datum: frist, farbe: tage < 0 ? .red : dringlichkeit.farbe(tage))
            }
            verlaufKnopf
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var fristText: some View {
        let letzteKuendigung = abo.verlauf.first { $0.art == .gekuendigt }
        VStack(alignment: .leading, spacing: 4) {
            Text(abo.istAktiv ? "Spätestens kündigen bis" : "Gekündigt am").font(.caption).foregroundStyle(.secondary)
            if !abo.istAktiv {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(abo.gekuendigtAm.map(Format.datum) ?? "Datum unbekannt")
                        .font(.system(size: 18, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(abo.gekuendigtAm == nil ? .secondary : .primary)
                    if let ende = letzteKuendigung?.vertragsende {
                        Text("läuft bis \(Format.datum(Abo.letzterTag(vor: ende)))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let frist = abo.spaetestensKuendigenBis, let tage = abo.tageBisFrist() {
                let farbe = tage < 0 ? Color.red : dringlichkeit.farbe(tage)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.datum(frist))
                        .font(.system(size: 18, weight: .medium))
                        .monospacedDigit()
                    Text(Format.inTagen(tage))
                        .font(.callout)
                        .foregroundStyle(farbe ?? Color.secondary)
                }
            } else {
                Text("Noch keine Frist")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Öffnet den Kündigungsverlauf: wann gekündigt, wann wieder aktiviert
    private var verlaufKnopf: some View {
        let anzahl = abo.verlauf.filter { $0.art != .angelegt }.count
        return Button {
            verlaufOffen.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 15, weight: .medium))
                Text(anzahl > 0 ? "Verlauf (\(anzahl))" : "Verlauf")
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 56, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Verlauf: Kündigungen, Wiederaufnahmen und Preisänderungen")
        .popover(isPresented: $verlaufOffen, arrowEdge: .bottom) {
            KuendigungsVerlauf(abo: abo)
        }
    }

    // MARK: - Formular

    /// Abschnitte wie in einem Formular, aber in einer Lazy-Liste: nur sichtbare Abschnitte
    /// werden aufgebaut – das macht das Öffnen der Karte deutlich schneller
    private var formular: some View {
        ScrollViewReader { leser in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Abschnitt { kopf }
                    .id("oben")

                // Wie sich die Kosten dieses Abos über die Zeit aufsummieren
                Abschnitt {
                    KostenVerlauf(abos: [abo], hoehe: 150)
                } kopfzeile: {
                    HStack {
                        Text("Kostenentwicklung")
                        Spacer()
                        VerlaufZeitraumPicker()
                            .controlSize(.small)
                    }
                }

                Abschnitt("Kosten") {
                    LabeledContent("Betrag") {
                        HStack(spacing: 4) {
                            TextField("Betrag", value: betragBindung,
                                      format: .number.precision(.fractionLength(2)).locale(Format.locale),
                                      prompt: Text("offen"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                            Text("€")
                        }
                    }
                    LabeledContent("Zahlung") {
                        Picker("Zahlung", selection: $abo.intervall) {
                            ForEach(Intervall.allCases) { Text($0.titel).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    if abo.intervall == .eigen {
                        LabeledContent("Alle") {
                            zahlFeld($abo.eigeneMonate, bereich: 1...120, einheit: "Monate")
                        }
                    }
                    LabeledContent("Mein Anteil") {
                        HStack(spacing: 4) {
                            TextField("Anteil", value: $abo.anteilProzent,
                                      format: .number.precision(.fractionLength(0...2)).locale(Format.locale))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("%")
                            Stepper("Anteil", value: $abo.anteilProzent, in: 0...100, step: 5).labelsHidden()
                        }
                    }
                    LabeledContent("Abo seit") {
                        DatePicker("Abo seit", selection: $abo.startdatum, in: Format.datumsBereich,
                                   displayedComponents: .date)
                            .labelsHidden()
                    }
                }

                kuendigungSektion
                erinnerungSektion
                kontaktSektion

                Abschnitt("Notizen") {
                    TextEditor(text: $abo.notizen)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90)
                }

                Abschnitt {
                    Button("Abo löschen…", role: .destructive, action: loeschen)
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        // Anderes Abo: wieder oben anfangen
        .onChange(of: abo.persistentModelID) { _, _ in leser.scrollTo("oben", anchor: .top) }
        }
        .labeledContentStyle(ZeilenStil())
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Kündigung

    /// Zwei Wege wie im Kalender: eine Regel ab dem Verlängerungstag oder ein festes Datum
    private var kuendigungSektion: some View {
        Abschnitt("Kündigung") {
            LabeledContent("Frist angeben als") {
                Picker("Frist angeben als", selection: fristAlsDatum) {
                    Text("Ab Verlängerung").tag(false)
                    Text("Festes Datum").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if abo.kuendigenBisFest != nil {
                LabeledContent("Kündigen bis") {
                    DatePicker("Kündigen bis", selection: festerTermin, in: Format.datumsBereich, displayedComponents: .date)
                        .labelsHidden()
                }
                verlaengerungPicker(titel: "Wiederholen")
            } else {
                if abo.autoVerlaengerung {
                    LabeledContent("Nächste Verlängerung") {
                        DatePicker("Nächste Verlängerung", selection: vertragsende, in: Format.datumsBereich,
                                   displayedComponents: .date)
                            .labelsHidden()
                    }
                    .help("Der Tag, an dem das Abo weiterläuft – meist der Tag der nächsten Zahlung")
                } else {
                    LabeledContent("Läuft bis einschließlich") {
                        DatePicker("Läuft bis einschließlich", selection: letzterTagBindung, in: Format.datumsBereich,
                                   displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                verlaengerungPicker(titel: "Verlängert sich")
                LabeledContent("Kündigungsfrist") {
                    Picker("Kündigungsfrist", selection: fristAuswahl) {
                        ForEach(Self.fristVorgaben, id: \.tag) { Text($0.titel).tag($0.tag) }
                        Divider()
                        Text("Eigene …").tag("eigen")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if fristAuswahl.wrappedValue == "eigen" {
                    LabeledContent("Eigene Frist") {
                        HStack(spacing: 4) {
                            zahlFeld($abo.fristWert, bereich: 0...365, einheit: nil)
                            Picker("Einheit", selection: $abo.fristEinheit) {
                                ForEach(FristEinheit.allCases) { Text($0.titel).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            Text("vor dem letzten Tag")
                        }
                    }
                }
            }

            klartext
        }
    }

    @ViewBuilder
    private func verlaengerungPicker(titel: String) -> some View {
        LabeledContent(titel) {
            Picker(titel, selection: verlaengerungAuswahl) {
                Text(abo.kuendigenBisFest != nil ? "Nie" : "Nicht automatisch").tag(0)
                Divider()
                ForEach(Self.verlaengerungVorgaben, id: \.monate) { Text($0.titel).tag($0.monate) }
                Divider()
                Text("Eigene …").tag(-1)
            }
            .labelsHidden()
            .fixedSize()
        }
        if verlaengerungAuswahl.wrappedValue == -1 {
            LabeledContent(abo.kuendigenBisFest != nil ? "Alle" : "Um") {
                zahlFeld($abo.verlaengerungsSchritt, bereich: 1...120, einheit: "Monate")
            }
        }
    }

    /// Ergebnis als kleine Zeitleiste: kündigen bis → letzter Tag → Verlängerung
    private var klartext: some View {
        HStack(alignment: .top, spacing: 12) {
            if let frist = abo.spaetestensKuendigenBis {
                let tage = abo.tageBisFrist() ?? 0
                let farbe = tage < 0 ? Color.red : dringlichkeit.farbe(tage)
                Kalenderblatt(datum: frist, farbe: farbe)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        zeitpunkt("Kündigen bis", frist, farbe: farbe, betont: true)
                        if abo.kuendigenBisFest == nil, let r = abo.naechstesEnde() {
                            pfeil
                            zeitpunkt("Letzter Tag", Abo.letzterTag(vor: r))
                            if abo.autoVerlaengerung {
                                pfeil
                                zeitpunkt("Verlängert sich", r)
                            }
                        }
                    }
                    Text(klartextErklaerung)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                Text("Trage die nächste Verlängerung ein oder wähle „Festes Datum“")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var klartextErklaerung: String {
        let schritt = abo.verlaengerungsSchritt
        let wiederholung = Self.verlaengerungText(schritt)
        if abo.kuendigenBisFest != nil {
            return abo.autoVerlaengerung
                ? "Der Termin wiederholt sich \(Self.wiederholText(schritt)) und rückt danach automatisch weiter."
                : "Einmaliger Termin."
        }
        let vorher = Self.fristText(abo.fristWert, abo.fristEinheit)
        let frist = vorher.map { "Frist \($0) vor dem letzten Tag." } ?? "Keine Frist: kündigen geht bis einschließlich zum letzten Tag."
        return frist + (abo.autoVerlaengerung
            ? " Ohne Kündigung läuft das Abo \(wiederholung) weiter."
            : " Danach endet das Abo von selbst.")
    }

    private func zeitpunkt(_ titel: String, _ datum: Date, farbe: Color? = nil, betont: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titel).font(.caption).foregroundStyle(.secondary)
            Text(Format.datum(datum))
                .monospacedDigit()
                .fontWeight(betont ? .medium : .regular)
                .foregroundStyle(farbe ?? Color.primary)
        }
    }

    private var pfeil: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .padding(.top, 16)
    }

    // MARK: Erinnerung

    private var erinnerungSektion: some View {
        Abschnitt("Erinnerung") {
            LabeledContent("Erinnere mich") {
                Toggle("Erinnere mich", isOn: erinnernAn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if abo.erinnerungTage != -1 {
                LabeledContent("Wann") {
                    Picker("Wann", selection: $abo.erinnerungTage) {
                        Text(standardText).tag(-2)
                        Divider()
                        ForEach(Self.erinnerungVorgaben, id: \.tage) { Text($0.titel).tag($0.tage) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                LabeledContent("Nächste Mitteilung") {
                    let termine = abo.erinnerungsTermine()
                    if termine.isEmpty {
                        Text(abo.istAktiv ? "keine anstehend" : "Abo ist gekündigt").foregroundStyle(.secondary)
                    } else {
                        Text(termine.map { Format.datumUhrzeit($0.datum) }.joined(separator: "  ·  "))
                            .monospacedDigit()
                    }
                }
                mitteilungsHinweis
            }
        }
    }

    @ViewBuilder
    private var mitteilungsHinweis: some View {
        if mitteilungen != .bleibt {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    switch mitteilungen {
                    case .nichtGefragt:
                        Text("Abos darf noch keine Mitteilungen senden")
                        Button("Mitteilungen erlauben") {
                            Task {
                                await Mitteilungen.berechtigungAnfragen()
                                mitteilungen = await Mitteilungen.zustand()
                            }
                        }
                        .buttonStyle(.link)
                    case .aus:
                        Text("Mitteilungen sind für Abos ausgeschaltet")
                        hinweisStil
                    default:
                        Text("Mitteilungen verschwinden gerade nach ein paar Sekunden")
                        hinweisStil
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var hinweisStil: some View {
        Text("Damit sie stehen bleiben, bis du sie wegklickst: in den Mitteilungseinstellungen bei Abos „Erlauben“ und den Stil „Hinweise“ wählen.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Button("Mitteilungseinstellungen öffnen") { Mitteilungen.systemeinstellungenOeffnen() }
            .buttonStyle(.link)
            .font(.callout)
    }

    private var standardText: String {
        _ = (standard1, standard2)
        let b = StandardErinnerung.beschreibung
        return b == "aus" ? "Standard (in den Einstellungen aus)" : "Standard: \(b)"
    }

    // MARK: Kontakt & Links

    private var kontaktSektion: some View {
        Abschnitt("Kontakt & Links") {
            feldZeile("Website", text: $abo.websiteLink, prompt: "https://…",
                      symbol: "arrow.up.right.square", hilfe: "Im Browser öffnen", ziel: Format.url(abo.websiteLink))
            feldZeile("Kündigungs-Link", text: $abo.kuendigungsLink, prompt: "https://…",
                      symbol: "arrow.up.right.square", hilfe: "Im Browser öffnen", ziel: Format.url(abo.kuendigungsLink))
            feldZeile("Kontakt-E-Mail", text: $abo.kontaktEmail, prompt: "service@…",
                      symbol: "envelope", hilfe: "E-Mail schreiben", ziel: Format.mail(abo.kontaktEmail))
            feldZeile("Telefon", text: $abo.telefon, prompt: "+49 …",
                      symbol: "phone", hilfe: "Anrufen", ziel: Format.telefon(abo.telefon))
            LabeledContent("Kunden-/Vertragsnr.") {
                HStack(spacing: 4) {
                    TextField("Vertragsnummer", text: $abo.vertragsnummer, prompt: Text("optional"))
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(abo.vertragsnummer, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Kopieren")
                    .disabled(abo.vertragsnummer.isEmpty)
                }
            }
        }
    }

    private func feldZeile(_ titel: String, text: Binding<String>, prompt: String,
                           symbol: String, hilfe: String, ziel: URL?) -> some View {
        LabeledContent(titel) {
            HStack(spacing: 4) {
                TextField(titel, text: text, prompt: Text(prompt))
                    .labelsHidden()
                    .frame(maxWidth: 320)
                Button {
                    if let ziel { openURL(ziel) }
                } label: {
                    Image(systemName: symbol)
                }
                .buttonStyle(.borderless)
                .help(hilfe)
                .disabled(ziel == nil)
            }
        }
    }

    private func zahlFeld(_ wert: Binding<Int>, bereich: ClosedRange<Int>, einheit: String?) -> some View {
        HStack(spacing: 4) {
            TextField("Wert", value: wert, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
            Stepper("Wert", value: wert, in: bereich).labelsHidden()
            if let einheit { Text(einheit) }
        }
    }

    // MARK: - Bindungen

    /// Betrag über `betragAendern`, damit Preisänderungen im Verlauf landen
    private var betragBindung: Binding<Double?> {
        Binding(get: { abo.betrag }, set: { abo.betragAendern($0) })
    }

    private var fristAlsDatum: Binding<Bool> {
        Binding(get: { abo.kuendigenBisFest != nil },
                set: { neu in
                    if neu {
                        let vorschlag = abo.spaetestensKuendigenBis
                            ?? Kalender.de.date(byAdding: .month, value: 1, to: Date()) ?? Date()
                        abo.kuendigenBisFest = Kalender.de.startOfDay(for: vorschlag)
                    } else {
                        abo.kuendigenBisFest = nil
                    }
                })
    }

    private var festerTermin: Binding<Date> {
        Binding(get: { abo.kuendigenBisFest ?? Date() },
                set: { abo.kuendigenBisFest = Kalender.de.startOfDay(for: $0) })
    }

    /// Zeigt das nächste (ggf. weitergerollte) Vertragsende; eine Änderung wird zum neuen Ausgangspunkt
    private var vertragsende: Binding<Date> {
        Binding(get: { abo.naechstesEnde() ?? abo.laufzeitende ?? Date() },
                set: { abo.laufzeitende = Kalender.de.startOfDay(for: $0) })
    }

    /// Ohne Verlängerung denkt man in „läuft bis“: gespeichert wird weiterhin der Tag danach
    private var letzterTagBindung: Binding<Date> {
        Binding(get: { (abo.naechstesEnde() ?? abo.laufzeitende).map(Abo.letzterTag(vor:)) ?? Date() },
                set: { abo.laufzeitende = Kalender.de.date(byAdding: .day, value: 1, to: Kalender.de.startOfDay(for: $0)) })
    }

    private var fristAuswahl: Binding<String> {
        Binding(get: {
                    if eigeneFrist { return "eigen" }
                    let tag = Self.fristTag(abo.fristWert, abo.fristEinheit)
                    return Self.fristVorgaben.contains { $0.tag == tag } ? tag : "eigen"
                },
                set: { neu in
                    if neu == "eigen" {
                        eigeneFrist = true
                    } else if let v = Self.fristVorgaben.first(where: { $0.tag == neu }) {
                        eigeneFrist = false
                        abo.fristWert = v.wert
                        abo.fristEinheit = v.einheit
                    }
                })
    }

    /// 0 = keine Verlängerung, -1 = eigene Monatszahl, sonst Monate
    private var verlaengerungAuswahl: Binding<Int> {
        Binding(get: {
                    guard abo.autoVerlaengerung else { return 0 }
                    if eigeneVerlaengerung { return -1 }
                    let schritt = abo.verlaengerungsSchritt
                    return Self.verlaengerungVorgaben.contains { $0.monate == schritt } ? schritt : -1
                },
                set: { neu in
                    switch neu {
                    case 0:
                        // Ohne Verlängerung braucht es ein festes Ende
                        if abo.laufzeitende == nil { abo.laufzeitende = abo.naechstesEnde() }
                        eigeneVerlaengerung = false
                        abo.autoVerlaengerung = false
                    case -1:
                        eigeneVerlaengerung = true
                        abo.autoVerlaengerung = true
                    default:
                        eigeneVerlaengerung = false
                        abo.autoVerlaengerung = true
                        abo.verlaengerungsSchritt = neu
                    }
                })
    }

    private var erinnernAn: Binding<Bool> {
        Binding(get: { abo.erinnerungTage != -1 },
                set: { abo.erinnerungTage = $0 ? -2 : -1 })
    }

    // MARK: - Vorgaben

    private struct FristVorgabe {
        let titel: String
        let wert: Int
        let einheit: FristEinheit
        var tag: String { AboDetailView.fristTag(wert, einheit) }
    }

    private static func fristTag(_ wert: Int, _ einheit: FristEinheit) -> String {
        wert == 0 ? "0" : "\(einheit.rawValue)\(wert)"
    }

    private static let fristVorgaben: [FristVorgabe] = [
        FristVorgabe(titel: "Keine – bis zum letzten Tag", wert: 0, einheit: .tage),
        FristVorgabe(titel: "1 Woche", wert: 1, einheit: .wochen),
        FristVorgabe(titel: "2 Wochen", wert: 2, einheit: .wochen),
        FristVorgabe(titel: "4 Wochen", wert: 4, einheit: .wochen),
        FristVorgabe(titel: "1 Monat", wert: 1, einheit: .monate),
        FristVorgabe(titel: "2 Monate", wert: 2, einheit: .monate),
        FristVorgabe(titel: "3 Monate", wert: 3, einheit: .monate),
        FristVorgabe(titel: "6 Monate", wert: 6, einheit: .monate),
    ]

    private static let verlaengerungVorgaben: [(titel: String, monate: Int)] = [
        ("Jeden Monat", 1), ("Jedes Quartal", 3), ("Jedes halbe Jahr", 6),
        ("Jedes Jahr", 12), ("Alle 2 Jahre", 24),
    ]

    private static let erinnerungVorgaben: [(titel: String, tage: Int)] = [
        ("Am Tag der Frist", 0), ("1 Tag vorher", 1), ("3 Tage vorher", 3),
        ("1 Woche vorher", 7), ("2 Wochen vorher", 14), ("1 Monat vorher", 30),
    ]

    static func verlaengerungText(_ monate: Int) -> String {
        switch monate {
        case 1: return "um einen Monat"
        case 3: return "um ein Quartal"
        case 6: return "um ein halbes Jahr"
        case 12: return "um ein Jahr"
        case 24: return "um zwei Jahre"
        default: return "um \(monate) Monate"
        }
    }

    static func wiederholText(_ monate: Int) -> String {
        switch monate {
        case 1: return "jeden Monat"
        case 3: return "jedes Quartal"
        case 6: return "jedes halbe Jahr"
        case 12: return "jedes Jahr"
        case 24: return "alle 2 Jahre"
        default: return "alle \(monate) Monate"
        }
    }

    /// „3 Monate“, „1 Woche“ … oder nil bei Frist 0
    static func fristText(_ wert: Int, _ einheit: FristEinheit) -> String? {
        guard wert > 0 else { return nil }
        switch einheit {
        case .tage: return wert == 1 ? "1 Tag" : "\(wert) Tage"
        case .wochen: return wert == 1 ? "1 Woche" : "\(wert) Wochen"
        case .monate: return wert == 1 ? "1 Monat" : "\(wert) Monate"
        }
    }
}

// MARK: - Kündigungsverlauf

/// Zeitleiste der Kündigungen; Einträge lassen sich korrigieren, löschen und nachtragen.
/// Änderungen am Verlauf ändern nie den Status des Abos.
struct KuendigungsVerlauf: View {
    @Bindable var abo: Abo
    @State private var nachtragenOffen = false
    @State private var neuArt: VerlaufEintrag.Art = .gekuendigt
    @State private var neuDatum = Date()
    @State private var neuBetrag: Double?
    @State private var leerenFragen = false

    var body: some View {
        let eintraege = abo.verlauf
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Verlauf").font(.headline.weight(.medium))
                Text(abo.name.isEmpty ? "Ohne Namen" : abo.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if eintraege.isEmpty {
                Text(abo.istAktiv
                     ? "Noch keine Einträge. Kündigen und Wiederaktivieren werden hier mit Datum festgehalten."
                     : "Gekündigt, bevor es den Verlauf gab – das Datum ist nicht bekannt. Du kannst es unten nachtragen.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(eintraege.enumerated()), id: \.element.id) { i, e in
                            VerlaufZeile(abo: abo, eintrag: e, letzte: i == eintraege.count - 1)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()
            if nachtragenOffen {
                nachtragenFormular
            } else if leerenFragen {
                HStack(spacing: 8) {
                    Text("Alle \(eintraege.count) Einträge löschen?")
                    Spacer()
                    Button("Abbrechen") { leerenFragen = false }
                    Button("Löschen", role: .destructive) {
                        abo.verlaufLeeren()
                        leerenFragen = false
                    }
                }
                .controlSize(.small)
            } else {
                HStack {
                    Button {
                        neuArt = abo.istAktiv ? .reaktiviert : .gekuendigt
                        neuDatum = Date()
                        nachtragenOffen = true
                    } label: {
                        Label("Eintrag nachtragen", systemImage: "plus")
                    }
                    Spacer()
                    if !eintraege.isEmpty {
                        Button("Verlauf leeren…", role: .destructive) { leerenFragen = true }
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }

    private var nachtragenFormular: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Ereignis", selection: $neuArt) {
                Text("Gekündigt").tag(VerlaufEintrag.Art.gekuendigt)
                Text("Aktiviert").tag(VerlaufEintrag.Art.reaktiviert)
                Text("Preis").tag(VerlaufEintrag.Art.preis)
                Text("Angelegt").tag(VerlaufEintrag.Art.angelegt)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            DatePicker("Zeitpunkt", selection: $neuDatum, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            if neuArt == .preis {
                HStack(spacing: 4) {
                    Text("Neuer Betrag")
                    Spacer()
                    TextField("Betrag", value: $neuBetrag,
                              format: .number.precision(.fractionLength(2)).locale(Format.locale), prompt: Text("0,00"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("€ \(abo.intervall.titel.lowercased())")
                }
                Text("Vorher galt \(Format.euro(abo.betrag(am: neuDatum))) – ab diesem Zeitpunkt rechnet der Kostenverlauf mit dem neuen Betrag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(neuArt == .preis ? "Der aktuelle Betrag des Abos bleibt unverändert"
                                  : "Ändert nur den Verlauf, nicht ob das Abo gerade aktiv oder gekündigt ist")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Abbrechen") { nachtragenOffen = false }
                Button("Hinzufügen") {
                    if neuArt == .preis {
                        abo.protokollieren(VerlaufEintrag(datum: neuDatum, art: .preis, quelle: .app,
                                                          betrag: neuBetrag, alterBetrag: abo.betrag(am: neuDatum),
                                                          intervall: abo.intervallRaw))
                    } else {
                        abo.protokollieren(VerlaufEintrag(datum: neuDatum, art: neuArt, quelle: .app,
                                                          betrag: abo.betrag(am: neuDatum), intervall: abo.intervallRaw))
                    }
                    nachtragenOffen = false
                }
                .disabled(neuArt == .preis && neuBetrag == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Ein Eintrag der Zeitleiste; beim Überfahren erscheint ein Menü zum Korrigieren oder Löschen
struct VerlaufZeile: View {
    @Bindable var abo: Abo
    let eintrag: VerlaufEintrag
    let letzte: Bool

    private enum Modus: Equatable { case normal, datum, loeschen }
    @State private var modus: Modus = .normal
    @State private var datum = Date()
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: eintrag.art.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(eintrag.art == .gekuendigt ? Color.primary : Color.secondary)
                    .frame(width: 20, height: 20)
                if !letzte {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(eintrag.art.titel).fontWeight(.medium)
                    Spacer()
                    if modus == .normal {
                        Menu {
                            Button("Datum ändern…") {
                                datum = eintrag.datum
                                modus = .datum
                            }
                            Button("Eintrag löschen…", role: .destructive) { modus = .loeschen }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .opacity(hover ? 1 : 0)
                        .help("Eintrag korrigieren oder löschen")
                    }
                }
                switch modus {
                case .normal:
                    Text("\(Format.datumUhrzeitLang(eintrag.datum)) · \(eintrag.quelle.titel)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                case .datum:
                    DatePicker("Zeitpunkt", selection: $datum, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    HStack {
                        Button("Abbrechen") { modus = .normal }
                        Button("Übernehmen") {
                            abo.verlaufDatumAendern(eintrag.id, auf: datum)
                            modus = .normal
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .controlSize(.small)
                case .loeschen:
                    Text("Diesen Eintrag endgültig löschen?")
                        .font(.callout)
                    HStack {
                        Button("Abbrechen") { modus = .normal }
                        Button("Löschen", role: .destructive) {
                            abo.verlaufEintragLoeschen(eintrag.id)
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.bottom, letzte ? 0 : 16)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            Button("Datum ändern…") {
                datum = eintrag.datum
                modus = .datum
            }
            Button("Eintrag löschen…", role: .destructive) { modus = .loeschen }
        }
    }

    private var detail: String? {
        let intervall = eintrag.intervall.flatMap(Intervall.init(rawValue:))?.titel.lowercased()
        if eintrag.art == .preis {
            let neu = Format.euro(eintrag.betrag)
            let text = eintrag.alterBetrag.map { "\(Format.euro($0)) → \(neu)" } ?? "neu \(neu)"
            return text + (intervall.map { " \($0)" } ?? "")
        }
        var teile: [String] = []
        if eintrag.art == .gekuendigt, let ende = eintrag.vertragsende {
            teile.append("läuft bis \(Format.datum(Abo.letzterTag(vor: ende)))")
        }
        if eintrag.art != .angelegt, let frist = eintrag.frist { teile.append("Frist \(Format.datum(frist))") }
        if let b = eintrag.betrag { teile.append("Preis \(Format.euro(b))" + (intervall.map { " \($0)" } ?? "")) }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }
}

// MARK: - Formular-Bausteine (schnell, weil ohne macOS-„Form“)

/// Ein Abschnitt wie im grouped Form: Überschrift und eine Karte mit Zeilen, getrennt durch Linien
struct Abschnitt<Inhalt: View, Kopf: View>: View {
    let inhalt: Inhalt
    let kopf: Kopf

    init(@ViewBuilder _ inhalt: () -> Inhalt, @ViewBuilder kopfzeile: () -> Kopf) {
        self.inhalt = inhalt()
        self.kopf = kopfzeile()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            kopf
                .font(.headline.weight(.medium))
                .padding(.horizontal, 4)
            _VariadicView.Tree(MitTrennlinien()) { inhalt }
                .padding(.horizontal, 12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

extension Abschnitt where Kopf == EmptyView {
    init(@ViewBuilder _ inhalt: () -> Inhalt) {
        self.init(inhalt, kopfzeile: { EmptyView() })
    }
}

extension Abschnitt where Kopf == Text {
    init(_ titel: String, @ViewBuilder _ inhalt: () -> Inhalt) {
        self.init(inhalt, kopfzeile: { Text(titel) })
    }
}

/// Setzt eine feine Linie zwischen die Zeilen eines Abschnitts
private struct MitTrennlinien: _VariadicView_UnaryViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let letzte = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { zeile in
                zeile.padding(.vertical, 8)
                if zeile.id != letzte { Divider() }
            }
        }
    }
}

/// Bezeichnung links, Bedienelement rechts – wie in den Systemeinstellungen
struct ZeilenStil: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            configuration.content
        }
    }
}

/// Die Karte nur neu berechnen, wenn sich das Abo oder die Anzeige-Parameter ändern
extension AboDetailView: Equatable {
    static func == (l: AboDetailView, r: AboDetailView) -> Bool {
        l.abo.persistentModelID == r.abo.persistentModelID
            && l.zurueckTitel == r.zurueckTitel
            && l.fokusName == r.fokusName
            && l.dringlichkeit == r.dringlichkeit
    }
}
