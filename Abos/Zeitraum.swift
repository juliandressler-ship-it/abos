import Foundation

// MARK: - Kosten-Ansicht der Übersicht

/// Pro Monat und pro Jahr sind Durchschnittswerte; „Zeitraum“ zählt die tatsächlichen Zahlungen
enum KostenAnsicht: String, CaseIterable, Identifiable {
    case monat, jahr, zeitraum
    var id: String { rawValue }

    var titel: String {
        switch self {
        case .monat: return "Pro Monat"
        case .jahr: return "Pro Jahr"
        case .zeitraum: return "Zeitraum"
        }
    }
}

enum ZeitraumVorgabe: String, CaseIterable, Identifiable {
    case dieserMonat, letzterMonat, diesesJahr, letztesJahr, letzte12Monate, eigener
    var id: String { rawValue }

    var titel: String {
        switch self {
        case .dieserMonat: return "Dieser Monat"
        case .letzterMonat: return "Letzter Monat"
        case .diesesJahr: return "Dieses Jahr"
        case .letztesJahr: return "Letztes Jahr"
        case .letzte12Monate: return "Letzte 12 Monate"
        case .eigener: return "Eigener Zeitraum …"
        }
    }

    /// Erster und letzter Tag (jeweils einschließlich)
    func bereich(von: Date, bis: Date, heute: Date = Date()) -> (start: Date, ende: Date) {
        let cal = Kalender.de
        let tag = cal.startOfDay(for: heute)
        let monatsAnfang = cal.date(from: cal.dateComponents([.year, .month], from: tag)) ?? tag
        let jahresAnfang = cal.date(from: cal.dateComponents([.year], from: tag)) ?? tag
        func plus(_ k: Calendar.Component, _ n: Int, _ d: Date) -> Date { cal.date(byAdding: k, value: n, to: d) ?? d }
        switch self {
        case .dieserMonat: return (monatsAnfang, plus(.day, -1, plus(.month, 1, monatsAnfang)))
        case .letzterMonat: return (plus(.month, -1, monatsAnfang), plus(.day, -1, monatsAnfang))
        case .diesesJahr: return (jahresAnfang, plus(.day, -1, plus(.year, 1, jahresAnfang)))
        case .letztesJahr: return (plus(.year, -1, jahresAnfang), plus(.day, -1, jahresAnfang))
        case .letzte12Monate: return (plus(.day, 1, plus(.year, -1, tag)), tag)
        case .eigener:
            let a = cal.startOfDay(for: min(von, bis)), b = cal.startOfDay(for: max(von, bis))
            return (a, b)
        }
    }

    /// Beschriftung wie „November 2026“, „2025“ oder „01.03.–15.04.2026“
    func beschreibung(von: Date, bis: Date, heute: Date = Date()) -> String {
        let (a, b) = bereich(von: von, bis: bis, heute: heute)
        switch self {
        case .dieserMonat, .letzterMonat:
            return a.formatted(.dateTime.month(.wide).year().locale(Format.locale))
        case .diesesJahr, .letztesJahr:
            return a.formatted(.dateTime.year().locale(Format.locale))
        case .letzte12Monate, .eigener:
            return "\(Format.datum(a)) – \(Format.datum(b))"
        }
    }
}

// MARK: - Zahlungen eines Abos

extension Abo {
    /// Eigener Anteil an einer einzelnen Zahlung
    var anteilProZahlung: Double? {
        betrag.map { $0 * max(0, anteilProzent) / 100 }
    }

    /// Zeiten, in denen das Abo lief: ab „Abo seit“, unterbrochen durch Kündigungen
    /// (bis zum letzten Tag der damaligen Laufzeit) und fortgesetzt ab einer Wiederaufnahme.
    /// `bis == nil` heißt: läuft weiter.
    var aktivePhasen: [(von: Date, bis: Date?)] {
        let cal = Kalender.de
        var phasen: [(von: Date, bis: Date?)] = []
        var beginn: Date? = cal.startOfDay(for: startdatum)
        // Verlauf ist neueste zuerst; hier chronologisch durchgehen
        for e in verlauf.reversed() {
            switch e.art {
            case .gekuendigt:
                if let b = beginn {
                    let ende = e.vertragsende.map(Abo.letzterTag(vor:)) ?? cal.startOfDay(for: e.datum)
                    phasen.append((von: b, bis: max(b, ende)))
                    beginn = nil
                }
            case .reaktiviert:
                if beginn == nil { beginn = cal.startOfDay(for: e.datum) }
            case .angelegt:
                break
            }
        }
        if let b = beginn {
            if istAktiv {
                let ende = (!autoVerlaengerung) ? laufzeitende.map(Abo.letzterTag(vor:)) : nil
                phasen.append((von: b, bis: ende))
            } else if let ende = laufzeitende.map(Abo.letzterTag(vor:)) {
                // Gekündigt, bevor es den Verlauf gab: nur bis zum bekannten Laufzeitende
                phasen.append((von: b, bis: max(b, ende)))
            }
        } else if istAktiv, let letzte = phasen.last?.bis {
            // Aktiv, aber ohne „Wieder aktiviert“-Eintrag: ab dem Tag nach der letzten Phase
            phasen.append((von: cal.date(byAdding: .day, value: 1, to: letzte) ?? letzte, bis: nil))
        }
        return phasen
    }

    /// Zahltage im Bereich (einschließlich): im Zahlungsintervall ab „Abo seit“,
    /// aber nur in Zeiten, in denen das Abo lief
    func zahltage(von start: Date, bis ende: Date) -> [Date] {
        guard betrag != nil else { return [] }
        let phasen = aktivePhasen
        guard !phasen.isEmpty else { return [] }
        let cal = Kalender.de
        let anfang = cal.startOfDay(for: startdatum)
        let offen = phasen.contains { $0.bis == nil }
        let spaetestens = offen ? Date.distantFuture : (phasen.compactMap(\.bis).max() ?? anfang)
        let grenze = min(ende, spaetestens)
        guard anfang <= grenze else { return [] }
        let schritt = monateProIntervall
        var k = 0
        if anfang < start {
            let monate = cal.dateComponents([.month], from: anfang, to: start).month ?? 0
            k = max(0, monate / schritt - 1)
        }
        var tage: [Date] = []
        var sicherung = 0
        while sicherung < 5000, let tag = cal.date(byAdding: .month, value: k * schritt, to: anfang), tag <= grenze {
            let laeuft = phasen.contains { tag >= $0.von && ($0.bis.map { tag <= $0 } ?? true) }
            if tag >= start && laeuft { tage.append(tag) }
            k += 1
            sicherung += 1
        }
        return tage
    }

    /// Summe der eigenen Zahlungen im Bereich; nil, wenn der Betrag noch offen ist
    func kosten(von start: Date, bis ende: Date) -> Double? {
        guard let proZahlung = anteilProZahlung else { return nil }
        return Double(zahltage(von: start, bis: ende).count) * proZahlung
    }
}

// MARK: - Einheit für „pro …“

/// Durchschnittskosten umgerechnet auf Monat, Woche, Tag oder Stunde
enum KostenEinheit: String, CaseIterable, Identifiable {
    case monat, woche, tag, stunde
    var id: String { rawValue }

    /// Faktor gegenüber den Kosten pro Monat
    var faktor: Double {
        switch self {
        case .monat: return 1
        case .woche: return 12.0 / 52.0
        case .tag: return 12.0 / 365.0
        case .stunde: return 12.0 / 365.0 / 24.0
        }
    }

    var titel: String {
        switch self {
        case .monat: return "Pro Monat"
        case .woche: return "Pro Woche"
        case .tag: return "Pro Tag"
        case .stunde: return "Pro Stunde"
        }
    }

    var kurz: String {
        switch self {
        case .monat: return "Monat"
        case .woche: return "Woche"
        case .tag: return "Tag"
        case .stunde: return "Stunde"
        }
    }

    /// „pro Monat“, „pro Tag“ … im Satz
    var text: String { "pro \(kurz)" }
}
