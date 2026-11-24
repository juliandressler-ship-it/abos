import AppKit
import Foundation
import ServiceManagement

/// Hintergrund-Prüfung für Erinnerungen. macOS behält von Abos nur eine geplante Mitteilung;
/// deshalb startet ein kleiner Hintergrunddienst `Abos --erinnern` beim Anmelden und alle
/// 15 Minuten, stellt fällige Erinnerungen zu und beendet sich gleich wieder. Kein Fenster,
/// kein Netzwerk – derselbe lokale Datenbestand wie die App.
enum Hintergrund {
    static let aktivSchluessel = "hintergrundPruefung"
    private static let dienst = SMAppService.agent(plistName: "de.juliandressler.Abos.erinnerung.plist")

    enum Zustand { case aktiv, freigabeNoetig, aus, fehlt }

    static var zustand: Zustand {
        switch dienst.status {
        case .enabled: return .aktiv
        case .requiresApproval: return .freigabeNoetig
        case .notFound: return .fehlt
        default: return .aus
        }
    }

    /// Für welchen Stand der App der Dienst zuletzt angemeldet wurde
    private static let angemeldetFuerSchluessel = "hintergrundAngemeldetFuer"

    /// Kennung dieses App-Stands: Build-Nummer und Zeitpunkt des Programms. macOS bindet den Dienst
    /// an genau den Build, der ihn angemeldet hat – nach einem Update startet er sonst nicht mehr.
    private static var appStand: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let datei = Bundle.main.executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        return "\(build)-\(Int(datei?.timeIntervalSince1970 ?? 0))"
    }

    /// Beim App-Start und beim Umschalten in den Einstellungen: Dienst an- oder abmelden.
    /// Nach einem Update wird er neu angemeldet, damit macOS ihn für den neuen Build zulässt –
    /// mit kurzer Verzögerung, weil macOS die neue Version erst erfassen muss.
    static func einrichten() {
        let d = UserDefaults.standard
        guard d.bool(forKey: aktivSchluessel) else {
            if dienst.status != .notRegistered { try? dienst.unregister() }
            d.removeObject(forKey: angemeldetFuerSchluessel)
            return
        }
        if dienst.status == .enabled && d.string(forKey: angemeldetFuerSchluessel) == appStand { return }
        if dienst.status == .enabled {
            // Update: erst kurz warten, dann neu anmelden und prüfen, ob der Dienst wirklich läuft
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { neuAnmelden(versuch: 1) }
        } else {
            anmelden()
        }
    }

    private static func anmelden() {
        let d = UserDefaults.standard
        do {
            try dienst.register()
            d.set(appStand, forKey: angemeldetFuerSchluessel)
        } catch {
            d.removeObject(forKey: angemeldetFuerSchluessel)
        }
    }

    /// Ab- und wieder anmelden. Der Dienst prüft sofort nach dem Anmelden einmal; kommt diese Prüfung
    /// nicht an, hat macOS den neuen Build noch nicht zugelassen – dann ein zweiter Versuch.
    private static func neuAnmelden(versuch: Int) {
        let start = Date()
        dienst.unregister { _ in
            DispatchQueue.main.async {
                anmelden()
                guard versuch < 3 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    let geprueft = UserDefaults.standard.object(forKey: Mitteilungen.geprueftSchluessel) as? Date
                    if (geprueft ?? .distantPast) < start { neuAnmelden(versuch: versuch + 1) }
                }
            }
        }
    }

    /// Öffnet Systemeinstellungen → Allgemein → Anmeldeobjekte, wo der Dienst erlaubt wird
    static func freigabeOeffnen() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Läuft im Hintergrundprozess (`Abos --erinnern`): prüfen und beenden
    @MainActor
    static func laufen() -> Never {
        Task { @MainActor in
            await Mitteilungen.pruefen(context: Datenbank.container.mainContext)
            exit(0)
        }
        RunLoop.main.run()
        exit(0)
    }
}
