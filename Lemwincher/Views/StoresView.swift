import SwiftUI
import MapKit

/// Onglet "Autour de moi" : carte, enseignes les moins chères et liste des magasins proches.
struct StoresView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        @Bindable var bindable = model
        NavigationStack {
            Group {
                if model.referenceLocation == nil {
                    LocationNeededView()
                } else {
                    VStack(spacing: 0) {
                        map
                        storeList(supermarketsOnly: $bindable.state.settings.supermarketsOnly,
                                  openNowOnly: $bindable.state.settings.openNowOnly)
                    }
                }
            }
            .navigationTitle("Autour de moi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.locationManager.request()
                        Task { await model.refreshStores() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.storesLoading || model.referenceLocation == nil)
                }
            }
            .appDestinations()
        }
        .task(id: model.locationKey) {
            await model.refreshStores()
            camera = .automatic
            // Carburants et classement des enseignes en parallèle.
            async let fuel: Void = model.refreshFuel()
            async let ranking: Void = model.refreshChainIndex()
            _ = await (fuel, ranking)
        }
    }

    // MARK: Carte

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            if model.settings.useHome, let home = model.settings.home {
                Marker("Domicile", systemImage: "house.fill", coordinate: home.coordinate)
                    .tint(Color.blue)
            }
            ForEach(mapStores) { store in
                Marker(store.name, systemImage: "cart.fill", coordinate: store.coordinate)
                    .tint(markerColor(for: store))
            }
        }
        .frame(height: 230)
    }

    /// Sur la carte : les 80 magasins les plus proches et les favoris (la liste, elle, est complète).
    /// Des centaines d'épingles superposées seraient illisibles et lentes à afficher.
    private var mapStores: [Store] {
        let visible = model.visibleStores
        var shown = Array(visible.prefix(80))
        let shownIDs = Set(shown.map(\.id))
        for store in model.settings.favoriteStores where !shownIDs.contains(store.id) {
            shown.append(store)
        }
        return shown
    }

    private func markerColor(for store: Store) -> Color {
        if model.isFavorite(store) { return Color.yellow }
        if (store.priceCount ?? 0) > 0 { return Color.brand }
        return store.isSupermarket ? Color.gray : Color.gray.opacity(0.6)
    }

    // MARK: Liste

    private func storeList(supermarketsOnly: Binding<Bool>, openNowOnly: Binding<Bool>) -> some View {
        let reference = model.referenceLocation
        let favorites = model.settings.favoriteStores.sorted {
            ($0.distance(from: reference) ?? .infinity) < ($1.distance(from: reference) ?? .infinity)
        }
        let visible = model.visibleStores
        let report = model.chainIndex

        return List {
            if !favorites.isEmpty {
                Section("Mes magasins") {
                    ForEach(favorites) { store in
                        NavigationLink(value: store) {
                            StoreRow(store: store,
                                     distance: store.distance(from: reference),
                                     chainEntry: report?.entry(for: store.chainKey),
                                     favorite: true)
                        }
                    }
                }
            }

            fuelSection

            chainSummarySection

            Section {
                Toggle(isOn: openNowOnly) {
                    Label("Ouverts maintenant", systemImage: "clock")
                }
                if model.storesLoading && model.stores.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Recherche des magasins…").foregroundStyle(.secondary)
                    }
                }
                if let error = model.storesError {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(visible) { store in
                    NavigationLink(value: store) {
                        StoreRow(store: store,
                                 distance: store.distance(from: reference),
                                 chainEntry: report?.entry(for: store.chainKey),
                                 favorite: model.isFavorite(store))
                    }
                    .accessibilityIdentifier("storeRow")
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Magasins affichés", selection: supermarketsOnly) {
                        Text("Supermarchés").tag(true)
                        Text("Tous les commerces").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    if !visible.isEmpty {
                        Text("\(visible.count) magasins à moins de \(Int(model.settings.radiusKm)) km")
                    }
                }
            } footer: {
                if let source = model.storesSource {
                    Text("Sources : \(source). Sur la carte : en vert les magasins avec des prix relevés, en jaune vos favoris. Horaires : OpenStreetMap (quand ils sont connus).")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await model.refreshStores()
            await model.refreshFuel(force: true)
        }
    }

    /// Station-service la moins chère autour de soi.
    private var fuelSection: some View {
        let fuel = model.settings.fuelType
        let best = FuelStats.ranked(model.fuelStations, fuel: fuel).first
        let reference = model.referenceLocation
        return Section {
            NavigationLink {
                FuelView()
            } label: {
                FuelSummaryRow(fuel: fuel,
                               best: best,
                               distance: best.flatMap { station in reference.map { station.location.distance(from: $0) } },
                               loading: model.fuelLoading)
            }
            .accessibilityIdentifier("fuelLink")
        }
    }

    /// Les enseignes présentes autour de vous, de la moins chère à la plus chère.
    @ViewBuilder
    private var chainSummarySection: some View {
        let nearby = model.nearestStoreByChain
        let reference = model.referenceLocation
        if let report = model.chainIndex {
            let entries = report.entries.filter { nearby[$0.key] != nil }
            if !entries.isEmpty {
                Section {
                    ForEach(Array(entries.prefix(6).enumerated()), id: \.element.id) { index, entry in
                        if let store = nearby[entry.key] {
                            NavigationLink(value: store) {
                                ChainRankRow(rank: index + 1, entry: entry, store: store,
                                             distance: store.distance(from: reference))
                            }
                        }
                    }
                    NavigationLink {
                        ChainRankingView()
                    } label: {
                        Label("Classement complet des enseignes", systemImage: "list.number")
                    }
                    .accessibilityIdentifier("chainRankingLink")
                } header: {
                    Text("Enseignes les moins chères autour de vous")
                } footer: {
                    Text("Indice calculé sur \(report.productCount) produits de grandes marques relevés en France (Open Prices, 12 mois). Le pourcentage compare chaque enseigne à la moyenne.")
                }
            }
        } else if model.chainIndexLoading {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Calcul du classement des enseignes…").foregroundStyle(.secondary)
                }
            }
        } else if let error = model.chainIndexError {
            Section {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Réessayer") { Task { await model.refreshChainIndex(force: true) } }
            }
        }
    }
}

/// Une ligne du classement des enseignes.
struct ChainRankRow: View {
    let rank: Int
    let entry: ChainIndexEntry
    let store: Store?
    let distance: Double?

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(rank == 1 ? Color.brand : Color(.tertiarySystemFill), in: Circle())
                .foregroundStyle(rank == 1 ? Color.white : Color.primary)
            StoreLogo(url: store?.displayLogoURL ?? Chain.logoURL(brand: entry.name), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.headline).lineLimit(1)
                if let store {
                    Text(Fmt.join(store.name, distance.map { Fmt.distance($0) }))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Pas de magasin dans votre zone").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                ChainIndexBadge(entry: entry)
                Text("\(entry.productCount) produits").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Classement complet des enseignes du pays.
struct ChainRankingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let nearby = model.nearestStoreByChain
        let reference = model.referenceLocation
        List {
            if let report = model.chainIndex {
                Section {
                    ForEach(Array(report.entries.enumerated()), id: \.element.id) { index, entry in
                        let store = nearby[entry.key]
                        if let store {
                            NavigationLink(value: store) {
                                ChainRankRow(rank: index + 1, entry: entry, store: store,
                                             distance: store.distance(from: reference))
                            }
                        } else {
                            ChainRankRow(rank: index + 1, entry: entry, store: nil, distance: nil)
                        }
                    }
                } header: {
                    Text("\(report.entries.count) enseignes comparées")
                } footer: {
                    Text("""
                    Comment c'est calculé : pour \(report.productCount) produits de grandes marques vendus partout \
                    (Nutella, Barilla, St Michel…), on prend le prix médian de chaque enseigne sur les 12 derniers mois \
                    (hors promotions), puis on le compare à la moyenne des enseignes. « -8 % » signifie 8 % moins cher \
                    que la moyenne. Les enseignes qui vendent surtout leurs propres marques (Lidl, Aldi…) n'apparaissent \
                    que si assez de ces produits y ont été relevés. Mis à jour le \
                    \(report.date.formatted(date: .abbreviated, time: .omitted)). Données : Open Prices.
                    """)
                }
                Section {
                    Link(destination: URL(string: "https://www.quechoisir.org/carte-interactive-drives-n21243/")!) {
                        Label("Comparer les magasins sur la carte UFC-Que Choisir", systemImage: "map")
                    }
                } footer: {
                    Text("Niveau de prix de chaque supermarché proposant un drive, d'après les prix en ligne de plus de 4 500 magasins.")
                }
            } else if model.chainIndexLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Calcul en cours (une vingtaine de secondes)…").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    Text(model.chainIndexError ?? "Le classement n'a pas encore été calculé.")
                        .foregroundStyle(.secondary)
                    Button("Calculer le classement") {
                        Task { await model.refreshChainIndex(force: true) }
                    }
                }
            }
        }
        .navigationTitle("Classement des enseignes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refreshChainIndex(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.chainIndexLoading)
            }
        }
        .refreshable { await model.refreshChainIndex(force: true) }
    }
}
