import Foundation

/// Horaires d'ouverture au format OpenStreetMap, ex. "Mo-Sa 08:30-20:00; Su 09:00-12:30".
/// Gère les formes courantes : jours et plages de jours, listes, plusieurs créneaux, "off",
/// passage de minuit, "24/7" et règles des jours fériés (ignorées).
/// Les syntaxes avancées (mois, semaines, lever du soleil, commentaires…) ne sont pas
/// interprétées : l'initialiseur renvoie alors nil et l'app affiche le texte brut.
struct OpeningHours: Hashable {
    struct Span: Hashable {
        /// Minutes depuis minuit. `end` dépasse 1440 quand le créneau finit après minuit.
        let start: Int
        let end: Int
    }

    enum Status: Equatable {
        case open(closesAt: Date?)
        case closed(opensAt: Date?)

        var isOpen: Bool {
            if case .open = self { return true }
            return false
        }
    }

    /// Créneaux par jour : 0 = lundi … 6 = dimanche.
    let week: [[Span]]

    static let dayLabels = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

    init(week: [[Span]]) {
        self.week = week
    }

    init?(_ raw: String) {
        guard let tokens = OpeningHours.tokenize(raw), !tokens.isEmpty,
              let week = OpeningHours.parse(tokens) else { return nil }
        self.week = week
    }

    /// Ouvert tous les jours, toute la journée.
    var isAlwaysOpen: Bool {
        week.allSatisfy { day in day.contains { $0.start <= 0 && $0.end >= 1440 } }
    }

    // MARK: Statut à un instant donné

    func status(at date: Date, calendar: Calendar = .current) -> Status {
        if isAlwaysOpen { return .open(closesAt: nil) }
        let startOfToday = calendar.startOfDay(for: date)
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let today = OpeningHours.weekdayIndex(of: date, calendar: calendar)
        let yesterday = (today + 6) % 7

        // Créneau commencé la veille qui déborde après minuit.
        for span in week[yesterday] where span.end > 1440 && now + 1440 >= span.start && now + 1440 < span.end {
            return .open(closesAt: calendar.date(byAdding: .minute, value: span.end - 1440, to: startOfToday))
        }
        for span in week[today] where span.start <= now && now < span.end {
            var end = span.end
            // Ouvert jusqu'à minuit puis dès 0 h le lendemain : on prolonge.
            if end == 1440, let next = week[(today + 1) % 7].first(where: { $0.start == 0 }) {
                end = 1440 + next.end
            }
            return .open(closesAt: calendar.date(byAdding: .minute, value: end, to: startOfToday))
        }
        return .closed(opensAt: nextOpening(after: now, today: today, startOfToday: startOfToday, calendar: calendar))
    }

    private func nextOpening(after now: Int, today: Int, startOfToday: Date, calendar: Calendar) -> Date? {
        for offset in 0..<8 {
            let day = (today + offset) % 7
            let starts = week[day].map(\.start).sorted()
            let candidate = offset == 0 ? starts.first(where: { $0 > now }) : starts.first
            if let start = candidate, let dayStart = calendar.date(byAdding: .day, value: offset, to: startOfToday) {
                return calendar.date(byAdding: .minute, value: start, to: dayStart)
            }
        }
        return nil
    }

    /// "Ouvert · ferme à 20h", "Ferme bientôt (20h)", "Fermé · ouvre demain à 8h30"…
    func statusText(at date: Date = Date(), calendar: Calendar = .current) -> String {
        switch status(at: date, calendar: calendar) {
        case .open(let closesAt):
            guard let closesAt else { return "Ouvert 24 h/24" }
            let time = OpeningHours.clock(of: closesAt, calendar: calendar)
            if closesAt.timeIntervalSince(date) <= 3600 { return "Ferme bientôt (\(time))" }
            return "Ouvert · ferme à \(time)"
        case .closed(let opensAt):
            guard let opensAt else { return "Fermé" }
            let time = OpeningHours.clock(of: opensAt, calendar: calendar)
            if calendar.isDate(opensAt, inSameDayAs: date) { return "Fermé · ouvre à \(time)" }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
               calendar.isDate(opensAt, inSameDayAs: tomorrow) {
                return "Fermé · ouvre demain à \(time)"
            }
            let day = OpeningHours.dayLabels[OpeningHours.weekdayIndex(of: opensAt, calendar: calendar)].lowercased()
            return "Fermé · ouvre \(day) à \(time)"
        }
    }

    // MARK: Affichage de la semaine

    /// "8h30–12h30, 14h–19h", "24 h/24" ou "Fermé".
    func description(forDay day: Int) -> String {
        let spans = week[day]
        if spans.isEmpty { return "Fermé" }
        if spans.contains(where: { $0.start <= 0 && $0.end >= 1440 }) { return "24 h/24" }
        return spans
            .map { "\(OpeningHours.clock($0.start))–\(OpeningHours.clock($0.end))" }
            .joined(separator: ", ")
    }

    /// 0 = lundi … 6 = dimanche.
    static func weekdayIndex(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// 510 -> "8h30", 1200 -> "20h", 1440 -> "minuit".
    static func clock(_ minutes: Int) -> String {
        if minutes == 1440 { return "minuit" }
        let value = ((minutes % 1440) + 1440) % 1440
        let h = value / 60
        let m = value % 60
        return m == 0 ? "\(h)h" : String(format: "%dh%02d", h, m)
    }

    static func clock(of date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    // MARK: Analyse du texte OpenStreetMap

    private enum Token: Equatable {
        case day(Int)
        case holiday
        case time(Int)
        case dash
        case comma
        case semicolon
        case off
        case allWeek
    }

    private static let dayNames = ["mo": 0, "tu": 1, "we": 2, "th": 3, "fr": 4, "sa": 5, "su": 6]

    private static func tokenize(_ raw: String) -> [Token]? {
        let chars = Array(raw.lowercased())
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                i += 1
            } else if c == "-" || c == "–" {
                tokens.append(.dash)
                i += 1
            } else if c == "," {
                tokens.append(.comma)
                i += 1
            } else if c == ";" {
                tokens.append(.semicolon)
                i += 1
            } else if c == "|" {
                // "||" (règle de repli) : traitée comme une règle ordinaire.
                guard i + 1 < chars.count, chars[i + 1] == "|" else { return nil }
                tokens.append(.semicolon)
                i += 2
            } else if c.isLetter {
                var j = i
                while j < chars.count, chars[j].isLetter { j += 1 }
                let word = String(chars[i..<j])
                if let day = dayNames[word] {
                    tokens.append(.day(day))
                } else if word == "ph" || word == "sh" {
                    tokens.append(.holiday)
                } else if word == "off" || word == "closed" {
                    tokens.append(.off)
                } else {
                    return nil
                }
                i = j
            } else if c.isASCII && c.isNumber {
                var j = i
                while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
                if j < chars.count, chars[j] == "/" {
                    guard j + 1 < chars.count, String(chars[i..<(j + 2)]) == "24/7" else { return nil }
                    tokens.append(.allWeek)
                    i = j + 2
                    continue
                }
                guard j < chars.count, chars[j] == ":" else { return nil }
                var k = j + 1
                while k < chars.count, chars[k].isASCII, chars[k].isNumber { k += 1 }
                guard k - (j + 1) == 2,
                      let hours = Int(String(chars[i..<j])),
                      let minutes = Int(String(chars[(j + 1)..<k])),
                      hours <= 48, minutes < 60 else { return nil }
                tokens.append(.time(hours * 60 + minutes))
                i = k
            } else {
                return nil
            }
        }
        return tokens
    }

    private static func isDayLike(_ token: Token) -> Bool {
        if case .day = token { return true }
        return token == .holiday
    }

    private static func parse(_ tokens: [Token]) -> [[Span]]? {
        var week: [[Span]] = Array(repeating: [], count: 7)
        var appliedRule = false
        var i = 0
        while i < tokens.count {
            // 1. Sélecteur de jours ("Mo-Fr", "Mo,We,Fr", "Sa,PH"…)
            var days = Set<Int>()
            var hasDaySelector = false
            var holidayOnly = true
            while i < tokens.count {
                if case .day(let first) = tokens[i] {
                    hasDaySelector = true
                    holidayOnly = false
                    i += 1
                    if i + 1 < tokens.count, tokens[i] == .dash, case .day(let last) = tokens[i + 1] {
                        var day = first
                        days.insert(day)
                        while day != last {
                            day = (day + 1) % 7
                            days.insert(day)
                        }
                        i += 2
                    } else {
                        days.insert(first)
                    }
                } else if tokens[i] == .holiday {
                    hasDaySelector = true
                    i += 1
                } else {
                    break
                }
                if i + 1 < tokens.count, tokens[i] == .comma, isDayLike(tokens[i + 1]) {
                    i += 1
                } else {
                    break
                }
            }

            // 2. Créneaux horaires ("08:00-12:00,14:00-19:00", "off", "24/7")
            var spans: [Span] = []
            var closed = false
            if i < tokens.count, tokens[i] == .off {
                closed = true
                i += 1
            } else if i < tokens.count, tokens[i] == .allWeek {
                spans = [Span(start: 0, end: 1440)]
                i += 1
            } else {
                while i + 2 < tokens.count,
                      case .time(let start) = tokens[i],
                      tokens[i + 1] == .dash,
                      case .time(let rawEnd) = tokens[i + 2] {
                    let end = rawEnd <= start ? rawEnd + 1440 : rawEnd
                    spans.append(Span(start: start, end: end))
                    i += 3
                    if i + 1 < tokens.count, tokens[i] == .comma, case .time = tokens[i + 1] {
                        i += 1
                    } else {
                        break
                    }
                }
                if spans.isEmpty { return nil }
            }

            // 3. Une règle remplace les précédentes pour les jours qu'elle cite.
            if !(hasDaySelector && holidayOnly) {
                let target: Set<Int> = hasDaySelector ? days : Set(0..<7)
                for day in target {
                    week[day] = closed ? [] : spans
                }
                appliedRule = true
            }

            // 4. Séparateur de règles.
            if i < tokens.count {
                guard tokens[i] == .semicolon || tokens[i] == .comma else { return nil }
                i += 1
            }
        }
        return appliedRule ? week : nil
    }
}
