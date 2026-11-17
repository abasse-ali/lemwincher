import Foundation
import CoreLocation
import Observation

/// État global de l'app : réglages, relevés de prix, liste de courses, magasins proches, classement.
@Observable
final class AppModel {
    var state: PersistedState
    var stores: [Store] = []
    var storesLoading = false
    var storesError: String?
    var storesSource: String?
    /// Le magasin le plus proche de chaque enseigne présente dans la zone (clé = enseigne).
    var nearestStoreByChain: [String: Store] = [:]
    /// Pays de la zone (ex. "FR"), déduit des magasins Open Prices proches.
    var detectedCountry: String?

    var chainIndex: ChainIndexReport?
    var chainIndexLoading = false
    var chainIndexError: String?

    let locationManager = LocationManager()
    let account = OpenPricesAccount()

    @ObservationIgnored private var refreshGeneration = 0

    init() {
        state = AppModel.load()
        chainIndex = AppModel.loadChainIndex()
    }

    // MARK: Position de référence

    var settings: AppSettings {
        get { state.settings }
        set { state.settings = newValue }
    }

    var radiusMeters: Double { state.settings.radiusKm * 1000 }

    /// Domicile si choisi dans les réglages, sinon position actuelle.
    var referenceLocation: CLLocation? {
        if state.settings.useHome, let home = state.settings.home {
            return home.location
        }
        return locationManager.location
    }

    /// Change quand la zone de recherche change (≈100 m ou rayon) : sert à recharger les données.
    var locationKey: String {
        guard let ref = referenceLocation else { return "none" }
        return String(format: "%.3f|%.3f|%.0f",
                      ref.coordinate.latitude, ref.coordinate.longitude, state.settings.radiusKm)
    }

    /// Pays utilisé pour les estimations nationales.
    var country: String? {
        detectedCountry ?? Locale.current.region?.identifier.uppercased()
    }

    // MARK: Magasins

    @MainActor
    func refreshStores() async {
        guard let ref = referenceLocation else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        storesLoading = true
        storesError = nil

        let radius = state.settings.radiusKm
        let result = await StoreFinder.nearby(lat: ref.coordinate.latitude,
                                              lon: ref.coordinate.longitude,
                                              radiusKm: radius)
        guard generation == refreshGeneration else { return }

        stores = result.stores
        nearestStoreByChain = AppModel.nearestByChain(result.stores)
        storesSource = result.source
        if let code = result.countryCode { detectedCountry = code }
        if result.stores.isEmpty {
            storesError = "Aucun magasin trouvé à moins de \(Int(radius)) km. Vérifiez votre connexion ou augmentez le rayon dans Réglages."
        }
        storesLoading = false
    }

    /// Magasins affichés : supermarchés (ou tout) + favoris + magasins avec des prix.
    var visibleStores: [Store] {
        guard state.settings.supermarketsOnly else { return stores }
        let favoriteIDs = Set(state.settings.favoriteStores.map(\.id))
        return stores.filter { $0.isSupermarket || ($0.priceCount ?? 0) > 0 || favoriteIDs.contains($0.id) }
    }

    /// Magasins proches + favoris + magasins déjà utilisés dans mes relevés.
    var knownStores: [Store] {
        var seen = Set<String>()
        var result: [Store] = []
        for store in stores + state.settings.favoriteStores + state.myPrices.map(\.store) where !seen.contains(store.id) {
            seen.insert(store.id)
            result.append(store)
        }
        return result
    }

    /// Le magasin où l'on se trouve probablement (le plus proche de la position GPS réelle).
    func storeAtCurrentPosition(maxDistance: Double = 250) -> Store? {
        guard let here = locationManager.location else { return nil }
        let candidates = knownStores.map { ($0, $0.location.distance(from: here)) }
            .filter { $0.1 <= maxDistance }
        return candidates.min { $0.1 < $1.1 }?.0
    }

    /// Le magasin le plus proche de chaque enseigne présente dans la zone (les magasins sont déjà triés par distance).
    private static func nearestByChain(_ sortedStores: [Store]) -> [String: Store] {
        var result: [String: Store] = [:]
        for store in sortedStores {
            guard let key = store.chainKey, result[key] == nil else { continue }
            result[key] = store
        }
        return result
    }

    // MARK: Favoris

    func isFavorite(_ store: Store) -> Bool {
        state.settings.favoriteStores.contains { $0.id == store.id }
    }

    func toggleFavorite(_ store: Store) {
        if isFavorite(store) {
            state.settings.favoriteStores.removeAll { $0.id == store.id }
        } else {
            state.settings.favoriteStores.append(store)
        }
    }

    // MARK: Classement des enseignes

    @MainActor
    func refreshChainIndex(force: Bool = false) async {
        let currency = state.settings.currency
        let country = self.country
        if !force, let report = chainIndex,
           report.currency == currency,
           report.country == (country ?? ""),
           Date().timeIntervalSince(report.date) < 3 * 24 * 3600 {
            return
        }
        guard !chainIndexLoading else { return }
        chainIndexLoading = true
        chainIndexError = nil
        do {
            let report = try await ChainIndexBuilder.build(country: country, currency: currency)
            chainIndex = report
            AppModel.saveChainIndex(report)
        } catch {
            if !error.isCancellation {
                chainIndexError = "Classement indisponible : \(error.localizedDescription)"
            }
        }
        chainIndexLoading = false
    }

    // MARK: Mes prix

    func addMyPrice(_ price: MyPrice) {
        state.myPrices.append(price)
        remember(price.product)
    }

    func markShared(_ id: UUID, priceID: Int) {
        if let index = state.myPrices.firstIndex(where: { $0.id == id }) {
            state.myPrices[index].sharedPriceID = priceID
        }
    }

    func deleteMyPrices(ids: Set<UUID>) {
        state.myPrices.removeAll { ids.contains($0.id) }
    }

    func myObservations(productCode: String? = nil, storeID: String? = nil) -> [PriceObservation] {
        let filtered = state.myPrices.filter { p in
            (productCode == nil || p.product.code == productCode) && (storeID == nil || p.store.id == storeID)
        }
        return PriceEngine.observations(from: filtered)
    }

    // MARK: Liste de courses

    func addToList(_ product: Product) {
        if let index = state.shoppingList.firstIndex(where: { $0.product.code == product.code }) {
            state.shoppingList[index].quantity += 1
        } else {
            state.shoppingList.append(ShoppingItem(product: product))
        }
    }

    func isInList(_ product: Product) -> Bool {
        state.shoppingList.contains { $0.product.code == product.code }
    }

    /// Texte de la liste pour la partager (Messages, WhatsApp…).
    var shoppingListText: String {
        let lines = state.shoppingList.map { item in
            (item.checked ? "✓ " : "• ") + (item.quantity > 1 ? "\(item.quantity) × " : "") + item.product.name
        }
        return "Ma liste de courses (Lemwincher)\n" + lines.joined(separator: "\n")
    }

    // MARK: Produits consultés

    func remember(_ product: Product) {
        guard product.hasDetails else { return }
        if state.recentProducts.first == product { return }
        state.recentProducts.removeAll { $0.code == product.code }
        state.recentProducts.insert(product, at: 0)
        if state.recentProducts.count > 15 {
            state.recentProducts.removeLast(state.recentProducts.count - 15)
        }
    }

    // MARK: Sauvegarde

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var fileURL: URL { documents.appendingPathComponent("lemwincher.json") }
    private static var chainIndexURL: URL { documents.appendingPathComponent("classement-enseignes.json") }

    private static func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    private static func loadChainIndex() -> ChainIndexReport? {
        guard let data = try? Data(contentsOf: chainIndexURL) else { return nil }
        return try? JSONDecoder().decode(ChainIndexReport.self, from: data)
    }

    private static func saveChainIndex(_ report: ChainIndexReport) {
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: chainIndexURL, options: .atomic)
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: AppModel.fileURL, options: .atomic)
        } catch {
            print("Lemwincher: sauvegarde impossible – \(error)")
        }
    }

    func resetAll() {
        state = PersistedState()
    }
}
