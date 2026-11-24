import SwiftUI
import MapKit

/// Fiche d'un magasin : adresse, itinéraire, enseigne, favori et prix connus.
struct StoreDetailView: View {
    @Environment(AppModel.self) private var model
    let store: Store

    @State private var community: [PriceObservation] = []
    @State private var loading = false
    @State private var loadError: String? = nil
    @State private var showAddPrice = false
    @State private var filter = ""
    /// Site de l'enseigne ou du magasin ouvert dans le navigateur de l'app.
    @State private var browser: StoreBrowserRequest?

    private var observations: [PriceObservation] {
        let mine = model.myObservations(storeID: store.id)
        let all = PriceEngine.latestPerProduct(community + mine)
            .sorted { $0.productName.localizedCaseInsensitiveCompare($1.productName) == .orderedAscending }
        let f = filter.trimmed
        guard !f.isEmpty else { return all }
        return all.filter { $0.productName.localizedCaseInsensitiveContains(f) }
    }

    var body: some View {
        let observations = self.observations
        let favorite = model.isFavorite(store)
        List {
            // En-tête façon Plans : carte arrondie, cartouche en verre (logo, nom, adresse), actions en verre.
            Section {
                ZStack(alignment: .bottomLeading) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: store.coordinate,
                                                                     latitudinalMeters: 700,
                                                                     longitudinalMeters: 700))) {
                        if let style = ChainStyle.forChain(store.chainKey) {
                            Marker(store.name, monogram: Text(style.monogram), coordinate: store.coordinate)
                                .tint(Color(chain: style))
                        }
                        if ChainStyle.forChain(store.chainKey) == nil {
                            Marker(store.name, systemImage: "cart.fill", coordinate: store.coordinate)
                                .tint(Color.brand)
                        }
                        UserAnnotation()
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    HStack(alignment: .center, spacing: 12) {
                        StoreLogo(url: store.displayLogoURL, size: 48, chainKey: store.chainKey)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name)
                                .font(.headline)
                                .lineLimit(2)
                            if let address = store.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let distance = store.distance(from: model.referenceLocation) {
                                Label("À \(Fmt.distance(distance))", systemImage: "location.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.brand)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(10)
                }
                .clearListRow(top: 2, bottom: 8)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        if let url = store.directionsURL {
                            Link(destination: url) {
                                ActionTileLabel(title: "Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            }
                            .buttonStyle(.glassProminent)
                            .tint(Color.brand)
                        }
                        if let phone = store.phoneURL {
                            Link(destination: phone) {
                                ActionTileLabel(title: "Appeler", systemImage: "phone.fill")
                            }
                            .buttonStyle(.glass)
                        }
                        Button {
                            model.toggleFavorite(store)
                        } label: {
                            ActionTileLabel(title: favorite ? "Mon magasin" : "Favori",
                                            systemImage: favorite ? "star.fill" : "star")
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(favorite ? "Retirer de mes magasins" : "Ajouter à mes magasins")
                    }
                }
                .clearListRow(top: 0, bottom: 4)
            }

            Section {
                if let chainName = store.chainName {
                    HStack {
                        Label("Enseigne : \(chainName)", systemImage: "building.2")
                        Spacer()
                        if let entry = model.chainIndex?.entry(for: store.chainKey) {
                            ChainIndexBadge(entry: entry)
                        }
                    }
                }

                StoreSiteButtons(store: store, request: $browser)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                // Mes rayons de ce magasin sur le site : un toucher, et le rayon s'ouvre directement.
                ForEach(model.state.trackedPages.filter { $0.store.id == store.id }) { page in
                    Button {
                        if let url = URL(string: page.url) { browser = .page(url) }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(page.shortTitle)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("Rayon suivi · \(page.siteName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bookmark.fill")
                        }
                    }
                    .accessibilityIdentifier("storeTrackedPage")
                }
                // Mauvais drive choisi sur le site : on repart de zéro pour ce magasin (les autres ne bougent pas).
                if model.state.sitePages.contains(where: { $0.store.id == store.id }) {
                    Button(role: .destructive) {
                        model.forgetSites(of: store)
                    } label: {
                        Label("Oublier le drive choisi sur le site", systemImage: "arrow.counterclockwise")
                    }
                }
                // Site propre du magasin (en plus de celui de l'enseigne), ouvert dans l'app pour en lire les prix.
                if let website = store.websiteURL, DriveSite.forStore(store) != nil {
                    Button {
                        browser = .website(website)
                    } label: {
                        Label("Site du magasin", systemImage: "safari")
                    }
                }
                Button {
                    showAddPrice = true
                } label: {
                    Label("Relever un prix dans ce magasin", systemImage: "plus.circle.fill")
                }
            }

            hoursSection

            Section {
                if loading && observations.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Chargement des prix…").foregroundStyle(.secondary)
                    }
                }
                if let loadError {
                    Text(loadError).font(.footnote).foregroundStyle(.secondary)
                }
                if !loading && observations.isEmpty && filter.trimmed.isEmpty {
                    Text("Aucun prix connu pour ce magasin. Soyez le premier à en relever !")
                        .foregroundStyle(.secondary)
                }
                ForEach(observations) { obs in
                    NavigationLink(value: obs.product) {
                        ObservationRow(obs: obs, showStore: false)
                    }
                }
            } header: {
                Text("Prix connus (\(observations.count))")
            } footer: {
                Text("Dernier prix connu de chaque produit. Sources : Open Prices et vos relevés.")
            }
        }
        .searchable(text: $filter, prompt: "Filtrer les produits")
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.toggleFavorite(store)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .foregroundStyle(favorite ? Color.yellow : Color.accentColor)
                }
            }
        }
        .sheet(isPresented: $showAddPrice) {
            AddPriceView(store: store)
        }
        .storeBrowser($browser, store: store)
        .task { await load() }
        .refreshable { await load() }
    }

    /// Horaires de la semaine (aujourd'hui en gras).
    @ViewBuilder
    private var hoursSection: some View {
        if let hours = store.hours {
            let today = OpeningHours.weekdayIndex(of: Date(), calendar: .current)
            Section {
                OpenStatusLabel(hours: hours)
                    .font(.subheadline)
                ForEach(0..<7, id: \.self) { day in
                    HStack {
                        Text(OpeningHours.dayLabels[day])
                        Spacer()
                        Text(hours.description(forDay: day))
                            .monospacedDigit()
                            .foregroundStyle(day == today ? Color.primary : Color.secondary)
                    }
                    .fontWeight(day == today ? .semibold : .regular)
                }
            } header: {
                Text("Horaires")
            } footer: {
                Text("Horaires OpenStreetMap, à vérifier les jours fériés.")
            }
        } else if let raw = store.openingHours {
            Section("Horaires") {
                Text(raw).font(.callout)
            }
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            let prices = try await OpenPricesAPI.pricesAt(store: store)
            community = PriceEngine.observations(from: prices)
        } catch {
            if !error.isCancellation {
                loadError = "Prix de la communauté indisponibles (\(error.localizedDescription))."
            }
        }
        loading = false
    }
}
