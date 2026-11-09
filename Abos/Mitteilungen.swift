import AppKit
import Foundation
import SwiftData
import UserNotifications

/// Lokale macOS-Mitteilungen für Kündigungsfristen. Kein Netzwerk, alles auf dem Gerät.
enum Mitteilungen {
    static let kategorieID = "ABO_FRIST"

    enum Aktion {
        static let erledigt = "ERLEDIGT"
        static let gekuendigt = "GEKUENDIGT"
        static let spaeter = "SPAETER"
    }

    static func kategorienRegistrieren() {
        let aktionen = [
            UNNotificationAction(identifier: Aktion.erledigt, title: "Erledigt", options: []),
            UNNotificationAction(identifier: Aktion.gekuendigt, title: "Gekündigt", options: []),
            UNNotificationAction(identifier: Aktion.spaeter, title: "In 1 Woche erneut", options: []),
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
        case .authorized, .provisional: return "erlaubt"
        case .denied: return "abgelehnt – bitte in den Systemeinstellungen erlauben"
        case .notDetermined: return "noch nicht gefragt"
        default: return "unbekannt"
        }
    }

    /// Plant alle Erinnerungen neu (alte werden vorher entfernt).
    @MainActor
    static func planen(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let abos = (try? context.fetch(FetchDescriptor<Abo>())) ?? []
        let cal = Kalender.de
        let jetzt = Date()

        for abo in abos where abo.istAktiv {
            guard let frist = abo.spaetestensKuendigenBis else { continue }
            let fristText = Format.datum(frist)

            // "In 1 Woche erneut"
            if let erneut = abo.erneutErinnernAm, erneut > jetzt {
                hinzufuegen(id: "\(abo.uuid)-erneut", abo: abo, datum: erneut,
                            titel: "Erinnerung: \(abo.name) kündigen?",
                            text: "Spätestens kündigen bis \(fristText).")
            }

            if let erledigt = abo.erledigtFuerFrist, cal.isDate(erledigt, inSameDayAs: frist) { continue }

            for termin in abo.erinnerungsTermine(jetzt: jetzt) {
                let rest = termin.vorlauf == 0 ? "heute ist der letzte Tag"
                    : termin.vorlauf == 1 ? "noch 1 Tag" : "noch \(termin.vorlauf) Tage"
                hinzufuegen(id: "\(abo.uuid)-\(termin.vorlauf)", abo: abo, datum: termin.datum,
                            titel: "Kündigungsfrist: \(abo.name)",
                            text: "Spätestens kündigen bis \(fristText) – \(rest).")
            }
        }
    }

    private static func hinzufuegen(id: String, abo: Abo, datum: Date, titel: String, text: String) {
        let inhalt = UNMutableNotificationContent()
        inhalt.title = titel
        inhalt.body = text
        inhalt.sound = .default
        inhalt.categoryIdentifier = kategorieID
        inhalt.userInfo = ["aboID": abo.uuid.uuidString]
        let komponenten = Kalender.de.dateComponents([.year, .month, .day, .hour, .minute], from: datum)
        let trigger = UNCalendarNotificationTrigger(dateMatching: komponenten, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: inhalt, trigger: trigger))
    }

    static func testSenden() {
        let inhalt = UNMutableNotificationContent()
        inhalt.title = "Abos – Testmitteilung"
        inhalt.body = "So sehen Erinnerungen an Kündigungsfristen aus."
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
