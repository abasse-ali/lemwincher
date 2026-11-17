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

struct LemwincherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
