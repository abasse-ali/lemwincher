import Foundation
import CoreLocation

/// Un prix observé dans un magasin, qu'il vienne d'Open Prices (communauté) ou de l'utilisateur.
struct PriceObservation: Identifiable, Hashable {
    enum Source: String, Hashable {
        case community
        case mine
    }

    let id: String
    let productCode: String
    let productName: String
    let brand: String?
    let quantity: String?
    let imageURL: String?
    let unitQuantity: Double?
    let unitName: String?
    let categories: [String]?
    let price: Double
    let currency: String
    let date: Date
    let isDiscounted: Bool
    let storeKey: String
    let storeName: String
    let storeAddress: String?
    let lat: Double?
    let lon: Double?
    let chainKey: String?
    let chainName: String?
    let countryCode: String?
    let source: Source

    var product: Product {
        Product(code: productCode, name: productName, brand: brand, quantity: quantity, imageURL: imageURL,
                unitQuantity: unitQuantity, unitName: unitName, categories: categories)
    }

    var store: Store? {
        guard let lat, let lon else { return nil }
        return Store(id: storeKey, name: storeName, brand: chainName, kind: nil, address: storeAddress,
                     lat: lat, lon: lon, priceCount: nil, logoURL: nil)
    }

    var unitAmount: UnitAmount? { UnitAmount(quantity: unitQuantity, unit: unitName) ?? UnitAmount.parse(quantity) }

    var unitPriceText: String? { unitAmount?.unitPriceText(price, currency: currency) }

    func distance(from reference: CLLocation?) -> CLLocationDistance? {
        guard let reference, let lat, let lon else { return nil }
        return CLLocation(latitude: lat, longitude: lon).distance(from: reference)
    }
}

// MARK: - Estimation par enseigne

/// Prix d'un produit dans une enseigne : un vrai prix relevé dans un de ses magasins (`reference`),
/// et la médiane entre magasins (utilisée seulement pour les statistiques, comme le classement).
struct ChainEstimate: Identifiable, Hashable {
    let key: String
    let name: String
    let median: Double
    let storeCount: Int
    let currency: String
    let latest: Date
    /// Vrai prix relevé (hors promo) dans le magasin de l'enseigne le plus pertinent pour l'utilisateur.
    var reference: PriceObservation? = nil

    var id: String { key }
    /// Prix affiché : le vrai prix relevé.
    var displayPrice: Double { reference?.price ?? median }
}

enum ChainStats {
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Par enseigne : un seul prix (le plus récent, hors promo) par magasin, la médiane entre magasins,
    /// et un vrai prix de référence (voir `representative`). Triées du prix affiché le plus bas au plus haut.
    static func estimates(from observations: [PriceObservation], near reference: CLLocation? = nil) -> [ChainEstimate] {
        let regular = observations.filter { !$0.isDiscounted && $0.chainKey != nil }
        let perStore = PriceEngine.latestPerStore(regular)
        var groups: [String: [PriceObservation]] = [:]
        for obs in perStore {
            guard let key = obs.chainKey else { continue }
            groups[key, default: []].append(obs)
        }
        let estimates: [ChainEstimate] = groups.compactMap { key, list in
            guard let first = list.first else { return nil }
            let name = Chain.displayName(for: key) ?? first.chainName ?? key
            let latest = list.map(\.date).max() ?? first.date
            return ChainEstimate(key: key, name: name, median: median(list.map(\.price)),
                                 storeCount: list.count, currency: first.currency, latest: latest,
                                 reference: representative(list, near: reference))
        }
        return estimates.sorted { $0.displayPrice < $1.displayPrice }
    }

    /// Le relevé le plus utile parmi les derniers prix de chaque magasin :
    /// le plus récent à moins de 30 km, sinon celui du magasin le plus proche, sinon le plus récent.
    static func representative(_ list: [PriceObservation], near reference: CLLocation?) -> PriceObservation? {
        guard !list.isEmpty else { return nil }
        if let reference {
            var withDistance: [(obs: PriceObservation, distance: Double)] = []
            for obs in list {
                if let distance = obs.distance(from: reference) { withDistance.append((obs, distance)) }
            }
            let near = withDistance.filter { $0.distance <= 30_000 }
            if let recent = near.max(by: { $0.obs.date < $1.obs.date }) { return recent.obs }
            if let nearest = withDistance.min(by: { $0.distance < $1.distance }) { return nearest.obs }
        }
        return list.max { $0.date < $1.date }
    }
}

// MARK: - Panier

struct BasketLine: Identifiable, Hashable {
    let item: ShoppingItem
    let price: Double
    let currency: String
    let isEstimate: Bool
    let storeKey: String
    let storeName: String

    var id: String { item.id.uuidString + "|" + storeKey }
    var subtotal: Double { price * Double(item.quantity) }
}

struct StoreBasket: Identifiable {
    let storeKey: String
    let storeName: String
    let store: Store?
    var lines: [BasketLine] = []
    var missing: [ShoppingItem] = []

    var id: String { storeKey }
    var total: Double { lines.reduce(0) { $0 + $1.subtotal } }
    var estimateCount: Int { lines.filter(\.isEstimate).count }
}

struct BasketResult {
    /// Magasins classés : le plus de produits trouvés d'abord, puis le total le plus bas.
    var stores: [StoreBasket] = []
    /// Pour chaque produit, le magasin où il est réellement le moins cher (relevés locaux).
    var bestSplit: [BasketLine] = []
    /// Produits sans aucun prix connu (ni local, ni estimation).
    var unknown: [ShoppingItem] = []

    var bestSplitTotal: Double { bestSplit.reduce(0) { $0 + $1.subtotal } }
    var bestSplitStoreCount: Int { Set(bestSplit.map(\.storeKey)).count }

    /// Prix d'un article qu'on vient de cocher (acheté), pour l'ajouter aux dépenses :
    /// 1. dans le magasin où l'on se trouve (s'il a un prix ; sinon prix à demander pour ce magasin) ;
    /// 2. sinon dans le meilleur magasin du panier ;
    /// 3. sinon dans le magasin où il est le moins cher.
    func purchaseQuote(for itemID: UUID, here: Store?) -> PurchaseQuote {
        func line(_ basket: StoreBasket) -> BasketLine? { basket.lines.first { $0.item.id == itemID } }
        let cheapest = stores.compactMap(line).min { $0.price < $1.price }
        if let here {
            if let basket = stores.first(where: { $0.storeKey == here.id }), let found = line(basket) {
                return PurchaseQuote(unitPrice: found.price, storeName: here.name, store: here, hint: found.price)
            }
            return PurchaseQuote(unitPrice: nil, storeName: here.name, store: here, hint: cheapest?.price)
        }
        if let best = stores.first, let found = line(best) {
            return PurchaseQuote(unitPrice: found.price, storeName: best.store?.name ?? best.storeName,
                                 store: best.store, hint: found.price)
        }
        if let cheapest, let basket = stores.first(where: { $0.storeKey == cheapest.storeKey }) {
            return PurchaseQuote(unitPrice: cheapest.price, storeName: basket.store?.name ?? basket.storeName,
                                 store: basket.store, hint: cheapest.price)
        }
        return PurchaseQuote(unitPrice: nil, storeName: nil, store: nil, hint: nil)
    }
}

/// Prix retenu pour un article coché.
struct PurchaseQuote: Equatable {
    /// Prix unitaire connu ; nil : à demander à l'utilisateur.
    let unitPrice: Double?
    let storeName: String?
    let store: Store?
    /// Prix connu ailleurs, pour pré-remplir la question.
    let hint: Double?
}

// MARK: - Produits moins chers au kilo

struct CheaperAlternative: Identifiable, Hashable {
    let obs: PriceObservation
    let unitPrice: Double
    let unit: String

    var id: String { obs.productCode }
}

// MARK: - Évolution de mes prix

/// Évolution du prix d'un produit dans un même magasin, d'après mes relevés.
struct PriceChange: Identifiable, Hashable {
    let product: Product
    let storeName: String
    let first: Double
    let last: Double
    let firstDate: Date
    let lastDate: Date
    let currency: String

    var id: String { product.code + "|" + storeName }
    var delta: Double { last - first }
    var percent: Double { first > 0 ? (last - first) / first * 100 : 0 }
}

// MARK: - Calculs

enum PriceEngine {
    /// Produits relevés au moins deux fois (jours différents) dans le même magasin,
    /// des plus fortes variations aux plus faibles. Les prix promo sont ignorés.
    static func priceChanges(_ prices: [MyPrice]) -> [PriceChange] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: prices.filter { !$0.isDiscounted }) { p in
            p.product.code + "|" + p.store.id + "|" + p.currency
        }
        let changes: [PriceChange] = groups.values.compactMap { list in
            let sorted = list.sorted { $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last,
                  !calendar.isDate(first.date, inSameDayAs: last.date) else { return nil }
            return PriceChange(product: last.product, storeName: last.store.name,
                               first: first.price, last: last.price,
                               firstDate: first.date, lastDate: last.date, currency: last.currency)
        }
        return changes.sorted { abs($0.percent) > abs($1.percent) }
    }

    static func observations(from prices: [OPPrice]) -> [PriceObservation] {
        prices.compactMap { p -> PriceObservation? in
            guard let code = p.productCode?.nilIfBlank ?? p.product?.code.nilIfBlank else { return nil }
            let loc = p.location
            let storeKey: String
            if let type = p.locationOsmType ?? loc?.osmType, let osmId = p.locationOsmId ?? loc?.osmId {
                storeKey = "\(type.uppercased()):\(osmId)"
            } else if let locationId = p.locationId ?? loc?.id {
                storeKey = "loc:\(locationId)"
            } else {
                return nil
            }
            let name = p.product?.productName?.nilIfBlank ?? p.productName?.nilIfBlank ?? code
            return PriceObservation(
                id: "op-\(p.id)",
                productCode: code,
                productName: name,
                brand: p.product?.brands?.nilIfBlank,
                quantity: p.product?.quantity?.nilIfBlank,
                imageURL: p.product?.imageUrl,
                unitQuantity: p.product?.productQuantity,
                unitName: p.product?.productQuantityUnit,
                categories: p.product?.categoriesTags,
                price: p.price,
                currency: p.currency ?? "EUR",
                date: p.date.flatMap { OpenPricesAPI.dayFormatter.date(from: $0) } ?? .distantPast,
                isDiscounted: p.priceIsDiscounted ?? false,
                storeKey: storeKey,
                storeName: loc?.osmName?.nilIfBlank ?? loc?.osmBrand?.nilIfBlank ?? "Magasin",
                storeAddress: loc?.shortAddress,
                lat: loc?.osmLat,
                lon: loc?.osmLon,
                chainKey: loc?.chainKey,
                chainName: loc?.chainName,
                countryCode: loc?.osmAddressCountryCode?.uppercased(),
                source: .community
            )
        }
    }

    static func observations(from mine: [MyPrice]) -> [PriceObservation] {
        mine.map { m in
            PriceObservation(
                id: "me-\(m.id.uuidString)",
                productCode: m.product.code,
                productName: m.product.name,
                brand: m.product.brand,
                quantity: m.product.quantity,
                imageURL: m.product.imageURL,
                unitQuantity: m.product.unitQuantity,
                unitName: m.product.unitName,
                categories: m.product.categories,
                price: m.price,
                currency: m.currency,
                date: m.date,
                isDiscounted: m.isDiscounted,
                storeKey: m.store.id,
                storeName: m.store.name,
                storeAddress: m.store.address,
                lat: m.store.lat,
                lon: m.store.lon,
                chainKey: m.store.chainKey,
                chainName: m.store.chainName,
                countryCode: nil,
                source: .mine
            )
        }
    }

    /// Garde les relevés du pays et de la devise de l'utilisateur.
    static func filter(_ observations: [PriceObservation], country: String?, currency: String) -> [PriceObservation] {
        observations.filter { obs in
            guard obs.currency == currency else { return false }
            guard let country, let obsCountry = obs.countryCode else { return true }
            return obsCountry == country
        }
    }

    /// Le prix le plus récent de chaque magasin.
    static func latestPerStore(_ observations: [PriceObservation]) -> [PriceObservation] {
        latest(observations) { $0.storeKey }
    }

    /// Le prix le plus récent de chaque produit.
    static func latestPerProduct(_ observations: [PriceObservation]) -> [PriceObservation] {
        latest(observations) { $0.productCode }
    }

    private static func latest(_ observations: [PriceObservation], key: (PriceObservation) -> String) -> [PriceObservation] {
        var best: [String: PriceObservation] = [:]
        for obs in observations {
            let k = key(obs)
            guard let current = best[k] else {
                best[k] = obs
                continue
            }
            let newer = obs.date > current.date
            let sameDayButMine = obs.date == current.date && obs.source == .mine && current.source == .community
            if newer || sameDayButMine { best[k] = obs }
        }
        return Array(best.values)
    }

    /// Compare le panier dans chaque magasin candidat.
    /// Pour chaque produit : prix réellement relevé dans le magasin, sinon estimation de son enseigne.
    static func basket(items: [ShoppingItem],
                       localByCode: [String: [PriceObservation]],
                       estimatesByCode: [String: [ChainEstimate]],
                       candidates: [Store]) -> BasketResult {
        var latestByCode: [String: [PriceObservation]] = [:]
        for (code, list) in localByCode {
            latestByCode[code] = latestPerStore(list)
        }

        var result = BasketResult()

        // Meilleure combinaison avec les vrais relevés.
        for item in items {
            if let cheapest = latestByCode[item.pricedProduct.code]?.min(by: { $0.price < $1.price }) {
                result.bestSplit.append(BasketLine(item: item, price: cheapest.price, currency: cheapest.currency,
                                                   isEstimate: false, storeKey: cheapest.storeKey,
                                                   storeName: cheapest.storeName))
            } else if (estimatesByCode[item.pricedProduct.code] ?? []).isEmpty {
                result.unknown.append(item)
            }
        }

        for store in candidates {
            var basket = StoreBasket(storeKey: store.id, storeName: store.name, store: store)
            let chain = store.chainKey
            for item in items {
                let code = item.pricedProduct.code
                if let obs = latestByCode[code]?.first(where: { $0.storeKey == store.id }) {
                    basket.lines.append(BasketLine(item: item, price: obs.price, currency: obs.currency,
                                                   isEstimate: false, storeKey: store.id, storeName: store.name))
                } else if let chain, let estimate = estimatesByCode[code]?.first(where: { $0.key == chain }) {
                    // Vrai prix relevé dans un autre magasin de la même enseigne.
                    basket.lines.append(BasketLine(item: item, price: estimate.displayPrice, currency: estimate.currency,
                                                   isEstimate: true, storeKey: store.id, storeName: store.name))
                } else {
                    basket.missing.append(item)
                }
            }
            if !basket.lines.isEmpty {
                result.stores.append(basket)
            }
        }

        result.stores.sort { a, b in
            if a.lines.count != b.lines.count { return a.lines.count > b.lines.count }
            return a.total < b.total
        }
        return result
    }

    /// Produits de la même catégorie moins chers au kilo / au litre que `reference` (prix au kilo).
    static func cheaperAlternatives(observations: [PriceObservation],
                                    excluding code: String,
                                    unit: String,
                                    below reference: Double?,
                                    limit: Int = 8) -> [CheaperAlternative] {
        var bestByProduct: [String: CheaperAlternative] = [:]
        for obs in observations where obs.productCode != code && !obs.isDiscounted {
            guard let amount = obs.unitAmount, amount.unit == unit else { continue }
            let unitPrice = amount.unitPrice(obs.price)
            guard unitPrice > 0 else { continue }
            if let current = bestByProduct[obs.productCode], current.unitPrice <= unitPrice { continue }
            bestByProduct[obs.productCode] = CheaperAlternative(obs: obs, unitPrice: unitPrice, unit: unit)
        }
        var list = Array(bestByProduct.values)
        if let reference {
            list = list.filter { $0.unitPrice < reference }
        }
        return Array(list.sorted { $0.unitPrice < $1.unitPrice }.prefix(limit))
    }
}
