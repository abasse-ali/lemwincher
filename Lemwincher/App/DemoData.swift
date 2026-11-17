import Foundation

/// Données de démonstration utilisées par les tests d'interface (argument de lancement "-uitest") :
/// domicile place du Capitole à Toulouse, une petite liste de courses et quelques relevés.
enum DemoData {
    static let capitole = GeoPoint(lat: 43.6045, lon: 1.4433)

    static let nutella = Product(code: "3017620422003", name: "Nutella", brand: "Ferrero", quantity: "400 g",
                                 imageURL: nil, unitQuantity: 400, unitName: "g", categories: nil)
    static let madeleines = Product(code: "3178530410105", name: "Petites Madeleines", brand: "St Michel", quantity: "500 g",
                                    imageURL: nil, unitQuantity: 500, unitName: "g", categories: nil)
    static let nocciolata = Product(code: "8052575090230", name: "Nocciolata", brand: "Rigoni di Asiago", quantity: "250 g",
                                    imageURL: nil, unitQuantity: 250, unitName: "g", categories: nil)

    static func state(showOnboarding: Bool) -> PersistedState {
        var state = PersistedState()
        state.settings.useHome = true
        state.settings.home = capitole
        state.settings.homeLabel = "Place du Capitole, Toulouse"
        state.settings.radiusKm = 8
        state.settings.currency = "EUR"
        state.settings.hasSeenOnboarding = !showOnboarding

        let bananas = Product.custom(named: "Bananes (1 kg)")
        state.shoppingList = [
            ShoppingItem(product: .custom(named: "Œufs")),
            ShoppingItem(product: nutella),
            ShoppingItem(product: madeleines, quantity: 2),
            ShoppingItem(product: nocciolata),
            ShoppingItem(product: bananas),
        ]
        state.recentProducts = [nutella, madeleines, nocciolata]

        let store = Store(id: "demo:capitole", name: "Carrefour City Capitole", brand: "Carrefour City",
                          kind: "supermarket", address: "Place du Capitole, Toulouse",
                          lat: 43.6043, lon: 1.4440, priceCount: nil, logoURL: nil,
                          openingHours: "Mo-Sa 07:00-22:00; Su 09:00-13:00")
        let day: TimeInterval = 24 * 3600
        let now = Date()
        state.myPrices = [
            MyPrice(product: nutella, store: store, price: 3.89, currency: "EUR", date: now.addingTimeInterval(-90 * day)),
            MyPrice(product: nutella, store: store, price: 4.15, currency: "EUR", date: now.addingTimeInterval(-3 * day)),
            MyPrice(product: bananas, store: store, price: 2.19, currency: "EUR", date: now.addingTimeInterval(-40 * day)),
            MyPrice(product: bananas, store: store, price: 1.99, currency: "EUR", date: now.addingTimeInterval(-3 * day)),
        ]
        state.watchlist = [
            WatchItem(product: nutella, targetPrice: 3.5, bestPrice: 4.15, bestStoreName: store.name, bestDate: now),
        ]

        // Budget de 100 € : quelques dépenses ce mois-ci et le mois dernier.
        state.settings.budgetAmount = 100
        let period = BudgetEngine.period(containing: now, startDay: 1)
        let elapsed = max(Calendar.current.dateComponents([.day], from: period.start, to: now).day ?? 0, 0)
        func dayInPeriod(_ offset: Int) -> Date {
            period.start.addingTimeInterval(TimeInterval(min(offset, elapsed)) * day + 11 * 3600)
        }
        state.expenses = [
            Expense(amount: 23.40, date: dayInPeriod(1), storeName: "Carrefour City Capitole", chainKey: "carrefour city",
                    category: .groceries, itemCount: 9),
            Expense(amount: 31.85, date: dayInPeriod(6), storeName: "E. Leclerc - Blagnac", chainKey: "e leclerc",
                    category: .groceries, itemCount: 17),
            Expense(amount: 8.90, date: dayInPeriod(9), storeName: "Monoprix", chainKey: "monoprix",
                    category: .household, itemCount: 3),
            Expense(amount: 96.40, date: period.start.addingTimeInterval(-10 * day), storeName: "Auchan", chainKey: "auchan",
                    category: .groceries),
            Expense(amount: 24.10, date: period.start.addingTimeInterval(-25 * day), storeName: "Lidl", chainKey: "lidl",
                    category: .groceries),
        ]
        return state
    }
}
