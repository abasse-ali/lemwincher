import SwiftUI

/// Onglet "Produits" : rayons, recherche (nom ou code-barres) dans tout le catalogue, suivis, rappels.
struct SearchView: View {
    @Environment(AppModel.self) private var model

    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var results: [OPProduct] = []
    @State private var searching = false
    @State private var searchError: String? = nil
    // Catalogue complet (Open Food Facts), page par page.
    @State private var catalog: [CatalogItem] = []
    @State private var catalogPage = 0
    @State private var catalogHasMore = false
    @State private var catalogLoading = false
    @State private var catalogTotal = 0
    @State private var recent: [PriceObservation] = []
    @State private var recentLoading = false
    @State private var showScanner = false

    private var trimmedQuery: String { query.trimmed }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if trimmedQuery.isEmpty {
                    idleContent
                } else {
                    searchContent
                }
            }
            .navigationTitle("Produits")
            .searchable(text: $query, prompt: "Produit, marque ou code-barres")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scanner", systemImage: "barcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet { code in
                    showScanner = false
                    path.append(Product(code: code, name: code))
                }
            }
            .task(id: query) { await search() }
            .task(id: model.locationKey) {
                await loadRecent()
                await model.enrichProducts()
                await refreshWatchlistIfNeeded()
                await model.refreshRecalls()
                await model.checkRecalls(for: model.state.recentProducts.map(\.code) + model.state.watchlist.map(\.id))
            }
            .refreshable {
                await loadRecent()
                await model.checkWatchlist(notify: false)
            }
            .appDestinations()
        }
    }

    /// Vérifie les prix suivis au plus une fois toutes les 3 heures quand l'app est ouverte.
    private func refreshWatchlistIfNeeded() async {
        if let last = model.watchlistLastChecked, Date().timeIntervalSince(last) < 3 * 3600 { return }
        await model.checkWatchlist(notify: false)
    }

    // MARK: Produits suivis

    @ViewBuilder
    private var watchlistSection: some View {
        if !model.state.watchlist.isEmpty {
            Section {
                ForEach(model.state.watchlist) { item in
                    NavigationLink(value: item.product) {
                        WatchRow(item: item, currency: model.settings.currency)
                    }
                }
                .onDelete { offsets in
                    model.state.watchlist.remove(atOffsets: offsets)
                }
            } header: {
                HStack {
                    Text("Prix suivis")
                    Spacer()
                    if model.watchChecking {
                        ProgressView().controlSize(.small)
                    }
                }
            } footer: {
                Text("Meilleur prix relevé autour de vous ces 60 derniers jours. Vous recevez une notification en cas de baisse.")
            }
        }
    }

    /// Lien vers les rappels de produits du département.
    private var recallsSection: some View {
        let mine = (model.state.shoppingList.map(\.product.code) + model.state.recentProducts.map(\.code) + model.state.watchlist.map(\.id))
            .filter { model.recall(for: $0) != nil }
        let count = model.localRecalls.count
        return Section {
            NavigationLink {
                RecallsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .background(mine.isEmpty ? Color.red.opacity(0.8) : Color.red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rappels de produits").font(.headline)
                        Text(recallsSubtitle(count: count, mine: Set(mine).count))
                            .font(.caption)
                            .foregroundStyle(mine.isEmpty ? Color.secondary : Color.red)
                    }
                }
            }
            .accessibilityIdentifier("recallsLink")
        }
    }

    private func recallsSubtitle(count: Int, mine: Int) -> String {
        if mine > 0 { return "\(mine) de vos produits concerné\(mine > 1 ? "s" : "") !" }
        if model.recallsLoading && count == 0 { return "Chargement…" }
        let place = model.departmentName.map { " (\($0) et France entière)" } ?? ""
        return "\(count) rappel\(count > 1 ? "s" : "") alimentaire\(count > 1 ? "s" : "") ces 30 jours\(place)"
    }

    // MARK: Contenu

    @ViewBuilder
    private var idleContent: some View {
        // Deux grandes tuiles : scanner un code-barres, comparer le rapport quantité/prix.
        Section {
            HStack(spacing: 12) {
                Button {
                    showScanner = true
                } label: {
                    BentoTile(title: "Scanner",
                              subtitle: "Le prix d'un produit dans chaque magasin autour de vous",
                              systemImage: "barcode.viewfinder", tint: .blue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scanTile")

                Button {
                    path.append(ValueCompareRoute())
                } label: {
                    BentoTile(title: "Comparer",
                              subtitle: "Le plus avantageux au kilo, au litre ou à la pièce",
                              systemImage: "scalemass.fill", tint: .brand)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("compareLink")
            }
            .clearListRow(top: 2, bottom: 2)
        } footer: {
            Text("Scannez ou cherchez un produit pour voir son prix dans chaque magasin autour de vous, du moins cher au plus cher.")
        }

        Section {
            RayonGrid { rayon in
                path.append(rayon)
            }
        } header: {
            Text("Rayons")
        } footer: {
            Text("Des centaines de milliers de produits vendus en France, avec leur photo, leur Nutri-Score et les prix relevés.")
        }

        TrackedPagesSection()

        watchlistSection

        recallsSection

        if !model.state.recentProducts.isEmpty {
            Section("Consultés récemment") {
                ForEach(model.state.recentProducts) { product in
                    NavigationLink(value: product) {
                        ProductRow(product: product,
                                   subtitle: model.recall(for: product.code) != nil ? "⚠️ Produit rappelé" : nil)
                    }
                    .accessibilityIdentifier("recentProduct")
                }
            }
        }

        Section {
            if recentLoading && recent.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Chargement…").foregroundStyle(.secondary)
                }
            } else if recent.isEmpty {
                Text(model.referenceLocation == nil
                     ? "Activez la localisation pour voir les prix autour de vous."
                     : "Aucun prix relevé récemment dans votre zone.")
                    .foregroundStyle(.secondary)
            }
            ForEach(recent) { obs in
                NavigationLink(value: obs.product) {
                    ObservationRow(obs: obs, showStore: true, distance: obs.distance(from: model.referenceLocation))
                }
            }
        } header: {
            Text("Derniers prix relevés autour de vous")
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if trimmedQuery.isBarcodeLike {
            Section {
                NavigationLink(value: Product(code: trimmedQuery, name: trimmedQuery)) {
                    Label("Comparer le code-barres \(trimmedQuery)", systemImage: "barcode")
                }
            }
        }

        let mine = localMatches
        if !mine.isEmpty {
            Section("Mes produits") {
                ForEach(mine) { product in
                    NavigationLink(value: product) {
                        ProductRow(product: product)
                    }
                }
            }
        }

        if !trimmedQuery.isBarcodeLike {
            Section {
                if searching && results.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Recherche…").foregroundStyle(.secondary)
                    }
                }
                if let searchError {
                    Text(searchError).foregroundStyle(.secondary)
                }
                ForEach(results.filter { model.dietAllows($0.asProduct()) }, id: \.code) { item in
                    NavigationLink(value: item.asProduct()) {
                        ProductRow(product: item.asProduct(),
                                   subtitle: item.priceCount.map { "\($0) prix relevés" })
                    }
                }
                if !searching && results.isEmpty && searchError == nil && trimmedQuery.count >= 2 {
                    Text("Aucun produit avec des prix relevés ne correspond.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Avec des prix relevés (Open Prices)")
            }

            catalogSection
        }
    }

    /// Tous les produits vendus en France qui correspondent (sans ceux déjà listés au-dessus).
    @ViewBuilder
    private var catalogSection: some View {
        let pricedCodes = Set(results.map(\.code))
        let others = catalog.filter { !pricedCodes.contains($0.id) && model.dietAllows($0.product) }
        Section {
            if catalogLoading && catalog.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche dans le catalogue…").foregroundStyle(.secondary)
                }
            }
            ForEach(others) { item in
                NavigationLink(value: item.product) {
                    CatalogRow(item: item)
                }
                .onAppear {
                    if item.id == others.last?.id { Task { await loadMoreCatalog() } }
                }
            }
            if catalogLoading && !catalog.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            if !catalogLoading && catalog.isEmpty && trimmedQuery.count >= 2 {
                Text("Aucun produit trouvé. Essayez un autre mot ou scannez le code-barres.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(catalogTotal > 0 ? "Tous les produits (\(catalogTotal.formatted()))" : "Tous les produits")
        } footer: {
            Text("Catalogue Open Food Facts. Touchez un produit pour voir les prix relevés dans les magasins autour de vous et dans chaque enseigne.")
        }
    }

    /// Produits de mes relevés dont le nom correspond.
    private var localMatches: [Product] {
        let q = trimmedQuery
        guard q.count >= 2 else { return [] }
        var seen = Set<String>()
        var found: [Product] = []
        for product in model.state.myPrices.map(\.product) + model.state.shoppingList.map(\.product)
        where !seen.contains(product.code) && product.name.localizedCaseInsensitiveContains(q) {
            seen.insert(product.code)
            found.append(product)
        }
        return found
    }

    // MARK: Chargement

    private func search() async {
        let q = trimmedQuery
        catalog = []
        catalogPage = 0
        catalogHasMore = false
        catalogTotal = 0
        catalogLoading = false
        guard q.count >= 2, !q.isBarcodeLike else {
            results = []
            searching = false
            searchError = nil
            return
        }
        searching = true
        searchError = nil
        try? await Task.sleep(for: .milliseconds(450))
        if Task.isCancelled { return }
        async let pricedTask = SearchView.searchPriced(q)
        catalogHasMore = true
        await loadMoreCatalog()
        let priced = await pricedTask
        if Task.isCancelled { return }
        switch priced {
        case .success(let found):
            results = found
        case .failure(let error):
            results = []
            searchError = "Recherche impossible : \(error.localizedDescription)"
        }
        searching = false
    }

    private static func searchPriced(_ text: String) async -> Result<[OPProduct], Error> {
        do {
            return .success(try await OpenPricesAPI.searchProducts(text))
        } catch {
            return .failure(error)
        }
    }

    /// Page suivante du catalogue complet pour la recherche en cours.
    private func loadMoreCatalog() async {
        let q = trimmedQuery
        guard catalogHasMore, !catalogLoading, q.count >= 2, !q.isBarcodeLike else { return }
        catalogLoading = true
        defer { catalogLoading = false }
        guard let page = try? await CatalogAPI.search(text: q, rayon: nil, page: catalogPage + 1),
              q == trimmedQuery else { return }
        let known = Set(catalog.map(\.id))
        catalog += page.items.filter { !known.contains($0.id) }
        catalogPage = page.page
        catalogTotal = page.total
        catalogHasMore = page.hasMore && !page.items.isEmpty
    }

    private func loadRecent() async {
        guard let ref = model.referenceLocation else {
            recent = []
            return
        }
        recentLoading = true
        defer { recentLoading = false }
        do {
            let prices = try await OpenPricesAPI.recentPricesNear(lat: ref.coordinate.latitude,
                                                                  lon: ref.coordinate.longitude,
                                                                  radiusKm: model.settings.radiusKm)
            let observations = PriceEngine.observations(from: prices)
            recent = Array(PriceEngine.latestPerProduct(observations)
                .sorted { $0.date > $1.date }
                .prefix(30))
        } catch {
            // On garde l'affichage précédent en cas d'erreur réseau.
        }
    }
}

/// Un produit suivi : meilleur prix actuel autour de soi, baisse éventuelle, prix cible.
struct WatchRow: View {
    let item: WatchItem
    let currency: String

    private var subtitle: String {
        guard let store = item.bestStoreName else { return "Pas encore de prix relevé autour de vous" }
        return Fmt.join(store, item.bestDate.map { Fmt.day($0) })
    }

    var body: some View {
        HStack(spacing: 12) {
            ProductThumb(url: item.product.imageURL, size: 44, name: item.product.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.name).lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let best = item.bestPrice {
                    Text(Fmt.price(best, currency)).font(.headline.monospacedDigit())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
                if item.hasNewDrop, let best = item.bestPrice, let previous = item.previousBestPrice {
                    Label(Fmt.price(best - previous, currency), systemImage: "arrow.down")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.brand)
                } else if let target = item.targetPrice {
                    Text("cible \(Fmt.price(target, currency))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
