import SwiftUI
import Charts

/// Comparatif d'un produit : prix relevés autour de soi, estimation par enseigne,
/// évolution du prix et produits similaires moins chers au kilo.
struct ProductCompareView: View {
    @Environment(AppModel.self) private var model

    @State private var product: Product
    @State private var local: [PriceObservation] = []
    @State private var national: [PriceObservation] = []
    @State private var loading = false
    @State private var loadError: String? = nil
    @State private var showAddPrice = false
    @State private var didLookup = false
    @State private var showOtherChains = false
    @State private var alternatives: [CheaperAlternative]? = nil
    @State private var alternativesLoading = false
    @State private var facts: ProductFacts? = nil
    @State private var didLoadFacts = false
    @State private var showTargetAlert = false
    @State private var targetText = ""

    init(product: Product) {
        _product = State(initialValue: product)
    }

    // MARK: Données dérivées

    /// Dernier prix connu dans chaque magasin du rayon, trié par prix.
    private var rows: [PriceObservation] {
        let reference = model.referenceLocation
        let radius = model.radiusMeters
        let mine = model.myObservations(productCode: product.code).filter { obs in
            guard let distance = obs.distance(from: reference) else { return true }
            return distance <= radius
        }
        return PriceEngine.latestPerStore(local + mine).sorted { $0.price < $1.price }
    }

    /// Relevés du pays (12 mois) dans la devise de l'utilisateur.
    private var nationalUsable: [PriceObservation] {
        PriceEngine.filter(national, country: model.country, currency: model.settings.currency)
    }

    /// Prix de référence au kilo / litre (médiane des enseignes, sinon le moins cher autour).
    private func referenceUnitPrice(estimates: [ChainEstimate], rows: [PriceObservation]) -> Double? {
        guard let amount = product.normalizedAmount else { return nil }
        if !estimates.isEmpty {
            return amount.unitPrice(ChainStats.median(estimates.map(\.median)))
        }
        if let cheapest = rows.first {
            return amount.unitPrice(cheapest.price)
        }
        return nil
    }

    // MARK: Vue

    var body: some View {
        let rows = self.rows
        let estimates = ChainStats.estimates(from: nationalUsable)
        let nearby = model.nearestStoreByChain
        let nearbyEstimates = estimates.filter { nearby[$0.key] != nil }
        let otherEstimates = estimates.filter { nearby[$0.key] == nil }

        List {
            if let recall = model.recall(for: product.code) {
                Section {
                    RecallBanner(recall: recall)
                }
            }

            Section {
                productHeader
                if let facts {
                    ProductFactsView(facts: facts)
                }
                actionButtons
            }

            watchSection(best: rows.first)

            if rows.count >= 2, let cheapest = rows.first, let dearest = rows.last, dearest.price > cheapest.price {
                Section {
                    Label {
                        Text("Jusqu'à \(Fmt.price(dearest.price - cheapest.price, cheapest.currency)) d'économie en l'achetant chez \(cheapest.storeName).")
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(Color.brand)
                    }
                }
            }

            localSection(rows: rows)

            if !product.isCustom {
                estimatesSection(nearbyEstimates: nearbyEstimates, otherEstimates: otherEstimates, nearby: nearby)
            }

            let points = chartPoints()
            if points.count >= 3 {
                Section {
                    PriceHistoryChart(points: points)
                        .padding(.vertical, 6)
                } header: {
                    Text("Évolution du prix (12 mois)")
                } footer: {
                    Text("Chaque point est un prix relevé ; la couleur indique l'enseigne.")
                }
            }

            if !product.isCustom, product.normalizedAmount != nil, !(product.categories ?? []).isEmpty {
                alternativesSection(reference: referenceUnitPrice(estimates: estimates, rows: rows))
            }
        }
        .navigationTitle("Comparatif")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText(rows: rows, estimates: nearbyEstimates)) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    model.toggleWatch(product, currentBest: rows.first)
                } label: {
                    Image(systemName: model.isWatched(product) ? "bell.fill" : "bell")
                }
                .accessibilityLabel(model.isWatched(product) ? "Ne plus suivre le prix" : "Suivre le prix")
            }
        }
        .sheet(isPresented: $showAddPrice) {
            AddPriceView(product: product)
        }
        .alert("Prix cible", isPresented: $showTargetAlert) {
            TextField("Ex. : 3,50", text: $targetText)
                .keyboardType(.decimalPad)
            Button("Enregistrer") {
                let value = Double(targetText.replacingOccurrences(of: ",", with: ".").trimmed)
                model.setTargetPrice(value.flatMap { $0 > 0 ? $0 : nil }, for: product.code)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Vous serez prévenu quand ce produit sera relevé à ce prix ou moins autour de vous.")
        }
        .task(id: model.locationKey) { await load() }
        .refreshable { await load() }
        .onAppear { model.markWatchSeen(product.code) }
    }

    // MARK: Suivi du prix

    @ViewBuilder
    private func watchSection(best: PriceObservation?) -> some View {
        if let item = model.state.watchlist.first(where: { $0.id == product.code }) {
            Section {
                HStack {
                    Label("Prix suivi", systemImage: "bell.fill").foregroundStyle(Color.brand)
                    Spacer()
                    Button(item.targetPrice.map { "Cible : \(Fmt.price($0, model.settings.currency))" } ?? "Fixer un prix cible") {
                        targetText = item.targetPrice.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
                        showTargetAlert = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } footer: {
                Text("Lemwincher vérifie régulièrement les nouveaux prix relevés autour de vous et vous prévient par une notification en cas de baisse.")
            }
        }
    }

    /// Texte partagé : les prix du produit autour de soi.
    private func shareText(rows: [PriceObservation], estimates: [ChainEstimate]) -> String {
        var lines = [Fmt.join(product.name, product.brand, product.quantity)]
        if rows.isEmpty && estimates.isEmpty {
            lines.append("Pas encore de prix relevé près de chez moi.")
        }
        for obs in rows.prefix(6) {
            lines.append("• \(Fmt.price(obs.price, obs.currency)) chez \(obs.storeName) (\(Fmt.day(obs.date)))")
        }
        if rows.isEmpty {
            for estimate in estimates.prefix(5) {
                lines.append("• ≈ \(Fmt.price(estimate.median, estimate.currency)) chez \(estimate.name) (prix médian en France)")
            }
        }
        lines.append("Comparé avec Lemwincher")
        return lines.joined(separator: "\n")
    }

    // MARK: Sections

    private var productHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ProductThumb(url: product.imageURL, size: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name).font(.title3.bold())
                if let brand = product.brand {
                    Text(brand).foregroundStyle(.secondary)
                }
                if let quantity = product.quantity {
                    Text(quantity).font(.subheadline).foregroundStyle(.secondary)
                }
                if !product.isCustom {
                    Label(product.code, systemImage: "barcode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            let inList = model.isInList(product)
            Button {
                model.addToList(product)
            } label: {
                Label(inList ? "Dans ma liste" : "Ajouter à ma liste",
                      systemImage: inList ? "checkmark" : "cart.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(inList)

            Button {
                showAddPrice = true
            } label: {
                Label("Relever un prix", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func localSection(rows: [PriceObservation]) -> some View {
        Section {
            if model.referenceLocation == nil {
                Text("Activez la localisation ou indiquez votre domicile dans Réglages pour comparer les prix autour de vous.")
                    .foregroundStyle(.secondary)
            }
            if loading && rows.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche des prix…").foregroundStyle(.secondary)
                }
            }
            if let loadError {
                Text(loadError).font(.footnote).foregroundStyle(.secondary)
            }
            if !loading && rows.isEmpty && model.referenceLocation != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personne n'a encore relevé ce produit à moins de \(Int(model.settings.radiusKm)) km.")
                        .foregroundStyle(.secondary)
                    Button("Relever son prix en magasin") { showAddPrice = true }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, obs in
                let distance = obs.distance(from: model.referenceLocation)
                let isCheapest = index == 0 && rows.count > 1
                let favorite = model.state.settings.favoriteStores.contains { $0.id == obs.storeKey }
                if let store = obs.store {
                    NavigationLink(value: store) {
                        CompareRow(obs: obs, rank: index + 1, distance: distance, cheapest: isCheapest, favorite: favorite)
                    }
                } else {
                    CompareRow(obs: obs, rank: index + 1, distance: distance, cheapest: isCheapest, favorite: favorite)
                }
            }
        } header: {
            Text("Prix relevés à moins de \(Int(model.settings.radiusKm)) km")
        } footer: {
            Text("Dernier prix connu dans chaque magasin. Sources : Open Prices (communauté) et vos relevés (icône personne).")
        }
    }

    @ViewBuilder
    private func estimatesSection(nearbyEstimates: [ChainEstimate],
                                  otherEstimates: [ChainEstimate],
                                  nearby: [String: Store]) -> some View {
        let reference = model.referenceLocation
        if !nearbyEstimates.isEmpty || !otherEstimates.isEmpty {
            Section {
                ForEach(Array(nearbyEstimates.enumerated()), id: \.element.id) { index, estimate in
                    let store = nearby[estimate.key]
                    let row = ChainEstimateRow(estimate: estimate,
                                               nearestStore: store,
                                               distance: store?.distance(from: reference),
                                               cheapest: index == 0 && nearbyEstimates.count > 1)
                    if let store {
                        NavigationLink(value: store) { row }
                    } else {
                        row
                    }
                }
                if !otherEstimates.isEmpty {
                    DisclosureGroup(isExpanded: $showOtherChains) {
                        ForEach(otherEstimates) { estimate in
                            ChainEstimateRow(estimate: estimate, nearestStore: nil, distance: nil, cheapest: false)
                        }
                    } label: {
                        Text(nearbyEstimates.isEmpty
                             ? "Enseignes en France (\(otherEstimates.count))"
                             : "Autres enseignes en France (\(otherEstimates.count))")
                    }
                }
            } header: {
                Text("Estimation par enseigne")
            } footer: {
                Text("Prix médian relevé dans les magasins de chaque enseigne en France sur 12 mois (hors promotions). Utile quand personne n'a encore relevé le produit près de chez vous.")
            }
        } else if loading {
            Section("Estimation par enseigne") {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Calcul des estimations…").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func alternativesSection(reference: Double?) -> some View {
        Section {
            if let alternatives {
                if alternatives.isEmpty {
                    Text("Aucun produit similaire moins cher au kilo trouvé pour l'instant.")
                        .foregroundStyle(.secondary)
                }
                ForEach(alternatives) { alternative in
                    NavigationLink(value: alternative.obs.product) {
                        AlternativeRow(alternative: alternative)
                    }
                }
            } else if alternativesLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche de produits similaires…").foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await findAlternatives(reference: reference) }
                } label: {
                    Label("Trouver un produit similaire moins cher", systemImage: "arrow.down.right.circle")
                }
            }
        } header: {
            if let amount = product.normalizedAmount {
                Text("Moins cher au \(amount.unit == "L" ? "litre" : "kilo")")
            }
        } footer: {
            if let reference, let amount = product.normalizedAmount {
                Text("Ce produit revient à environ \(Fmt.price(reference, model.settings.currency))/\(amount.unit). Produits de la même catégorie relevés en France sur 12 mois.")
            }
        }
    }

    // MARK: Graphique

    private func chartPoints() -> [PriceChartPoint] {
        let limit = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        var seen = Set<String>()
        var observations: [PriceObservation] = []
        for obs in nationalUsable + local + model.myObservations(productCode: product.code)
        where obs.date >= limit && !seen.contains(obs.id) && obs.currency == model.settings.currency {
            seen.insert(obs.id)
            observations.append(obs)
        }
        // Les 4 enseignes les plus représentées gardent leur couleur, les autres sont regroupées.
        var counts: [String: Int] = [:]
        for obs in observations where obs.source == .community {
            counts[obs.chainName ?? "Autres", default: 0] += 1
        }
        let mainSeries = Set(counts.sorted { $0.value > $1.value }.prefix(4).map(\.key))
        return observations.map { obs in
            let series: String
            if obs.source == .mine {
                series = "Mes relevés"
            } else if let chain = obs.chainName, mainSeries.contains(chain) {
                series = chain
            } else {
                series = "Autres"
            }
            return PriceChartPoint(id: obs.id, date: obs.date, price: obs.price, series: series)
        }
    }

    // MARK: Chargement

    private func load() async {
        if !product.isCustom && !didLookup &&
            (!product.hasDetails || product.imageURL == nil || product.categories == nil || product.unitQuantity == nil) {
            didLookup = true
            if let info = await ProductLookup.lookup(code: product.code) {
                if !product.hasDetails { product.name = info.name }
                product.brand = product.brand ?? info.brand
                product.quantity = product.quantity ?? info.quantity
                product.imageURL = product.imageURL ?? info.imageURL
                product.unitQuantity = product.unitQuantity ?? info.unitQuantity
                product.unitName = product.unitName ?? info.unitName
                product.categories = product.categories ?? info.categories
            }
        }
        model.remember(product)
        guard !product.isCustom else { return }

        loading = true
        loadError = nil
        let code = product.code
        let lat = model.referenceLocation?.coordinate.latitude
        let lon = model.referenceLocation?.coordinate.longitude
        let radius = model.settings.radiusKm
        let needFacts = !didLoadFacts
        async let localTask = ProductCompareView.fetchLocal(code: code, lat: lat, lon: lon, radiusKm: radius)
        async let nationalTask = ProductCompareView.fetchNational(code: code)
        async let factsTask = ProductCompareView.fetchFacts(code: code, needed: needFacts)
        let localPrices = await localTask
        let nationalPrices = await nationalTask
        let loadedFacts = await factsTask
        if Task.isCancelled { return }

        if let localPrices { local = PriceEngine.observations(from: localPrices) }
        if let nationalPrices { national = PriceEngine.observations(from: nationalPrices) }
        if needFacts {
            facts = loadedFacts
            didLoadFacts = true
        }
        if localPrices == nil && nationalPrices == nil {
            loadError = "Prix de la communauté indisponibles. Vérifiez votre connexion internet."
        }
        loading = false
        await model.checkRecalls(for: [code])
    }

    private static func fetchFacts(code: String, needed: Bool) async -> ProductFacts? {
        guard needed else { return nil }
        return try? await OpenFoodFactsAPI.facts(code: code)
    }

    private static func fetchLocal(code: String, lat: Double?, lon: Double?, radiusKm: Double) async -> [OPPrice]? {
        guard let lat, let lon else { return [] }
        return try? await OpenPricesAPI.pricesNear(productCode: code, lat: lat, lon: lon, radiusKm: radiusKm)
    }

    private static func fetchNational(code: String) async -> [OPPrice]? {
        try? await OpenPricesAPI.nationalPrices(productCode: code)
    }

    private func findAlternatives(reference: Double?) async {
        guard let amount = product.normalizedAmount, let categories = product.categories else {
            alternatives = []
            return
        }
        alternativesLoading = true
        let candidates = Array(categories.filter { $0.hasPrefix("en:") }.reversed().prefix(3))
        var best: [CheaperAlternative] = []
        for category in candidates {
            guard let prices = try? await OpenPricesAPI.categoryPrices(category: category) else { continue }
            let observations = PriceEngine.filter(PriceEngine.observations(from: prices),
                                                  country: model.country,
                                                  currency: model.settings.currency)
            let list = PriceEngine.cheaperAlternatives(observations: observations,
                                                       excluding: product.code,
                                                       unit: amount.unit,
                                                       below: reference)
            if list.count > best.count { best = list }
            if best.count >= 3 { break }
        }
        alternatives = best
        alternativesLoading = false
    }
}

// MARK: - Graphique

struct PriceChartPoint: Identifiable {
    let id: String
    let date: Date
    let price: Double
    let series: String
}

struct PriceHistoryChart: View {
    let points: [PriceChartPoint]

    var body: some View {
        Chart(points) { point in
            PointMark(x: .value("Date", point.date),
                      y: .value("Prix", point.price))
                .foregroundStyle(by: .value("Enseigne", point.series))
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
    }
}

/// Un produit similaire moins cher au kilo / litre.
struct AlternativeRow: View {
    let alternative: CheaperAlternative

    var body: some View {
        let obs = alternative.obs
        HStack(spacing: 12) {
            ProductThumb(url: obs.imageURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(obs.productName).lineLimit(2)
                Text(Fmt.join(obs.brand, obs.quantity, obs.chainName ?? obs.storeName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Fmt.price(alternative.unitPrice, obs.currency))/\(alternative.unit)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.brand)
                Text(Fmt.price(obs.price, obs.currency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
