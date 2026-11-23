import SwiftUI
import MapKit

/// Écrans ouverts depuis « Autour de moi » (tuiles de la carte héros).
enum StoresRoute: Hashable {
    case fuel, ranking
}

/// Onglet "Autour de moi" : carte, enseignes les moins chères et liste des magasins proches.
struct StoresView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic
    @State private var path = NavigationPath()
    /// Magasin touché sur la carte : sa fiche rapide s'ouvre en bas de l'écran.
    @State private var selectedStoreID: String?
    /// Relie le bouton « Ma position » (posé sur la carte) à la carte.
    @Namespace private var mapScope
    /// Recherche de magasins (nom, enseigne, adresse), puis sur Plans pour ceux qui ne sont pas encore connus.
    @State private var searchText = ""
    @State private var planResults: [Store] = []
    @State private var planSearching = false
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !searchText.trimmed.isEmpty }

    private var searchMatches: [Store] {
        StoreSearch.matches(model.knownStores, query: searchText, reference: model.referenceLocation)
    }

    private var selectedStore: Binding<Store?> {
        Binding(get: { selectedStoreID.flatMap { id in (model.knownStores + planResults).first { $0.id == id } } },
                set: { selectedStoreID = $0?.id })
    }

    var body: some View {
        @Bindable var bindable = model
        NavigationStack(path: $path) {
            Group {
                if model.referenceLocation == nil {
                    LocationNeededView()
                } else {
                    // La carte commence en haut de l'écran, sous la barre en verre ; la liste suit.
                    VStack(spacing: 0) {
                        map
                        storeList(supermarketsOnly: $bindable.state.settings.supermarketsOnly,
                                  openNowOnly: $bindable.state.settings.openNowOnly)
                    }
                    .ignoresSafeArea(edges: .top)
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
            .navigationDestination(for: StoresRoute.self) { route in
                switch route {
                case .fuel: FuelView()
                case .ranking: ChainRankingView()
                }
            }
            .sheet(item: selectedStore) { store in
                StoreQuickSheet(store: store) {
                    selectedStoreID = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { path.append(store) }
                }
                .presentationDetents([.height(300), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(300)))
            }
        }
        .task(id: model.locationKey) {
            await model.refreshStores()
            camera = .automatic
            // Carburants et classement des enseignes en parallèle.
            async let fuel: Void = model.refreshFuel()
            async let ranking: Void = model.refreshChainIndex()
            _ = await (fuel, ranking)
        }
        .task(id: searchText) { await searchPlans() }
        // La carte se cadre sur les résultats de la recherche (et revient aux magasins proches ensuite).
        .onChange(of: mapStores.map(\.id)) { _, _ in
            withAnimation(.smooth) { camera = .automatic }
        }
    }

    /// Supermarchés trouvés par Plans pour la recherche (après une courte pause dans la frappe).
    private func searchPlans() async {
        let query = searchText.trimmed
        guard query.count >= 2 else {
            planResults = []
            planSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }
        planSearching = true
        let found = await StoreSearch.apple(query: query, near: model.referenceLocation, excluding: model.knownStores)
        if Task.isCancelled { return }
        planResults = found
        planSearching = false
    }

    // MARK: Carte

    private var map: some View {
        // Toucher un magasin : fiche rapide avec son site (rayons et prix), l'itinéraire et la fiche complète.
        Map(position: $camera, selection: $selectedStoreID, scope: mapScope) {
            UserAnnotation()
            if model.settings.useHome, let home = model.settings.home {
                Marker("Domicile", systemImage: "house.fill", coordinate: home.coordinate)
                    .tint(Color.blue)
            }
            ForEach(mapStores) { store in
                storeMarker(store)
            }
        }
        // Sous la barre du haut : un voile pour que le titre et les boutons restent lisibles.
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color(.systemBackground).opacity(0.75), Color(.systemBackground).opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .allowsHitTesting(false)
        }
        // En bas de la carte (hors de la barre du haut) : la recherche de magasins et « Ma position ».
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                searchField
                MapUserLocationButton(scope: mapScope)
            }
            .padding(12)
        }
        .mapScope(mapScope)
        .frame(height: 330)
    }

    /// Champ de recherche en verre posé sur la carte.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Rechercher un supermarché", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("storeSearchField")
            if planSearching {
                ProgressView()
                    .controlSize(.small)
            }
            if isSearching {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    /// Épingle d'un magasin : l'initiale de l'enseigne sur sa couleur (« E » bleu pour Leclerc),
    /// une étoile jaune pour les favoris, un caddie gris pour les autres commerces.
    @MapContentBuilder
    private func storeMarker(_ store: Store) -> some MapContent {
        let favorite = model.isFavorite(store)
        let style = ChainStyle.forChain(store.chainKey)
        if let style, !favorite {
            Marker(store.name, monogram: Text(style.monogram), coordinate: store.coordinate)
                .tint(Color(chain: style))
                .tag(store.id)
        }
        if favorite || style == nil {
            Marker(store.name, systemImage: favorite ? "star.fill" : "cart.fill", coordinate: store.coordinate)
                .tint(markerColor(for: store))
                .tag(store.id)
        }
    }

    /// Sur la carte : les 80 magasins les plus proches et les favoris (la liste, elle, est complète).
    /// Des centaines d'épingles superposées seraient illisibles et lentes à afficher.
    /// Pendant une recherche : seulement les magasins trouvés.
    private var mapStores: [Store] {
        if isSearching {
            return Array(searchMatches.prefix(60)) + planResults
        }
        let visible = model.visibleStores
        var shown = Array(visible.prefix(80))
        let shownIDs = Set(shown.map(\.id))
        for store in model.settings.favoriteStores where !shownIDs.contains(store.id) {
            shown.append(store)
        }
        return shown
    }

    private func markerColor(for store: Store) -> Color {
        if model.isFavorite(store) { return Color.lemon }
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
          if isSearching {
            searchSections
          } else {
            Section {
                bestNearbyCard
                    .clearListRow(top: 4, bottom: 4)
            }

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
                    Text("Sources : \(source). Sur la carte : chaque enseigne a sa couleur et son initiale (E pour E.Leclerc, L pour Lidl…), ★ vos magasins, en vert les autres magasins avec des prix relevés. Horaires : OpenStreetMap (quand ils sont connus).")
                }
            }
          }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await model.refreshStores()
            await model.refreshFuel(force: true)
        }
    }

    /// Résultats de la recherche : magasins connus (nom, enseigne, adresse), puis ceux trouvés sur Plans.
    @ViewBuilder
    private var searchSections: some View {
        let reference = model.referenceLocation
        let report = model.chainIndex
        let matches = searchMatches
        Section {
            if matches.isEmpty {
                Text("Aucun magasin connu ne correspond.")
                    .foregroundStyle(.secondary)
            }
            ForEach(matches.prefix(40)) { store in
                NavigationLink(value: store) {
                    StoreRow(store: store,
                             distance: store.distance(from: reference),
                             chainEntry: report?.entry(for: store.chainKey),
                             favorite: model.isFavorite(store))
                }
                .accessibilityIdentifier("storeSearchResult")
            }
        } header: {
            Text(matches.isEmpty ? "Magasins autour de vous" : "Magasins autour de vous (\(matches.count))")
        }

        Section {
            if planSearching && planResults.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche sur Plans…").foregroundStyle(.secondary)
                }
            } else if planResults.isEmpty && searchText.trimmed.count >= 2 {
                Text("Aucun autre supermarché trouvé sur Plans.")
                    .foregroundStyle(.secondary)
            }
            ForEach(planResults) { store in
                NavigationLink(value: store) {
                    StoreRow(store: store,
                             distance: store.distance(from: reference),
                             chainEntry: report?.entry(for: store.chainKey),
                             favorite: model.isFavorite(store))
                }
            }
        } header: {
            Text("Sur Plans")
        } footer: {
            Text("Supermarchés trouvés par Plans, jusqu'à 25 km environ. Touchez-en un pour sa fiche : itinéraire, site de l'enseigne, relevé de prix, ou l'ajouter à vos magasins.")
        }
    }

    /// Carte héros : l'enseigne la moins chère près de chez vous et le carburant le moins cher.
    private var bestNearbyCard: some View {
        let reference = model.referenceLocation
        let fuel = model.settings.fuelType
        let bestFuel = FuelStats.ranked(model.fuelStations, fuel: fuel).first
        let nearby = model.nearestStoreByChain
        let bestChain = model.chainIndex?.entries.first { nearby[$0.key] != nil }
        let bestStore = bestChain.flatMap { nearby[$0.key] }

        return HeroCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Le moins cher autour de vous", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.92)
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            if let bestStore { path.append(bestStore) } else { path.append(StoresRoute.ranking) }
                        } label: {
                            heroTile(icon: "cart.fill",
                                     title: bestChain?.name ?? "Enseignes",
                                     value: bestChain?.differenceText ?? (model.chainIndexLoading ? "…" : "—"),
                                     caption: bestStore.map { Fmt.join($0.name, $0.distance(from: reference).map { Fmt.distance($0) }) }
                                        ?? (model.chainIndexLoading ? "Calcul du classement…" : "Classement des enseignes"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bestChainTile")

                        Button {
                            path.append(StoresRoute.fuel)
                        } label: {
                            heroTile(icon: "fuelpump.fill",
                                     title: fuel.label,
                                     value: (bestFuel?.price(for: fuel)?.value).map { Fmt.fuel($0) } ?? (model.fuelLoading ? "…" : "—"),
                                     caption: bestFuel.map { station in
                                         Fmt.join(station.title, reference.map { Fmt.distance(station.location.distance(from: $0)) })
                                     } ?? (model.fuelLoading ? "Prix officiels…" : "Carburant le moins cher"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("fuelLink")
                    }
                }
            }
        }
    }

    /// Tuile en verre de la carte héros : icône, libellé, grand chiffre, précision.
    private func heroTile(icon: String, title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.bold))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).opacity(0.7)
            }
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption2)
                .opacity(0.88)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    NavigationLink(value: StoresRoute.ranking) {
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
            StoreLogo(url: store?.displayLogoURL ?? Chain.logoURL(brand: entry.name), size: 34,
                      chainKey: store?.chainKey ?? entry.key)
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
