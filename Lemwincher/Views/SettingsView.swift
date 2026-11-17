import SwiftUI
import MapKit

/// Onglet "Réglages" : rayon, domicile, magasins favoris, compte Open Prices, devise, sources.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var address = ""
    @State private var geocoding = false
    @State private var geocodeError: String? = nil
    @State private var confirmReset = false
    @State private var username = ""
    @State private var password = ""

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        @Bindable var bindable = model
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Rayon de recherche")
                            Spacer()
                            Text("\(Int(model.settings.radiusKm)) km")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $bindable.state.settings.radiusKm, in: 1...20, step: 1)
                    }
                } header: {
                    Text("Zone")
                } footer: {
                    Text("Les magasins et les prix sont recherchés dans ce rayon autour de vous (ou de votre domicile). En ville, 8 km permet d'inclure les hypermarchés de périphérie.")
                }

                homeSection(useHome: $bindable.state.settings.useHome)

                favoritesSection

                accountSection

                Section {
                    Picker("Devise", selection: $bindable.state.settings.currency) {
                        ForEach(AppSettings.currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                } header: {
                    Text("Devise")
                } footer: {
                    Text("Utilisée pour vos relevés, les estimations et le total du panier.")
                }

                Section {
                    Link(destination: URL(string: "https://prices.openfoodfacts.org")!) {
                        Label("Open Prices – prix collaboratifs", systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                        Label("© contributeurs OpenStreetMap", systemImage: "map")
                    }
                } header: {
                    Text("Sources des données")
                } footer: {
                    Text("Les prix de la communauté viennent d'Open Prices (Open Food Facts, licence ODbL), les magasins d'OpenStreetMap. Lemwincher n'est affilié à aucune enseigne.")
                }

                Section {
                    Button("Effacer toutes mes données", role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text("Lemwincher \(appVersion) · vos données restent sur votre iPhone.")
                }
            }
            .navigationTitle("Réglages")
            .confirmationDialog("Effacer vos relevés de prix, votre liste, vos magasins et vos réglages ?",
                                isPresented: $confirmReset,
                                titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) {
                    model.resetAll()
                }
            }
        }
    }

    // MARK: Domicile

    private func homeSection(useHome: Binding<Bool>) -> some View {
        Section {
            Picker("Comparer autour de", selection: useHome) {
                Text("Ma position").tag(false)
                Text("Mon domicile").tag(true)
            }
            .pickerStyle(.segmented)

            if model.settings.home != nil {
                Label(model.settings.homeLabel ?? "Domicile enregistré", systemImage: "house.fill")
            } else {
                Text("Aucun domicile enregistré").foregroundStyle(.secondary)
            }

            Button {
                setHomeToCurrentLocation()
            } label: {
                Label("Mon domicile = ma position actuelle", systemImage: "location.fill")
            }
            .disabled(model.locationManager.location == nil)

            HStack {
                TextField("Ou tapez l'adresse du domicile", text: $address)
                    .textContentType(.fullStreetAddress)
                    .submitLabel(.search)
                    .onSubmit { Task { await geocodeAddress() } }
                if geocoding {
                    ProgressView()
                } else {
                    Button("Chercher") { Task { await geocodeAddress() } }
                        .buttonStyle(.borderless)
                        .disabled(address.trimmed.isEmpty)
                }
            }
            if let geocodeError {
                Text(geocodeError).font(.caption).foregroundStyle(Color.red)
            }
        } header: {
            Text("Domicile")
        } footer: {
            Text("Avec « Mon domicile », l'app compare toujours les magasins autour de chez vous, même quand vous êtes ailleurs.")
        }
    }

    // MARK: Magasins favoris

    private var favoritesSection: some View {
        Section {
            if model.settings.favoriteStores.isEmpty {
                Text("Touchez l'étoile dans la fiche d'un magasin pour l'ajouter ici.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.settings.favoriteStores) { store in
                HStack {
                    StoreLogo(url: store.displayLogoURL, size: 30)
                    VStack(alignment: .leading) {
                        Text(store.name)
                        if let address = store.address {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                model.state.settings.favoriteStores.remove(atOffsets: offsets)
            }
        } header: {
            Text("Mes magasins")
        } footer: {
            Text("Vos magasins habituels apparaissent en premier et peuvent servir de filtre pour comparer votre liste.")
        }
    }

    // MARK: Compte Open Prices

    @ViewBuilder
    private var accountSection: some View {
        let account = model.account
        Section {
            if account.isLoggedIn {
                Label("Connecté : \(account.username ?? "compte Open Food Facts")", systemImage: "person.crop.circle.badge.checkmark")
                let shared = model.state.myPrices.filter { $0.sharedPriceID != nil }.count
                Text("\(shared) prix partagé\(shared > 1 ? "s" : "") depuis cet iPhone")
                    .foregroundStyle(.secondary)
                Button("Se déconnecter", role: .destructive) {
                    account.logout()
                }
            } else {
                TextField("Identifiant Open Food Facts", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Mot de passe", text: $password)
                    .textContentType(.password)
                Button {
                    Task {
                        if await account.login(username: username, password: password) {
                            password = ""
                        }
                    }
                } label: {
                    if account.isWorking {
                        ProgressView()
                    } else {
                        Text("Se connecter")
                    }
                }
                .disabled(account.isWorking || username.trimmed.isEmpty || password.isEmpty)
                if let error = account.lastError {
                    Text(error).font(.caption).foregroundStyle(Color.red)
                }
                Link("Créer un compte gratuit", destination: URL(string: "https://prices.openfoodfacts.org")!)
            }
        } header: {
            Text("Partager mes relevés (Open Prices)")
        } footer: {
            Text("Facultatif. Vos relevés partagés (avec la photo de l'étiquette) enrichissent la base commune : c'est ce qui rend la comparaison précise dans votre quartier. Le mot de passe n'est jamais enregistré ; seul un jeton de session est gardé dans le trousseau de l'iPhone.")
        }
    }

    // MARK: Actions

    private func setHomeToCurrentLocation() {
        guard let location = model.locationManager.location else { return }
        model.state.settings.home = GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        model.state.settings.homeLabel = "Position du \(Date().formatted(date: .abbreviated, time: .omitted))"
        model.state.settings.useHome = true
        geocodeError = nil
    }

    @MainActor
    private func geocodeAddress() async {
        let query = address.trimmed
        guard !query.isEmpty else { return }
        geocoding = true
        geocodeError = nil
        defer { geocoding = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let location = model.locationManager.location {
            request.region = MKCoordinateRegion(center: location.coordinate,
                                                latitudinalMeters: 100_000,
                                                longitudinalMeters: 100_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                geocodeError = "Adresse introuvable."
                return
            }
            let coordinate = item.placemark.coordinate
            model.state.settings.home = GeoPoint(lat: coordinate.latitude, lon: coordinate.longitude)
            model.state.settings.homeLabel = item.placemark.title ?? query
            model.state.settings.useHome = true
            address = ""
        } catch {
            geocodeError = "Adresse introuvable."
        }
    }
}
