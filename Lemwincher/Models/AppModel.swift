import Foundation
import CoreGraphics
import CoreLocation
import Observation

/// État global de l'app : réglages, relevés de prix, liste de courses, magasins proches,
/// classement des enseignes, carburants, rappels de produits et produits suivis.
@Observable
final class AppModel {
    /// Instance partagée (app, Siri, tâches en arrière-plan).
    static let shared = AppModel()

    var state: PersistedState
    var selectedTab: AppTab = .stores
    /// Réglages ouverts (roue dentée ⚙︎ en haut des écrans).
    var showSettings = false

    // Magasins
    var stores: [Store] = []
    var storesLoading = false
    var storesError: String?
    var storesSource: String?
    /// Le magasin le plus proche de chaque enseigne présente dans la zone (clé = enseigne).
    var nearestStoreByChain: [String: Store] = [:]
    /// Pays de la zone (ex. "FR"), déduit des magasins Open Prices proches.
    var detectedCountry: String?

    // Classement des enseignes
    var chainIndex: ChainIndexReport?
    var chainIndexLoading = false
    var chainIndexError: String?

    // Carburants
    var fuelStations: [FuelStation] = []
    var fuelLoading = false
    var fuelError: String?
    var fuelUpdated: Date?

    // Rappels de produits
    var departmentName: String?
    var localRecalls: [Recall] = []
    var recallsLoading = false
    var recallsError: String?
    /// Rappels en cours, par code-barres normalisé (produits de la liste, suivis, consultés).
    var recallsByGTIN: [String: Recall] = [:]

    // Produits suivis
    var watchChecking = false

    // Budget : message affiché après une dépense qui franchit 80 % ou 100 % du budget.
    var budgetAlert: String?

    /// Produits précis proposés sous les articles de la liste, par recherche ("oeufs").
    var suggestions: [String: SuggestionResults] = [:]

    let locationManager = LocationManager()
    let account = OpenPricesAccount()
    /// Lancé par les tests d'interface : données de démonstration à Toulouse, pas de GPS.
    let isUITest: Bool

    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var fuelLoadedKey: String?
    @ObservationIgnored private var departmentKey: String?
    @ObservationIgnored private var recallsLoadedKey: String?
    /// Codes-barres déjà vérifiés auprès de RappelConso (observé : la fiche affiche « aucun rappel en cours »).
    private var checkedRecallCodes: Set<String> = []
    @ObservationIgnored private var enrichedCodes: Set<String> = []

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITest = arguments.contains("-uitest")
        if isUITest {
            state = DemoData.state(showOnboarding: arguments.contains("-onboarding"))
            chainIndex = nil
        } else {
            state = AppModel.load()
            chainIndex = AppModel.loadChainIndex()
        }
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
        // Affichage immédiat de la dernière liste connue pendant le chargement.
        if stores.isEmpty, let cached = StoreCache.load(near: ref, radiusKm: radius) {
            applyStores(cached.stores, source: cacheSource(cached))
            if let code = cached.countryCode { detectedCountry = code }
        }

        let result = await StoreFinder.nearby(lat: ref.coordinate.latitude,
                                              lon: ref.coordinate.longitude,
                                              radiusKm: radius)
        guard generation == refreshGeneration else { return }

        if result.complete {
            applyStores(result.stores, source: result.source)
            StoreCache.save(StoreCacheEntry(lat: ref.coordinate.latitude, lon: ref.coordinate.longitude,
                                            radiusKm: radius, date: Date(), stores: result.stores,
                                            countryCode: result.countryCode))
        } else if let cached = StoreCache.load(near: ref, radiusKm: radius), !cached.stores.isEmpty {
            // Overpass saturé : on garde la dernière liste complète (horaires, téléphones), complétée par
            // les magasins proches trouvés par Photon et les données fraîches d'Open Prices.
            let merged = StoreFinder.merge(cached: cached.stores, fresh: result.stores, center: ref)
            applyStores(merged, source: cacheSource(cached))
            if result.fromOSM && merged.count > cached.stores.count {
                StoreCache.save(StoreCacheEntry(lat: cached.lat, lon: cached.lon, radiusKm: cached.radiusKm,
                                                date: cached.date, stores: merged,
                                                countryCode: cached.countryCode ?? result.countryCode))
            }
        } else {
            applyStores(result.stores, source: result.source)
            if result.fromOSM {
                StoreCache.save(StoreCacheEntry(lat: ref.coordinate.latitude, lon: ref.coordinate.longitude,
                                                radiusKm: radius, date: Date(), stores: result.stores,
                                                countryCode: result.countryCode))
            }
        }
        if let code = result.countryCode { detectedCountry = code }
        if stores.isEmpty {
            storesError = "Aucun magasin trouvé à moins de \(Int(radius)) km. Vérifiez votre connexion ou augmentez le rayon dans Réglages."
            Log.error(.stores, "Aucun magasin trouvé à moins de \(Int(radius)) km", details: "Source : \(result.source)")
        } else if result.complete {
            Log.success(.stores, "\(stores.count) magasins à moins de \(Int(radius)) km", details: "Source : \(result.source)")
        } else {
            Log.warning(.stores, "\(stores.count) magasins : liste partielle (OpenStreetMap ne répond pas)",
                        details: "Source : \(storesSource ?? result.source)")
        }
        storesLoading = false
    }

    private func applyStores(_ list: [Store], source: String) {
        stores = list
        nearestStoreByChain = AppModel.nearestByChain(list)
        storesSource = source
    }

    private func cacheSource(_ entry: StoreCacheEntry) -> String {
        "OpenStreetMap (liste du \(entry.date.formatted(date: .abbreviated, time: .omitted))) et Open Prices"
    }

    /// Magasins affichés : supermarchés (ou tout) + favoris + magasins avec des prix ; option « ouverts maintenant ».
    var visibleStores: [Store] {
        var list = stores
        if state.settings.supermarketsOnly {
            let favoriteIDs = Set(state.settings.favoriteStores.map(\.id))
            list = list.filter { $0.isSupermarket || ($0.priceCount ?? 0) > 0 || favoriteIDs.contains($0.id) }
        }
        if state.settings.openNowOnly {
            let now = Date()
            list = list.filter { $0.hours?.status(at: now).isOpen ?? true }
        }
        return list
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

    /// Magasins connus du plus proche au plus loin (position GPS réelle de préférence).
    func storesByDistance(including extra: Store? = nil) -> [Store] {
        var list = knownStores
        if let extra, !list.contains(where: { $0.id == extra.id }) {
            list.insert(extra, at: 0)
        }
        let reference = locationManager.location ?? referenceLocation
        return list.sorted {
            ($0.distance(from: reference) ?? .infinity) < ($1.distance(from: reference) ?? .infinity)
        }
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
            if !isUITest { AppModel.saveChainIndex(report) }
            Log.success(.prices, "Classement des enseignes calculé : \(report.entries.count) enseignes, \(report.productCount) produits")
        } catch {
            if !error.isCancellation {
                chainIndexError = "Classement indisponible : \(error.localizedDescription)"
                Log.error(.prices, "Classement des enseignes indisponible", details: error.localizedDescription)
            }
        }
        chainIndexLoading = false
    }

    // MARK: Carburants

    @MainActor
    func refreshFuel(force: Bool = false) async {
        guard let ref = referenceLocation else { return }
        let key = locationKey
        if !force, key == fuelLoadedKey, let updated = fuelUpdated,
           Date().timeIntervalSince(updated) < 30 * 60, !fuelStations.isEmpty {
            return
        }
        guard !fuelLoading else { return }
        fuelLoading = true
        fuelError = nil
        let lat = ref.coordinate.latitude
        let lon = ref.coordinate.longitude
        let radius = min(max(state.settings.radiusKm, 5), 20)
        do {
            let stations = try await GovDataAPI.fuelStations(lat: lat, lon: lon, radiusKm: radius)
            fuelStations = FuelStats.label(stations, places: [], stores: stores)
            fuelUpdated = Date()
            fuelLoadedKey = key
            fuelLoading = false
            Log.success(.fuel, "\(stations.count) stations-service à moins de \(Int(radius)) km")
            // Noms des stations (OpenStreetMap), quand le serveur répond.
            if let places = await StoreFinder.fuelPlaces(lat: lat, lon: lon, radiusKm: radius), key == locationKey {
                fuelStations = FuelStats.label(stations, places: places, stores: stores)
            }
        } catch {
            if !error.isCancellation {
                fuelError = "Prix des carburants indisponibles : \(error.localizedDescription)"
                Log.error(.fuel, "Prix des carburants indisponibles", details: error.localizedDescription)
            }
            fuelLoading = false
        }
    }

    // MARK: Rappels de produits

    /// Département de la zone (ex. "Haute-Garonne"), pour filtrer les rappels.
    @MainActor
    func refreshDepartment() async {
        guard let ref = referenceLocation else { return }
        let key = String(format: "%.2f|%.2f", ref.coordinate.latitude, ref.coordinate.longitude)
        guard key != departmentKey else { return }
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(ref).first else { return }
        departmentKey = key
        departmentName = placemark.subAdministrativeArea ?? placemark.administrativeArea
    }

    @MainActor
    func refreshRecalls(force: Bool = false) async {
        await refreshDepartment()
        let key = (departmentName ?? "France") + "|" + OpenPricesAPI.dayFormatter.string(from: Date())
        if !force, key == recallsLoadedKey { return }
        guard !recallsLoading else { return }
        recallsLoading = true
        recallsError = nil
        do {
            localRecalls = try await GovDataAPI.recentRecalls(department: departmentName, days: 30)
            recallsLoadedKey = key
            Log.success(.recalls, "\(localRecalls.count) rappels de produits ces 30 jours (\(departmentName ?? "France"))")
        } catch {
            if !error.isCancellation {
                recallsError = "Rappels indisponibles : \(error.localizedDescription)"
                Log.error(.recalls, "Rappels indisponibles", details: error.localizedDescription)
            }
        }
        recallsLoading = false
    }

    /// Vérifie (une fois par session) si ces produits font l'objet d'un rappel en cours.
    @MainActor
    func checkRecalls(for codes: [String]) async {
        let pending = Array(Set(codes.filter { $0.isBarcodeLike && !checkedRecallCodes.contains($0) }))
        guard !pending.isEmpty else { return }
        guard let recalls = try? await GovDataAPI.recalls(forBarcodes: pending) else { return }
        for code in pending { checkedRecallCodes.insert(code) }
        let active = recalls.filter { $0.isActive() }
        if active.isEmpty {
            Log.info(.recalls, "\(pending.count) produit\(pending.count > 1 ? "s" : "") vérifié\(pending.count > 1 ? "s" : "") : aucun rappel en cours")
        } else {
            Log.warning(.recalls, "Rappel en cours : " + active.prefix(3).map(\.title).joined(separator: ", "))
        }
        for recall in recalls where recall.isActive() {
            guard let gtin = recall.gtin else { continue }
            if let existing = recallsByGTIN[gtin], (existing.published ?? .distantPast) > (recall.published ?? .distantPast) {
                continue
            }
            recallsByGTIN[gtin] = recall
        }
    }

    func recall(for code: String) -> Recall? {
        guard code.isBarcodeLike else { return nil }
        return recallsByGTIN[Recall.normalizedGTIN(code)]
    }

    /// RappelConso a été interrogé pour ce code-barres (pour dire « aucun rappel en cours »).
    func recallChecked(_ code: String) -> Bool {
        checkedRecallCodes.contains(code)
    }

    // MARK: Produits suivis

    func isWatched(_ product: Product) -> Bool {
        state.watchlist.contains { $0.id == product.code }
    }

    /// Suit (ou ne suit plus) le prix d'un produit. `currentBest` : meilleur prix actuel autour de soi.
    func toggleWatch(_ product: Product, currentBest: PriceObservation?) {
        if isWatched(product) {
            state.watchlist.removeAll { $0.id == product.code }
            return
        }
        var item = WatchItem(product: product)
        if let currentBest {
            item.bestPrice = currentBest.price
            item.bestStoreName = currentBest.storeName
            item.bestDate = currentBest.date
            item.lastChecked = Date()
        }
        state.watchlist.append(item)
        if !isUITest {
            Task { await Notifier.requestPermission() }
        }
    }

    func setTargetPrice(_ price: Double?, for code: String) {
        guard let index = state.watchlist.firstIndex(where: { $0.id == code }) else { return }
        state.watchlist[index].targetPrice = price
    }

    func markWatchSeen(_ code: String) {
        guard let index = state.watchlist.firstIndex(where: { $0.id == code }),
              state.watchlist[index].hasNewDrop else { return }
        state.watchlist[index].hasNewDrop = false
    }

    /// Dernière vérification des prix suivis (la plus ancienne).
    var watchlistLastChecked: Date? {
        state.watchlist.compactMap(\.lastChecked).min()
    }

    /// Cherche de nouveaux prix pour les produits suivis. Renvoie le nombre de baisses trouvées.
    @MainActor
    @discardableResult
    func checkWatchlist(notify: Bool) async -> Int {
        guard !state.watchlist.isEmpty, !watchChecking else { return 0 }
        watchChecking = true
        defer { watchChecking = false }

        let reference = referenceLocation
        let radiusKm = state.settings.radiusKm
        let currency = state.settings.currency
        var drops = 0
        for item in state.watchlist {
            var observations: [PriceObservation] = []
            if !item.product.isCustom, let reference {
                let prices = (try? await OpenPricesAPI.pricesNear(productCode: item.product.code,
                                                                  lat: reference.coordinate.latitude,
                                                                  lon: reference.coordinate.longitude,
                                                                  radiusKm: radiusKm)) ?? []
                observations = PriceEngine.observations(from: prices)
            }
            observations += myObservations(productCode: item.product.code).filter { obs in
                guard let distance = obs.distance(from: reference) else { return true }
                return distance <= radiusKm * 1000
            }
            observations = observations.filter { $0.currency == currency }
            let outcome = WatchEvaluator.evaluate(item, observations: observations)
            if let index = state.watchlist.firstIndex(where: { $0.id == item.id }) {
                state.watchlist[index] = outcome.item
            }
            if let alert = outcome.alert {
                drops += 1
                Log.success(.prices, alert)
                if notify {
                    Notifier.notify(title: "Baisse de prix", body: alert, id: "suivi-\(item.id)")
                }
            }
        }
        Log.info(.prices, "\(state.watchlist.count) prix suivi\(state.watchlist.count > 1 ? "s" : "") vérifié\(state.watchlist.count > 1 ? "s" : "") : \(drops) baisse\(drops > 1 ? "s" : "")")
        return drops
    }

    // MARK: Budget

    var budgetSummary: BudgetSummary {
        BudgetEngine.summary(expenses: state.expenses,
                             budget: state.settings.budgetAmount,
                             startDay: state.settings.budgetStartDay)
    }

    /// Ajoute une dépense ; prévient si elle fait franchir 80 % ou 100 % du budget du mois.
    func addExpense(_ expense: Expense) {
        let before = budgetSummary
        state.expenses.append(expense)
        Log.success(.budget, "Dépense ajoutée : \(Fmt.price(expense.amount, state.settings.currency))"
                    + (expense.storeName.map { " chez \($0)" } ?? ""),
                    details: expense.note)
        // Autorisation des notifications demandée une seule fois par iOS (alertes de budget).
        if state.settings.budgetAlerts && !isUITest {
            Task { await Notifier.requestPermission() }
        }
        guard before.period.contains(expense.date) else { return }
        let after = budgetSummary
        guard let threshold = BudgetEngine.thresholdCrossed(before: before.spent, after: after.spent,
                                                            budget: after.budget) else { return }
        let currency = state.settings.currency
        let message = threshold >= 100
            ? "Budget du mois dépassé : \(Fmt.price(after.spent, currency)) dépensés sur \(Fmt.price(after.budget, currency))."
            : "80 % du budget atteint : il reste \(Fmt.price(after.remaining, currency)) pour \(after.daysLeft) jour\(after.daysLeft > 1 ? "s" : "")."
        budgetAlert = message
        Log.warning(.budget, message)
        if state.settings.budgetAlerts && !isUITest {
            Notifier.notify(title: "Budget courses", body: message, id: "budget-\(threshold)")
        }
    }

    func updateExpense(_ expense: Expense) {
        guard let index = state.expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        state.expenses[index] = expense
    }

    func deleteExpenses(ids: Set<UUID>) {
        state.expenses.removeAll { ids.contains($0.id) }
    }

    // MARK: Alimentation et recettes

    /// Ce produit peut-il être proposé (sans porc si demandé) ?
    func dietAllows(_ product: Product) -> Bool {
        DietFilter.allows(product, noPork: state.settings.noPork)
    }

    /// Mes recettes d'abord (toujours affichées : c'est moi qui les ai écrites), puis celles de l'app
    /// compatibles avec l'alimentation choisie.
    var recipes: [Recipe] {
        myRecipes + RecipeEngine.allowed(RecipeBook.all, noPork: state.settings.noPork, vegetarian: state.settings.vegetarian)
    }

    /// Mes recettes, la dernière modifiée en premier.
    var myRecipes: [Recipe] {
        state.myRecipes.sorted { $0.modified > $1.modified }.map(\.recipe)
    }

    /// Une recette par son identifiant (les miennes comprises).
    func recipe(id: String) -> Recipe? {
        if id.hasPrefix(MyRecipe.idPrefix) {
            return state.myRecipes.first { $0.recipeID == id }?.recipe
        }
        return RecipeBook.recipe(id: id)
    }

    /// Ma recette modifiable derrière une recette affichée (nil pour les recettes de l'app).
    func myRecipe(for recipeID: String) -> MyRecipe? {
        state.myRecipes.first { $0.recipeID == recipeID }
    }

    /// Crée ou met à jour une de mes recettes.
    func saveMyRecipe(_ recipe: MyRecipe) {
        var saved = recipe
        saved.modified = Date()
        if let index = state.myRecipes.firstIndex(where: { $0.id == saved.id }) {
            state.myRecipes[index] = saved
            Log.success(.recipes, "Recette modifiée : \(saved.recipe.name)")
        } else {
            state.myRecipes.insert(saved, at: 0)
            Log.success(.recipes, "Recette ajoutée à Mes recettes : \(saved.recipe.name)",
                        details: "\(saved.ingredients.count) ingrédients · \(saved.steps.count) étapes")
        }
    }

    /// Supprime une de mes recettes (et la retire des favoris et du menu de la semaine).
    func deleteMyRecipe(_ id: UUID) {
        guard let index = state.myRecipes.firstIndex(where: { $0.id == id }) else { return }
        let removed = state.myRecipes.remove(at: index)
        state.favoriteRecipes.removeAll { $0 == removed.recipeID }
        state.weekMenu.removeAll { $0 == removed.recipeID }
        Log.info(.recipes, "Recette supprimée : \(removed.recipe.name)")
    }

    /// Noms des articles de la liste (et des produits choisis dessous), pour savoir ce qui manque à une recette.
    var listNames: [String] {
        state.shoppingList.flatMap { item in [item.product.name] + [item.choice?.name].compactMap { $0 } }
    }

    /// Ajoute à la liste les articles qui n'y sont pas encore. Renvoie le nombre d'articles ajoutés.
    @discardableResult
    func addIngredients(_ names: [String]) -> Int {
        var added = 0
        for name in names where !RecipeEngine.isInList(name, listNames: listNames) {
            state.shoppingList.append(ShoppingItem(product: .custom(named: name)))
            added += 1
        }
        return added
    }

    func isFavorite(recipe id: String) -> Bool {
        state.favoriteRecipes.contains(id)
    }

    func toggleFavorite(recipe id: String) {
        if let index = state.favoriteRecipes.firstIndex(of: id) {
            state.favoriteRecipes.remove(at: index)
        } else {
            state.favoriteRecipes.append(id)
        }
    }

    /// Menu de la semaine enregistré (les recettes qui n'existent plus ou ne conviennent plus sont ignorées).
    var weekMenu: [Recipe] {
        let allowed = Set(recipes.map(\.id))
        return state.weekMenu.compactMap { id in allowed.contains(id) ? recipe(id: id) : nil }
    }

    // MARK: Articles cochés = achetés = dépenses

    /// Coche un article (acheté) ; avec un montant, il devient une dépense du mois.
    func checkListItem(_ id: UUID, amount: Double?, storeName: String?, store: Store?) {
        guard let index = state.shoppingList.firstIndex(where: { $0.id == id }) else { return }
        state.shoppingList[index].checked = true
        guard let amount, amount > 0 else {
            Log.info(.list, "« \(state.shoppingList[index].pricedProduct.name) » coché, sans dépense")
            return
        }
        let expense = BudgetEngine.purchase(of: state.shoppingList[index], amount: amount,
                                            storeName: storeName, store: store)
        state.shoppingList[index].expenseID = expense.id
        addExpense(expense)
    }

    /// Décoche un article : sa dépense est retirée du budget.
    func uncheckListItem(_ id: UUID) {
        guard let index = state.shoppingList.firstIndex(where: { $0.id == id }) else { return }
        if let expenseID = state.shoppingList[index].expenseID {
            deleteExpenses(ids: [expenseID])
        }
        state.shoppingList[index].checked = false
        state.shoppingList[index].expenseID = nil
    }

    /// Dépense liée à un article coché (nil si elle a été supprimée depuis le budget).
    func listExpense(for item: ShoppingItem) -> Expense? {
        guard let id = item.expenseID else { return nil }
        return state.expenses.first { $0.id == id }
    }

    /// Quantité changée sur un article coché : sa dépense suit.
    func rescaleListExpense(itemID: UUID, from old: Int, to new: Int) {
        guard let item = state.shoppingList.first(where: { $0.id == itemID }), item.checked,
              let expense = listExpense(for: item),
              let index = state.expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        state.expenses[index] = BudgetEngine.rescaled(expense, from: old, to: new, name: item.pricedProduct.name)
    }

    /// Économie possible ce mois-ci en allant dans l'enseigne la moins chère du quartier.
    var savingsTip: SavingsTip? {
        BudgetEngine.savingsTip(expenses: budgetSummary.expenses, report: chainIndex, nearbyChains: nearestStoreByChain)
    }

    // MARK: Produits précis sous un article de la liste

    func suggestionResults(for query: String) -> SuggestionResults {
        suggestions[SuggestionEngine.key(query)] ?? SuggestionResults()
    }

    /// Produits de « Mes prix » (dont ceux capturés sur les sites des enseignes) qui correspondent à l'article.
    func personalSuggestions(for query: String) -> [ProductSuggestion] {
        SuggestionEngine.personal(state.myPrices, query: query, reference: referenceLocation,
                                  radiusMeters: radiusMeters, currency: state.settings.currency)
    }

    /// Charge les produits correspondant à un article ("Œufs") : d'abord ceux qui ont des prix,
    /// puis le catalogue complet, page par page (`more`).
    @MainActor
    func loadSuggestions(for query: String, more: Bool = false) async {
        let key = SuggestionEngine.key(query)
        guard !key.isEmpty else { return }
        var results = suggestions[key] ?? SuggestionResults()
        if results.loading { return }
        if results.loaded && !more {
            // Déjà chargé ; on ne recommence que si Open Prices n'avait pas répondu.
            guard results.pricesUnavailable else { return }
            results = SuggestionResults()
        }
        if more && !results.hasMore { return }
        results.loading = true
        suggestions[key] = results

        if !results.loaded {
            let context = SuggestionService.Context(reference: referenceLocation,
                                                    radiusMeters: radiusMeters,
                                                    country: country,
                                                    currency: state.settings.currency,
                                                    nearbyChains: nearestStoreByChain)
            let priced = await SuggestionService.pricedSuggestions(for: query, context: context)
            results.items = priced.items
            results.pricesUnavailable = priced.failed
            if priced.failed {
                Log.warning(.prices, "Prix indisponibles pour « \(query) » : Open Prices ne répond pas")
            } else {
                let withPrice = priced.items.filter { $0.offer != nil }.count
                Log.info(.products, "« \(query) » : \(withPrice) produit\(withPrice > 1 ? "s" : "") avec un prix relevé")
            }
        }
        let catalogText = SuggestionEngine.catalogText(query)
        if !catalogText.isEmpty,
           let page = try? await CatalogAPI.search(text: catalogText, rayon: nil, page: results.catalogPage + 1, pageSize: 10) {
            let known = Set(results.items.map(\.id))
            let extra = page.items
                .filter { !known.contains($0.id) }
                .map { ProductSuggestion(product: $0.product, offer: nil, nutriScore: $0.nutriScore) }
            results.items += extra
            results.catalogPage = page.page
            results.hasMore = page.hasMore && !page.items.isEmpty
        }
        results.loading = false
        results.loaded = true
        suggestions[key] = results
    }

    /// Choisit (ou retire) le produit précis d'un article de la liste.
    func choose(_ product: Product?, for itemID: UUID) {
        guard let index = state.shoppingList.firstIndex(where: { $0.id == itemID }) else { return }
        state.shoppingList[index].choice = product
        if let product { remember(product) }
    }

    // MARK: Photos et fiches des produits

    /// Complète (photo, marque, contenance) les produits de la liste, des suivis et des consultés récemment.
    @MainActor
    func enrichProducts() async {
        let products = state.shoppingList.map(\.product) + state.watchlist.map(\.product) + state.recentProducts
        let pending = products.filter { !$0.isCustom && $0.imageURL == nil && !enrichedCodes.contains($0.code) }
        var seen = Set<String>()
        for product in pending where seen.insert(product.code).inserted {
            enrichedCodes.insert(product.code)
            guard let found = await ProductLookup.lookup(code: product.code) else { continue }
            apply(details: found)
        }
    }

    private func apply(details found: Product) {
        func merged(_ product: Product) -> Product {
            var p = product
            if !p.hasDetails { p.name = found.name }
            p.brand = p.brand ?? found.brand
            p.quantity = p.quantity ?? found.quantity
            p.imageURL = p.imageURL ?? found.imageURL
            p.unitQuantity = p.unitQuantity ?? found.unitQuantity
            p.unitName = p.unitName ?? found.unitName
            p.categories = p.categories ?? found.categories
            return p
        }
        for i in state.shoppingList.indices where state.shoppingList[i].product.code == found.code {
            state.shoppingList[i].product = merged(state.shoppingList[i].product)
        }
        for i in state.watchlist.indices where state.watchlist[i].product.code == found.code {
            state.watchlist[i].product = merged(state.watchlist[i].product)
        }
        for i in state.recentProducts.indices where state.recentProducts[i].code == found.code {
            state.recentProducts[i] = merged(state.recentProducts[i])
        }
    }

    // MARK: Mes prix

    func addMyPrice(_ price: MyPrice) {
        state.myPrices.append(price)
        remember(price.product)
    }

    // MARK: Rayons des sites gardés en mémoire

    /// Mise à jour des rayons suivis en cours (affichée dans « Mes rayons en ligne »).
    var trackedRefreshing = false

    /// Enregistre une capture : les prix dans « Mes prix » (sans doublon), et la page parmi les rayons suivis.
    @discardableResult
    func recordCapture(_ items: [CapturedPrice], site: DriveSite, store: Store, pageURL: URL?,
                       pageTitle: String?, track: Bool) -> [PriceUpdate] {
        let currency = state.settings.currency
        let result = CaptureUpdater.apply(items, to: state.myPrices, store: store, currency: currency,
                                          source: "site \(site.name)")
        state.myPrices = result.prices
        for update in result.updates where update.kind != .unchanged {
            remember(update.product)
        }
        Log.success(.sites, "Site \(site.name) : \(result.updates.count) prix enregistrés pour \(store.name)",
                    details: CaptureUpdater.changesText(result.updates) + (pageURL.map { "\n" + Log.describe($0) } ?? ""))
        guard track, let pageURL, pageURL.scheme?.hasPrefix("http") == true else { return result.updates }
        let codes = result.updates.map(\.product.code)
        if let index = state.trackedPages.firstIndex(where: { $0.url == pageURL.absoluteString && $0.store.id == store.id }) {
            var page = state.trackedPages[index]
            page.productCodes = Array(Set(page.productCodes + codes)).sorted()
            page.lastChecked = Date()
            page.lastError = nil
            page.lastChanges = result.updates.filter { $0.kind != .unchanged }.count
            state.trackedPages[index] = page
        } else {
            state.trackedPages.append(TrackedPage(url: pageURL.absoluteString,
                                                  title: TrackedPage.displayTitle(pageTitle: pageTitle, url: pageURL,
                                                                                  siteName: site.name),
                                                  siteName: site.name,
                                                  store: store,
                                                  productCodes: Array(Set(codes)).sorted(),
                                                  lastChecked: Date()))
        }
        return result.updates
    }

    /// Relit les rayons suivis (ceux qui n'ont pas été lus depuis 12 h, ou `only` tout de suite) dans un
    /// navigateur invisible, met à jour leurs prix et prévient des baisses.
    @MainActor
    func refreshTrackedPages(only id: UUID? = nil, force: Bool = false) async {
        // Pendant les tests d'interface : seulement sur demande (bouton « Mettre à jour maintenant »).
        guard !trackedRefreshing, !isUITest || id != nil || force else { return }
        let due = state.trackedPages.filter { page in
            if let id { return page.id == id }
            return force || page.isDue()
        }
        guard !due.isEmpty else { return }
        trackedRefreshing = true
        defer { trackedRefreshing = false }
        let session = CaptureSession(viewport: CGRect(x: 0, y: 0, width: 390, height: 844))
        // Dans la fenêtre (derrière l'interface) : le site charge tous ses produits comme à l'écran.
        session.attachBehindInterface()
        defer { session.detachFromInterface() }
        let currency = state.settings.currency
        for page in due {
            guard let url = URL(string: page.url) else { continue }
            let json = await session.capture(url: url, maxMs: 60_000)
            let items = DriveCaptureParser.parse(json)
            guard let index = state.trackedPages.firstIndex(where: { $0.id == page.id }) else { continue }
            state.trackedPages[index].lastChecked = Date()
            guard !items.isEmpty else {
                state.trackedPages[index].lastError = "Aucun prix lu : la page a peut-être changé, ou le site demande de choisir le magasin."
                Log.warning(.tracked, "Rayon « \(page.shortTitle) » (\(page.siteName)) : aucun prix lu",
                            details: Log.describe(url))
                continue
            }
            let result = CaptureUpdater.apply(items, to: state.myPrices, store: page.store, currency: currency,
                                              source: "site \(page.siteName)")
            state.myPrices = result.prices
            let codes = result.updates.map(\.product.code)
            state.trackedPages[index].productCodes = Array(Set(state.trackedPages[index].productCodes + codes)).sorted()
            state.trackedPages[index].lastChanges = result.updates.filter { $0.kind != .unchanged }.count
            state.trackedPages[index].lastError = nil
            Log.success(.tracked, "Rayon « \(page.shortTitle) » (\(page.siteName)) mis à jour : \(items.count) prix",
                        details: CaptureUpdater.changesText(result.updates))
            if !isUITest,
               let summary = CaptureUpdater.dropsSummary(result.updates, currency: currency, storeName: page.store.name) {
                Notifier.notify(title: "Baisse de prix · \(page.shortTitle)", body: summary, id: "rayon-\(page.id.uuidString)")
            }
        }
    }

    /// Derniers prix des produits d'un rayon suivi, avec le prix précédent (pour ↓ ↑).
    func trackedProducts(_ page: TrackedPage) -> [TrackedProduct] {
        let codes = Set(page.productCodes)
        let entries = state.myPrices.filter { codes.contains($0.product.code) && $0.store.id == page.store.id }
        return Dictionary(grouping: entries, by: \.product.code).values.compactMap { list -> TrackedProduct? in
            let sorted = list.sorted { $0.date > $1.date }
            guard let latest = sorted.first else { return nil }
            return TrackedProduct(latest: latest, previous: sorted.dropFirst().first)
        }
        .sorted { $0.latest.product.name.localizedCaseInsensitiveCompare($1.latest.product.name) == .orderedAscending }
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
        state.shoppingList.contains { $0.product.code == product.code || $0.choice?.code == product.code }
    }

    /// Remplace la fiche d'un produit de la liste (nom, photo…) une fois trouvée.
    func updateListProduct(_ product: Product) {
        for index in state.shoppingList.indices where state.shoppingList[index].product.code == product.code {
            state.shoppingList[index].product = product
        }
    }

    /// Texte de la liste pour la partager (Messages, WhatsApp…).
    var shoppingListText: String {
        var lines: [String] = []
        for item in state.shoppingList {
            var line = item.checked ? "✓ " : "• "
            if item.quantity > 1 { line += "\(item.quantity) × " }
            line += item.product.name
            if let choice = item.choice {
                let brand = choice.brand.map { ", " + $0 } ?? ""
                line += " (\(choice.name)\(brand))"
            }
            lines.append(line)
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

    func exportBackup() -> Data? {
        try? Backup.export(state)
    }

    func importBackup(_ data: Data) throws -> Backup.Summary {
        let incoming = try Backup.decode(data)
        return Backup.merge(incoming, into: &state)
    }

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
        // Les tests d'interface ne doivent jamais écraser de vraies données.
        guard !isUITest else { return }
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: AppModel.fileURL, options: .atomic)
        } catch {
            Log.error(.app, "Enregistrement des données impossible", details: error.localizedDescription)
        }
    }

    func resetAll() {
        state = PersistedState()
        state.settings.hasSeenOnboarding = true
        Log.warning(.app, "Toutes les données ont été effacées (Réglages)")
    }
}
