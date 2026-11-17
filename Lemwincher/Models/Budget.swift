import Foundation

// MARK: - Dépenses

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case groceries = "courses"
    case household = "maison"
    case fuel = "carburant"
    case other = "autre"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .groceries: return "Courses alimentaires"
        case .household: return "Hygiène et maison"
        case .fuel: return "Carburant"
        case .other: return "Autre"
        }
    }

    var icon: String {
        switch self {
        case .groceries: return "cart.fill"
        case .household: return "house.fill"
        case .fuel: return "fuelpump.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

/// Une dépense (un passage en caisse, un plein…).
struct Expense: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Double
    var date: Date
    var storeName: String? = nil
    var storeID: String? = nil
    /// Enseigne du magasin ("e leclerc"…), pour les conseils d'économie.
    var chainKey: String? = nil
    var category: ExpenseCategory = .groceries
    var note: String? = nil
    var itemCount: Int? = nil
}

extension Expense {
    enum CodingKeys: String, CodingKey {
        case id, amount, date, storeName, storeID, chainKey, category, note, itemCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        amount = try c.decode(Double.self, forKey: .amount)
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        storeName = try? c.decode(String.self, forKey: .storeName)
        storeID = try? c.decode(String.self, forKey: .storeID)
        chainKey = try? c.decode(String.self, forKey: .chainKey)
        category = (try? c.decode(ExpenseCategory.self, forKey: .category)) ?? .groceries
        note = try? c.decode(String.self, forKey: .note)
        itemCount = try? c.decode(Int.self, forKey: .itemCount)
    }
}

// MARK: - Période et bilan

/// Une période de budget : du jour de départ (ex. le 1er, ou le jour de la paie) au même jour du mois suivant.
struct BudgetPeriod: Equatable, Hashable {
    let start: Date
    /// Exclu.
    let end: Date
    let days: Int

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

struct BudgetSummary {
    enum Status: Equatable {
        case ok
        /// 80 % atteints, ou rythme de dépense qui mène au dépassement.
        case warning
        case over
    }

    let period: BudgetPeriod
    let budget: Double
    let spent: Double
    /// Dépenses de la période, les plus récentes d'abord.
    let expenses: [Expense]
    /// Jours écoulés, aujourd'hui compris (1 … days).
    let daysElapsed: Int

    var remaining: Double { budget - spent }
    var fraction: Double { budget > 0 ? spent / budget : 0 }
    /// Jours restants, aujourd'hui compris.
    var daysLeft: Int { max(period.days - daysElapsed + 1, 1) }
    /// Ce qu'on peut encore dépenser par jour jusqu'à la fin de la période.
    var dailyAllowance: Double { max(remaining, 0) / Double(daysLeft) }
    /// Dépense prévue en fin de période au rythme actuel.
    var projected: Double {
        guard daysElapsed > 0 else { return spent }
        return spent / Double(daysElapsed) * Double(period.days)
    }

    var status: Status {
        if spent > budget + 0.004 { return .over }
        if fraction >= 0.8 || (daysElapsed >= 5 && projected > budget * 1.05) { return .warning }
        return .ok
    }

    /// Message affiché sous la jauge.
    func message(currency: String) -> String {
        switch status {
        case .over:
            return "Budget dépassé de \(Fmt.price(spent - budget, currency)) ce mois-ci."
        case .warning:
            if fraction >= 0.8 {
                return "Attention : \(Int((fraction * 100).rounded())) % du budget est déjà dépensé."
            }
            return "Au rythme actuel, vous dépenserez environ \(Fmt.price(projected, currency)) d'ici la fin du mois."
        case .ok:
            if spent == 0 { return "Aucune dépense pour l'instant : ajoutez vos courses avec le bouton +." }
            return "Vous êtes dans les clous : continuez comme ça !"
        }
    }
}

/// Total d'une période passée (historique).
struct PeriodTotal: Identifiable, Hashable {
    let period: BudgetPeriod
    let total: Double
    var id: Date { period.start }
}

/// Point de la courbe des dépenses cumulées.
struct BudgetPoint: Identifiable, Hashable {
    let date: Date
    let amount: Double
    let series: String
    var id: String { series + "\(date.timeIntervalSince1970)" }
}

/// Part des dépenses par magasin ou par catégorie.
struct SpendingShare: Identifiable, Hashable {
    let name: String
    let total: Double
    let fraction: Double
    var id: String { name }
}

/// Conseil d'économie fondé sur le classement des enseignes.
struct SavingsTip: Hashable {
    let chainName: String
    let storeName: String?
    let saving: Double
    let difference: String
}

enum BudgetEngine {
    /// Période qui contient `date`. Le jour de départ est ramené entre 1 et 28.
    static func period(containing date: Date, startDay: Int, calendar: Calendar = .current) -> BudgetPeriod {
        let day = min(max(startDay, 1), 28)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var startParts = DateComponents(year: parts.year, month: parts.month, day: day)
        if (parts.day ?? 1) < day {
            startParts.month = (parts.month ?? 1) - 1
        }
        let start = calendar.date(from: startParts).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(30 * 86_400)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 30
        return BudgetPeriod(start: start, end: end, days: max(days, 1))
    }

    static func summary(expenses: [Expense], budget: Double, startDay: Int,
                        now: Date = Date(), calendar: Calendar = .current) -> BudgetSummary {
        let period = period(containing: now, startDay: startDay, calendar: calendar)
        let inPeriod = expenses.filter { period.contains($0.date) }.sorted { $0.date > $1.date }
        let spent = inPeriod.reduce(0) { $0 + $1.amount }
        let elapsed = (calendar.dateComponents([.day], from: period.start, to: calendar.startOfDay(for: now)).day ?? 0) + 1
        return BudgetSummary(period: period, budget: budget, spent: spent, expenses: inPeriod,
                             daysElapsed: min(max(elapsed, 1), period.days))
    }

    /// Totaux des `count` dernières périodes (la plus ancienne d'abord), période en cours comprise.
    static func history(expenses: [Expense], startDay: Int, count: Int,
                        now: Date = Date(), calendar: Calendar = .current) -> [PeriodTotal] {
        var result: [PeriodTotal] = []
        var reference = now
        for _ in 0..<max(count, 1) {
            let period = period(containing: reference, startDay: startDay, calendar: calendar)
            let total = expenses.filter { period.contains($0.date) }.reduce(0) { $0 + $1.amount }
            result.insert(PeriodTotal(period: period, total: total), at: 0)
            reference = period.start.addingTimeInterval(-3600)
        }
        return result
    }

    /// Courbe des dépenses cumulées jour après jour, et rythme idéal (budget réparti sur la période).
    static func cumulative(_ summary: BudgetSummary, calendar: Calendar = .current) -> [BudgetPoint] {
        var points: [BudgetPoint] = []
        var total = 0.0
        let ordered = summary.expenses.sorted { $0.date < $1.date }
        for offset in 0..<summary.daysElapsed {
            guard let day = calendar.date(byAdding: .day, value: offset, to: summary.period.start),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            total += ordered.filter { $0.date >= day && $0.date < next }.reduce(0) { $0 + $1.amount }
            points.append(BudgetPoint(date: day, amount: total, series: "Dépensé"))
        }
        let lastDay = calendar.date(byAdding: .day, value: summary.period.days - 1, to: summary.period.start) ?? summary.period.end
        points.append(BudgetPoint(date: summary.period.start, amount: 0, series: "Rythme idéal"))
        points.append(BudgetPoint(date: lastDay, amount: summary.budget, series: "Rythme idéal"))
        return points
    }

    /// Dépenses regroupées par magasin (ou par catégorie), de la plus grosse à la plus petite.
    static func shares(_ expenses: [Expense], by key: (Expense) -> String) -> [SpendingShare] {
        let total = expenses.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        var sums: [String: Double] = [:]
        for expense in expenses {
            sums[key(expense), default: 0] += expense.amount
        }
        return sums
            .map { SpendingShare(name: $0.key, total: $0.value, fraction: $0.value / total) }
            .sorted { $0.total > $1.total }
    }

    /// Seuil franchi par une nouvelle dépense (80 ou 100 % du budget), sinon nil.
    static func thresholdCrossed(before: Double, after: Double, budget: Double) -> Int? {
        guard budget > 0 else { return nil }
        if before <= budget && after > budget { return 100 }
        if before < budget * 0.8 && after >= budget * 0.8 { return 80 }
        return nil
    }

    /// Économie possible en faisant les mêmes courses dans l'enseigne la moins chère du quartier.
    static func savingsTip(expenses: [Expense], report: ChainIndexReport?,
                           nearbyChains: [String: Store]) -> SavingsTip? {
        guard let report else { return nil }
        let candidates = report.entries.filter { nearbyChains[$0.key] != nil }
        guard let best = candidates.min(by: { $0.index < $1.index }) else { return nil }
        var saving = 0.0
        for expense in expenses where expense.category == .groceries {
            guard let key = expense.chainKey, key != best.key,
                  let entry = report.entry(for: key), entry.index > best.index else { continue }
            saving += expense.amount * (1 - best.index / entry.index)
        }
        guard saving >= 1 else { return nil }
        return SavingsTip(chainName: best.name,
                          storeName: nearbyChains[best.key]?.name,
                          saving: saving,
                          difference: best.differenceText)
    }
}
