import AppKit
import SwiftData
import UniformTypeIdentifiers

// MARK: - Backup-Format

/// Komplettes Backup als JSON. Alle Felder außer uuid und name sind optional,
/// damit auch ältere oder von Hand bearbeitete Backups gelesen werden können.
struct AboSicherung: Codable {
    var format = "abos-backup"
    var version = 1
    var exportiertAm = Date()
    var abos: [AboDaten]
}

struct AboDaten: Codable {
    var uuid: UUID
    var name: String
    var kategorie: String?
    var betrag: Double?
    var intervall: String?
    var eigeneMonate: Int?
    var startdatum: Date?
    var laufzeitende: Date?
    var fristWert: Int?
    var fristEinheit: String?
    var kuendigenBisFest: Date?
    var autoVerlaengerung: Bool?
    var verlaengerungMonate: Int?
    var anteilProzent: Double?
    var status: String?
    var websiteLink: String?
    var kuendigungsLink: String?
    var kontaktEmail: String?
    var telefon: String?
    var vertragsnummer: String?
    var erinnerungTage: Int?
    var verlauf: [VerlaufEintrag]?
    var notizen: String?
    var erledigtFuerFrist: Date?
    var erneutErinnernAm: Date?
    var erstelltAm: Date?

    init(_ a: Abo) {
        uuid = a.uuid; name = a.name; kategorie = a.kategorie; betrag = a.betrag
        intervall = a.intervallRaw; eigeneMonate = a.eigeneMonate; startdatum = a.startdatum
        laufzeitende = a.laufzeitende; fristWert = a.fristWert; fristEinheit = a.fristEinheitRaw
        kuendigenBisFest = a.kuendigenBisFest; autoVerlaengerung = a.autoVerlaengerung
        verlaengerungMonate = a.verlaengerungMonate; anteilProzent = a.anteilProzent; status = a.statusRaw
        websiteLink = a.websiteLink; kuendigungsLink = a.kuendigungsLink; kontaktEmail = a.kontaktEmail
        telefon = a.telefon; vertragsnummer = a.vertragsnummer; erinnerungTage = a.erinnerungTage
        verlauf = a.verlauf; notizen = a.notizen; erledigtFuerFrist = a.erledigtFuerFrist
        erneutErinnernAm = a.erneutErinnernAm; erstelltAm = a.erstelltAm
    }

    /// Überträgt die Werte; Felder, die im Backup fehlen, bleiben unverändert.
    /// Optionale Datumsfelder werden so übernommen, wie sie im Backup stehen.
    func anwenden(auf a: Abo) {
        a.uuid = uuid
        a.name = name
        if let kategorie { a.kategorie = kategorie }
        a.betrag = betrag
        if let intervall, Intervall(rawValue: intervall) != nil { a.intervallRaw = intervall }
        if let eigeneMonate { a.eigeneMonate = eigeneMonate }
        if let startdatum { a.startdatum = startdatum }
        a.laufzeitende = laufzeitende
        if let fristWert { a.fristWert = fristWert }
        if let fristEinheit, FristEinheit(rawValue: fristEinheit) != nil { a.fristEinheitRaw = fristEinheit }
        a.kuendigenBisFest = kuendigenBisFest
        if let autoVerlaengerung { a.autoVerlaengerung = autoVerlaengerung }
        if let verlaengerungMonate { a.verlaengerungMonate = verlaengerungMonate }
        if let anteilProzent { a.anteilProzent = anteilProzent }
        if let status, AboStatus(rawValue: status) != nil { a.statusRaw = status }
        if let websiteLink { a.websiteLink = websiteLink }
        if let kuendigungsLink { a.kuendigungsLink = kuendigungsLink }
        if let kontaktEmail { a.kontaktEmail = kontaktEmail }
        if let telefon { a.telefon = telefon }
        if let vertragsnummer { a.vertragsnummer = vertragsnummer }
        if let erinnerungTage { a.erinnerungTage = erinnerungTage }
        if let verlauf {
            a.verlaufLeeren()
            verlauf.forEach { a.protokollieren($0) }
        }
        if let notizen { a.notizen = notizen }
        a.erledigtFuerFrist = erledigtFuerFrist
        a.erneutErinnernAm = erneutErinnernAm
        if let erstelltAm { a.erstelltAm = erstelltAm }
    }
}

// MARK: - Export und Import

/// Sichern und Wiederherstellen über die normalen Speichern-/Öffnen-Dialoge von macOS
@MainActor
enum Sicherung {
    static let letztesBackupSchluessel = "letztesBackup"

    private static var context: ModelContext { Datenbank.container.mainContext }

    private static func alleAbos() -> [Abo] {
        (try? context.fetch(FetchDescriptor<Abo>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    private static var heute: String {
        Date().formatted(.iso8601.year().month().day())
    }

    // Backup (JSON)

    static func backupExportieren() {
        try? context.save()
        let panel = NSSavePanel()
        panel.title = "Backup exportieren"
        panel.message = "Sichert alle Abos inklusive Verlauf, Kontakt und Notizen"
        panel.nameFieldStringValue = "Abos-Backup \(heute).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try backupDaten(alleAbos()).write(to: url, options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: letztesBackupSchluessel)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            fehler("Backup konnte nicht gespeichert werden", error)
        }
    }

    static func backupImportieren() {
        let panel = NSOpenPanel()
        panel.title = "Backup importieren"
        panel.message = "Abos-Backup (.json) auswählen"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let sicherung: AboSicherung
        do {
            sicherung = try backupLesen(Data(contentsOf: url))
        } catch {
            fehler("Die Datei ist kein lesbares Abos-Backup", error)
            return
        }

        let vorhanden = Dictionary(alleAbos().map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let neu = sicherung.abos.filter { vorhanden[$0.uuid] == nil }.count
        let ersetzt = sicherung.abos.count - neu

        let frage = NSAlert()
        frage.messageText = "Backup vom \(Format.datum(sicherung.exportiertAm)) importieren?"
        var zeilen = ["Das Backup enthält \(Format.anzahl(sicherung.abos.count, "Abo", "Abos")).",
                      "\(neu) neu, \(ersetzt) vorhandene werden mit dem Stand aus dem Backup überschrieben."]
        zeilen.append("Abos, die nicht im Backup sind, bleiben unverändert. Mit ⌘Z lässt sich der Import rückgängig machen.")
        frage.informativeText = zeilen.joined(separator: "\n\n")
        frage.addButton(withTitle: "Importieren")
        frage.addButton(withTitle: "Abbrechen")
        guard frage.runModal() == .alertFirstButtonReturn else { return }

        context.undoManager?.beginUndoGrouping()
        einspielen(sicherung, in: context)
        context.undoManager?.endUndoGrouping()
        context.undoManager?.setActionName("Backup importieren")
        do {
            try context.save()
        } catch {
            fehler("Import konnte nicht gespeichert werden", error)
        }
        Mitteilungen.planen(context: context)
    }

    /// Abos aus dem Backup übernehmen: gleiche uuid wird überschrieben, neue werden angelegt, nichts gelöscht
    static func einspielen(_ sicherung: AboSicherung, in context: ModelContext) {
        let vorhanden = Dictionary(((try? context.fetch(FetchDescriptor<Abo>())) ?? []).map { ($0.uuid, $0) },
                                   uniquingKeysWith: { a, _ in a })
        for daten in sicherung.abos {
            if let abo = vorhanden[daten.uuid] {
                daten.anwenden(auf: abo)
            } else {
                let abo = Abo(name: daten.name)
                context.insert(abo)
                daten.anwenden(auf: abo)
            }
        }
    }

    static func backupDaten(_ abos: [Abo]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(AboSicherung(abos: abos.map(AboDaten.init)))
    }

    static func backupLesen(_ daten: Data) throws -> AboSicherung {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sicherung = try decoder.decode(AboSicherung.self, from: daten)
        guard sicherung.format == "abos-backup" else { throw CocoaError(.fileReadCorruptFile) }
        return sicherung
    }

    // Tabelle (CSV, z. B. für Excel oder Numbers)

    static func csvExportieren() {
        try? context.save()
        let panel = NSSavePanel()
        panel.title = "Als Tabelle exportieren"
        panel.message = "CSV-Datei für Excel oder Numbers (nur zum Ansehen, nicht zum Wiederherstellen)"
        panel.nameFieldStringValue = "Abos \(heute).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try csvText(alleAbos()).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            fehler("Tabelle konnte nicht gespeichert werden", error)
        }
    }

    static func csvText(_ abos: [Abo]) -> String {
        let kopf = ["Name", "Kategorie", "Status", "Betrag", "Intervall", "Anteil %", "Pro Monat", "Pro Jahr",
                    "Kündigen bis", "Nächste Verlängerung", "Automatische Verlängerung", "Gekündigt am",
                    "Website", "Kündigungs-Link", "Kontakt-E-Mail", "Telefon", "Vertragsnummer", "Notizen"]
        var zeilen = [kopf.map(feld).joined(separator: ";")]
        for a in abos {
            let werte = [
                a.name, a.kategorie, a.status.titel, zahl(a.betrag), a.intervall.titel, zahl(a.anteilProzent),
                zahl(a.proMonat), zahl(a.proJahr), datum(a.spaetestensKuendigenBis), datum(a.naechstesEnde()),
                a.autoVerlaengerung ? "ja" : "nein", datum(a.gekuendigtAm),
                a.websiteLink, a.kuendigungsLink, a.kontaktEmail, a.telefon, a.vertragsnummer, a.notizen,
            ]
            zeilen.append(werte.map(feld).joined(separator: ";"))
        }
        // BOM, damit Excel die Umlaute richtig erkennt
        return "\u{FEFF}" + zeilen.joined(separator: "\r\n") + "\r\n"
    }

    private static func feld(_ s: String) -> String {
        guard s.contains(where: { ";\"\n\r".contains($0) }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func zahl(_ wert: Double?) -> String {
        guard let wert else { return "" }
        return wert.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Format.locale))
    }

    private static func datum(_ d: Date?) -> String { d.map(Format.datum) ?? "" }

    private static func fehler(_ titel: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = titel
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
