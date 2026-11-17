import Foundation
import CoreLocation

/// Meilleur prix connu d'un produit pour l'utilisateur.
struct PriceOffer: Hashable {
    let price: Double
    let currency: String
    /// Magasin ("Lidl Minimes") ou enseigne ("Lidl").
    let place: String
    let distance: Double?
    /// Prix médian de l'enseigne (pas un prix relevé dans le magasin).
    let isEstimate: Bool
}

/// Un produit précis proposé sous un article de la liste ("Œufs" -> "6 œufs plein air Loué").
struct ProductSuggestion: Identifiable, Hashable {
    let product: Product
    let offer: PriceOffer?
    let nutriScore: String?

    var id: String { product.code }
}

/// Résultats affichés sous un article de la liste.
struct SuggestionResults {
    var items: [ProductSuggestion] = []
    var catalogPage = 0
    var hasMore = false
    var loading = false
    var loaded = false
}

enum SuggestionEngine {
    /// "Œufs Frais" -> "oeufs frais" (minuscules, sans accents, ligatures dépliées).
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Clé de cache d'une recherche.
    static func key(_ query: String) -> String {
        tokens(query).joined(separator: " ")
    }

    /// Mots sans intérêt pour trouver un produit : unités, quantités, petits mots.
    private static let ignoredWords: Set<String> = [
        "kg", "g", "gr", "mg", "l", "cl", "ml", "dl", "x", "de", "du", "des", "d", "la", "le", "les",
        "au", "aux", "en", "et", "un", "une", "lot", "pack", "paquet", "sachet", "boite", "pot", "pots",
    ]

    /// "oeufs" -> "oeuf", "bananes" -> "banane", "noix" reste "noix".
    static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s") || (word.hasSuffix("x") && !word.hasSuffix("ix")) else { return word }
        return String(word.dropLast())
    }

    /// Mots qui comptent, normalisés et au singulier : "Bananes (1 kg)" -> ["banane"].
    static func significantWords(_ query: String) -> [String] {
        tokens(query)
            .filter { $0.count >= 2 && !$0.allSatisfy(\.isNumber) && !ignoredWords.contains($0) }
            .map(singular)
    }

    /// Mots qui comptent dans leur écriture d'origine, pour la recherche dans le catalogue.
    static func catalogText(_ query: String) -> String {
        query.components(separatedBy: CharacterSet.letters.inverted)
            .filter { word in
                let n = normalize(word)
                return n.count >= 2 && !ignoredWords.contains(n)
            }
            .joined(separator: " ")
    }

    /// Écritures à essayer côté serveur pour le mot principal ("œuf", "oeuf" ; "pâte", "pate").
    static func searchVariants(_ query: String) -> [String] {
        let words = query.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        guard let first = words.first(where: { word in
            let n = normalize(word)
            return n.count >= 2 && !ignoredWords.contains(n)
        }) else { return [] }
        var variants = [singular(first), singular(normalize(first))]
        if variants[0].contains("oe") { variants.append(variants[0].replacingOccurrences(of: "oe", with: "œ")) }
        var unique: [String] = []
        for variant in variants where !unique.contains(variant) {
            unique.append(variant)
        }
        return unique
    }

    /// Pertinence d'un nom de produit pour une recherche :
    /// 3 = le produit EST ça ("10 œufs frais" pour "oeuf"), 2 = il en contient ("chocolat au lait" pour "lait"),
    /// 0 = hors sujet ("bœuf" pour "oeuf").
    static func relevance(name: String, query: String) -> Int {
        let queryWords = significantWords(query)
        let nameWords = tokens(name)
        guard !queryWords.isEmpty else { return 0 }
        for word in queryWords where !nameWords.contains(where: { $0.hasPrefix(word) }) {
            return 0
        }
        let mainWord = nameWords.first { $0.first?.isLetter == true }
        if let mainWord, mainWord.hasPrefix(queryWords[0]) { return 3 }
        return 2
    }

    /// Meilleure offre : le prix réellement relevé le plus bas autour de soi,
    /// sinon le prix médian de l'enseigne la moins chère du quartier, sinon de France.
    static func bestOffer(observations: [PriceObservation],
                          reference: CLLocation?,
                          radiusMeters: Double,
                          country: String?,
                          currency: String,
                          nearbyChains: [String: Store]) -> PriceOffer? {
        let usable = PriceEngine.filter(observations, country: country, currency: currency)
        let local = PriceEngine.latestPerStore(usable.filter { obs in
            guard let distance = obs.distance(from: reference) else { return false }
            return distance <= radiusMeters
        })
        if let best = local.min(by: { $0.price < $1.price }) {
            return PriceOffer(price: best.price, currency: best.currency, place: best.storeName,
                              distance: best.distance(from: reference), isEstimate: false)
        }
        let estimates = ChainStats.estimates(from: usable)
        if let near = estimates.first(where: { nearbyChains[$0.key] != nil }) {
            return PriceOffer(price: near.median, currency: near.currency, place: near.name,
                              distance: nearbyChains[near.key]?.distance(from: reference), isEstimate: true)
        }
        if let any = estimates.first {
            return PriceOffer(price: any.median, currency: any.currency, place: any.name + ", France",
                              distance: nil, isEstimate: true)
        }
        return nil
    }

    /// Les produits avec un prix d'abord (du moins cher au plus cher), puis les autres.
    static func sorted(_ suggestions: [ProductSuggestion]) -> [ProductSuggestion] {
        suggestions.sorted { a, b in
            switch (a.offer, b.offer) {
            case let (x?, y?): return x.price < y.price
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return false
            }
        }
    }
}
