import SwiftUI

/// « -24 % » sur fond rouge, ou « PROMO » quand le prix habituel n'est pas connu.
struct DiscountBadge: View {
    let percent: Int?

    var body: some View {
        Text(percent.map { "-\($0) %" } ?? "PROMO")
            .font(.caption.weight(.heavy).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.red.gradient, in: Capsule())
            .fixedSize()
    }
}

/// Prix promo, et prix habituel barré quand il est connu.
struct PromoPriceView: View {
    let deal: PromoDeal
    var large = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Fmt.price(deal.price, deal.currency))
                .font((large ? Font.title3 : Font.headline).bold().monospacedDigit())
                .foregroundStyle(.red)
            if let regular = deal.regularPrice, regular > deal.price + 0.005 {
                Text(Fmt.price(regular, deal.currency))
                    .font(.caption.monospacedDigit())
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Carte d'une promo dans le carrousel de l'accueil.
struct PromoCard: View {
    let deal: PromoDeal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ProductThumb(url: deal.product.imageURL, size: 86, name: deal.product.name)
                    .frame(maxWidth: .infinity)
                DiscountBadge(percent: deal.discountPercent)
            }
            Text(deal.product.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            PromoPriceView(deal: deal)
            Text(Fmt.join(deal.storeName, deal.distance.map { Fmt.distance($0) }))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 158, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Ligne d'une promo dans la liste complète.
struct PromoRow: View {
    let deal: PromoDeal
    var showStore = true

    private var sourceText: String {
        Fmt.join(deal.isMine ? "Votre relevé" : "Open Prices", Fmt.day(deal.date))
    }

    var body: some View {
        HStack(spacing: 12) {
            ProductThumb(url: deal.product.imageURL, size: 52, name: deal.product.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(deal.product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                let details = Fmt.join(deal.product.brand, deal.product.quantity)
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if showStore {
                    Label(Fmt.join(deal.storeName, deal.distance.map { Fmt.distance($0) }), systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(sourceText).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                DiscountBadge(percent: deal.discountPercent)
                PromoPriceView(deal: deal)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Toutes les promos relevées autour de soi, par magasin ou par remise.
struct PromotionsView: View {
    enum Order: String, CaseIterable, Identifiable {
        case byStore = "Par magasin"
        case byDiscount = "Meilleures remises"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var order: Order = .byStore

    private var deals: [PromoDeal] {
        let all = model.promoDeals
        let text = query.trimmed
        guard !text.isEmpty else { return all }
        let needle = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        return all.filter { deal in
            [deal.product.name, deal.product.brand ?? "", deal.storeName]
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
                .contains(needle)
        }
    }

    private struct StoreGroup: Identifiable {
        let id: String
        let name: String
        let distance: Double?
        let deals: [PromoDeal]
    }

    /// Magasins du plus proche au plus loin, chacun avec ses promos (plus fortes remises d'abord).
    private func groups(_ deals: [PromoDeal]) -> [StoreGroup] {
        Dictionary(grouping: deals) { $0.observation.storeKey }
            .map { key, list in StoreGroup(id: key, name: list[0].storeName, distance: list[0].distance, deals: list) }
            .sorted { a, b in
                let da = a.distance ?? .infinity, db = b.distance ?? .infinity
                return da != db ? da < db : a.name < b.name
            }
    }

    var body: some View {
        let deals = deals
        List {
            Section {
                Picker("Ordre", selection: $order) {
                    ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .clearListRow(top: 0, bottom: 0)
            }

            if deals.isEmpty {
                Section {
                    if model.promosLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Recherche des promos…").foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView(query.trimmed.isEmpty ? "Aucune promo autour de vous" : "Aucune promo trouvée",
                                               systemImage: "tag.slash",
                                               description: Text(query.trimmed.isEmpty
                                                   ? "Les promos lues sur les sites des enseignes et celles relevées par la communauté ces 14 derniers jours s'affichent ici."
                                                   : "Essayez un autre produit, une marque ou un magasin."))
                    }
                }
            } else if order == .byDiscount {
                Section {
                    ForEach(deals) { deal in row(deal, showStore: true) }
                } header: {
                    Text("\(deals.count) promos")
                }
            } else {
                ForEach(groups(deals)) { group in
                    Section {
                        ForEach(group.deals) { deal in row(deal, showStore: false) }
                    } header: {
                        Text(Fmt.join(group.name, group.distance.map { Fmt.distance($0) }))
                    }
                }
            }

            Section {
            } footer: {
                Text("Promos des 14 derniers jours à moins de \(Int(model.settings.radiusKm)) km : celles lues sur les sites des enseignes (vos rayons suivis, vos relevés) et celles partagées sur Open Prices. Le prix barré vient du site, sinon du dernier prix normal relevé dans le même magasin.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Promos")
        .searchable(text: $query, prompt: "Produit, marque ou magasin")
        .refreshable { await model.refreshPromos(force: true) }
        .task { await model.refreshPromos() }
    }

    private func row(_ deal: PromoDeal, showStore: Bool) -> some View {
        NavigationLink(value: deal.product) {
            PromoRow(deal: deal, showStore: showStore)
        }
        .swipeActions(edge: .trailing) {
            Button {
                model.addToList(deal.product)
            } label: {
                Label("Ma liste", systemImage: "cart.badge.plus")
            }
            .tint(Color.brand)
        }
        .accessibilityIdentifier("promoRow")
    }
}
