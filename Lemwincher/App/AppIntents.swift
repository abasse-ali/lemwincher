import AppIntents

/// « Dis Siri, ajoute à ma liste Lemwincher » : ajoute un produit à la liste de courses.
struct AddToShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter à ma liste de courses"
    static var description = IntentDescription("Ajoute un produit à la liste de courses de Lemwincher.")

    @Parameter(title: "Produit", requestValueDialog: "Quel produit voulez-vous ajouter ?")
    var product: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ajouter \(\.$product) à ma liste")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = product.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .result(dialog: "Aucun produit indiqué.")
        }
        let model = AppModel.shared
        model.addToList(.custom(named: name))
        model.save()
        let count = model.state.shoppingList.filter { !$0.checked }.count
        let message = "\(name) est dans votre liste (\(count) produit\(count > 1 ? "s" : "") à acheter)."
        return .result(dialog: "\(message)")
    }
}

/// Ouvre l'app sur la liste de courses.
struct OpenShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir ma liste de courses"
    static var description = IntentDescription("Affiche la liste de courses et le magasin le moins cher.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.selectedTab = .list
        return .result()
    }
}

/// Ouvre l'app sur la comparaison de prix (scanner un produit).
struct OpenCompareIntent: AppIntent {
    static var title: LocalizedStringResource = "Comparer un prix"
    static var description = IntentDescription("Ouvre Lemwincher pour comparer le prix d'un produit.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.selectedTab = .compare
        return .result()
    }
}

/// « Dis Siri, combien il me reste Lemwincher » : budget restant du mois.
struct BudgetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Budget courses restant"
    static var description = IntentDescription("Indique combien il reste sur le budget courses du mois.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let summary = model.budgetSummary
        let currency = model.settings.currency
        let message: String
        if summary.remaining >= 0 {
            message = "Il vous reste \(Fmt.price(summary.remaining, currency)) sur \(Fmt.price(summary.budget, currency)) pour \(summary.daysLeft) jours, soit \(Fmt.price(summary.dailyAllowance, currency)) par jour."
        } else {
            message = "Votre budget de \(Fmt.price(summary.budget, currency)) est dépassé de \(Fmt.price(-summary.remaining, currency)) ce mois-ci."
        }
        return .result(dialog: "\(message)")
    }
}

/// Ouvre l'app sur le budget.
struct OpenBudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir mon budget"
    static var description = IntentDescription("Affiche le budget courses du mois.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.selectedTab = .budget
        return .result()
    }
}

struct LemwincherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BudgetStatusIntent(),
                    phrases: [
                        "Combien il me reste \(.applicationName)",
                        "Mon budget \(.applicationName)",
                    ],
                    shortTitle: "Budget restant",
                    systemImageName: "eurosign.circle")
        AppShortcut(intent: OpenBudgetIntent(),
                    phrases: [
                        "Ouvre mon budget \(.applicationName)",
                    ],
                    shortTitle: "Mon budget",
                    systemImageName: "chart.pie")
        AppShortcut(intent: AddToShoppingListIntent(),
                    phrases: [
                        "Ajoute à ma liste \(.applicationName)",
                        "Ajouter un produit à ma liste \(.applicationName)",
                    ],
                    shortTitle: "Ajouter à la liste",
                    systemImageName: "cart.badge.plus")
        AppShortcut(intent: OpenShoppingListIntent(),
                    phrases: [
                        "Ouvre ma liste \(.applicationName)",
                        "Ma liste de courses \(.applicationName)",
                    ],
                    shortTitle: "Ma liste",
                    systemImageName: "cart")
        AppShortcut(intent: OpenCompareIntent(),
                    phrases: [
                        "Compare un prix avec \(.applicationName)",
                    ],
                    shortTitle: "Comparer un prix",
                    systemImageName: "barcode.viewfinder")
    }
}
