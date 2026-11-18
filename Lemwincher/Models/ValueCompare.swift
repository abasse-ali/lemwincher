import Foundation

// MARK: - Contenu d'un paquet

/// Ce que contient un paquet : son poids ou son volume total (kg, L) et son nombre de pièces.
/// « 10 steaks hachés 10 x 100 g » → 10 pièces et 1 kg ; « 2 steaks hachés » → 2 pièces.
struct PackSize: Hashable {
    var amount: UnitAmount?
    var count: Int?

    /// « 10 pièces · 1 kg ».
    var text: String? {
        var parts: [String] = []
        if let count, count > 1 { parts.append("\(count) pièces") }
        if let amount { parts.append(amount.text) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func of(_ product: Product) -> PackSize {
        parse(name: product.name, quantity: product.quantity, amount: product.normalizedAmount)
    }

    /// Contenance (« 1 kg », « 6 x 1,5 L ») et nombre de pièces (« 10 steaks », « x12 », « lot de 4 »),
    /// lus dans la contenance puis dans le nom.
    static func parse(name: String, quantity: String?, amount: UnitAmount? = nil) -> PackSize {
        PackSize(amount: amount ?? UnitAmount.parse(quantity) ?? UnitAmount.parse(name),
                 count: pieceCount(in: quantity) ?? pieceCount(in: name))
    }

    private static let units = "kg|g|gr|mg|l|cl|ml|dl"

    /// Essayés dans l'ordre ; le nombre de pièces est toujours le premier groupe.
    private static let countPatterns: [NSRegularExpression] = [
        // « 10 x 100 g », « 6x1,5l », « 4 × 125 g »
        #"(\d{1,3})\s*[x×*]\s*\d+(?:[.,]\d+)?\s*(?:\#(units))\b"#,
        // « lot de 4 », « boite de 12 », « pack 6 »
        #"\b(?:lot|pack|boite|paquet|sachet|barquette|filet|carton|coffret|plateau|etui)\s+(?:de\s+)?(\d{1,3})\b(?!\s*(?:[.,]\d|(?:\#(units))\b))"#,
        // « x12 », « x 6 », « × 4 » (pas « x 100 g »)
        #"(?:^|[\s(])[x×]\s?(\d{1,3})\b(?!\s*(?:[.,]\d|(?:\#(units))\b))"#,
        // « 10 pièces », « 12 oeufs », « 4 yaourts », « 2 steaks »
        #"\b(\d{1,3})\s*(?:pieces?|pcs?|unites?|portions?|tranches?|parts?|sachets?|capsules?|dosettes?|rouleaux?|oeufs?|steaks?|yaourts?|pots?|briques?|bouteilles?|canettes?|tablettes?|barres?|crepes?|galettes?|burgers?|saucisses?|merguez|nuggets?|filets?|escalopes?|croissants?|madeleines?|biscuits?|gaufres?|cookies?|pains?|brioches?|wraps?|tortillas?|pizzas?|cuisses?|pilons?|ailes?|cordons?)\b"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// « 10 Steak haché surgelé » : un nombre en tête suivi d'un mot qui n'est pas une unité.
    private static let leadingPattern = try! NSRegularExpression(pattern: #"^\s*(\d{1,3})\s+([a-z]+)"#,
                                                                 options: [.caseInsensitive])
    private static let notPieces: Set<String> = [
        "kg", "g", "gr", "mg", "l", "cl", "ml", "dl", "x", "cm", "mm", "m", "an", "ans", "mois", "min", "h",
        "j", "jours", "degres", "pour", "de", "a", "en", "et",
    ]

    /// Nombre de pièces écrit dans un texte, ou nil.
    static func pieceCount(in text: String?) -> Int? {
        guard let raw = text?.trimmed, !raw.isEmpty else { return nil }
        let normalized = SuggestionEngine.normalize(raw)
        let ns = normalized as NSString
        let range = NSRange(location: 0, length: ns.length)
        for pattern in countPatterns {
            if let match = pattern.firstMatch(in: normalized, range: range),
               let value = Int(ns.substring(with: match.range(at: 1))), (1...200).contains(value) {
                return value
            }
        }
        if let match = leadingPattern.firstMatch(in: normalized, range: range),
           let value = Int(ns.substring(with: match.range(at: 1))), (1...200).contains(value),
           !notPieces.contains(ns.substring(with: match.range(at: 2)).lowercased()) {
            return value
        }
        return nil
    }
}

// MARK: - Comparer le rapport quantité/prix

/// Unité de comparaison.
enum ValueBasis: String, CaseIterable, Identifiable, Codable {
    case kilo, litre, piece

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kilo: return "Au kilo"
        case .litre: return "Au litre"
        case .piece: return "À la pièce"
        }
    }

    /// « au kilo », « à la pièce ».
    var phrase: String { label.lowercased() }
}

/// Un produit dont le prix est connu, à comparer.
struct ValueItem: Identifiable, Hashable {
    let id: String
    let product: Product
    let price: Double
    let currency: String
    /// Où et quand : « Aldi Toulouse · hier ».
    var place: String?
    let pack: PackSize
    /// Noté à la main dans « Comparer » (on peut le supprimer).
    var isManual: Bool

    init(id: String, product: Product, price: Double, currency: String, place: String? = nil,
         pack: PackSize? = nil, isManual: Bool = false) {
        self.id = id
        self.product = product
        self.price = price
        self.currency = currency
        self.place = place
        self.pack = pack ?? PackSize.of(product)
        self.isManual = isManual
    }

    /// Prix au kilo, au litre ou à la pièce (nil si la contenance correspondante est inconnue).
    func unitPrice(_ basis: ValueBasis) -> Double? {
        switch basis {
        case .kilo:
            guard let amount = pack.amount, amount.unit == "kg", amount.value > 0 else { return nil }
            return price / amount.value
        case .litre:
            guard let amount = pack.amount, amount.unit == "L", amount.value > 0 else { return nil }
            return price / amount.value
        case .piece:
            guard let count = pack.count, count > 0 else { return nil }
            return price / Double(count)
        }
    }
}

enum ValueCompare {
    static func comparableCount(_ items: [ValueItem], basis: ValueBasis) -> Int {
        items.filter { $0.unitPrice(basis) != nil }.count
    }

    /// Unités possibles (au moins un produit comparable), dans l'ordre kilo, litre, pièce.
    static func availableBases(_ items: [ValueItem]) -> [ValueBasis] {
        ValueBasis.allCases.filter { comparableCount(items, basis: $0) > 0 }
    }

    /// Au kilo (ou au litre) quand au moins autant de produits y sont comparables qu'à la pièce,
    /// sinon à la pièce. nil : aucune contenance connue.
    static func defaultBasis(_ items: [ValueItem]) -> ValueBasis? {
        let kilo = comparableCount(items, basis: .kilo)
        let litre = comparableCount(items, basis: .litre)
        let piece = comparableCount(items, basis: .piece)
        let weight: ValueBasis = kilo >= litre ? .kilo : .litre
        let weightCount = max(kilo, litre)
        if weightCount == 0 && piece == 0 { return nil }
        return weightCount >= piece ? weight : .piece
    }

    /// Classement pour une unité.
    struct Ranking {
        let basis: ValueBasis
        /// Du plus avantageux au moins avantageux.
        let ranked: [ValueItem]
        /// Contenance inconnue pour cette unité : du moins cher au plus cher.
        let others: [ValueItem]

        var best: ValueItem? { ranked.first }

        /// « +150 » : combien ce produit revient plus cher que le meilleur, à l'unité (en %).
        func extraPercent(_ item: ValueItem) -> Int? {
            guard let best, item.id != best.id,
                  let bestUnit = best.unitPrice(basis), bestUnit > 0,
                  let unit = item.unitPrice(basis) else { return nil }
            return Int(((unit / bestUnit - 1) * 100).rounded())
        }
    }

    static func rank(_ items: [ValueItem], basis: ValueBasis) -> Ranking {
        let ranked = items
            .compactMap { item -> (item: ValueItem, unit: Double)? in
                guard let unit = item.unitPrice(basis) else { return nil }
                return (item: item, unit: unit)
            }
            .sorted { a, b in
                if abs(a.unit - b.unit) > 0.0001 { return a.unit < b.unit }
                return a.item.price < b.item.price
            }
            .map(\.item)
        let others = items.filter { $0.unitPrice(basis) == nil }.sorted { $0.price < $1.price }
        return Ranking(basis: basis, ranked: ranked, others: others)
    }

    /// « 7,99 €/kg », « 1,10 €/L », « 0,80 € la pièce ».
    static func unitPriceText(_ value: Double, basis: ValueBasis, currency: String) -> String {
        switch basis {
        case .kilo: return "\(Fmt.price(value, currency))/kg"
        case .litre: return "\(Fmt.price(value, currency))/L"
        case .piece: return "\(Fmt.price(value, currency)) la pièce"
        }
    }

    /// « « 10 steaks hachés » revient 60 % moins cher à la pièce que « 2 steaks hachés »
    /// (0,80 € la pièce contre 2,00 € la pièce). »
    static func summary(_ ranking: Ranking) -> String? {
        guard ranking.ranked.count >= 2, let best = ranking.best, let worst = ranking.ranked.last,
              let bestUnit = best.unitPrice(ranking.basis), let worstUnit = worst.unitPrice(ranking.basis),
              worstUnit > bestUnit + 0.0001 else { return nil }
        let saving = Int(((1 - bestUnit / worstUnit) * 100).rounded())
        let currency = best.currency
        return "« \(best.product.name) » revient \(saving) % moins cher \(ranking.basis.phrase) que « \(worst.product.name) » "
            + "(\(unitPriceText(bestUnit, basis: ranking.basis, currency: currency)) contre "
            + "\(unitPriceText(worstUnit, basis: ranking.basis, currency: currency)))."
    }

    /// « Steak haché » pour « 10 Steak haché surgelé 15 % MG » : de quoi chercher les produits similaires.
    static func genericQuery(for name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.letters.inverted.subtracting(CharacterSet(charactersIn: "'’-")))
            .filter { word in
                let n = SuggestionEngine.normalize(word)
                return n.count >= 2 && !["de", "du", "des", "la", "le", "les", "au", "aux", "en", "et", "x", "lot", "pack",
                                          "kg", "g", "gr", "cl", "ml", "mg", "pieces", "piece", "bio"].contains(n)
            }
        return words.prefix(2).joined(separator: " ")
    }
}

/// Un produit vu en magasin, noté à la main dans « Comparer » (« 10 steaks hachés surgelés », 7,99 €).
struct ManualCompareEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// « 10 x 100 g » (facultatif : le nom suffit souvent).
    var quantity: String? = nil
    var price: Double
    var currency: String
    var storeName: String? = nil
    var date = Date()

    var item: ValueItem {
        var product = Product.custom(named: name)
        product.quantity = quantity?.nilIfBlank
        return ValueItem(id: "manual:" + id.uuidString, product: product, price: price, currency: currency,
                         place: Fmt.join(storeName?.nilIfBlank, "noté \(Fmt.day(date))"), isManual: true)
    }
}

// MARK: - Tri des produits proposés dans « Ma liste »

enum SuggestionSort: String, Codable, CaseIterable, Identifiable {
    case price, value

    var id: String { rawValue }

    var label: String {
        switch self {
        case .price: return "Prix"
        case .value: return "Rapport quantité/prix"
        }
    }
}

extension SuggestionEngine {
    private static func valueItems(_ suggestions: [ProductSuggestion]) -> [ValueItem] {
        suggestions.compactMap { suggestion in
            suggestion.offer.map { ValueItem(id: suggestion.id, product: suggestion.product,
                                             price: $0.price, currency: $0.currency) }
        }
    }

    /// Unité du tri « Rapport quantité/prix » pour ces produits (au kilo, sinon à la pièce).
    static func valueBasis(_ suggestions: [ProductSuggestion]) -> ValueBasis? {
        ValueCompare.defaultBasis(valueItems(suggestions))
    }

    /// Du meilleur rapport quantité/prix au moins bon ; ensuite les produits au prix connu mais sans contenance
    /// (par prix), enfin ceux sans prix.
    static func sortedByValue(_ suggestions: [ProductSuggestion]) -> [ProductSuggestion] {
        let items = valueItems(suggestions)
        guard let basis = ValueCompare.defaultBasis(items) else { return suggestions }
        let ranking = ValueCompare.rank(items, basis: basis)
        var byID: [String: ProductSuggestion] = [:]
        for suggestion in suggestions where suggestion.offer != nil && byID[suggestion.id] == nil {
            byID[suggestion.id] = suggestion
        }
        let priced = (ranking.ranked + ranking.others).compactMap { byID[$0.id] }
        return priced + suggestions.filter { $0.offer == nil }
    }
}
