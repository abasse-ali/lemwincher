import Foundation

/// Fichier de sauvegarde exporté par l'app.
struct BackupFile: Codable {
    let version: Int
    let exportedAt: Date
    let state: PersistedState
}

/// Sauvegarde / restauration des données et export CSV des relevés.
enum Backup {
    struct Summary: Equatable {
        var prices = 0
        var listItems = 0
        var favorites = 0
        var watched = 0
        var expenses = 0

        var isEmpty: Bool { prices + listItems + favorites + watched + expenses == 0 }

        var text: String {
            if isEmpty { return "Rien de nouveau : tout était déjà dans l'app." }
            var parts: [String] = []
            if prices > 0 { parts.append("\(prices) relevé\(prices > 1 ? "s" : "")") }
            if listItems > 0 { parts.append("\(listItems) produit\(listItems > 1 ? "s" : "") de liste") }
            if favorites > 0 { parts.append("\(favorites) magasin\(favorites > 1 ? "s" : "") favori\(favorites > 1 ? "s" : "")") }
            if watched > 0 { parts.append("\(watched) produit\(watched > 1 ? "s" : "") suivi\(watched > 1 ? "s" : "")") }
            if expenses > 0 { parts.append("\(expenses) dépense\(expenses > 1 ? "s" : "")") }
            return "Ajouté : " + parts.joined(separator: ", ") + "."
        }
    }

    static func export(_ state: PersistedState, now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(BackupFile(version: 1, exportedAt: now, state: state))
    }

    /// Lit une sauvegarde de l'app (ou directement le fichier de données interne).
    static func decode(_ data: Data) throws -> PersistedState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(BackupFile.self, from: data) {
            return file.state
        }
        return try JSONDecoder().decode(PersistedState.self, from: data)
    }

    /// Ajoute le contenu d'une sauvegarde sans rien effacer ; les doublons sont ignorés.
    static func merge(_ incoming: PersistedState, into state: inout PersistedState) -> Summary {
        var summary = Summary()

        let priceIDs = Set(state.myPrices.map(\.id))
        for price in incoming.myPrices where !priceIDs.contains(price.id) {
            state.myPrices.append(price)
            summary.prices += 1
        }

        var listCodes = Set(state.shoppingList.map(\.product.code))
        for item in incoming.shoppingList where !listCodes.contains(item.product.code) {
            state.shoppingList.append(item)
            listCodes.insert(item.product.code)
            summary.listItems += 1
        }

        var favoriteIDs = Set(state.settings.favoriteStores.map(\.id))
        for store in incoming.settings.favoriteStores where !favoriteIDs.contains(store.id) {
            state.settings.favoriteStores.append(store)
            favoriteIDs.insert(store.id)
            summary.favorites += 1
        }

        var watchedCodes = Set(state.watchlist.map(\.id))
        for item in incoming.watchlist where !watchedCodes.contains(item.id) {
            state.watchlist.append(item)
            watchedCodes.insert(item.id)
            summary.watched += 1
        }

        let expenseIDs = Set(state.expenses.map(\.id))
        for expense in incoming.expenses where !expenseIDs.contains(expense.id) {
            state.expenses.append(expense)
            summary.expenses += 1
        }

        var recentCodes = Set(state.recentProducts.map(\.code))
        for product in incoming.recentProducts where !recentCodes.contains(product.code) && state.recentProducts.count < 15 {
            state.recentProducts.append(product)
            recentCodes.insert(product.code)
        }

        if state.settings.home == nil, let home = incoming.settings.home {
            state.settings.home = home
            state.settings.homeLabel = incoming.settings.homeLabel
        }
        return summary
    }

    /// Relevés au format CSV (séparateur « ; », lisible par Excel / Numbers en français).
    static func csv(_ prices: [MyPrice]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var lines = ["date;magasin;enseigne;adresse;produit;marque;code_barres;prix;devise;promo;partage"]
        for p in prices.sorted(by: { $0.date < $1.date }) {
            let price = String(format: "%.2f", p.price).replacingOccurrences(of: ".", with: ",")
            let fields = [
                formatter.string(from: p.date),
                p.store.name,
                p.store.chainName ?? "",
                p.store.address ?? "",
                p.product.name,
                p.product.brand ?? "",
                p.product.isCustom ? "" : p.product.code,
                price,
                p.currency,
                p.isDiscounted ? "oui" : "non",
                p.sharedPriceID == nil ? "non" : "oui",
            ]
            lines.append(fields.map(escape).joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(";") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
