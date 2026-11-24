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

    /// Beim App-Start und beim Umschalten in den Einstellungen: Dienst an- oder abmelden
    static func einrichten() {
        if UserDefaults.standard.bool(forKey: aktivSchluessel) {
            if dienst.status != .enabled { try? dienst.register() }
        } else if dienst.status != .notRegistered {
            try? dienst.unregister()
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
