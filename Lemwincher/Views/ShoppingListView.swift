import SwiftUI

/// Onglet "Ma liste" : liste de courses et magasin le moins cher pour tout le panier.
struct ShoppingListView: View {
    @Environment(AppModel.self) private var model

    /// Relevés à moins de X km, par code produit.
    @State private var local: [String: [PriceObservation]] = [:]
    /// Relevés du pays (12 mois), par code produit : servent aux estimations par enseigne.
    @State private var national: [String: [PriceObservation]] = [:]
    @State private var loading = false
    @State private var showCustomAlert = false
    @State private var customName = ""
    @State private var quickAdd = ""
    @State private var showShoppingDone = false
    @State private var path = NavigationPath()
    /// Articles dépliés (produits précis affichés en dessous).
    @State private var expanded: Set<UUID> = []
    /// Article cherché sur le site d'une enseigne (navigateur intégré).
    @State private var captureRequest: CaptureRequest?

    struct CaptureRequest: Identifiable {
        let query: String
        var id: String { query }
    }

    /// Article coché dont le prix est inconnu : on demande combien il a coûté.
    @State private var pricePrompt: PricePrompt?
    @State private var promptAmount = ""

    struct PricePrompt: Identifiable {
        let itemID: UUID
        let name: String
        let quote: PurchaseQuote
        var id: UUID { itemID }
    }

    /// Cocher = acheté : le prix devient une dépense du mois. Décocher la retire.
    private func toggle(_ item: ShoppingItem) {
        if item.checked {
            model.uncheckListItem(item.id)
            return
        }
        let quote = basket.purchaseQuote(for: item.id, here: model.storeAtCurrentPosition())
        if let unit = quote.unitPrice {
            model.checkListItem(item.id, amount: unit * Double(item.quantity),
                                storeName: quote.storeName, store: quote.store)
        } else {
            promptAmount = quote.hint.map { String(format: "%.2f", $0 * Double(item.quantity)).replacingOccurrences(of: ".", with: ",") } ?? ""
            pricePrompt = PricePrompt(itemID: item.id, name: item.pricedProduct.name, quote: quote)
        }
    }

    private var promptValue: Double? {
        let value = Double(promptAmount.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
        guard let value, value > 0, value < 10_000 else { return nil }
        return value
    }

    /// Déplier un article lance la recherche de ses produits précis.
    private func expansion(for item: ShoppingItem) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(item.id) },
            set: { open in
                if open {
                    expanded.insert(item.id)
                    let query = item.product.name
                    Task { await model.loadSuggestions(for: query) }
                } else {
                    expanded.remove(item.id)
                }
            }
        )
    }

    /// Change quand la liste de produits ou la zone change : relance la comparaison.
    private var listKey: String {
        model.state.shoppingList.map(\.pricedProduct.code).sorted().joined(separator: ",") + "#" + model.locationKey
    }

    // MARK: Calcul du panier

    /// Comparatif des articles qui restent à acheter (les articles cochés sont déjà payés, et comptés au budget).
    private var basket: BasketResult {
        let items = model.state.shoppingList.filter { !$0.checked }
        let reference = model.referenceLocation
        let radius = model.radiusMeters
        let currency = model.settings.currency
        let country = model.country
        let codes = Set(items.map(\.pricedProduct.code))

        var localByCode = local.mapValues { list in list.filter { $0.currency == currency } }
        let mine = PriceEngine.observations(from: model.state.myPrices.filter { codes.contains($0.product.code) })
        for obs in mine where obs.currency == currency {
            if let distance = obs.distance(from: reference), distance > radius { continue }
            localByCode[obs.productCode, default: []].append(obs)
        }

        var estimatesByCode: [String: [ChainEstimate]] = [:]
        for (code, list) in national {
            estimatesByCode[code] = ChainStats.estimates(from: PriceEngine.filter(list, country: country, currency: currency),
                                                         near: reference)
        }

        return PriceEngine.basket(items: items,
                                  localByCode: localByCode,
                                  estimatesByCode: estimatesByCode,
                                  candidates: candidateStores(localByCode: localByCode))
    }

    /// Magasins comparés : ceux qui ont de vrais relevés, le plus proche de chaque enseigne et les favoris.
    private func candidateStores(localByCode: [String: [PriceObservation]]) -> [Store] {
        let storesByID = Dictionary(model.stores.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: Store] = [:]
        for list in localByCode.values {
            for obs in list {
                guard result[obs.storeKey] == nil else { continue }
                if let store = storesByID[obs.storeKey] ?? obs.store {
                    result[store.id] = store
                }
            }
        }
        for store in model.nearestStoreByChain.values where result[store.id] == nil {
            result[store.id] = store
        }
        for store in model.state.settings.favoriteStores where result[store.id] == nil {
            result[store.id] = store
        }
        var list = Array(result.values)
        let favorites = model.state.settings.favoriteStores
        if model.state.settings.favoritesOnly && !favorites.isEmpty {
            let ids = Set(favorites.map(\.id))
            list = list.filter { ids.contains($0.id) }
        }
        return list
    }

    // MARK: Vue

    var body: some View {
        @Bindable var bindable = model
        NavigationStack(path: $path) {
            List {
                quickAddSection
                budgetSection
                recallSection
                if model.state.shoppingList.isEmpty {
                    ContentUnavailableView {
                        Label("Votre liste est vide", systemImage: "cart")
                    } description: {
                        Text("Tapez un produit ci-dessus, ou ajoutez-le depuis l'onglet Produits (bouton « Ajouter à ma liste »). Lemwincher vous dira où faire vos courses pour payer le moins cher.")
                    } actions: {
                        Button("Produit sans code-barres") { showCustomAlert = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Section {
                        ForEach($bindable.state.shoppingList) { $item in
                            DisclosureGroup(isExpanded: expansion(for: item)) {
                                ProductChoicesView(item: item,
                                                   onOpen: { product in path.append(product) },
                                                   onCapture: { query in captureRequest = CaptureRequest(query: query) })
                            } label: {
                                ShoppingRow(item: $item, onToggle: { toggle(item) })
                            }
                            // Glisser la ligne vers la droite : acheté (dépense) / pas acheté.
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    toggle(item)
                                } label: {
                                    if item.checked {
                                        Label("Pas acheté", systemImage: "arrow.uturn.backward")
                                    } else {
                                        Label("Acheté", systemImage: "checkmark")
                                    }
                                }
                                .tint(item.checked ? Color.gray : Color.brand)
                            }
                            // Pas d'identifiant ici : il écraserait ceux des boutons à l'intérieur (cases, produits, site).
                        }
                        .onDelete { offsets in
                            bindable.state.shoppingList.remove(atOffsets: offsets)
                        }
                    } header: {
                        Text("Produits (\(model.state.shoppingList.count))")
                    } footer: {
                        Text("Touchez un article pour voir les produits correspondants et leur prix, puis choisissez celui que vous achetez. Une fois acheté, cochez-le (ou glissez-le vers la droite) : son prix s'ajoute à vos dépenses du mois.")
                    }
                    if !model.state.settings.favoriteStores.isEmpty {
                        Section {
                            Toggle(isOn: $bindable.state.settings.favoritesOnly) {
                                Label("Seulement mes magasins (\(model.state.settings.favoriteStores.count))",
                                      systemImage: "star")
                            }
                        }
                    }
                    basketSections
                }
            }
            .navigationTitle("Ma liste")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !model.state.shoppingList.isEmpty {
                        ShareLink(item: model.shoppingListText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showShoppingDone = true
                        } label: {
                            Label("J'ai fait mes courses…", systemImage: "eurosign.circle")
                        }
                        Button {
                            showCustomAlert = true
                        } label: {
                            Label("Produit sans code-barres", systemImage: "text.badge.plus")
                        }
                        Button(role: .destructive) {
                            model.state.shoppingList.removeAll(where: \.checked)
                        } label: {
                            Label("Retirer les produits cochés", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) {
                            model.state.shoppingList.removeAll()
                        } label: {
                            Label("Vider la liste", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Produit sans code-barres", isPresented: $showCustomAlert) {
                TextField("Ex. : Riz parfumé 5 kg", text: $customName)
                Button("Ajouter") { addCustomProduct() }
                Button("Annuler", role: .cancel) { customName = "" }
            } message: {
                Text("Fruits, légumes, vrac… Utilisez le même nom quand vous relevez son prix dans « Mes prix ».")
            }
            .sheet(isPresented: $showShoppingDone) {
                shoppingDoneEditor
            }
            .alert("Combien l'avez-vous payé ?",
                   isPresented: Binding(get: { pricePrompt != nil }, set: { if !$0 { pricePrompt = nil } }),
                   presenting: pricePrompt) { prompt in
                TextField("Ex. : 2,29", text: $promptAmount)
                    .keyboardType(.decimalPad)
                Button("Ajouter au budget") {
                    model.checkListItem(prompt.itemID, amount: promptValue,
                                        storeName: prompt.quote.storeName, store: prompt.quote.store)
                }
                Button("Cocher sans dépense") {
                    model.checkListItem(prompt.itemID, amount: nil, storeName: nil, store: nil)
                }
                Button("Annuler", role: .cancel) {}
            } message: { prompt in
                Text("Prix de « \(prompt.name) »\(prompt.quote.storeName.map { " chez \($0)" } ?? "") inconnu : indiquez le montant payé, il s'ajoute à vos dépenses du mois.")
            }
            .sheet(item: $captureRequest) { request in
                // Le site de l'enseigne la plus proche s'ouvre directement sur le produit.
                DriveCaptureView(query: request.query,
                                 preferredChain: DriveSite.nearest(in: model.storesByDistance())?.chainPrefix)
            }
            .task(id: listKey) {
                await model.checkRecalls(for: model.state.shoppingList.map(\.pricedProduct.code))
                await loadPrices()
                await model.enrichProducts()
            }
            .refreshable { await loadPrices() }
            .appDestinations()
        }
    }

    // MARK: Budget

    /// Budget restant du mois, et ce que coûterait la liste au meilleur magasin.
    @ViewBuilder
    private var budgetSection: some View {
        let summary = model.budgetSummary
        let currency = model.settings.currency
        let best = model.state.shoppingList.isEmpty ? nil : basket.stores.first
        Section {
            Button {
                model.selectedTab = .budget
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "eurosign.circle.fill")
                        .font(.title2)
                        .foregroundStyle(summary.status == .ok ? Color.brand : (summary.status == .warning ? Color.orange : Color.red))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.remaining >= 0
                             ? "Budget : il reste \(Fmt.price(summary.remaining, currency)) ce mois-ci"
                             : "Budget dépassé de \(Fmt.price(-summary.remaining, currency))")
                            .font(.subheadline.weight(.semibold))
                        if let best {
                            Text(basketBudgetText(best: best, remaining: summary.remaining, currency: currency))
                                .font(.caption)
                                .foregroundStyle(best.total <= summary.remaining ? Color.secondary : Color.orange)
                        } else {
                            Text("\(Fmt.price(summary.dailyAllowance, currency)) par jour jusqu'à la fin du mois")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listBudget")
        }
    }

    private func basketBudgetText(best: StoreBasket, remaining: Double, currency: String) -> String {
        let total = Fmt.price(best.total, currency)
        if best.total <= remaining {
            return "Ce panier (\(total) chez \(best.storeName)) rentre dans votre budget."
        }
        return "Ce panier (\(total) chez \(best.storeName)) dépasse le budget restant de \(Fmt.price(best.total - remaining, currency))."
    }

    /// « J'ai fait mes courses » : dépense pré-remplie avec le meilleur magasin et le total
    /// des articles pas encore cochés (les cochés sont déjà dans le budget).
    private var shoppingDoneEditor: some View {
        let best = basket.stores.first
        let remaining = model.state.shoppingList.filter { !$0.checked }.count
        let prefill = Expense(amount: ((best?.total ?? 0) * 100).rounded() / 100,
                              date: Date(),
                              storeName: best?.store?.name ?? best?.storeName,
                              storeID: best?.store?.id,
                              chainKey: best?.store?.chainKey,
                              category: .groceries,
                              note: "Liste de courses",
                              itemCount: remaining)
        return ExpenseEditor(expense: nil, prefill: prefill, clearOptionLabel: "Vider la liste de courses") {
            model.state.shoppingList.removeAll()
        }
    }

    // MARK: Ajout rapide

    private var quickAddSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.brand)
                TextField("Ajouter un produit (ex. : lait, 3017620422003…)", text: $quickAdd)
                    .submitLabel(.done)
                    .onSubmit(addQuickItem)
                    .accessibilityIdentifier("quickAddField")
            }
            ForEach(quickSuggestions) { product in
                Button {
                    quickAdd = ""
                    model.addToList(product)
                } label: {
                    ProductRow(product: product, subtitle: "Déjà consulté : touchez pour l'ajouter")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Produits déjà consultés ou relevés dont le nom correspond à la saisie.
    private var quickSuggestions: [Product] {
        let q = quickAdd.trimmed
        guard q.count >= 2 else { return [] }
        var seen = Set<String>()
        var found: [Product] = []
        for product in model.state.recentProducts + model.state.myPrices.map(\.product)
        where !seen.contains(product.code) && !model.isInList(product) && product.name.localizedCaseInsensitiveContains(q) {
            seen.insert(product.code)
            found.append(product)
        }
        return Array(found.prefix(3))
    }

    private func addQuickItem() {
        let text = quickAdd.trimmed
        quickAdd = ""
        guard !text.isEmpty else { return }
        guard text.isBarcodeLike else {
            model.addToList(.custom(named: text))
            return
        }
        model.addToList(Product(code: text, name: text))
        // Nom, marque et photo du produit à partir du code-barres.
        Task {
            if let found = await ProductLookup.lookup(code: text) {
                model.updateListProduct(found)
            }
        }
    }

    // MARK: Rappels

    private struct RecalledItem: Identifiable {
        let item: ShoppingItem
        let recall: Recall
        var id: UUID { item.id }
    }

    @ViewBuilder
    private var recallSection: some View {
        let recalled = model.state.shoppingList.compactMap { item -> RecalledItem? in
            guard let recall = model.recall(for: item.pricedProduct.code) else { return nil }
            return RecalledItem(item: item, recall: recall)
        }
        if !recalled.isEmpty {
            Section {
                ForEach(recalled) { entry in
                    RecallBanner(recall: entry.recall, productName: entry.item.product.name)
                }
            } header: {
                Text("Attention : produit rappelé")
            }
        }
    }

    // MARK: Comparatif du panier

    @ViewBuilder
    private var basketSections: some View {
        let result = basket
        let itemCount = model.state.shoppingList.count
        let currency = model.settings.currency
        let reference = model.referenceLocation

        if loading && result.stores.isEmpty {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Comparaison des prix autour de vous…").foregroundStyle(.secondary)
                }
            }
        }

        if !result.stores.isEmpty {
            Section {
                ForEach(Array(result.stores.prefix(8).enumerated()), id: \.element.id) { index, storeBasket in
                    let row = StoreBasketRow(basket: storeBasket,
                                             itemCount: itemCount,
                                             currency: currency,
                                             best: index == 0,
                                             distance: storeBasket.store?.distance(from: reference),
                                             favorite: model.state.settings.favoriteStores.contains { $0.id == storeBasket.storeKey })
                    if let store = storeBasket.store {
                        NavigationLink(value: store) { row }
                    } else {
                        row
                    }
                }
            } header: {
                Text("Où faire mes courses ?")
            } footer: {
                Text("Uniquement des prix réellement relevés : dans le magasin lui-même quand il existe, sinon dans le magasin de la même enseigne le plus proche (indiqué « autre magasin »). Classement : d'abord le nombre de produits trouvés, puis le total.")
            }
        }

        if result.bestSplitStoreCount > 1 {
            Section {
                ForEach(result.bestSplit) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.item.quantity > 1 ? "\(line.item.quantity) × \(line.item.pricedProduct.name)" : line.item.pricedProduct.name)
                                .lineLimit(1)
                            Text(line.storeName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.price(line.subtotal, line.currency)).monospacedDigit()
                    }
                }
                HStack {
                    Text("Total").bold()
                    Spacer()
                    Text(Fmt.price(result.bestSplitTotal, currency)).bold().monospacedDigit()
                }
            } header: {
                Text("Le moins cher en combinant \(result.bestSplitStoreCount) magasins")
            } footer: {
                Text("Uniquement avec des prix réellement relevés autour de vous.")
            }
        }

        if !result.unknown.isEmpty && !loading {
            Section {
                ForEach(result.unknown) { item in
                    Text(item.product.name).foregroundStyle(.secondary)
                }
            } header: {
                Text("Sans prix connu")
            } footer: {
                Text("Relevez leur prix lors de vos prochaines courses (Budget › + › Relever un prix) pour les inclure dans la comparaison.")
            }
        }
    }

    // MARK: Actions

    private func addCustomProduct() {
        let name = customName.trimmed
        customName = ""
        guard !name.isEmpty else { return }
        model.addToList(.custom(named: name))
    }

    private func loadPrices() async {
        let codes = Array(Set(model.state.shoppingList.map(\.pricedProduct.code).filter { !$0.hasPrefix("custom:") }))
        guard !codes.isEmpty else {
            local = [:]
            national = [:]
            return
        }
        let lat = model.referenceLocation?.coordinate.latitude
        let lon = model.referenceLocation?.coordinate.longitude
        let radiusKm = model.settings.radiusKm

        loading = true
        let results = await withTaskGroup(of: (String, [PriceObservation], [PriceObservation]).self,
                                          returning: [(String, [PriceObservation], [PriceObservation])].self) { group in
            for code in codes {
                group.addTask {
                    var localObservations: [PriceObservation] = []
                    if let lat, let lon {
                        let prices = (try? await OpenPricesAPI.pricesNear(productCode: code, lat: lat, lon: lon, radiusKm: radiusKm)) ?? []
                        localObservations = PriceEngine.observations(from: prices)
                    }
                    let nationalPrices = (try? await OpenPricesAPI.nationalPrices(productCode: code)) ?? []
                    return (code, localObservations, PriceEngine.observations(from: nationalPrices))
                }
            }
            var collected: [(String, [PriceObservation], [PriceObservation])] = []
            for await entry in group {
                collected.append(entry)
            }
            return collected
        }
        if Task.isCancelled {
            loading = false
            return
        }
        var newLocal: [String: [PriceObservation]] = [:]
        var newNational: [String: [PriceObservation]] = [:]
        for (code, localObservations, nationalObservations) in results {
            newLocal[code] = localObservations
            newNational[code] = nationalObservations
        }
        local = newLocal
        national = newNational
        loading = false
    }
}

// MARK: - Lignes

struct ShoppingRow: View {
    @Environment(AppModel.self) private var model
    @Binding var item: ShoppingItem
    /// Cocher / décocher (acheté : dépense ajoutée au budget).
    var onToggle: (() -> Void)? = nil

    /// Retrait des lignes de détail : sous le nom (case 26 + 12 + vignette 36 + 12).
    private let detailIndent: CGFloat = 86

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button {
                    if let onToggle { onToggle() } else { item.checked.toggle() }
                } label: {
                    Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(item.checked ? Color.brand : Color.secondary)
                        .frame(width: 26)
                }
                // « borderless » : dans une ligne de liste dépliable, le bouton garde son propre toucher.
                .buttonStyle(.borderless)
                .accessibilityLabel(item.checked ? "Acheté (décocher)" : "Cocher : acheté")
                .accessibilityIdentifier("checkItem")

                ProductThumb(url: item.choice?.imageURL ?? item.product.imageURL, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.product.name)
                        .strikethrough(item.checked)
                        .foregroundStyle(item.checked ? Color.secondary : Color.primary)
                        .lineLimit(2)
                    if item.choice == nil, let brand = item.product.brand {
                        Text(brand).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                QuantityControl(quantity: $item.quantity)
                    .onChange(of: item.quantity) { old, new in
                        model.rescaleListExpense(itemID: item.id, from: old, to: new)
                    }
            }
            // Détails sur toute la largeur, sous le nom : le produit choisi et la dépense.
            if let choice = item.choice {
                Label(Fmt.join(choice.name, choice.brand, choice.quantity), systemImage: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(Color.brand)
                    .lineLimit(2)
                    .padding(.leading, detailIndent)
            }
            if item.checked, let expense = model.listExpense(for: item) {
                Label(Fmt.join(Fmt.price(expense.amount, model.settings.currency) + " dépensés", expense.storeName),
                      systemImage: "eurosign.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, detailIndent)
                    .accessibilityIdentifier("itemExpense")
            }
        }
    }
}

// MARK: - Produits précis sous un article

/// Sous un article ("Œufs") : les produits correspondants avec leur meilleur prix, à choisir.
struct ProductChoicesView: View {
    @Environment(AppModel.self) private var model
    let item: ShoppingItem
    /// Ouvre le comparatif d'un produit.
    let onOpen: (Product) -> Void
    /// Ouvre le site d'une enseigne sur ce produit (pour capturer ses prix).
    var onCapture: ((String) -> Void)? = nil

    /// Ce qu'on cherche : le nom noté par l'utilisateur.
    private var query: String { item.product.name }

    var body: some View {
        let results = model.suggestionResults(for: query)
        let items = SuggestionEngine.merge(personal: model.personalSuggestions(for: query), remote: results.items)
            .filter { model.dietAllows($0.product) }
        Group {
            if let choice = item.choice {
                Button {
                    model.choose(nil, for: item.id)
                } label: {
                    Label("Ne plus choisir « \(choice.name) »", systemImage: "xmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
            // Toujours au moins une ligne tant que rien n'est chargé (une zone vide ne se chargerait jamais).
            if !results.loaded && results.items.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche des produits et de leurs prix…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .task(id: query) { await model.loadSuggestions(for: query) }
            }
            if results.pricesUnavailable && !results.loading {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(Color.orange)
                    Text("Prix momentanément indisponibles (Open Prices ne répond pas).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Réessayer") {
                        Task { await model.loadSuggestions(for: query) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if results.loaded && items.isEmpty && !results.pricesUnavailable {
                Text("Aucun produit trouvé pour « \(query) ».")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { suggestion in
                SuggestionRow(suggestion: suggestion,
                              chosen: item.choice?.code == suggestion.product.code,
                              onChoose: {
                                  let same = item.choice?.code == suggestion.product.code
                                  model.choose(same ? nil : suggestion.product, for: item.id)
                              },
                              onOpen: { onOpen(suggestion.product) })
            }
            if results.hasMore {
                Button {
                    Task { await model.loadSuggestions(for: query, more: true) }
                } label: {
                    HStack {
                        Label("Plus de produits", systemImage: "plus.magnifyingglass")
                        if results.loading {
                            Spacer()
                            ProgressView()
                        }
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .disabled(results.loading)
                .accessibilityIdentifier("moreSuggestions")
            }
            if let onCapture, results.loaded {
                Button {
                    onCapture(query)
                } label: {
                    Label("Prix du jour sur le site d'une enseigne (Aldi, Leclerc…)", systemImage: "safari")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("captureFromSite")
            }
        }
    }
}

/// Un produit précis : photo, nom, contenance, meilleur prix ; toucher = le choisir, (i) = comparatif.
struct SuggestionRow: View {
    let suggestion: ProductSuggestion
    let chosen: Bool
    let onChoose: () -> Void
    let onOpen: () -> Void

    /// Où et quand ce prix a été relevé : "Lidl Minimes · 1,2 km · 12 nov." / "relevé chez E.Leclerc Rouen · hier".
    private var placeText: String? {
        guard let offer = suggestion.offer else { return nil }
        let distance: String? = offer.distance.flatMap { $0 < 100_000 ? Fmt.distance($0) : nil }
        let place = offer.isLocal ? offer.storeName : "relevé chez \(offer.storeName)"
        return Fmt.join(place, distance, offer.source, Fmt.day(offer.date), Fmt.isOld(offer.date) ? "ancien relevé" : nil)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onChoose) {
                HStack(spacing: 10) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(chosen ? Color.brand : Color.secondary)
                    ProductThumb(url: suggestion.product.imageURL, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.product.name)
                            .font(.subheadline)
                            .lineLimit(2)
                        Text(Fmt.join(suggestion.product.brand, suggestion.product.quantity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let placeText {
                            // Deux lignes : le magasin ET la date du relevé doivent rester visibles.
                            Text(placeText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Le prix garde toujours sa largeur ; c'est le nom qui se raccourcit.
                    priceView
                        .fixedSize()
                        .layoutPriority(2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(Color.primary)
            .accessibilityIdentifier("suggestion")

            Button(action: onOpen) {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Comparer les prix de ce produit")
        }
    }

    @ViewBuilder
    private var priceView: some View {
        if let offer = suggestion.offer {
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.price(offer.price, offer.currency))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(offer.isLocal ? Color.brand : Color.primary)
                if let unit = suggestion.product.normalizedAmount {
                    Text(unit.unitPriceText(offer.price, currency: offer.currency))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let grade = suggestion.nutriScore {
            NutriMiniBadge(grade: grade)
        } else {
            Text("prix non relevé")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Petit sélecteur de quantité − 2 + (plus compact qu'un Stepper).
struct QuantityControl: View {
    @Binding var quantity: Int

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if quantity > 1 { quantity -= 1 }
            } label: {
                Image(systemName: "minus").frame(width: 28, height: 28)
            }
            .disabled(quantity <= 1)
            .accessibilityLabel("Moins")

            Text("\(quantity)")
                .monospacedDigit()
                .frame(minWidth: 20)

            Button {
                if quantity < 99 { quantity += 1 }
            } label: {
                Image(systemName: "plus").frame(width: 28, height: 28)
            }
            .accessibilityLabel("Plus")
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.borderless)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

struct StoreBasketRow: View {
    let basket: StoreBasket
    let itemCount: Int
    let currency: String
    let best: Bool
    let distance: Double?
    var favorite: Bool = false

    private var summary: String {
        let estimates = basket.estimateCount
        let estimateText: String? = estimates > 0
            ? "\(estimates) prix d'un autre magasin \(basket.store?.chainName ?? "de l'enseigne")"
            : nil
        let distanceText: String? = distance.map { Fmt.distance($0) }
        return Fmt.join("\(basket.lines.count)/\(itemCount) produits", estimateText, distanceText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(basket.storeName).font(.headline).lineLimit(1)
                        if favorite {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.yellow)
                        }
                        if best {
                            Text("Meilleur choix")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.brand, in: Capsule())
                                .foregroundStyle(Color.white)
                        }
                    }
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(Fmt.price(basket.total, currency))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(best ? Color.brand : Color.primary)
            }
            if !basket.missing.isEmpty {
                Text("Prix inconnu ici : " + basket.missing.map(\.product.name).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
