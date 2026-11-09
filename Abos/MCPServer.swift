import Foundation
import SwiftData

/// Lokaler MCP-Server (Model Context Protocol) über stdin/stdout.
/// Claude startet ihn als Unterprozess: `Abos.app/Contents/MacOS/Abos --mcp`.
/// Kein Netzwerk – die Daten liegen weiter nur in der App-Datenbank auf diesem Mac.
/// Löschen ist bewusst nicht möglich; das geht nur in der App.
@MainActor
final class MCPServer {
    private let container: ModelContainer = {
        let c = Datenbank.oeffnen()
        Umstellung.fristenAnpassen(c.mainContext)
        return c
    }()

    func laufen() {
        while let zeile = readLine(strippingNewline: true) {
            guard !zeile.trimmingCharacters(in: .whitespaces).isEmpty,
                  let daten = zeile.data(using: .utf8),
                  let anfrage = try? JSONSerialization.jsonObject(with: daten) as? [String: Any]
            else {
                senden(["jsonrpc": "2.0", "id": NSNull(),
                        "error": ["code": -32700, "message": "Ungültiges JSON"]])
                continue
            }
            if let antwort = verarbeiten(anfrage) { senden(antwort) }
        }
    }

    private func senden(_ objekt: [String: Any]) {
        guard var daten = try? JSONSerialization.data(withJSONObject: objekt, options: [.withoutEscapingSlashes]) else { return }
        daten.append(0x0A)
        FileHandle.standardOutput.write(daten)
    }

    // MARK: - JSON-RPC

    private func verarbeiten(_ anfrage: [String: Any]) -> [String: Any]? {
        let methode = anfrage["method"] as? String ?? ""
        guard let id = anfrage["id"] else { return nil } // Benachrichtigungen brauchen keine Antwort
        let params = anfrage["params"] as? [String: Any] ?? [:]

        func ergebnis(_ wert: Any) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": wert] }
        func fehler(_ code: Int, _ text: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]
        }

        switch methode {
        case "initialize":
            return ergebnis([
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "abos", "title": "Abos", "version": "1.0"],
                "instructions": """
                Zugriff auf die lokale Abo- und Versicherungsverwaltung „Abos“ des Nutzers. \
                Beträge in Euro. pro_monat/pro_jahr berücksichtigen Zahlungsintervall und den eigenen Anteil. \
                Vor dem Anlegen mit abos_auflisten prüfen, ob es das Abo schon gibt. \
                Für Sparpotenziale zuerst auswertung aufrufen. Löschen ist nur in der App möglich.
                """,
            ])
        case "ping":
            return ergebnis([String: Any]())
        case "tools/list":
            return ergebnis(["tools": Self.werkzeuge])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let argumente = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try aufrufen(name, argumente)
                return ergebnis(["content": [["type": "text", "text": text]], "isError": false])
            } catch let f as WerkzeugFehler {
                return ergebnis(["content": [["type": "text", "text": f.text]], "isError": true])
            } catch {
                return ergebnis(["content": [["type": "text", "text": "Fehler: \(error)"]], "isError": true])
            }
        default:
            return fehler(-32601, "Methode unbekannt: \(methode)")
        }
    }

    struct WerkzeugFehler: Error { let text: String }

    // MARK: - Werkzeuge

    private func aufrufen(_ name: String, _ a: [String: Any]) throws -> String {
        let context = ModelContext(container)
        let abos = try context.fetch(FetchDescriptor<Abo>(sortBy: [SortDescriptor(\.name)]))

        switch name {
        case "abos_auflisten":
            let status = (a["status"] as? String) ?? "alle"
            let kategorie = (a["kategorie"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let suche = (a["suche"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let liste = abos.filter { abo in
                (status == "alle" || abo.statusRaw == status)
                    && (kategorie.isEmpty || abo.kategorie.localizedCaseInsensitiveCompare(kategorie) == .orderedSame)
                    && (suche.isEmpty || abo.name.localizedCaseInsensitiveContains(suche)
                        || abo.kategorie.localizedCaseInsensitiveContains(suche)
                        || abo.notizen.localizedCaseInsensitiveContains(suche))
            }
            return json(["anzahl": liste.count, "abos": liste.map { beschreibung($0, kurz: true) }])

        case "abo_details":
            return json(beschreibung(try finden(a, in: abos), kurz: false))

        case "auswertung":
            return json(auswertung(abos))

        case "abo_anlegen":
            guard let name = (a["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                throw WerkzeugFehler(text: "„name“ fehlt.")
            }
            if a["trotzdem_anlegen"] as? Bool != true,
               let gleich = abos.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                throw WerkzeugFehler(text: "Es gibt bereits ein Abo „\(gleich.name)“ (id \(gleich.uuid)). "
                    + "Zum Ändern abo_aendern verwenden oder trotzdem_anlegen: true setzen.")
            }
            let abo = Abo(name: name)
            abo.protokollieren(VerlaufEintrag(art: .angelegt, quelle: .claude))
            try uebernehmen(a, in: abo)
            context.insert(abo)
            try speichern(context)
            return json(["angelegt": beschreibung(abo, kurz: false)])

        case "abo_aendern":
            let abo = try finden(a, in: abos)
            try uebernehmen(a, in: abo)
            try speichern(context)
            return json(["geaendert": beschreibung(abo, kurz: false)])

        default:
            throw WerkzeugFehler(text: "Unbekanntes Werkzeug: \(name)")
        }
    }

    private func speichern(_ context: ModelContext) throws {
        try context.save()
        // Laufende App benachrichtigen, damit sie neu lädt
        DistributedNotificationCenter.default().postNotificationName(Datenbank.geaendert, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    private func finden(_ a: [String: Any], in abos: [Abo]) throws -> Abo {
        if let idText = a["id"] as? String, !idText.isEmpty {
            guard let id = UUID(uuidString: idText), let abo = abos.first(where: { $0.uuid == id }) else {
                throw WerkzeugFehler(text: "Kein Abo mit id \(idText).")
            }
            return abo
        }
        guard let name = (a["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            throw WerkzeugFehler(text: "„id“ oder „name“ angeben.")
        }
        if let exakt = abos.filter({ $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }).first {
            return exakt
        }
        let treffer = abos.filter { $0.name.localizedCaseInsensitiveContains(name) }
        if treffer.count == 1 { return treffer[0] }
        if treffer.isEmpty { throw WerkzeugFehler(text: "Kein Abo „\(name)“ gefunden.") }
        throw WerkzeugFehler(text: "Mehrere Treffer für „\(name)“: "
            + treffer.map { "\($0.name) (id \($0.uuid))" }.joined(separator: ", ") + ". Bitte id angeben.")
    }

    /// Übernimmt alle angegebenen Felder; nicht angegebene bleiben unverändert
    private func uebernehmen(_ a: [String: Any], in abo: Abo) throws {
        if let v = a["neuer_name"] as? String, !v.isEmpty { abo.name = v }
        if let v = a["kategorie"] as? String { abo.kategorie = v.trimmingCharacters(in: .whitespaces) }
        if a.keys.contains("betrag") {
            if a["betrag"] is NSNull { abo.betrag = nil } else if let v = zahl(a["betrag"]) { abo.betrag = max(0, v) }
        }
        if let v = a["intervall"] as? String {
            guard let i = Intervall(rawValue: v) else {
                throw WerkzeugFehler(text: "intervall muss monatlich, quartal, jaehrlich oder eigen sein.")
            }
            abo.intervall = i
        }
        if let v = zahl(a["alle_x_monate"]) { abo.eigeneMonate = max(1, Int(v)) }
        if let v = zahl(a["anteil_prozent"]) { abo.anteilProzent = min(100, max(0, v)) }
        if let v = a["status"] as? String {
            switch v {
            case "aktiv": abo.reaktivieren(quelle: .claude)
            case "gekuendigt": abo.kuendigen(quelle: .claude)
            default: throw WerkzeugFehler(text: "status muss aktiv oder gekuendigt sein.")
            }
        }
        if let v = a["abo_seit"] as? String { abo.startdatum = try datum(v, "abo_seit") }
        if let v = a["naechste_verlaengerung"] as? String { abo.laufzeitende = try datum(v, "naechste_verlaengerung") }
        if let v = a["letzter_tag"] as? String {
            abo.laufzeitende = Kalender.de.date(byAdding: .day, value: 1, to: try datum(v, "letzter_tag"))
        }
        if let v = zahl(a["kuendigungsfrist_wert"]) { abo.fristWert = max(0, Int(v)) }
        if let v = a["kuendigungsfrist_einheit"] as? String {
            guard let e = FristEinheit(rawValue: v) else {
                throw WerkzeugFehler(text: "kuendigungsfrist_einheit muss tage, wochen oder monate sein.")
            }
            abo.fristEinheit = e
        }
        if a.keys.contains("kuendigen_bis") {
            if let v = a["kuendigen_bis"] as? String, !v.isEmpty {
                abo.kuendigenBisFest = try datum(v, "kuendigen_bis")
            } else {
                abo.kuendigenBisFest = nil
            }
        }
        if let v = a["automatische_verlaengerung"] as? Bool { abo.autoVerlaengerung = v }
        if let v = zahl(a["verlaengerung_monate"]) { abo.verlaengerungsSchritt = Int(v) }
        if let v = a["website"] as? String { abo.websiteLink = v }
        if let v = a["kuendigungs_link"] as? String { abo.kuendigungsLink = v }
        if let v = a["kontakt_email"] as? String { abo.kontaktEmail = v }
        if let v = a["telefon"] as? String { abo.telefon = v }
        if let v = a["vertragsnummer"] as? String { abo.vertragsnummer = v }
        if let v = a["notizen"] as? String { abo.notizen = v }
        if let v = a["notiz_anhaengen"] as? String, !v.isEmpty {
            abo.notizen = abo.notizen.isEmpty ? v : abo.notizen + "\n" + v
        }
    }

    // MARK: - Ausgabe

    private func beschreibung(_ abo: Abo, kurz: Bool) -> [String: Any] {
        var d: [String: Any] = [
            "id": abo.uuid.uuidString,
            "name": abo.name,
            "kategorie": abo.kategorie,
            "status": abo.statusRaw,
            "betrag": abo.betrag.map(runden) ?? NSNull(),
            "intervall": abo.intervallRaw,
            "pro_monat": abo.proMonat.map(runden) ?? NSNull(),
            "pro_jahr": abo.proJahr.map(runden) ?? NSNull(),
            "spaetestens_kuendigen_bis": iso(abo.spaetestensKuendigenBis) ?? NSNull(),
        ]
        if let t = abo.tageBisFrist(), abo.istAktiv { d["tage_bis_frist"] = t }
        if kurz { return d }
        d["alle_x_monate"] = abo.intervall == .eigen ? abo.eigeneMonate : NSNull()
        d["anteil_prozent"] = runden(abo.anteilProzent)
        d["abo_seit"] = iso(abo.startdatum) ?? NSNull()
        d["naechste_verlaengerung"] = iso(abo.naechstesEnde()) ?? NSNull()
        d["letzter_tag_der_laufzeit"] = iso(abo.naechstesEnde().map(Abo.letzterTag(vor:))) ?? NSNull()
        d["kuendigungsfrist"] = abo.kuendigenBisFest != nil
            ? "festes Datum"
            : (AboDetailView.fristText(abo.fristWert, abo.fristEinheit).map { "\($0) vor dem letzten Tag der Laufzeit" } ?? "keine, bis zum letzten Tag der Laufzeit")
        d["automatische_verlaengerung"] = abo.autoVerlaengerung
        d["verlaengerung_monate"] = abo.verlaengerungsSchritt
        d["website"] = abo.websiteLink
        d["kuendigungs_link"] = abo.kuendigungsLink
        d["kontakt_email"] = abo.kontaktEmail
        d["telefon"] = abo.telefon
        d["vertragsnummer"] = abo.vertragsnummer
        d["notizen"] = abo.notizen
        d["verlauf"] = abo.verlauf.map { e -> [String: Any] in
            ["datum": Self.zeitFormat.string(from: e.datum), "ereignis": e.art.rawValue, "quelle": e.quelle.rawValue,
             "frist_damals": iso(e.frist) ?? NSNull(),
             "laeuft_bis": iso(e.vertragsende.map(Abo.letzterTag(vor:))) ?? NSNull()]
        }
        return d
    }

    private func auswertung(_ abos: [Abo]) -> [String: Any] {
        let aktive = abos.filter(\.istAktiv)
        let gesamt = aktive.compactMap(\.proMonat).reduce(0, +)
        let kategorien = Auswertung.kategorien(abos).map { k -> [String: Any] in
            ["kategorie": k.name, "anzahl": k.anzahl,
             "pro_monat": k.proMonat.map(runden) ?? NSNull(),
             "pro_jahr": k.proMonat.map { runden($0 * 12) } ?? NSNull(),
             "anteil_prozent": k.proMonat.map { gesamt > 0 ? runden($0 / gesamt * 100) : 0 } ?? NSNull()]
        }
        let heute = Date()
        let bald = aktive.compactMap { abo -> [String: Any]? in
            guard let t = abo.tageBisFrist(heute: heute), t >= 0, t <= 90 else { return nil }
            return ["name": abo.name, "spaetestens_kuendigen_bis": iso(abo.spaetestensKuendigenBis) ?? "",
                    "tage_bis_frist": t, "pro_jahr": abo.proJahr.map(runden) ?? NSNull()]
        }
        let gekuendigt = abos.filter { !$0.istAktiv }
        return [
            "stand": iso(heute) ?? "",
            "aktive_abos": aktive.count,
            "gesamt_pro_monat": runden(gesamt),
            "gesamt_pro_jahr": runden(gesamt * 12),
            "nach_kategorie": kategorien,
            "teuerste_aktive": Sortierung(feld: .preis, umgekehrt: false).sortiert(aktive).prefix(5)
                .map { abo -> [String: Any] in
                    ["name": abo.name, "kategorie": abo.kategorie, "pro_monat": abo.proMonat.map(runden) as Any? ?? NSNull()]
                },
            "ohne_betrag": aktive.filter { $0.betrag == nil }.map(\.name),
            "fristen_naechste_90_tage": bald,
            "ohne_automatische_verlaengerung": aktive.filter { !$0.autoVerlaengerung }.map(\.name),
            "gekuendigt": gekuendigt.map(\.name),
            "durch_kuendigungen_gespart_pro_jahr": runden(gekuendigt.compactMap(\.proJahr).reduce(0, +)),
        ]
    }

    // MARK: - Hilfen

    private func json(_ objekt: Any) -> String {
        guard let daten = try? JSONSerialization.data(withJSONObject: objekt,
                                                      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(decoding: daten, as: UTF8.self)
    }

    /// Auf Cent gerundet; als Dezimalzahl, damit JSON „2.17“ statt „2.1699999“ zeigt
    private func runden(_ wert: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), wert))
    }

    private func zahl(_ wert: Any?) -> Double? {
        if let d = wert as? Double { return d }
        if let i = wert as? Int { return Double(i) }
        if let s = wert as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    private static let isoFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Kalender.de
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let zeitFormat = ISO8601DateFormatter()

    private func iso(_ datum: Date?) -> String? { datum.map { Self.isoFormat.string(from: $0) } }

    private func datum(_ text: String, _ feld: String) throws -> Date {
        guard let d = Self.isoFormat.date(from: text) else {
            throw WerkzeugFehler(text: "\(feld) bitte als JJJJ-MM-TT angeben, z. B. 2026-12-31.")
        }
        return Kalender.de.startOfDay(for: d)
    }

    // MARK: - Schemas

    private static let felder: [String: Any] = [
        "kategorie": ["type": "string", "description": "z. B. Versicherung, Software, Telekommunikation, Medien, Streaming"],
        "betrag": ["type": ["number", "null"], "description": "Betrag pro Zahlung in Euro; null = noch offen"],
        "intervall": ["type": "string", "enum": ["monatlich", "quartal", "jaehrlich", "eigen"],
                      "description": "Zahlungsintervall"],
        "alle_x_monate": ["type": "integer", "description": "Nur bei intervall=eigen: Zahlung alle X Monate"],
        "anteil_prozent": ["type": "number", "description": "Eigener Kostenanteil in Prozent (Standard 100)"],
        "status": ["type": "string", "enum": ["aktiv", "gekuendigt"]],
        "abo_seit": ["type": "string", "description": "Beginn, JJJJ-MM-TT"],
        "naechste_verlaengerung": ["type": "string",
                                   "description": "Tag der nächsten Verlängerung bzw. Zahlung, JJJJ-MM-TT (Abo seit 08.11., monatlich → 2026-12-08)"],
        "letzter_tag": ["type": "string", "description": "Alternativ: letzter Tag der Laufzeit, JJJJ-MM-TT (Tag vor der Verlängerung)"],
        "kuendigungsfrist_wert": ["type": "integer",
                                  "description": "Kündigungsfrist vor dem letzten Tag der Laufzeit; 0 = bis einschließlich letzter Tag"],
        "kuendigungsfrist_einheit": ["type": "string", "enum": ["tage", "wochen", "monate"]],
        "kuendigen_bis": ["type": "string",
                          "description": "Festes Datum „spätestens kündigen bis“, JJJJ-MM-TT; ersetzt die Berechnung aus der Frist. Leerer Text entfernt es."],
        "automatische_verlaengerung": ["type": "boolean"],
        "verlaengerung_monate": ["type": "integer", "description": "Um so viele Monate verlängert sich der Vertrag"],
        "website": ["type": "string"],
        "kuendigungs_link": ["type": "string"],
        "kontakt_email": ["type": "string"],
        "telefon": ["type": "string"],
        "vertragsnummer": ["type": "string", "description": "Kunden- oder Vertragsnummer (keine Passwörter)"],
        "notizen": ["type": "string", "description": "Ersetzt die Notizen"],
        "notiz_anhaengen": ["type": "string", "description": "Hängt eine Zeile an die Notizen an"],
    ]

    private static var werkzeuge: [[String: Any]] {
        var anlegen = felder
        anlegen["name"] = ["type": "string", "description": "Name des Abos oder der Versicherung"]
        anlegen["trotzdem_anlegen"] = ["type": "boolean", "description": "Auch anlegen, wenn der Name schon existiert"]
        var aendern = felder
        aendern["id"] = ["type": "string", "description": "id aus abos_auflisten (bevorzugt)"]
        aendern["name"] = ["type": "string", "description": "Name zum Finden, falls keine id"]
        aendern["neuer_name"] = ["type": "string", "description": "Umbenennen"]
        let lesen: [String: Any] = ["readOnlyHint": true, "destructiveHint": false]
        return [
            ["name": "abos_auflisten",
             "title": "Abos auflisten",
             "description": "Listet Abos und Versicherungen mit Kosten pro Monat/Jahr und Kündigungsfrist. Optional filtern.",
             "annotations": lesen,
             "inputSchema": ["type": "object", "properties": [
                 "status": ["type": "string", "enum": ["aktiv", "gekuendigt", "alle"], "description": "Standard: alle"],
                 "kategorie": ["type": "string"],
                 "suche": ["type": "string", "description": "Sucht in Name, Kategorie und Notizen"],
             ]]],
            ["name": "abo_details",
             "title": "Abo-Details",
             "description": "Alle Felder eines Abos inklusive Kontakt, Links, Frist, Notizen und Kündigungsverlauf (wann gekündigt bzw. wieder aktiviert).",
             "annotations": lesen,
             "inputSchema": ["type": "object", "properties": [
                 "id": ["type": "string"], "name": ["type": "string"],
             ]]],
            ["name": "auswertung",
             "title": "Auswertung",
             "description": "Gesamtkosten, Kosten pro Kategorie, teuerste Abos, Abos ohne Betrag, anstehende Kündigungsfristen (90 Tage) und Ersparnis durch Kündigungen. Grundlage, um Sparpotenziale zu finden.",
             "annotations": lesen,
             "inputSchema": ["type": "object", "properties": [String: Any]()]],
            ["name": "abo_anlegen",
             "title": "Abo anlegen",
             "description": "Legt ein neues Abo bzw. eine neue Versicherung an. Daten als JJJJ-MM-TT.",
             "annotations": ["readOnlyHint": false, "destructiveHint": false],
             "inputSchema": ["type": "object", "properties": anlegen, "required": ["name"]]],
            ["name": "abo_aendern",
             "title": "Abo ändern",
             "description": "Ändert Felder eines bestehenden Abos (nur die angegebenen). Auch zum Kündigen-Markieren (status=gekuendigt) oder Reaktivieren.",
             "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true],
             "inputSchema": ["type": "object", "properties": aendern]],
        ]
    }
}
