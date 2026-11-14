import AppKit
import SwiftUI

/// Sprache der App: wie auf dem Mac (Standard), Deutsch oder Englisch.
/// Gespeichert wird die Wahl über „AppleLanguages“ der App; wirksam nach einem Neustart.
enum AppSprache: String, CaseIterable, Identifiable {
    case system, de, en
    var id: String { rawValue }

    static let schluessel = "appSprache"

    /// Gerade aktive Sprache der Oberfläche ("de" oder "en")
    static var aktiv: String { Bundle.main.preferredLocalizations.first ?? "de" }

    static var gewaehlt: AppSprache {
        AppSprache(rawValue: UserDefaults.standard.string(forKey: schluessel) ?? "") ?? .system
    }

    /// Wahl speichern; macOS liest „AppleLanguages“ beim nächsten Start der App
    static func setzen(_ sprache: AppSprache) {
        let d = UserDefaults.standard
        d.set(sprache.rawValue, forKey: schluessel)
        switch sprache {
        case .system: d.removeObject(forKey: "AppleLanguages")
        case .de, .en: d.set([sprache.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Ändert die Wahl etwas an der aktiven Sprache?
    static var neustartNoetig: Bool {
        switch gewaehlt {
        case .system:
            let mac = Locale.preferredLanguages.first.map { Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: [$0]).first ?? "de" }
            return (mac ?? aktiv) != aktiv
        case .de, .en:
            return gewaehlt.rawValue != aktiv
        }
    }

    /// Startet die App neu, damit die neue Sprache gilt
    @MainActor
    static func neuStarten() {
        let konfig = NSWorkspace.OpenConfiguration()
        konfig.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: konfig) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Auswahl in den Einstellungen
struct SprachEinstellung: View {
    @State private var wahl = AppSprache.gewaehlt
    @State private var neustart = AppSprache.neustartNoetig

    var body: some View {
        Picker("Sprache", selection: $wahl) {
            Text("Wie auf dem Mac").tag(AppSprache.system)
            Text(verbatim: "Deutsch").tag(AppSprache.de)
            Text(verbatim: "English").tag(AppSprache.en)
        }
        .onChange(of: wahl) { _, neu in
            AppSprache.setzen(neu)
            neustart = AppSprache.neustartNoetig
        }
        if neustart {
            HStack {
                Text("Die neue Sprache gilt nach einem Neustart der App.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Jetzt neu starten") { AppSprache.neuStarten() }
            }
        }
    }
}
