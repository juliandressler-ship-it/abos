import AppKit
import Foundation
import ServiceManagement

/// Erinnerungen prüfen, solange die App läuft – auch mit geschlossenem Fenster (Abos bleibt dann im Dock).
/// Beim Start, alle 15 Minuten und nach dem Aufwachen des Macs werden fällige Erinnerungen zugestellt
/// und die nächste bei macOS eingeplant; die kommt auch, wenn Abos beendet ist.
///
/// Früher gab es dafür einen eigenen Hintergrunddienst. macOS lässt ihn bei einer nur lokal signierten
/// App nach jedem Update nicht mehr starten (Absturzberichte „Launch Constraint Violation“) –
/// deshalb wird er hier wieder abgemeldet.
@MainActor
enum Hintergrund {
    private static var zeitgeber: Timer?
    private static var beobachter: Any?

    static func starten() {
        alterDienstAbmelden()
        guard zeitgeber == nil else { return }
        // Immer den aktuellen Datenbestand nehmen – er wird neu geöffnet, wenn Claude etwas ändert
        let pruefen = { Task { @MainActor in await Mitteilungen.pruefen(context: Datenbank.container.mainContext) } }
        _ = pruefen()
        zeitgeber = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { _ = pruefen() }
        }
        zeitgeber?.tolerance = 60
        beobachter = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { _ = pruefen() }
        }
    }

    /// Den früheren Hintergrunddienst (Version 1.5) abmelden, falls er noch angemeldet ist
    private static func alterDienstAbmelden() {
        let dienst = SMAppService.agent(plistName: "de.juliandressler.Abos.erinnerung.plist")
        if dienst.status != .notRegistered && dienst.status != .notFound {
            dienst.unregister { _ in }
        }
        UserDefaults.standard.removeObject(forKey: "hintergrundAngemeldetFuer")
        UserDefaults.standard.removeObject(forKey: "hintergrundPruefung")
    }
}
