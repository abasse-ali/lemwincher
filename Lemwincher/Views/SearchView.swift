import SwiftUI

/// Onglet "Comparer" : recherche de produit (nom ou code-barres) et derniers prix autour de soi.
struct SearchView: View {
    @Environment(AppModel.self) private var model

    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var results: [OPProduct] = []
    @State private var searching = false
    @State private var searchError: String? = nil
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
            .navigationTitle("Comparer")
            .searchable(text: $query, prompt: "Produit, marque ou code-barres")
            .toolbar {
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
            .task(id: model.locationKey) { await loadRecent() }
            .refreshable { await loadRecent() }
            .appDestinations()
        }
    }

    // MARK: Contenu

    @ViewBuilder
    private var idleContent: some View {
        Section {
            Button {
                showScanner = true
            } label: {
                Label("Scanner un code-barres en magasin", systemImage: "barcode.viewfinder")
                    .font(.headline)
            }
        } footer: {
            Text("Scannez ou cherchez un produit pour voir son prix dans chaque magasin autour de vous, du moins cher au plus cher.")
        }

        if !model.state.recentProducts.isEmpty {
            Section("Consultés récemment") {
                ForEach(model.state.recentProducts) { product in
                    NavigationLink(value: product) {
                        ProductRow(product: product)
                    }
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
                ForEach(results, id: \.code) { item in
                    NavigationLink(value: item.asProduct()) {
                        ProductRow(product: item.asProduct(),
                                   subtitle: item.priceCount.map { "\($0) prix relevés" })
                    }
                }
                if !searching && results.isEmpty && searchError == nil && trimmedQuery.count >= 2 {
                    Text("Aucun produit avec des prix ne correspond. Essayez un autre mot ou scannez le code-barres.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Produits avec des prix (Open Prices)")
            }
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
        do {
            let found = try await OpenPricesAPI.searchProducts(q)
            if Task.isCancelled { return }
            results = found
        } catch {
            if error.isCancellation { return }
            results = []
            searchError = "Recherche impossible : \(error.localizedDescription)"
        }
        searching = false
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
