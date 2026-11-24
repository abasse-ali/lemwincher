import Foundation

/// Rayon (ou recherche) d'un site d'enseigne gardé en mémoire : ses produits et leurs prix
/// sont relus automatiquement à l'ouverture de l'app.
struct TrackedPage: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Adresse de la page lue (rayon, recherche, page du magasin).
    var url: String
    /// Titre de la page (« Crèmes et beurres à petits prix - ALDI »).
    var title: String
    var siteName: String
    /// Magasin auquel les prix sont rattachés.
    var store: Store
    /// Produits lus sur cette page (codes-barres ou codes « custom: »).
    var productCodes: [String] = []
    var lastChecked: Date
    var autoUpdate: Bool = true
    /// Résultat de la dernière mise à jour.
    var lastChanges: Int = 0
    var lastError: String? = nil

    /// Nom d'un rayon : « Recherche « œufs » » pour une recherche (le titre du site dit juste « Recherche »),
    /// sinon le titre de la page.
    static func displayTitle(pageTitle: String?, url: URL, siteName: String) -> String {
        let searchKeys: Set<String> = ["q", "query", "text", "s", "search", "keyword"]
        var query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { searchKeys.contains($0.name.lowercased()) }?.value
        if query == nil, url.pathComponents.contains(where: { ["search", "recherche"].contains($0.lowercased()) }),
           let last = url.pathComponents.last, !["search", "recherche"].contains(last.lowercased()) {
            query = last.removingPercentEncoding ?? last
        }
        if let query = query?.trimmed.nilIfBlank {
            return "Recherche « \(query) »"
        }
        return pageTitle?.trimmed.nilIfBlank ?? siteName
    }

    /// Une mise à jour automatique est due (12 h depuis la dernière lecture).
    func isDue(now: Date = Date(), every interval: TimeInterval = 12 * 3600) -> Bool {
        autoUpdate && now.timeIntervalSince(lastChecked) >= interval
    }

    /// « Crèmes et beurres » plutôt que « Crèmes et beurres à petits prix - ALDI ».
    var shortTitle: String {
        let first = title.components(separatedBy: CharacterSet(charactersIn: "|–—")).first ?? title
        let cleaned = first.replacingOccurrences(of: " - " + siteName, with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " à petits prix", with: "", options: .caseInsensitive)
            .trimmed
        return cleaned.isEmpty ? siteName : cleaned
    }
}

extension TrackedPage {
    private enum CodingKeys: String, CodingKey {
        case id, url, title, siteName, store, productCodes, lastChecked, autoUpdate, lastChanges, lastError
    }

    // Décodage tolérant, comme le reste des données sauvegardées.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        url = try c.decode(String.self, forKey: .url)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        siteName = (try? c.decode(String.self, forKey: .siteName)) ?? ""
        store = try c.decode(Store.self, forKey: .store)
        productCodes = (try? c.decode([String].self, forKey: .productCodes)) ?? []
        lastChecked = (try? c.decode(Date.self, forKey: .lastChecked)) ?? .distantPast
        autoUpdate = (try? c.decode(Bool.self, forKey: .autoUpdate)) ?? true
        lastChanges = (try? c.decode(Int.self, forKey: .lastChanges)) ?? 0
        lastError = try? c.decode(String.self, forKey: .lastError)
    }
}

/// Produit d'un rayon suivi : son dernier prix et le précédent (pour ↓ ↑).
struct TrackedProduct: Identifiable {
    let latest: MyPrice
    let previous: MyPrice?

    var id: UUID { latest.id }
}

/// Ce qu'une lecture a changé pour un produit.
struct PriceUpdate: Hashable {
    enum Kind: Hashable {
        /// Produit vu pour la première fois dans ce magasin.
        case new
        /// Même prix qu'avant (relevé simplement daté du jour).
        case unchanged
        /// Prix différent : `previous` est l'ancien prix.
        case changed(previous: Double)
    }

    let product: Product
    let price: Double
    let kind: Kind

    var isDrop: Bool {
        if case .changed(let previous) = kind { return price < previous - 0.004 }
        return false
    }

    var isRise: Bool {
        if case .changed(let previous) = kind { return price > previous + 0.004 }
        return false
    }
}

enum CaptureUpdater {
    /// Ajoute les prix lus à « Mes prix » sans doublons : un prix inchangé est daté du jour,
    /// un prix différent (ou une promo qui commence / finit) devient un nouveau relevé.
    static func apply(_ items: [CapturedPrice], to prices: [MyPrice], store: Store, currency: String,
                      source: String, now: Date = Date()) -> (prices: [MyPrice], updates: [PriceUpdate]) {
        var result = prices
        var updates: [PriceUpdate] = []
        for item in items where item.include {
            let product = item.product
            let latestIndex = result.indices
                .filter { result[$0].product.code == product.code && result[$0].store.id == store.id && result[$0].currency == currency }
                .max { result[$0].date < result[$1].date }
            if let index = latestIndex {
                let latest = result[index]
                if abs(latest.price - item.price) < 0.005 && latest.isDiscounted == item.promo {
                    result[index].date = now
                    result[index].source = source
                    // Photo, marque ou contenance apparues depuis : on les garde.
                    if result[index].product.imageURL == nil { result[index].product.imageURL = product.imageURL }
                    if item.promo { result[index].oldPrice = item.oldPrice ?? result[index].oldPrice }
                    updates.append(PriceUpdate(product: product, price: item.price, kind: .unchanged))
                    continue
                }
                updates.append(PriceUpdate(product: product, price: item.price, kind: .changed(previous: latest.price)))
            } else {
                updates.append(PriceUpdate(product: product, price: item.price, kind: .new))
            }
            var entry = MyPrice(product: product, store: store, price: item.price, currency: currency, date: now)
            entry.source = source
            entry.isDiscounted = item.promo
            entry.oldPrice = item.promo ? item.oldPrice : nil
            result.append(entry)
        }
        return (result, updates)
    }

    /// « 3 nouveaux, 2 baisses, 20 inchangés » (journal de l'app).
    static func changesText(_ updates: [PriceUpdate]) -> String {
        func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
            "\(count) \(count > 1 ? plural : singular)"
        }
        let new = updates.filter { $0.kind == .new }.count
        let drops = updates.filter(\.isDrop).count
        let rises = updates.filter(\.isRise).count
        let unchanged = updates.filter { $0.kind == .unchanged }.count
        let promos = updates.count - new - drops - rises - unchanged
        var parts: [String] = []
        if new > 0 { parts.append(plural(new, "nouveau", "nouveaux")) }
        if drops > 0 { parts.append(plural(drops, "baisse", "baisses")) }
        if rises > 0 { parts.append(plural(rises, "hausse", "hausses")) }
        if promos > 0 { parts.append(plural(promos, "promo changée", "promos changées")) }
        if unchanged > 0 { parts.append(plural(unchanged, "inchangé", "inchangés")) }
        return parts.isEmpty ? "aucun prix" : parts.joined(separator: ", ")
    }

    /// « 2 baisses : Beurre doux 2,19 € (au lieu de 2,35 €)… » pour la notification.
    static func dropsSummary(_ updates: [PriceUpdate], currency: String, storeName: String) -> String? {
        let drops = updates.filter(\.isDrop)
        guard !drops.isEmpty else { return nil }
        let details = drops.prefix(3).compactMap { update -> String? in
            guard case .changed(let previous) = update.kind else { return nil }
            return "\(update.product.name) \(Fmt.price(update.price, currency)) (au lieu de \(Fmt.price(previous, currency)))"
        }
        let head = drops.count == 1 ? "Baisse de prix chez \(storeName) : " : "\(drops.count) baisses de prix chez \(storeName) : "
        return head + details.joined(separator: " ; ") + (drops.count > 3 ? "…" : "")
    }
}
