import Foundation
import SwiftData

// MARK: - Auswahlwerte

enum Intervall: String, CaseIterable, Identifiable {
    case monatlich, quartal, jaehrlich, eigen
    var id: String { rawValue }
    var titel: String {
        switch self {
        case .monatlich: return "Monatlich"
        case .quartal: return "Quartal"
        case .jaehrlich: return "Jährlich"
        case .eigen: return "Eigen"
        }
    }
}

enum FristEinheit: String, CaseIterable, Identifiable {
    case tage, wochen, monate
    var id: String { rawValue }
    var titel: String {
        switch self {
        case .tage: return "Tage"
        case .wochen: return "Wochen"
        case .monate: return "Monate"
        }
    }
}

enum AboStatus: String, CaseIterable, Identifiable {
    case aktiv, gekuendigt
    var id: String { rawValue }
    var titel: String { self == .aktiv ? "Aktiv" : "Gekündigt" }
}

// MARK: - Datenmodell

@Model
final class Abo {
    var uuid: UUID = UUID()
    var name: String = ""
    var kategorie: String = ""
    /// nil = Betrag noch offen
    var betrag: Double? = nil
    var intervallRaw: String = Intervall.monatlich.rawValue
    var eigeneMonate: Int = 2
    var startdatum: Date = Date()
    var laufzeitende: Date? = nil
    var fristWert: Int = 0
    var fristEinheitRaw: String = FristEinheit.monate.rawValue
    /// Fest eingetragener Kündigungstermin; ersetzt die Berechnung über die Frist
    var kuendigenBisFest: Date? = nil
    var autoVerlaengerung: Bool = true
    /// Verlängerung um X Monate; 0 = wie das Zahlungsintervall
    var verlaengerungMonate: Int = 0
    var anteilProzent: Double = 100
    var statusRaw: String = AboStatus.aktiv.rawValue
    var websiteLink: String = ""
    var kuendigungsLink: String = ""
    var kontaktEmail: String = ""
    var telefon: String = ""
    /// Kunden- oder Vertragsnummer (keine Zugangsdaten)
    var vertragsnummer: String = ""
    /// Erinnerung: -2 = Standard aus den Einstellungen, -1 = keine, sonst Tage vor der Frist (0 = am Tag)
    var erinnerungTage: Int = -2
    /// Kündigungsverlauf als JSON (Liste von VerlaufEintrag); als Text gespeichert, damit die Migration simpel bleibt
    var verlaufJSON: String = ""
    var notizen: String = ""
    /// Frist, für die per Mitteilung "Erledigt" gewählt wurde (keine weiteren Erinnerungen dafür)
    var erledigtFuerFrist: Date? = nil
    /// "In 1 Woche erneut": Zeitpunkt der nächsten Erinnerung
    var erneutErinnernAm: Date? = nil
    var erstelltAm: Date = Date()

    init(name: String = "",
         kategorie: String = "",
         betrag: Double? = nil,
         intervall: Intervall = .monatlich,
         status: AboStatus = .aktiv) {
        self.name = name
        self.kategorie = kategorie
        self.betrag = betrag
        self.intervallRaw = intervall.rawValue
        self.statusRaw = status.rawValue
        self.startdatum = Kalender.de.startOfDay(for: Date())
    }
}

// MARK: - Berechnungen

extension Abo {
    var intervall: Intervall {
        get { Intervall(rawValue: intervallRaw) ?? .monatlich }
        set { intervallRaw = newValue.rawValue }
    }

    var fristEinheit: FristEinheit {
        get { FristEinheit(rawValue: fristEinheitRaw) ?? .monate }
        set { fristEinheitRaw = newValue.rawValue }
    }

    var status: AboStatus {
        get { AboStatus(rawValue: statusRaw) ?? .aktiv }
        set { statusRaw = newValue.rawValue }
    }

    var istAktiv: Bool { status == .aktiv }

    var monateProIntervall: Int {
        switch intervall {
        case .monatlich: return 1
        case .quartal: return 3
        case .jaehrlich: return 12
        case .eigen: return max(1, eigeneMonate)
        }
    }

    /// Um so viele Monate verlängert sich der Vertrag automatisch
    var verlaengerungsSchritt: Int {
        get { verlaengerungMonate > 0 ? verlaengerungMonate : monateProIntervall }
        set { verlaengerungMonate = max(1, newValue) }
    }

    /// Eigener Kostenanteil pro Monat (Anteil und Intervall berücksichtigt)
    var proMonat: Double? {
        guard let betrag else { return nil }
        return betrag * max(0, anteilProzent) / 100 / Double(monateProIntervall)
    }

    var proJahr: Double? { proMonat.map { $0 * 12 } }

    /// Zeitlogik in einem Satz: Am **Verlängerungstag** (nächste Zahlung) läuft das Abo weiter.
    /// Der Tag davor ist der **letzte Tag der Laufzeit**. Die Kündigungsfrist zählt ab diesem letzten Tag;
    /// ohne Frist kann man bis einschließlich zum letzten Tag kündigen.
    /// `laufzeitende` und `naechstesEnde()` meinen deshalb immer den Verlängerungstag.

    /// Letzter Tag der Laufzeit vor einem Verlängerungstag
    static func letzterTag(vor verlaengerung: Date) -> Date {
        Kalender.de.date(byAdding: .day, value: -1, to: verlaengerung) ?? verlaengerung
    }

    /// Spätestes Kündigungsdatum für einen Verlängerungstag: letzter Tag der Laufzeit minus Frist
    func fristDatum(fuerEnde verlaengerung: Date) -> Date {
        let cal = Kalender.de
        let letzter = Abo.letzterTag(vor: verlaengerung)
        switch fristEinheit {
        case .tage: return cal.date(byAdding: .day, value: -fristWert, to: letzter) ?? letzter
        case .wochen: return cal.date(byAdding: .day, value: -7 * fristWert, to: letzter) ?? letzter
        case .monate: return cal.date(byAdding: .month, value: -fristWert, to: letzter) ?? letzter
        }
    }

    /// Nächster Verlängerungstag (Tag der nächsten Zahlung). Bei automatischer Verlängerung rollt er
    /// um die Verlängerungsdauer weiter, bis die Kündigungsfrist nicht mehr in der Vergangenheit liegt.
    func naechstesEnde(heute: Date = Date()) -> Date? {
        let cal = Kalender.de
        let tagesbeginn = cal.startOfDay(for: heute)
        let schritt = verlaengerungsSchritt

        let anker: Date
        var k: Int
        if let ende = laufzeitende {
            guard autoVerlaengerung else { return ende }
            anker = ende
            k = 0
        } else {
            guard autoVerlaengerung else { return nil }
            anker = startdatum
            k = 1
        }

        // Grob vorspringen, damit weit zurückliegende Daten nicht lange schleifen
        let monateSeitAnker = cal.dateComponents([.month], from: anker, to: tagesbeginn).month ?? 0
        k = max(k, monateSeitAnker / schritt - 1)

        var kandidat = cal.date(byAdding: .month, value: k * schritt, to: anker) ?? anker
        var sicherung = 0
        while cal.startOfDay(for: fristDatum(fuerEnde: kandidat)) < tagesbeginn && sicherung < 1000 {
            k += 1
            sicherung += 1
            kandidat = cal.date(byAdding: .month, value: k * schritt, to: anker) ?? kandidat
        }
        return kandidat
    }

    /// "Spätestens kündigen bis"
    var spaetestensKuendigenBis: Date? {
        if let fest = kuendigenBisFest { return naechsterFesterTermin(fest) }
        return naechstesEnde().map { fristDatum(fuerEnde: $0) }
    }

    /// „Kündigen bis“ direkt setzen. Bei festem Datum wird das Datum ersetzt; bei einer Frist
    /// vor Vertragsende bleibt die Frist gleich und das Vertragsende wird passend verschoben.
    func kuendigenBisSetzen(_ datum: Date) {
        let cal = Kalender.de
        let tag = cal.startOfDay(for: datum)
        if kuendigenBisFest != nil {
            kuendigenBisFest = tag
            return
        }
        let letzter: Date
        switch fristEinheit {
        case .tage: letzter = cal.date(byAdding: .day, value: fristWert, to: tag) ?? tag
        case .wochen: letzter = cal.date(byAdding: .day, value: 7 * fristWert, to: tag) ?? tag
        case .monate: letzter = cal.date(byAdding: .month, value: fristWert, to: tag) ?? tag
        }
        let ende = cal.date(byAdding: .day, value: 1, to: letzter) ?? letzter
        if cal.isDate(fristDatum(fuerEnde: ende), inSameDayAs: tag) {
            laufzeitende = ende
        } else {
            // Am Monatsende nicht über die Frist darstellbar (z. B. 31.03. bei 3 Monaten):
            // dann gilt das gewählte Datum als fester Termin
            kuendigenBisFest = tag
        }
    }

    /// Eigene Kosten pro Monat (faktor 1) oder Jahr (faktor 12) setzen; daraus wird der Betrag
    /// pro Zahlung zurückgerechnet (Intervall und Anteil bleiben gleich)
    func eigeneKostenSetzen(_ wert: Double?, faktor: Double) {
        guard let wert else { betrag = nil; return }
        if let alt = proMonat.map({ $0 * faktor }), abs(alt - wert) < 0.005 { return }
        let anteil = max(0, anteilProzent) / 100
        guard anteil > 0 else { return }
        betrag = max(0, wert) / faktor * Double(monateProIntervall) / anteil
    }

    /// Ein fester Termin rollt bei automatischer Verlängerung um die Verlängerungsdauer weiter
    func naechsterFesterTermin(_ fest: Date, heute: Date = Date()) -> Date {
        guard autoVerlaengerung else { return fest }
        let cal = Kalender.de
        let tagesbeginn = cal.startOfDay(for: heute)
        var kandidat = fest
        var k = 0
        while cal.startOfDay(for: kandidat) < tagesbeginn && k < 1000 {
            k += 1
            kandidat = cal.date(byAdding: .month, value: k * verlaengerungsSchritt, to: fest) ?? kandidat
        }
        return kandidat
    }

    /// Tage vor der Frist, an denen eine Mitteilung kommt
    var erinnerungsVorlaeufe: [Int] {
        switch erinnerungTage {
        case -1: return []
        case -2:
            let d = UserDefaults.standard
            return Array(Set([d.integer(forKey: "vorlauf1"), d.integer(forKey: "vorlauf2")].filter { $0 > 0 }))
                .sorted(by: >)
        default: return [max(0, erinnerungTage)]
        }
    }

    /// Konkrete Erinnerungszeitpunkte (jeweils 9:00 Uhr), nur zukünftige
    func erinnerungsTermine(jetzt: Date = Date()) -> [(vorlauf: Int, datum: Date)] {
        guard istAktiv, let frist = spaetestensKuendigenBis else { return [] }
        let cal = Kalender.de
        var liste: [(vorlauf: Int, datum: Date)] = []
        for vorlauf in erinnerungsVorlaeufe {
            guard let tag = cal.date(byAdding: .day, value: -vorlauf, to: frist),
                  let ziel = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tag),
                  ziel > jetzt else { continue }
            liste.append((vorlauf: vorlauf, datum: ziel))
        }
        return liste
    }

    /// Kündigen und im Verlauf festhalten, welche Frist und welches Vertragsende galten
    func kuendigen(quelle: VerlaufEintrag.Quelle = .app) {
        guard istAktiv else { return }
        let frist = spaetestensKuendigenBis
        let ende = naechstesEnde()
        status = .gekuendigt
        erneutErinnernAm = nil
        protokollieren(VerlaufEintrag(art: .gekuendigt, quelle: quelle, frist: frist, vertragsende: ende))
    }

    /// Ein gekündigtes Abo läuft weiter; alte Erinnerungs-Markierungen werden verworfen
    func reaktivieren(quelle: VerlaufEintrag.Quelle = .app) {
        guard !istAktiv else { return }
        status = .aktiv
        erledigtFuerFrist = nil
        erneutErinnernAm = nil
        protokollieren(VerlaufEintrag(art: .reaktiviert, quelle: quelle, frist: spaetestensKuendigenBis,
                                      vertragsende: naechstesEnde()))
    }

    // MARK: Verlauf

    /// Neueste Einträge zuerst
    var verlauf: [VerlaufEintrag] {
        guard let daten = verlaufJSON.data(using: .utf8), !verlaufJSON.isEmpty,
              let liste = try? VerlaufEintrag.decoder.decode([VerlaufEintrag].self, from: daten)
        else { return [] }
        return liste.sorted { $0.datum > $1.datum }
    }

    func protokollieren(_ eintrag: VerlaufEintrag) {
        verlaufSpeichern(verlauf + [eintrag])
    }

    /// Korrektur: Zeitpunkt eines Eintrags ändern
    func verlaufDatumAendern(_ id: UUID, auf datum: Date) {
        verlaufSpeichern(verlauf.map { e in
            var e = e
            if e.id == id { e.datum = datum }
            return e
        })
    }

    func verlaufEintragLoeschen(_ id: UUID) {
        verlaufSpeichern(verlauf.filter { $0.id != id })
    }

    func verlaufLeeren() {
        verlaufJSON = ""
    }

    private func verlaufSpeichern(_ liste: [VerlaufEintrag]) {
        let sortiert = liste.sorted { $0.datum < $1.datum }
        guard !sortiert.isEmpty, let daten = try? VerlaufEintrag.encoder.encode(sortiert) else {
            verlaufJSON = ""
            return
        }
        verlaufJSON = String(decoding: daten, as: UTF8.self)
    }

    /// Wann zuletzt gekündigt wurde (nur wenn das Abo gerade gekündigt ist)
    var gekuendigtAm: Date? {
        guard !istAktiv else { return nil }
        return verlauf.first { $0.art == .gekuendigt }?.datum
    }

    /// Tage bis zur Kündigungsfrist (negativ = verstrichen)
    func tageBisFrist(heute: Date = Date()) -> Int? {
        guard let frist = spaetestensKuendigenBis else { return nil }
        let cal = Kalender.de
        return cal.dateComponents([.day], from: cal.startOfDay(for: heute), to: cal.startOfDay(for: frist)).day
    }
}

// MARK: - Verlauf

struct VerlaufEintrag: Codable, Identifiable, Hashable {
    enum Art: String, Codable {
        case angelegt, gekuendigt, reaktiviert

        var titel: String {
            switch self {
            case .angelegt: return "Angelegt"
            case .gekuendigt: return "Gekündigt"
            case .reaktiviert: return "Wieder aktiviert"
            }
        }

        var symbol: String {
            switch self {
            case .angelegt: return "plus.circle"
            case .gekuendigt: return "xmark.circle"
            case .reaktiviert: return "arrow.uturn.backward.circle"
            }
        }
    }

    enum Quelle: String, Codable {
        case app, mitteilung, claude

        var titel: String {
            switch self {
            case .app: return "in der App"
            case .mitteilung: return "über die Mitteilung"
            case .claude: return "durch Claude"
            }
        }
    }

    var id = UUID()
    var datum = Date()
    var art: Art
    var quelle: Quelle
    /// „Spätestens kündigen bis“ zum Zeitpunkt des Eintrags
    var frist: Date?
    /// Nächstes Vertragsende zum Zeitpunkt des Eintrags
    var vertragsende: Date?

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Hilfen

enum Kalender {
    static var de: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Format.locale
        cal.timeZone = .current
        return cal
    }
}

enum Format {
    static let locale = Locale(identifier: "de_DE")

    static func euro(_ wert: Double?) -> String {
        guard let wert else { return "offen" }
        return wert.formatted(.currency(code: "EUR").locale(locale))
    }

    static func datum(_ datum: Date?) -> String {
        guard let datum else { return "–" }
        return datum.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(locale))
    }

    /// „Mo., 8. Dezember 2026“
    static func datumLang(_ datum: Date) -> String {
        datum.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year().locale(locale))
    }

    /// „08.11.2026, 22:44“
    static func datumUhrzeitLang(_ datum: Date) -> String {
        datum.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    /// „Mo., 24.11., 09:00“
    static func datumUhrzeit(_ datum: Date) -> String {
        datum.formatted(.dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    static func inTagen(_ tage: Int) -> String {
        switch tage {
        case ..<0: return "verstrichen"
        case 0: return "heute"
        case 1: return "morgen"
        default: return "in \(tage) Tagen"
        }
    }

    /// Nur http/https-Links öffnen; fehlendes Schema wird ergänzt
    static func url(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let mitSchema = t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") ? t : "https://" + t
        guard let url = URL(string: mitSchema), url.host != nil else { return nil }
        return url
    }

    /// mailto-Link, optional mit Betreff und Text
    static func mail(_ adresse: String, betreff: String? = nil, text: String? = nil) -> URL? {
        let a = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.contains("@"), !a.contains(" ") else { return nil }
        var teile = URLComponents()
        teile.scheme = "mailto"
        teile.path = a
        var parameter: [URLQueryItem] = []
        if let betreff { parameter.append(URLQueryItem(name: "subject", value: betreff)) }
        if let text { parameter.append(URLQueryItem(name: "body", value: text)) }
        if !parameter.isEmpty { teile.queryItems = parameter }
        return teile.url
    }

    static func telefon(_ nummer: String) -> URL? {
        let ziffern = nummer.filter { $0.isNumber || $0 == "+" }
        guard ziffern.count >= 4 else { return nil }
        return URL(string: "tel:\(ziffern)")
    }
}

// MARK: - Umstellungen

enum Umstellung {
    /// Bis Version 1.0 zählte die Frist ab dem Verlängerungstag, seitdem ab dem letzten Tag der Laufzeit
    /// (einen Tag früher). Fristen in Tagen werden um einen Tag verkürzt, damit sich das bisher
    /// angezeigte Kündigungsdatum nicht verschiebt (aus „1 Tag“ wird „bis zum letzten Tag“).
    @MainActor
    static func fristenAnpassen(_ context: ModelContext) {
        let schluessel = "umstellungFristAbLetztemTag"
        guard !UserDefaults.standard.bool(forKey: schluessel) else { return }
        let abos = (try? context.fetch(FetchDescriptor<Abo>())) ?? []
        for abo in abos where abo.fristEinheit == .tage && abo.fristWert > 0 {
            abo.fristWert -= 1
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: schluessel)
    }
}

