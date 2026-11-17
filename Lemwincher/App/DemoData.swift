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
        return state
    }
}
