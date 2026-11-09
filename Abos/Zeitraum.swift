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

    /// Letzter Tag, an dem noch gezahlt wird; nil = läuft weiter
    var letzterZahltag: Date? {
        if istAktiv {
            guard !autoVerlaengerung, let ende = laufzeitende else { return nil }
            return Abo.letzterTag(vor: ende)
        }
        // Gekündigt: bis zum Ende der Laufzeit, die bei der Kündigung galt
        if let eintrag = verlauf.first(where: { $0.art == .gekuendigt }) {
            if let r = eintrag.vertragsende { return Abo.letzterTag(vor: r) }
            return eintrag.datum
        }
        // Gekündigt, bevor es den Verlauf gab: Ende unbekannt, keine Zahlungen annehmen
        return laufzeitende.map(Abo.letzterTag(vor:)) ?? .distantPast
    }

    /// Zahltage im Bereich (einschließlich), gerechnet ab „Abo seit“ im Zahlungsintervall
    func zahltage(von start: Date, bis ende: Date) -> [Date] {
        guard betrag != nil else { return [] }
        let cal = Kalender.de
        let anfang = cal.startOfDay(for: startdatum)
        let grenze = min(ende, letzterZahltag ?? .distantFuture)
        guard anfang <= grenze else { return [] }
        let schritt = monateProIntervall
        var k = 0
        if anfang < start {
            let monate = cal.dateComponents([.month], from: anfang, to: start).month ?? 0
            k = max(0, monate / schritt - 1)
        }
        var tage: [Date] = []
        var sicherung = 0
        while sicherung < 2000, let tag = cal.date(byAdding: .month, value: k * schritt, to: anfang), tag <= grenze {
            if tag >= start { tage.append(tag) }
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
