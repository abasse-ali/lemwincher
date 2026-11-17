import SwiftUI
import UIKit

/// Formulaire pour relever un prix en magasin (avec détection du magasin et mode « à la chaîne »).
struct AddPriceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let fixedStore: Store?

    @State private var barcode: String
    @State private var name: String
    @State private var brand: String
    @State private var details: Product?
    @State private var priceText = ""
    @State private var date = Date()
    @State private var isDiscounted = false
    @State private var storeID: String
    @State private var storeAutoDetected = false
    @State private var showScanner = false
    @State private var lookingUp = false
    @State private var photo: UIImage? = nil
    @State private var showCamera = false
    @State private var shareOnOpenPrices = true
    @State private var saving = false
    @State private var shareError: String? = nil
    @State private var continueAfterError = false
    @State private var savedCount = 0

    init(product: Product? = nil, store: Store? = nil) {
        fixedStore = store
        let isCustom = product?.isCustom ?? true
        _barcode = State(initialValue: isCustom ? "" : (product?.code ?? ""))
        _name = State(initialValue: (product?.hasDetails ?? false) ? (product?.name ?? "") : "")
        _brand = State(initialValue: product?.brand ?? "")
        _details = State(initialValue: product)
        _storeID = State(initialValue: store?.id ?? "")
    }

    // MARK: Données dérivées

    private var storeChoices: [Store] {
        var list = model.knownStores
        if let fixedStore, !list.contains(where: { $0.id == fixedStore.id }) {
            list.insert(fixedStore, at: 0)
        }
        let reference = model.locationManager.location ?? model.referenceLocation
        return list.sorted {
            ($0.distance(from: reference) ?? .infinity) < ($1.distance(from: reference) ?? .infinity)
        }
    }

    private var selectedStore: Store? {
        storeChoices.first { $0.id == storeID }
    }

    private var parsedPrice: Double? {
        let text = priceText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard let value = Double(text), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        parsedPrice != nil && selectedStore != nil && !name.trimmed.isEmpty && !saving
    }

    /// Partage possible : connecté, produit avec code-barres et magasin OpenStreetMap.
    private var shareAvailable: Bool {
        model.account.isLoggedIn && barcode.trimmed.isBarcodeLike && selectedStore?.osmId != nil
    }

    private var willShare: Bool {
        shareAvailable && shareOnOpenPrices && photo != nil
    }

    // MARK: Vue

    var body: some View {
        NavigationStack {
            Form {
                if savedCount > 0 {
                    Section {
                        Label("\(savedCount) prix enregistré\(savedCount > 1 ? "s" : "") — au suivant !",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.brand)
                    }
                }

                Section {
                    HStack {
                        TextField("Code-barres (facultatif)", text: $barcode)
                            .keyboardType(.numberPad)
                        if lookingUp {
                            ProgressView()
                        }
                        Button {
                            showScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder").font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                    TextField("Nom du produit", text: $name)
                    TextField("Marque (facultatif)", text: $brand)
                } header: {
                    Text("Produit")
                } footer: {
                    Text("Sans code-barres (fruits, légumes, vrac…), donnez toujours le même nom au produit pour pouvoir le comparer.")
                }

                Section {
                    if storeChoices.isEmpty {
                        Text("Aucun magasin chargé. Ouvrez d'abord l'onglet « Autour de moi ».")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Magasin", selection: $storeID) {
                            Text("Choisir…").tag("")
                            ForEach(storeChoices) { store in
                                Text(storeLabel(store)).tag(store.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } header: {
                    Text("Magasin")
                } footer: {
                    if storeAutoDetected, let store = selectedStore {
                        Label("Vous êtes chez \(store.name) : magasin choisi automatiquement.", systemImage: "location.fill")
                    }
                }

                Section("Prix") {
                    HStack {
                        TextField("0,00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .font(.title2.monospacedDigit())
                        Text(model.settings.currency).foregroundStyle(.secondary)
                    }
                    Toggle("Prix en promotion", isOn: $isDiscounted)
                    DatePicker("Date du relevé", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                shareSection

                Section {
                    Button {
                        save(continueAfter: true)
                    } label: {
                        Label("Enregistrer et relever le suivant", systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Relever un prix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedCount > 0 ? "Terminer" : "Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save(continueAfter: false) }
                        .disabled(!canSave)
                }
            }
            .overlay {
                if saving {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Envoi à Open Prices…")
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet { code in
                    barcode = code
                    showScanner = false
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let image { photo = image }
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .alert("Prix enregistré, mais pas partagé", isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )) {
                Button("OK") { finish(continueAfter: continueAfterError) }
            } message: {
                Text(shareError ?? "")
            }
            .onAppear(perform: detectStore)
            .task(id: barcode) { await lookupProduct() }
        }
    }

    @ViewBuilder
    private var shareSection: some View {
        if model.account.isLoggedIn {
            Section {
                Toggle("Partager sur Open Prices", isOn: $shareOnOpenPrices)
                    .disabled(!shareAvailable)
                if shareOnOpenPrices && shareAvailable {
                    HStack(spacing: 12) {
                        if let photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button {
                            showCamera = true
                        } label: {
                            Label(photo == nil ? "Photographier l'étiquette" : "Reprendre la photo",
                                  systemImage: "camera")
                        }
                    }
                }
            } header: {
                Text("Aider les autres")
            } footer: {
                if !shareAvailable {
                    Text("Le partage nécessite un code-barres et un magasin OpenStreetMap.")
                } else if photo == nil && shareOnOpenPrices {
                    Text("Open Prices demande une photo de l'étiquette (ou du ticket) comme preuve du prix.")
                } else {
                    Text("Votre prix sera visible par tous les utilisateurs d'Open Prices près de chez vous.")
                }
            }
        } else {
            Section {
                Text("Connectez-vous à Open Prices dans Réglages pour partager vos relevés : plus il y a de prix près de chez vous, plus la comparaison est précise.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func storeLabel(_ store: Store) -> String {
        let reference = model.locationManager.location ?? model.referenceLocation
        guard let distance = store.distance(from: reference) else { return store.name }
        return "\(store.name) · \(Fmt.distance(distance))"
    }

    // MARK: Actions

    /// Choisit automatiquement le magasin où l'on se trouve.
    private func detectStore() {
        guard fixedStore == nil, storeID.isEmpty, let here = model.storeAtCurrentPosition() else { return }
        storeID = here.id
        storeAutoDetected = true
    }

    /// Remplit nom / marque / photo / contenance à partir du code-barres.
    private func lookupProduct() async {
        let code = barcode.trimmed
        guard code.isBarcodeLike else { return }
        if let details, details.code == code, details.hasDetails {
            if name.trimmed.isEmpty { name = details.name }
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        lookingUp = true
        let found = await ProductLookup.lookup(code: code)
        lookingUp = false
        guard !Task.isCancelled, let found else { return }
        details = found
        if name.trimmed.isEmpty { name = found.name }
        if brand.trimmed.isEmpty { brand = found.brand ?? "" }
    }

    private func makeProduct() -> Product {
        let productName = name.trimmed
        let code = barcode.trimmed
        guard !code.isEmpty else {
            var custom = Product.custom(named: productName)
            custom.brand = brand.nilIfBlank?.trimmed
            return custom
        }
        var product = Product(code: code, name: productName)
        product.brand = brand.nilIfBlank?.trimmed
        if let details, details.code == code {
            product.imageURL = details.imageURL
            product.quantity = details.quantity
            product.unitQuantity = details.unitQuantity
            product.unitName = details.unitName
            product.categories = details.categories
        }
        return product
    }

    private func save(continueAfter: Bool) {
        guard let price = parsedPrice, let store = selectedStore else { return }
        let entry = MyPrice(product: makeProduct(),
                            store: store,
                            price: price,
                            currency: model.settings.currency,
                            date: date,
                            isDiscounted: isDiscounted)
        model.addMyPrice(entry)

        guard willShare, let photo else {
            finish(continueAfter: continueAfter)
            return
        }
        saving = true
        Task {
            do {
                let priceID = try await model.account.share(entry, photo: photo)
                model.markShared(entry.id, priceID: priceID)
                saving = false
                finish(continueAfter: continueAfter)
            } catch {
                saving = false
                continueAfterError = continueAfter
                shareError = error.localizedDescription
            }
        }
    }

    private func finish(continueAfter: Bool) {
        guard continueAfter else {
            dismiss()
            return
        }
        // Mode « à la chaîne » : on garde le magasin et la date, on vide le produit et on rouvre le scanner.
        savedCount += 1
        barcode = ""
        name = ""
        brand = ""
        details = nil
        priceText = ""
        isDiscounted = false
        photo = nil
        showScanner = true
    }
}
