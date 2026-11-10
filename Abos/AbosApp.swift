import AppKit
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
enum Datenbank {
    /// Aktueller Container; wird neu geöffnet, wenn Claude (MCP) etwas geändert hat
    static var container: ModelContainer = oeffnen()
    /// Ersetzte Container bleiben offen, solange noch Ansichten deren Objekte halten könnten
    static var frueher: [ModelContainer] = []

    static func oeffnen() -> ModelContainer {
        do {
            return try ModelContainer(for: Abo.self)
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }

    /// Systemweite Nachricht „Daten geändert“ zwischen MCP-Server und App (ohne Inhalt)
    static let geaendert = Notification.Name("de.juliandressler.Abos.datenGeaendert")
}

/// Startpunkt: mit `--mcp` als lokaler MCP-Server für Claude, sonst die normale App
@main
enum Start {
    static func main() {
        StandardErinnerung.registrieren()
        MainActor.assumeIsolated {
            if CommandLine.arguments.contains("--mcp") {
                MCPServer().laufen()
            } else {
                AbosApp.main()
            }
        }
    }
}

struct AbosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = Datenbank.container

    init() {
        Umstellung.fristenAnpassen(Datenbank.container.mainContext)
    }

    var body: some Scene {
        Window("Abos", id: "haupt") {
            ContentView()
                .id(ObjectIdentifier(container))
                .environment(\.locale, Format.locale)
                .modelContainer(container)
                .onReceive(DistributedNotificationCenter.default().publisher(for: Datenbank.geaendert)) { _ in
                    // Claude hat über den MCP-Server geschrieben: offene Änderungen sichern, frisch laden
                    try? container.mainContext.save()
                    Datenbank.frueher.append(container)
                    Datenbank.container = Datenbank.oeffnen()
                    container = Datenbank.container
                }
        }
        .defaultSize(width: 1100, height: 760)
        .commands { AboBefehle() }

        Settings {
            EinstellungenView()
                .environment(\.locale, Format.locale)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Mitteilungen.kategorienRegistrieren()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Fokus.einrichten() }
    }

    /// Wie bei anderen Mac-Apps: Fenster schließen lässt die App im Dock weiterlaufen, ⌘Q beendet sie
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Mitteilungen auch anzeigen, während die App im Vordergrund ist
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let aktion = response.actionIdentifier
        let idText = response.notification.request.content.userInfo["aboID"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let idText, let id = UUID(uuidString: idText) {
                    Mitteilungen.aktionAusfuehren(aktion, aboID: id, context: Datenbank.container.mainContext)
                }
            }
            completionHandler()
        }
    }
}

// MARK: - Einstellungen

struct EinstellungenView: View {
    @AppStorage(StandardErinnerung.ersteSchluessel) private var erste = 0
    @AppStorage(StandardErinnerung.zweiteSchluessel) private var zweite = -1
    @State private var berechtigung = "…"
    @AppStorage(Sicherung.letztesBackupSchluessel) private var letztesBackup: Double = 0

    var body: some View {
        Form {
            Section("Standard-Erinnerung") {
                Picker("Erinnerung", selection: $erste) {
                    ForEach(StandardErinnerung.optionen, id: \.tage) { Text($0.titel).tag($0.tage) }
                }
                Picker("Zweite Erinnerung", selection: $zweite) {
                    ForEach(StandardErinnerung.optionen, id: \.tage) { Text($0.titel).tag($0.tage) }
                }
                Text("Gilt für alle Abos, bei denen in der Abo-Karte „Standard“ eingestellt ist. Mitteilungen kommen jeweils um 9:00 Uhr.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("macOS-Mitteilungen") {
                LabeledContent("Berechtigung", value: berechtigung)
                HStack {
                    Button("Testmitteilung senden") { Mitteilungen.testSenden() }
                    Button("Systemeinstellungen öffnen") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Text("Damit die Buttons „Erledigt“, „Gekündigt“ und „In 1 Woche erneut“ immer sichtbar sind, in den Systemeinstellungen für Abos den Stil „Hinweise“ wählen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Daten & Backup") {
                LabeledContent("Letztes Backup",
                               value: letztesBackup == 0 ? "noch keins"
                                   : Format.datum(Date(timeIntervalSinceReferenceDate: letztesBackup)))
                HStack {
                    Button("Backup exportieren…") { Sicherung.backupExportieren() }
                    Button("Backup importieren…") { Sicherung.backupImportieren() }
                    Button("Als Tabelle (CSV)…") { Sicherung.csvExportieren() }
                }
                Text("Deine Abos liegen nur auf diesem Mac und werden von Time Machine mitgesichert. Ein Backup ist eine einzelne Datei, die du z. B. in iCloud Drive ablegen und hier wieder importieren kannst.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task { berechtigung = await Mitteilungen.berechtigungText() }
    }
}
