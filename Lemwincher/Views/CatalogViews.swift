import SwiftUI

// MARK: - Grille des rayons

/// Les rayons du catalogue, en tuiles (3 par ligne).
struct RayonGrid: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Rayon.all) { rayon in
                NavigationLink(value: rayon) {
                    RayonTile(rayon: rayon)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rayon-\(rayon.tag)")
            }
        }
        .padding(.vertical, 6)
    }
}

struct RayonTile: View {
    let rayon: Rayon

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: rayon.icon)
                .font(.title2)
                .foregroundStyle(Color.white)
                .frame(width: 46, height: 46)
                .background(Color(hue: rayon.hue, saturation: 0.55, brightness: 0.85).gradient,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(rayon.name)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Un rayon

/// Produits d'un rayon : tout le catalogue, ceux qui ont des prix, ou les moins chers au kilo.
struct RayonView: View {
    @Environment(AppModel.self) private var model
    let rayon: Rayon

    enum Mode: String, CaseIterable, Identifiable {
        case all = "Tous"
        case priced = "Avec prix"
        case cheapest = "Moins chers"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .all
    @State private var filter = ""

    // Catalogue complet
    @State private var items: [CatalogItem] = []
    @State private var total = 0
    @State private var page = 0
    @State private var hasMore = true
    // Produits avec des prix
    @State private var priced: [OPProduct] = []
    @State private var pricedPage = 0
    @State private var pricedHasMore = true
    // Moins chers au kilo
    @State private var cheapest: [CheaperAlternative] = []

    @State private var loading = false
    @State private var errorText: String? = nil
    /// Change à chaque rechargement : les réponses d'un chargement précédent sont ignorées.
    @State private var generation = 0

    private var reloadKey: String { mode.rawValue + "|" + filter.trimmed }

    var body: some View {
        List {
            Section {
                Picker("Affichage", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(modeDescription)
            }

            Section {
                content
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Chargement…").foregroundStyle(.secondary)
                    }
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                if mode == .all && total > 0 {
                    Text("\(total.formatted()) produits")
                }
            }
        }
        .navigationTitle(rayon.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter, prompt: "Chercher dans \(rayon.name.lowercased())")
        .task(id: reloadKey) { await reload() }
    }

    private var modeDescription: String {
        switch mode {
        case .all: return "Tous les produits vendus en France (Open Food Facts), les plus courants d'abord."
        case .priced: return "Produits dont le prix a été relevé en magasin (Open Prices) : touchez-en un pour comparer."
        case .cheapest: return "Prix au kilo / au litre les plus bas relevés en France ces 12 derniers mois."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .all:
            if !loading && items.isEmpty && errorText == nil {
                Text("Aucun produit trouvé.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                NavigationLink(value: item.product) {
                    CatalogRow(item: item)
                }
                .onAppear {
                    if item.id == items.last?.id { Task { await loadMore() } }
                }
            }
        case .priced:
            if !loading && priced.isEmpty && errorText == nil {
                Text("Aucun prix relevé pour ce rayon pour l'instant.").foregroundStyle(.secondary)
            }
            ForEach(priced, id: \.code) { product in
                NavigationLink(value: product.asProduct()) {
                    ProductRow(product: product.asProduct(),
                               subtitle: product.priceCount.map { "\($0) prix relevés" })
                }
                .onAppear {
                    if product.code == priced.last?.code { Task { await loadMore() } }
                }
            }
        case .cheapest:
            if !loading && cheapest.isEmpty && errorText == nil {
                Text("Pas assez de prix au kilo dans ce rayon.").foregroundStyle(.secondary)
            }
            ForEach(cheapest) { alternative in
                NavigationLink(value: alternative.obs.product) {
                    AlternativeRow(alternative: alternative)
                }
            }
        }
    }

    // MARK: Chargement

    private func reload() async {
        if !filter.trimmed.isEmpty {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
        }
        generation += 1
        items = []
        total = 0
        page = 0
        hasMore = true
        priced = []
        pricedPage = 0
        pricedHasMore = true
        cheapest = []
        errorText = nil
        loading = false
        if mode == .cheapest {
            await loadCheapest()
        } else {
            await loadMore()
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        let text = filter.trimmed
        let current = generation
        loading = true
        defer {
            if current == generation { loading = false }
        }
        do {
            switch mode {
            case .all:
                guard hasMore else { return }
                let next = try await CatalogAPI.search(text: text, rayon: rayon, page: page + 1)
                guard current == generation else { return }
                let known = Set(items.map(\.id))
                items += next.items.filter { !known.contains($0.id) }
                total = next.total
                page = next.page
                hasMore = next.hasMore && !next.items.isEmpty
            case .priced:
                guard pricedHasMore else { return }
                let next = try await OpenPricesAPI.pricedProducts(category: rayon.tag, nameContains: text, page: pricedPage + 1)
                guard current == generation else { return }
                let known = Set(priced.map(\.code))
                priced += next.products.filter { !known.contains($0.code) }
                pricedPage += 1
                pricedHasMore = next.hasMore && !next.products.isEmpty
            case .cheapest:
                break
            }
        } catch {
            if !error.isCancellation {
                errorText = "Chargement impossible : \(error.localizedDescription)"
            }
        }
    }

    private func loadCheapest() async {
        let current = generation
        loading = true
        defer {
            if current == generation { loading = false }
        }
        do {
            let prices = try await OpenPricesAPI.categoryPrices(category: rayon.tag)
            guard current == generation else { return }
            var observations = PriceEngine.filter(PriceEngine.observations(from: prices),
                                                  country: model.country,
                                                  currency: model.settings.currency)
            let text = filter.trimmed
            if !text.isEmpty {
                observations = observations.filter { $0.productName.localizedCaseInsensitiveContains(text) }
            }
            // Unité la plus fréquente du rayon (kg ou L).
            let units = observations.compactMap { $0.unitAmount?.unit }
            let unit = units.filter { $0 == "L" }.count > units.count / 2 ? "L" : "kg"
            cheapest = Array(PriceEngine.cheaperAlternatives(observations: observations, excluding: "",
                                                            unit: unit, below: nil, limit: 40))
        } catch {
            if !error.isCancellation {
                errorText = "Chargement impossible : \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Lignes

/// Un produit du catalogue : photo, nom, marque, contenance, Nutri-Score.
struct CatalogRow: View {
    let item: CatalogItem

    var body: some View {
        HStack(spacing: 12) {
            ProductThumb(url: item.product.imageURL, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.name).lineLimit(2)
                let details = Fmt.join(item.product.brand, item.product.quantity)
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let grade = item.nutriScore {
                NutriMiniBadge(grade: grade)
            }
        }
    }
}

/// Petite lettre Nutri-Score.
struct NutriMiniBadge: View {
    let grade: String

    var body: some View {
        Text(grade.uppercased())
            .font(.caption.bold())
            .foregroundStyle(Color.white)
            .frame(width: 24, height: 24)
            .background(GradeBadge.color(for: grade), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Nutri-Score \(grade.uppercased())")
    }
}
