import AppKit
import Foundation
import SwiftData
import UserNotifications

/// Standard-Erinnerungen für alle Abos, die nichts Eigenes eingestellt haben.
/// Werte: -1 = aus, 0 = am Tag der Frist, sonst Tage vorher.
enum StandardErinnerung {
    static let ersteSchluessel = "standardErinnerung1"
    static let zweiteSchluessel = "standardErinnerung2"

    static let optionen: [(tage: Int, titel: String)] = [
        (-1, String(localized: "Aus")), (0, String(localized: "Am Tag der Frist")), (1, String(localized: "1 Tag vorher")), (3, String(localized: "3 Tage vorher")),
        (7, String(localized: "1 Woche vorher")), (14, String(localized: "2 Wochen vorher")), (30, String(localized: "1 Monat vorher")),
    ]

    /// Uhrzeit der Mitteilungen in Minuten nach Mitternacht (Standard 9:00)
    static let uhrzeitSchluessel = "erinnerungUhrzeit"

    static func registrieren() {
        UserDefaults.standard.register(defaults: [ersteSchluessel: 0, zweiteSchluessel: -1, uhrzeitSchluessel: 9 * 60,
                                                  Hintergrund.aktivSchluessel: true])
    }

    static var uhrzeit: (stunde: Int, minute: Int) {
        let m = min(max(UserDefaults.standard.integer(forKey: uhrzeitSchluessel), 0), 24 * 60 - 1)
        return (m / 60, m % 60)
    }

    /// Aktive Vorläufe, größter zuerst
    static var vorlaeufe: [Int] {
        let d = UserDefaults.standard
        return Array(Set([d.integer(forKey: ersteSchluessel), d.integer(forKey: zweiteSchluessel)].filter { $0 >= 0 }))
            .sorted(by: >)
    }

    static func text(_ tage: Int) -> String {
        optionen.first { $0.tage == tage }?.titel ?? String(localized: "\(tage) Tage vorher")
    }

    /// z. B. „am Tag der Frist“ oder „1 Woche vorher und am Tag der Frist“
    static var beschreibung: String {
        let v = vorlaeufe
        guard !v.isEmpty else { return String(localized: "aus") }
        return v.map { $0 == 0 ? String(localized: "am Tag der Frist") : text($0) }.joined(separator: " und ")
    }
}

/// Lokale macOS-Mitteilungen für Kündigungsfristen. Kein Netzwerk, alles auf dem Gerät.
enum Mitteilungen {
    static let kategorieID = "ABO_FRIST"
    /// So viele kommende Kündigungsfristen pro Abo werden berücksichtigt
    static let fristenVoraus = 3
    /// Merkzettel in den Einstellungen der App (auch die Hintergrund-Prüfung liest und schreibt sie)
    static let geplantSchluessel = "mitteilungEingeplant"
    static let geprueftSchluessel = "mitteilungenGeprueftBis"
    static let zugestelltSchluessel = "mitteilungenZugestellt"

    enum Aktion {
        static let erledigt = "ERLEDIGT"
        static let gekuendigt = "GEKUENDIGT"
        static let spaeter = "SPAETER"
    }

    static func kategorienRegistrieren() {
        let aktionen = [
            UNNotificationAction(identifier: Aktion.erledigt, title: String(localized: "Erledigt"), options: []),
            UNNotificationAction(identifier: Aktion.gekuendigt, title: String(localized: "Gekündigt"), options: []),
            UNNotificationAction(identifier: Aktion.spaeter, title: String(localized: "In 1 Woche erneut"), options: []),
        ]
        let kategorie = UNNotificationCategory(identifier: kategorieID, actions: aktionen,
                                               intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([kategorie])
    }

    static func berechtigungAnfragen() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    enum Zustand {
        /// Stil „Hinweise“: bleibt stehen, bis man sie wegklickt
        case bleibt
        /// Stil „Banner“: verschwindet nach ein paar Sekunden
        case verschwindet
        case nichtGefragt
        case aus
    }

    static func zustand() async -> Zustand {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .notDetermined: return .nichtGefragt
        case .authorized, .provisional: return s.alertStyle == .alert ? .bleibt : .verschwindet
        default: return .aus
        }
    }

    static func systemeinstellungenOeffnen() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func berechtigungText() async -> String {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional: return String(localized: "erlaubt")
        case .denied: return String(localized: "abgelehnt – bitte in den Systemeinstellungen erlauben")
        case .notDetermined: return String(localized: "noch nicht gefragt")
        default: return String(localized: "unbekannt")
        }
    }

    /// Eine Erinnerung, die zu einem bestimmten Zeitpunkt fällig wird
    struct Termin {
        let id: String
        let aboID: UUID
        let name: String
        let datum: Date
        let frist: Date
        /// true bei „In 1 Woche erneut“
        let erneut: Bool
    }

    /// Alle Erinnerungen nach `start`, früheste zuerst – für die nächsten Kündigungsfristen jedes aktiven Abos
    @MainActor
    static func termine(context: ModelContext, ab start: Date) -> [Termin] {
        let abos = (try? context.fetch(FetchDescriptor<Abo>())) ?? []
        let cal = Kalender.de
        var liste: [Termin] = []
        for abo in abos where abo.istAktiv {
            if let erneut = abo.erneutErinnernAm, erneut > start, let frist = abo.spaetestensKuendigenBis(ab: erneut) {
                let tag = Int(erneut.timeIntervalSince1970)
                liste.append(Termin(id: "\(abo.uuid)-erneut-\(tag)", aboID: abo.uuid, name: abo.name,
                                    datum: erneut, frist: frist, erneut: true))
            }
            for t in abo.erinnerungsTermine(jetzt: start, fristen: fristenVoraus) {
                // Für diese Frist schon „Erledigt“ gewählt
                if let erledigt = abo.erledigtFuerFrist, cal.isDate(erledigt, inSameDayAs: t.frist) { continue }
                let tag = Int(cal.startOfDay(for: t.frist).timeIntervalSince1970)
                liste.append(Termin(id: "\(abo.uuid)-\(tag)-\(t.vorlauf)", aboID: abo.uuid, name: abo.name,
                                    datum: t.datum, frist: t.frist, erneut: false))
            }
        }
        return liste.sorted { $0.datum < $1.datum }
    }

    /// Plant die nächste fällige Erinnerung bei macOS ein, damit sie pünktlich kommt.
    /// macOS behält für Abos nur eine geplante Mitteilung – alle weiteren stellt die
    /// Hintergrund-Prüfung zu, sobald sie fällig sind.
    @MainActor
    static func planen(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard let naechster = termine(context: context, ab: Date()).first else {
            UserDefaults.standard.removeObject(forKey: geplantSchluessel)
            return
        }
        let komponenten = Kalender.de.dateComponents([.year, .month, .day, .hour, .minute], from: naechster.datum)
        center.add(UNNotificationRequest(identifier: naechster.id, content: inhalt(naechster, am: naechster.datum),
                                         trigger: UNCalendarNotificationTrigger(dateMatching: komponenten, repeats: false)))
        UserDefaults.standard.set(naechster.id, forKey: geplantSchluessel)
    }

    /// Hintergrund-Prüfung: alles zustellen, was seit der letzten Prüfung fällig wurde und noch nicht
    /// gekommen ist, dann die nächste Erinnerung einplanen. Verpasste Erinnerungen (Mac aus) kommen
    /// nachträglich, solange ihre Frist noch nicht vorbei ist.
    @MainActor
    static func pruefen(context: ModelContext) async {
        if Abo.geplanteWechselAnwenden(context: context) {
            DistributedNotificationCenter.default().postNotificationName(Datenbank.geaendert, object: nil, userInfo: nil,
                                                                         deliverImmediately: true)
        }
        let d = UserDefaults.standard
        let cal = Kalender.de
        let center = UNUserNotificationCenter.current()
        let jetzt = Date()
        let heute = cal.startOfDay(for: jetzt)
        // Beim ersten Mal nichts nachholen; sonst höchstens zwei Wochen zurück
        let zuletzt = d.object(forKey: geprueftSchluessel) as? Date ?? jetzt
        let start = max(zuletzt, cal.date(byAdding: .day, value: -14, to: jetzt) ?? jetzt)

        let ausstehend = Set(await center.pendingNotificationRequests().map(\.identifier))
        let imMitteilungszentrum = Set(await center.deliveredNotifications().map(\.request.identifier))
        let eingeplant = d.string(forKey: geplantSchluessel)
        var zugestellt = d.stringArray(forKey: zugestelltSchluessel) ?? []

        for t in termine(context: context, ab: start) where t.datum <= jetzt {
            guard cal.startOfDay(for: t.frist) >= heute else { continue }       // Frist schon vorbei
            if zugestellt.contains(t.id) || imMitteilungszentrum.contains(t.id) { continue }
            if ausstehend.contains(t.id) { continue }                            // macOS stellt sie gleich selbst zu
            if t.id == eingeplant {                                              // war eingeplant und ist schon gekommen
                zugestellt.append(t.id)
                continue
            }
            try? await center.add(UNNotificationRequest(identifier: t.id, content: inhalt(t, am: jetzt), trigger: nil))
            zugestellt.append(t.id)
        }

        d.set(Array(zugestellt.suffix(300)), forKey: zugestelltSchluessel)
        d.set(jetzt, forKey: geprueftSchluessel)
        planen(context: context)
        // Der Auftrag an macOS läuft asynchron; kurz warten, bevor sich der Prozess beendet
        try? await Task.sleep(for: .seconds(1))
    }

    /// Text der Mitteilung; „noch … Tage“ zählt ab dem Tag, an dem sie erscheint
    private static func inhalt(_ t: Termin, am tag: Date) -> UNMutableNotificationContent {
        let cal = Kalender.de
        let fristText = Format.datum(t.frist)
        let inhalt = UNMutableNotificationContent()
        if t.erneut {
            inhalt.title = String(localized: "Erinnerung: \(t.name) kündigen?")
            inhalt.body = String(localized: "Spätestens kündigen bis \(fristText).")
        } else {
            let rest = cal.dateComponents([.day], from: cal.startOfDay(for: tag), to: cal.startOfDay(for: t.frist)).day ?? 0
            let restText = rest <= 0 ? String(localized: "heute ist der letzte Tag")
                : rest == 1 ? String(localized: "noch 1 Tag") : String(localized: "noch \(rest) Tage")
            inhalt.title = String(localized: "Kündigungsfrist: \(t.name)")
            inhalt.body = String(localized: "Spätestens kündigen bis \(fristText) – \(restText).")
        }
        inhalt.sound = .default
        inhalt.categoryIdentifier = kategorieID
        inhalt.userInfo = ["aboID": t.aboID.uuidString]
        return inhalt
    }

    static func testSenden() {
        let inhalt = UNMutableNotificationContent()
        inhalt.title = String(localized: "Abos – Testmitteilung")
        inhalt.body = String(localized: "So sehen Erinnerungen an Kündigungsfristen aus.")
        inhalt.sound = .default
        inhalt.categoryIdentifier = kategorieID
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-\(UUID())", content: inhalt, trigger: trigger))
    }

    /// Reaktion auf die Buttons in der Mitteilung
    @MainActor
    static func aktionAusfuehren(_ aktion: String, aboID: UUID, context: ModelContext) {
        let suche = FetchDescriptor<Abo>(predicate: #Predicate { $0.uuid == aboID })
        guard let abo = try? context.fetch(suche).first else { return }
        switch aktion {
        case Aktion.erledigt:
            abo.erledigtFuerFrist = abo.spaetestensKuendigenBis
            abo.erneutErinnernAm = nil
        case Aktion.gekuendigt:
            abo.kuendigen(quelle: .mitteilung)
        case Aktion.spaeter:
            abo.erneutErinnernAm = Kalender.de.date(byAdding: .day, value: 7, to: Date())
        default:
            return // Klick auf die Mitteilung selbst öffnet nur die App
        }
        try? context.save()
        planen(context: context)
    }
}
