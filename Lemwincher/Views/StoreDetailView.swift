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
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(center: store.coordinate,
                                                                 latitudinalMeters: 700,
                                                                 longitudinalMeters: 700))) {
                    Marker(store.name, systemImage: "cart.fill", coordinate: store.coordinate)
                        .tint(Color.brand)
                    UserAnnotation()
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())

                HStack(alignment: .top, spacing: 12) {
                    StoreLogo(url: store.displayLogoURL, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.name).font(.title2.bold())
                        if let address = store.address {
                            Text(address).foregroundStyle(.secondary)
                        }
                        if let distance = store.distance(from: model.referenceLocation) {
                            Label("À \(Fmt.distance(distance))", systemImage: "location")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

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
                if let url = store.directionsURL {
                    Link(destination: url) {
                        Label("Itinéraire avec Plans", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                }
                if let phone = store.phoneURL {
                    Link(destination: phone) {
                        Label("Appeler le magasin", systemImage: "phone.fill")
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
                    model.toggleFavorite(store)
                } label: {
                    Label(favorite ? "Retirer de mes magasins" : "Ajouter à mes magasins",
                          systemImage: favorite ? "star.slash" : "star")
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
