import SwiftUI
import MapKit
import UniformTypeIdentifiers

/// Réglages (roue dentée ⚙︎) : alimentation, rayon, domicile, magasins favoris, compte Open Prices,
/// devise, sauvegarde, sources.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Ouvert en feuille depuis ⚙︎ : bouton « OK » pour fermer.
    var isSheet = false

    @State private var address = ""
    @State private var geocoding = false
    @State private var geocodeError: String? = nil
    @State private var confirmReset = false
    @State private var username = ""
    @State private var password = ""
    @State private var showImporter = false
    @State private var importMessage: String? = nil

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
                    Toggle(isOn: $bindable.state.settings.noPork) {
                        Label("Sans porc", systemImage: "checkmark.seal")
                    }
                    Toggle(isOn: $bindable.state.settings.vegetarian) {
                        Label("Recettes végétariennes seulement", systemImage: "leaf")
                    }
                    Picker(selection: $bindable.state.settings.defaultServings) {
                        ForEach([1, 2, 4, 6], id: \.self) { count in
                            Text(count == 1 ? "1 personne" : "\(count) personnes").tag(count)
                        }
                    } label: {
                        Label("Je cuisine pour", systemImage: "person.2")
                    }
                    Toggle(isOn: $bindable.state.settings.readStepsAloud) {
                        Label("Lire les étapes à voix haute", systemImage: "speaker.wave.2")
                    }
                } header: {
                    Text("Mon alimentation")
                } footer: {
                    Text("Sans porc : les recettes et les produits proposés n'en contiennent pas (jambon, lardons, saucisson, chorizo… sauf versions dinde, volaille ou bœuf). La fiche d'un produit signale aussi le porc et la gélatine trouvés dans sa liste d'ingrédients.")
                }
                .tint(Color.brand)

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
                    Picker(selection: $bindable.state.settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    } label: {
                        Label("Apparence", systemImage: "circle.lefthalf.filled")
                    }
                    Picker("Devise", selection: $bindable.state.settings.currency) {
                        ForEach(AppSettings.currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    Picker("Mon carburant", selection: $bindable.state.settings.fuelType) {
                        ForEach(FuelType.allCases) { fuel in
                            Text(fuel.label).tag(fuel)
                        }
                    }
                } header: {
                    Text("Préférences")
                } footer: {
                    Text("Apparence : « Comme l'iPhone » suit le mode clair ou sombre de l'iPhone. La devise sert à vos relevés, aux prix affichés et au total du panier. Le carburant est celui affiché dans « Autour de moi ».")
                }

                backupSection

                Section {
                    Link(destination: URL(string: "https://prices.openfoodfacts.org")!) {
                        Label("Open Prices – prix collaboratifs", systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                        Label("© contributeurs OpenStreetMap", systemImage: "map")
                    }
                    Link(destination: URL(string: "https://www.prix-carburants.gouv.fr")!) {
                        Label("Prix des carburants (gouvernement)", systemImage: "fuelpump")
                    }
                    Link(destination: URL(string: "https://rappel.conso.gouv.fr")!) {
                        Label("RappelConso (gouvernement)", systemImage: "exclamationmark.shield")
                    }
                    Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                        Label("Open Food Facts – Nutri-Score", systemImage: "leaf")
                    }
                } header: {
                    Text("Sources des données")
                } footer: {
                    Text("Prix de la communauté : Open Prices (Open Food Facts, licence ODbL). Magasins et horaires : OpenStreetMap. Carburants et rappels : data.economie.gouv.fr (Licence Ouverte). Lemwincher n'est affilié à aucune enseigne.")
                }

                Section {
                    Button {
                        model.state.settings.hasSeenOnboarding = false
                    } label: {
                        Label("Revoir la présentation", systemImage: "sparkles")
                    }
                    Button("Effacer toutes mes données", role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text("Vos données restent sur votre iPhone. Astuce Siri : « Ajoute à ma liste Lemwincher ».")
                }

                Section {
                    VStack(spacing: 8) {
                        BrandLogo(size: 64)
                        Text("Lemwincher")
                            .font(.headline)
                        Text("Le moins cher, près de chez vous")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                            .accessibilityIdentifier("closeSettings")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }
            .alert("Restauration", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
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
                    StoreLogo(url: store.displayLogoURL, size: 30, chainKey: store.chainKey)
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

    // MARK: Sauvegarde

    private var backupSection: some View {
        Section {
            if let data = model.exportBackup() {
                ShareLink(item: BackupExport(data: data),
                          preview: SharePreview("Sauvegarde Lemwincher")) {
                    Label("Exporter une sauvegarde", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                showImporter = true
            } label: {
                Label("Restaurer une sauvegarde", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Sauvegarde")
        } footer: {
            Text("Gardez une copie de vos relevés, de votre liste et de vos magasins (dans Fichiers, iCloud Drive, par e-mail…). La restauration ajoute les données sans rien effacer.")
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = "Import impossible : \(error.localizedDescription)"
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let summary = try model.importBackup(data)
                importMessage = summary.text
            } catch {
                importMessage = "Ce fichier n'est pas une sauvegarde Lemwincher valide."
            }
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

/// Fichier de sauvegarde partagé (Fichiers, iCloud Drive, AirDrop, e-mail…).
struct BackupExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            export.data
        }
        .suggestedFileName("lemwincher-sauvegarde.json")
    }
}
