import SwiftUI

/// Ouvre « Comparer » (onglet Produits, fiche d'un produit) ; `query` : produits similaires cherchés au départ.
struct ValueCompareRoute: Hashable {
    var query: String = ""
}

/// Comparer le rapport quantité/prix de produits similaires : au kilo, au litre ou à la pièce
/// (« 10 steaks hachés » à 7,99 € ou « 2 steaks hachés » à 3,99 € ?).
struct ValueCompareView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: String
    @State private var query: String
    /// Unité choisie par l'utilisateur (sinon : au kilo, ou à la pièce si le poids manque).
    @State private var chosenBasis: ValueBasis?
    @State private var showEditor = false

    init(initialQuery: String = "") {
        _draft = State(initialValue: initialQuery)
        _query = State(initialValue: initialQuery.trimmed)
    }

    private var manualItems: [ValueItem] { model.state.compareEntries.map(\.item) }

    /// Produits similaires dont le prix est connu : vos relevés, les rayons des sites, Open Prices.
    private var foundItems: [ValueItem] {
        guard !query.isEmpty else { return [] }
        let results = model.suggestionResults(for: query)
        return SuggestionEngine.merge(personal: model.personalSuggestions(for: query), remote: results.items)
            .filter { model.dietAllows($0.product) }
            .compactMap { suggestion in
                guard let offer = suggestion.offer else { return nil }
                let place = offer.isLocal ? offer.storeName : "relevé chez \(offer.storeName)"
                return ValueItem(id: suggestion.id, product: suggestion.product, price: offer.price,
                                 currency: offer.currency, place: Fmt.join(place, offer.source, Fmt.day(offer.date)))
            }
    }

    var body: some View {
        let items = manualItems + foundItems
        let available = ValueCompare.availableBases(items)
        let basis = chosenBasis.flatMap { available.contains($0) ? $0 : nil } ?? ValueCompare.defaultBasis(items)
        let results = model.suggestionResults(for: query)
        let loading = !query.isEmpty && (results.loading || !results.loaded)

        List {
            searchSection(loading: loading)

            if let basis, available.count > 1 {
                Section {
                    Picker("Comparer", selection: Binding(get: { basis }, set: { chosenBasis = $0 })) {
                        ForEach(available) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("compareBasis")
                }
            }

            if let basis {
                let ranking = ValueCompare.rank(items, basis: basis)
                if let summary = ValueCompare.summary(ranking) {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .font(.title2)
                                .foregroundStyle(Color.brand)
                            Text(summary)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    ForEach(Array(ranking.ranked.enumerated()), id: \.element.id) { index, item in
                        row(item, rank: index + 1, ranking: ranking)
                    }
                } header: {
                    Text("Classement \(basis.phrase) (\(ranking.ranked.count))")
                } footer: {
                    Text(basisFooter(basis))
                }
                if !ranking.others.isEmpty {
                    othersSection(ranking.others, basis: basis)
                }
            } else if !items.isEmpty {
                othersSection(items.sorted { $0.price < $1.price }, basis: nil)
            }

            if items.isEmpty {
                emptyState(loading: loading)
            }

            manualSection
        }
        .navigationTitle("Comparer")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            ManualCompareEditor(currency: model.settings.currency) { entry in
                model.state.compareEntries.append(entry)
                Log.info(.compare, "Produit noté : \(entry.name) à \(Fmt.price(entry.price, entry.currency))",
                         details: entry.item.pack.text ?? "contenance inconnue")
            }
        }
        .task(id: query) {
            guard !query.isEmpty else { return }
            await model.loadSuggestions(for: query)
        }
    }

    // MARK: Sections

    private func searchSection(loading: Bool) -> some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Quel produit ? (ex. : steak haché)", text: $draft)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { query = draft.trimmed }
                    .accessibilityIdentifier("compareQuery")
                if loading {
                    ProgressView()
                } else if !draft.isEmpty {
                    Button {
                        draft = ""
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Effacer la recherche")
                }
            }
        } footer: {
            Text("Les produits similaires dont le prix est connu (vos relevés, les rayons des sites d'enseignes, Open Prices) sont classés du plus avantageux au moins avantageux.")
        }
    }

    @ViewBuilder
    private func row(_ item: ValueItem, rank: Int, ranking: ValueCompare.Ranking) -> some View {
        let best = rank == 1 && ranking.ranked.count > 1
        let content = ValueRow(item: item, rank: rank, basis: ranking.basis, best: best,
                               extraPercent: ranking.extraPercent(item))
        if item.isManual {
            content
                .swipeActions {
                    Button(role: .destructive) {
                        remove(item)
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
        } else {
            NavigationLink(value: item.product) {
                content
            }
        }
    }

    private func othersSection(_ others: [ValueItem], basis: ValueBasis?) -> some View {
        Section {
            ForEach(others) { item in
                if item.isManual {
                    ValueRow(item: item)
                        .swipeActions {
                            Button(role: .destructive) {
                                remove(item)
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                } else {
                    NavigationLink(value: item.product) {
                        ValueRow(item: item)
                    }
                }
            }
        } header: {
            Text(basis == nil ? "Prix connus (\(others.count))" : "Contenance inconnue (\(others.count))")
        } footer: {
            Text(basis == nil
                 ? "Ni le poids ni le nombre de pièces ne sont indiqués : pour comparer, notez-les (« 10 steaks », « 4 x 125 g »)."
                 : "Ni poids ni nombre de pièces \(basis == .piece ? "" : "comparables ")connus pour ces produits : ils sont classés par prix.")
        }
    }

    @ViewBuilder
    private func emptyState(loading: Bool) -> some View {
        if query.isEmpty {
            ContentUnavailableView {
                Label("Comparez le rapport quantité/prix", systemImage: "scalemass")
            } description: {
                Text("Cherchez un produit (steak haché, lait, œufs…) ou notez ceux que vous voyez en magasin : l'app vous dit lequel revient le moins cher au kilo, au litre ou à la pièce.")
            }
        } else if !loading {
            Text("Aucun prix connu pour « \(query) ». Notez les produits vus en magasin, ou capturez les prix sur le site d'une enseigne (Ma liste › article › « Prix du jour sur le site »).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var manualSection: some View {
        Section {
            Button {
                showEditor = true
            } label: {
                Label("Noter un produit vu en magasin", systemImage: "square.and.pencil")
            }
            .accessibilityIdentifier("compareAddManual")
            if !model.state.compareEntries.isEmpty {
                Button(role: .destructive) {
                    model.state.compareEntries.removeAll()
                } label: {
                    Label("Effacer les produits notés (\(model.state.compareEntries.count))", systemImage: "trash")
                }
            }
        } footer: {
            Text("Exemple : « 10 steaks hachés surgelés » à 7,99 € et « 2 steaks hachés » à 3,99 € : 0,80 € contre 2,00 € la pièce. Indiquez le poids (« 10 x 100 g ») pour comparer au kilo.")
        }
    }

    private func basisFooter(_ basis: ValueBasis) -> String {
        switch basis {
        case .kilo: return "Prix ramené au kilo d'après le poids indiqué. Le pourcentage dit combien chaque produit revient plus cher que le premier."
        case .litre: return "Prix ramené au litre d'après le volume indiqué. Le pourcentage dit combien chaque produit revient plus cher que le premier."
        case .piece: return "Prix divisé par le nombre de pièces (steaks, œufs, yaourts…). Si le poids est connu, comparez aussi au kilo : les pièces n'ont pas toujours la même taille."
        }
    }

    private func remove(_ item: ValueItem) {
        model.state.compareEntries.removeAll { "manual:" + $0.id.uuidString == item.id }
    }
}

/// Une ligne du classement : rang, photo, nom, contenance, prix à l'unité et prix payé.
struct ValueRow: View {
    let item: ValueItem
    var rank: Int? = nil
    var basis: ValueBasis? = nil
    var best = false
    var extraPercent: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.caption.bold())
                    .frame(width: 26, height: 26)
                    .background(best ? Color.brand : Color(.tertiarySystemFill), in: Circle())
                    .foregroundStyle(best ? Color.white : Color.primary)
            }
            ProductThumb(url: item.product.imageURL, size: 44, name: item.product.name)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(item.product.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if item.isManual {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("noté à la main")
                    }
                }
                if let details = Fmt.join(item.product.brand, item.pack.text).nilIfBlank {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let place = item.place {
                    Text(place)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                if let basis, let unit = item.unitPrice(basis) {
                    Text(ValueCompare.unitPriceText(unit, basis: basis, currency: item.currency))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(best ? Color.brand : Color.primary)
                    Text(Fmt.price(item.price, item.currency))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(Fmt.price(item.price, item.currency))
                        .font(.subheadline.bold().monospacedDigit())
                }
                if best {
                    Text("Le plus avantageux")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.brand)
                } else if let extraPercent, extraPercent > 0 {
                    Text("+\(extraPercent) %")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.orange)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Noter un produit vu en magasin : nom, contenance, prix ; l'app montre ce qu'elle a compris.
struct ManualCompareEditor: View {
    @Environment(\.dismiss) private var dismiss
    let currency: String
    let onSave: (ManualCompareEntry) -> Void

    @State private var name = ""
    @State private var quantity = ""
    @State private var priceText = ""
    @State private var storeName = ""

    private var price: Double? {
        let cleaned = priceText.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let value = Double(cleaned), value > 0, value < 10_000 else { return nil }
        return value
    }

    private var pack: PackSize { PackSize.parse(name: name, quantity: quantity.nilIfBlank) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Produit (ex. : 10 steaks hachés surgelés)", text: $name)
                        .accessibilityIdentifier("compareName")
                    TextField("Poids ou nombre (facultatif : 10 x 100 g)", text: $quantity)
                        .accessibilityIdentifier("compareQuantity")
                    TextField("Prix (ex. : 7,99)", text: $priceText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("comparePrice")
                    TextField("Magasin (facultatif)", text: $storeName)
                } footer: {
                    Text("Le nombre de pièces (« 10 steaks », « x12 », « lot de 4 ») et le poids (« 1 kg », « 4 x 125 g ») sont lus dans le nom ou dans la contenance.")
                }

                Section("Ce que l'app a compris") {
                    if let text = pack.text {
                        Label(text, systemImage: "shippingbox")
                    } else {
                        Text("Ni poids ni nombre de pièces : indiquez-les pour pouvoir comparer.")
                            .foregroundStyle(.secondary)
                    }
                    if let price {
                        let item = ValueItem(id: "apercu", product: .custom(named: name.nilIfBlank ?? "Produit"),
                                             price: price, currency: currency, pack: pack)
                        ForEach(ValueBasis.allCases) { basis in
                            if let unit = item.unitPrice(basis), basis != .piece || (pack.count ?? 0) > 1 {
                                LabeledContent(basis.label,
                                               value: ValueCompare.unitPriceText(unit, basis: basis, currency: currency))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Noter un produit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { save() }
                        .disabled(name.trimmed.isEmpty || price == nil)
                        .accessibilityIdentifier("compareSave")
                }
            }
        }
    }

    private func save() {
        guard let price, !name.trimmed.isEmpty else { return }
        onSave(ManualCompareEntry(name: name.trimmed, quantity: quantity.nilIfBlank?.trimmed, price: price,
                                  currency: currency, storeName: storeName.nilIfBlank?.trimmed))
        dismiss()
    }
}
