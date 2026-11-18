import Foundation

/// Alimentation : sans porc (réglage par défaut), végétarien pour les recettes.
enum DietFilter {
    /// Mots qui désignent toujours du porc.
    private static let porkWords: Set<String> = [
        "porc", "porcs", "porcine", "porcines", "cochon", "cochons", "saindoux", "andouille", "andouilles",
        "andouillette", "andouillettes", "coppa", "pancetta", "prosciutto", "speck", "guanciale", "rillons", "grattons",
    ]

    /// Mots qui désignent presque toujours du porc, sauf précision (« de dinde », « de volaille », « de bœuf »…).
    private static let usuallyPorkWords: Set<String> = [
        "jambon", "jambons", "jambonneau", "jambonneaux", "lardon", "lardons", "lard", "bacon", "saucisson",
        "saucissons", "chorizo", "chorizos", "rillettes", "boudin", "boudins", "cervelas", "mortadelle", "salami",
        "salamis", "rosette", "knack", "knacks", "knacki", "knackis", "chipolata", "chipolatas", "saucisse",
        "saucisses", "terrine", "terrines", "poitrine",
    ]

    /// Précisions qui écartent le porc : « lardons de dinde », « chorizo de bœuf », « rillettes de thon »…
    private static let notPorkWords: Set<String> = [
        "dinde", "poulet", "volaille", "volailles", "boeuf", "bovin", "bovine", "veau", "agneau", "mouton", "canard",
        "oie", "thon", "saumon", "sardine", "sardines", "maquereau", "maquereaux", "truite", "poisson", "poissons",
        "crabe", "halal", "vegetal", "vegetale", "vegetales", "vegetaux", "vegetarien", "vegetarienne",
        "vegetariens", "vegetariennes", "vegan", "vegane", "veggie", "soja", "tofu",
    ]

    /// Catégories Open Food Facts de charcuterie (porc sauf précision dans le nom).
    private static let usuallyPorkCategories: Set<String> = [
        "en:hams", "en:white-hams", "en:cooked-hams", "en:dry-hams", "en:sausages", "en:dry-sausages",
        "en:charcuteries", "en:rillettes", "en:pates", "en:terrines",
    ]

    /// Mots de viande ou de poisson (pour savoir si une recette est végétarienne).
    private static let meatOrFishWords: Set<String> = [
        "poulet", "boeuf", "dinde", "veau", "agneau", "mouton", "canard", "porc", "jambon", "lardon", "lardons",
        "saucisse", "saucisses", "merguez", "chorizo", "viande", "steak", "steaks", "thon", "saumon", "cabillaud",
        "colin", "poisson", "poissons", "crevette", "crevettes", "sardine", "sardines", "maquereau", "moules", "anchois",
    ]

    /// Le produit contient-il du porc, d'après son nom et ses catégories ?
    static func isPork(name: String, categories: [String]? = nil) -> Bool {
        let words = Set(SuggestionEngine.tokens(name))
        if !words.isDisjoint(with: porkWords) { return true }
        let tags = (categories ?? []).map { $0.lowercased() }
        if tags.contains(where: { $0.contains("pork") }) { return true }
        // « Pâté » garde son accent : sans lui, ce serait « pâte » (les pâtes).
        let lower = name.lowercased().precomposedStringWithCanonicalMapping
        let usually = !words.isDisjoint(with: usuallyPorkWords)
            || lower.contains("pâté")
            || tags.contains(where: { usuallyPorkCategories.contains($0) })
        guard usually else { return false }
        return words.isDisjoint(with: notPorkWords)
    }

    /// Ingrédients Open Food Facts qui révèlent du porc (« en:pork-fat », « en:bacon »…).
    static func porkIngredients(_ tags: [String]) -> Bool {
        tags.map { $0.lowercased() }.contains { tag in
            if tag.contains("chicken") || tag.contains("turkey") || tag.contains("poultry") || tag.contains("beef") {
                return false
            }
            return tag.contains("pork") || tag == "en:bacon" || tag == "en:lard" || tag == "en:ham"
                || tag.hasSuffix("-ham") || tag.contains("chorizo") || tag.contains("salami")
        }
    }

    /// Gélatine sans origine précisée (souvent porcine) : on le signale sans masquer le produit.
    static func unspecifiedGelatin(_ tags: [String]) -> Bool {
        let lower = tags.map { $0.lowercased() }
        return lower.contains("en:gelatin") || lower.contains("en:gelatine")
    }

    static func isMeatOrFish(_ name: String) -> Bool {
        !Set(SuggestionEngine.tokens(name)).isDisjoint(with: meatOrFishWords)
    }

    /// Le produit peut-il être proposé, avec ce réglage ?
    static func allows(_ product: Product, noPork: Bool) -> Bool {
        !(noPork && isPork(name: product.name, categories: product.categories))
    }
}
