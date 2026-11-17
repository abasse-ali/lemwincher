import Foundation

/// Reconnaissance des enseignes (E.Leclerc, Carrefour Market, Lidl…) à partir des noms OpenStreetMap / Open Prices.
enum Chain {
    /// "Centre Commercial E.Leclerc" -> "centre commercial e leclerc"
    static func normalize(_ raw: String) -> String {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Variantes d'écriture regroupées sous une même enseigne.
    private static let aliases: [String: String] = [
        "leclerc": "e leclerc",
        "centre e leclerc": "e leclerc",
        "intermarche super": "intermarche",
        "intermarche hyper": "intermarche",
        "carrefour hypermarche": "carrefour",
        "auchan hypermarche": "auchan",
        "aldi nord": "aldi",
        "aldi sud": "aldi",
        "monoprix city": "monoprix",
        "spar supermarche": "spar",
    ]

    /// Préfixes à ignorer devant le nom de l'enseigne.
    private static let ignoredPrefixes = ["centre commercial ", "hypermarche ", "supermarche ", "magasin "]

    /// Noms affichés des enseignes connues (clé normalisée -> nom).
    static let displayNames: [String: String] = [
        "e leclerc": "E.Leclerc", "e leclerc drive": "E.Leclerc Drive", "e leclerc express": "E.Leclerc Express",
        "carrefour": "Carrefour", "carrefour market": "Carrefour Market", "carrefour city": "Carrefour City",
        "carrefour express": "Carrefour Express", "carrefour contact": "Carrefour Contact", "carrefour bio": "Carrefour Bio",
        "carrefour drive": "Carrefour Drive",
        "auchan": "Auchan", "auchan supermarche": "Auchan Supermarché", "my auchan": "My Auchan", "auchan drive": "Auchan Drive",
        "intermarche": "Intermarché", "intermarche express": "Intermarché Express", "intermarche contact": "Intermarché Contact",
        "intermarche drive": "Intermarché Drive",
        "super u": "Super U", "hyper u": "Hyper U", "u express": "U Express", "utile": "Utile", "marche u": "Marché U",
        "lidl": "Lidl", "aldi": "Aldi", "netto": "Netto", "leader price": "Leader Price",
        "casino": "Casino", "geant casino": "Géant Casino", "le petit casino": "Le Petit Casino", "casino shop": "Casino Shop",
        "spar": "Spar", "vival": "Vival", "monoprix": "Monoprix", "monop": "Monop'", "franprix": "Franprix",
        "cora": "Cora", "match": "Match", "grand frais": "Grand Frais", "biocoop": "Biocoop", "naturalia": "Naturalia",
        "la vie claire": "La Vie Claire", "picard": "Picard", "colruyt": "Colruyt", "proxi": "Proxi",
        "coccinelle express": "Coccinelle Express", "g20": "G20", "metro": "Metro", "promocash": "Promocash",
        "chronodrive": "Chronodrive", "bio c bon": "Bio c' Bon", "so bio": "So.bio", "diagonal": "Diagonal",
        "action": "Action", "costco": "Costco", "paris store": "Paris Store",
    ]

    /// Clés connues, les plus longues d'abord ("carrefour market" avant "carrefour").
    private static let knownKeysLongestFirst: [String] = displayNames.keys.sorted { $0.count > $1.count }

    private static func canonical(_ normalized: String) -> String {
        var value = normalized
        for prefix in ignoredPrefixes where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        return aliases[value] ?? value
    }

    /// Enseigne connue au début d'un nom ("carrefour market toulouse minimes" -> "carrefour market").
    private static func knownPrefix(of value: String) -> String? {
        if displayNames[value] != nil { return value }
        for key in knownKeysLongestFirst where value.hasPrefix(key + " ") {
            return aliases[key] ?? key
        }
        return nil
    }

    /// Clé d'enseigne : la marque OSM si elle existe, sinon une enseigne connue reconnue dans le nom.
    static func key(brand: String?, name: String?) -> String? {
        if let brand = brand?.nilIfBlank {
            let value = canonical(normalize(brand))
            if value.isEmpty { return nil }
            return knownPrefix(of: value) ?? value
        }
        if let name = name?.nilIfBlank {
            return knownPrefix(of: canonical(normalize(name)))
        }
        return nil
    }

    static func displayName(for key: String) -> String? {
        displayNames[key]
    }

    /// Logo de l'enseigne dans la banque d'images d'Open Food Facts (s'il existe).
    static func logoURL(brand: String?) -> String? {
        guard let brand = brand?.nilIfBlank else { return nil }
        let slug = normalize(brand).replacingOccurrences(of: " ", with: "-")
        guard !slug.isEmpty else { return nil }
        return "https://raw.githubusercontent.com/openfoodfacts/brand-images/refs/heads/main/xx/stores/\(slug).png"
    }
}
