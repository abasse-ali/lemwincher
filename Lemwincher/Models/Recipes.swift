import Foundation

// MARK: - Modèle

enum RecipeCourse: String, CaseIterable, Identifiable, Codable {
    case starter, main, dessert, breakfast

    var id: String { rawValue }

    /// Pour les filtres : « Plats ».
    var label: String {
        switch self {
        case .starter: return "Entrées"
        case .main: return "Plats"
        case .dessert: return "Desserts"
        case .breakfast: return "Petit-déj"
        }
    }

    /// Pour une recette : « Plat ».
    var singular: String {
        switch self {
        case .starter: return "Entrée"
        case .main: return "Plat"
        case .dessert: return "Dessert"
        case .breakfast: return "Petit-déjeuner"
        }
    }
}

enum RecipeTag: String, CaseIterable, Hashable {
    case cheap, family, light

    var label: String {
        switch self {
        case .cheap: return "Économique"
        case .family: return "Familial"
        case .light: return "Léger"
        }
    }
}

struct RecipeIngredient: Hashable, Identifiable {
    /// Ce qu'on lit dans la recette (« Blancs de poulet »).
    let name: String
    /// Quantité pour le nombre de personnes de la recette (nil : « à votre goût »).
    let quantity: Double?
    /// "g", "ml", "" (pièces), "gousse", "c. à soupe", "c. à café", "tranche", "sachet", "pincée"…
    let unit: String
    /// Article de « Ma liste » correspondant (« Poulet » pour les blancs comme pour les cuisses).
    let shopping: String
    /// Sel, poivre, huile, eau : supposés déjà à la maison.
    let pantry: Bool

    var id: String { name }

    init(_ name: String, _ quantity: Double? = nil, _ unit: String = "", shop: String? = nil, pantry: Bool = false) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.shopping = shop ?? name
        self.pantry = pantry
    }

    /// Quantité adaptée au nombre de personnes (« 200 g », « 1 ½ », « 2 gousses »).
    func amount(scale: Double) -> String {
        guard let quantity else { return "" }
        return RecipeFormat.amount(quantity * scale, unit: unit)
    }
}

struct Recipe: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let course: RecipeCourse
    /// Durée totale (préparation + cuisson), hors repos.
    let minutes: Int
    /// Nombre de personnes pour lequel les quantités sont écrites.
    let servings: Int
    let tags: Set<RecipeTag>
    /// Ingrédient principal, pour varier le menu de la semaine (« poulet », « bœuf », « œufs »…).
    let protein: String?
    /// Une phrase qui donne envie.
    let summary: String
    let ingredients: [RecipeIngredient]
    let steps: [String]
    /// Calculés une fois à la création (les listes de recettes sont filtrées à chaque affichage).
    let isVegetarian: Bool
    let containsPork: Bool

    init(id: String, name: String, emoji: String, course: RecipeCourse, minutes: Int, servings: Int,
         tags: Set<RecipeTag>, protein: String?, summary: String, ingredients: [RecipeIngredient], steps: [String]) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.course = course
        self.minutes = minutes
        self.servings = servings
        self.tags = tags
        self.protein = protein
        self.summary = summary
        self.ingredients = ingredients
        self.steps = steps
        isVegetarian = !ingredients.contains { DietFilter.isMeatOrFish($0.name) || DietFilter.isMeatOrFish($0.shopping) }
        containsPork = ingredients.contains { DietFilter.isPork(name: $0.name) || DietFilter.isPork(name: $0.shopping) }
    }

    var isQuick: Bool { minutes <= 20 }

    /// Ingrédients à acheter (sans le sel, le poivre, l'huile…).
    var shoppingIngredients: [RecipeIngredient] { ingredients.filter { !$0.pantry } }

    func scale(for people: Int) -> Double {
        Double(max(people, 1)) / Double(max(servings, 1))
    }

    /// Texte à partager (Messages, Notes…).
    func shareText(people: Int) -> String {
        let scale = scale(for: people)
        var lines = ["\(emoji) \(name) — pour \(people) personne\(people > 1 ? "s" : "") · \(RecipeFormat.duration(minutes))", "", "Ingrédients :"]
        for ingredient in ingredients {
            let amount = ingredient.amount(scale: scale)
            lines.append("• " + (amount.isEmpty ? ingredient.name : "\(ingredient.name) : \(amount)"))
        }
        lines.append("")
        lines.append("Préparation :")
        for (index, step) in steps.enumerated() {
            lines.append("\(index + 1). \(step)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Minuteur proposé par une étape (« Laissez mijoter 20 min »).
struct StepTimer: Hashable, Identifiable {
    let seconds: Int
    var id: Int { seconds }

    var label: String { RecipeFormat.duration(seconds / 60) }
}

// MARK: - Formats

enum RecipeFormat {
    /// 1200 g -> « 1,2 kg » ; 250 ml -> « 25 cl » ; 1,5 pièce -> « 1 ½ ».
    static func amount(_ value: Double, unit: String) -> String {
        switch unit {
        case "g":
            if value >= 1000 { return number(value / 1000, step: 0.1) + " kg" }
            return number(value, step: value >= 50 ? 5 : 1) + " g"
        case "ml":
            if value >= 1000 { return number(value / 1000, step: 0.1) + " L" }
            if value >= 100 { return number(value / 10, step: 1) + " cl" }
            return number(value, step: 5) + " ml"
        case "":
            return count(value)
        default:
            return count(value) + " " + unitLabel(unit, plural: value > 1.01)
        }
    }

    /// Nombre arrondi au pas donné, à la française (« 1,5 »).
    static func number(_ value: Double, step: Double) -> String {
        let rounded = max((value / step).rounded() * step, step)
        if abs(rounded - rounded.rounded()) < 0.001 { return String(Int(rounded.rounded())) }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    /// Pièces : quarts en dessous de 1,5 (« ¾ »), demis jusqu'à 5 (« 2 ½ »), entiers au-delà.
    static func count(_ value: Double) -> String {
        let quarters: Int
        if value < 1.5 {
            quarters = max(Int((value * 4).rounded()), 1)
        } else if value < 5 {
            quarters = Int((value * 2).rounded()) * 2
        } else {
            quarters = Int(value.rounded()) * 4
        }
        let whole = quarters / 4
        let symbol = ["", "¼", "½", "¾"][quarters % 4]
        if whole == 0 { return symbol }
        return symbol.isEmpty ? String(whole) : "\(whole) \(symbol)"
    }

    static func unitLabel(_ unit: String, plural: Bool) -> String {
        let variable: Set<String> = ["gousse", "tranche", "sachet", "boîte", "pavé", "feuille", "pincée", "brin"]
        return plural && variable.contains(unit) ? unit + "s" : unit
    }

    /// 75 -> « 1 h 15 » ; 20 -> « 20 min ».
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", rest))"
    }
}

// MARK: - Moteur

enum RecipeEngine {
    static func allowed(_ recipes: [Recipe], noPork: Bool, vegetarian: Bool) -> [Recipe] {
        recipes.filter { (!noPork || !$0.containsPork) && (!vegetarian || $0.isVegetarian) }
    }

    /// Par nom de plat ou par ingrédient (« poulet », « courgette »).
    static func search(_ recipes: [Recipe], query: String) -> [Recipe] {
        let words = SuggestionEngine.significantWords(query)
        guard !words.isEmpty else { return recipes }
        return recipes.filter { recipe in
            let tokens = SuggestionEngine.tokens(([recipe.name] + recipe.ingredients.map(\.name)).joined(separator: " "))
            return words.allSatisfy { word in tokens.contains { $0.hasPrefix(word) } }
        }
    }

    /// Mots des noms déjà analysés : les mêmes noms reviennent sans cesse (articles × ingrédients × recettes),
    /// on ne les découpe qu'une fois.
    private static var wordsCache: [String: (significant: [String], tokens: [String])] = [:]

    static func words(_ text: String) -> (significant: [String], tokens: [String]) {
        if let cached = wordsCache[text] { return cached }
        let value = (significant: SuggestionEngine.significantWords(text), tokens: SuggestionEngine.tokens(text))
        wordsCache[text] = value
        return value
    }

    /// Un article de la liste couvre-t-il cet ingrédient ? (« Poulet » couvre « Blancs de poulet »).
    /// Même règle que `SuggestionEngine.relevance(...) > 0`, dans les deux sens.
    static func matches(listName: String, shopping: String) -> Bool {
        let list = words(listName)
        let item = words(shopping)
        func covers(_ query: [String], _ tokens: [String]) -> Bool {
            !query.isEmpty && query.allSatisfy { word in tokens.contains { $0.hasPrefix(word) } }
        }
        return covers(list.significant, item.tokens) || covers(item.significant, list.tokens)
    }

    static func isInList(_ shopping: String, listNames: [String]) -> Bool {
        listNames.contains { matches(listName: $0, shopping: shopping) }
    }

    static func missing(_ recipe: Recipe, listNames: [String]) -> [RecipeIngredient] {
        recipe.shoppingIngredients.filter { !isInList($0.shopping, listNames: listNames) }
    }

    static func matchCount(_ recipe: Recipe, listNames: [String]) -> Int {
        recipe.shoppingIngredients.count - missing(recipe, listNames: listNames).count
    }

    /// Recettes qui utilisent ce qui est déjà dans la liste : le plus d'ingrédients en commun d'abord.
    static func suggested(_ recipes: [Recipe], listNames: [String]) -> [Recipe] {
        let scored = recipes.map { (recipe: $0,
                                    have: matchCount($0, listNames: listNames),
                                    lack: missing($0, listNames: listNames).count) }
        return scored
            .filter { $0.have > 0 }
            .sorted { $0.have != $1.have ? $0.have > $1.have : $0.lack < $1.lack }
            .map(\.recipe)
    }

    /// Menu de la semaine : `count` plats, en variant l'ingrédient principal ; économiques d'abord si demandé.
    static func weekMenu<G: RandomNumberGenerator>(from recipes: [Recipe], count: Int, cheapFirst: Bool,
                                                    using rng: inout G) -> [Recipe] {
        var pool = recipes.filter { $0.course == .main }.shuffled(using: &rng)
        if cheapFirst {
            pool = pool.filter { $0.tags.contains(.cheap) } + pool.filter { !$0.tags.contains(.cheap) }
        }
        var chosen: [Recipe] = []
        var proteins = Set<String>()
        for recipe in pool where chosen.count < count {
            if proteins.insert(recipe.protein ?? recipe.id).inserted { chosen.append(recipe) }
        }
        for recipe in pool where chosen.count < count && !chosen.contains(recipe) {
            chosen.append(recipe)
        }
        return chosen
    }

    /// Une autre idée pour un jour du menu : un plat absent du menu, d'un ingrédient principal pas encore pris.
    static func replacement<G: RandomNumberGenerator>(for recipe: Recipe, in menu: [Recipe], from recipes: [Recipe],
                                                       using rng: inout G) -> Recipe? {
        let taken = Set(menu.filter { $0 != recipe }.compactMap(\.protein))
        let candidates = recipes.filter { $0.course == .main && !menu.contains($0) }.shuffled(using: &rng)
        return candidates.first { !taken.contains($0.protein ?? "") } ?? candidates.first
    }

    /// Articles à acheter pour des recettes : sans les placards, ni ce qui est déjà dans la liste, sans doublons.
    static func shoppingNames(for recipes: [Recipe], listNames: [String]) -> [String] {
        var names: [String] = []
        for recipe in recipes {
            for ingredient in recipe.shoppingIngredients where !isInList(ingredient.shopping, listNames: listNames + names) {
                names.append(ingredient.shopping)
            }
        }
        return names
    }

    private static let hourPattern = try! NSRegularExpression(pattern: #"(\d+)\s?h(?:\s?(\d{1,2}))?(?![a-zà-ÿ])"#,
                                                               options: [.caseInsensitive])
    private static let minutePattern = try! NSRegularExpression(pattern: #"(\d+)(?:\s?(?:à|-)\s?\d+)?\s?min"#,
                                                                 options: [.caseInsensitive])

    /// Durées citées dans une étape (« 20 min », « 1 h 15 », « 5 à 8 min » -> la plus courte, pour surveiller).
    static func timers(in step: String) -> [StepTimer] {
        var text = step as NSString
        var seconds: [Int] = []
        for match in hourPattern.matches(in: step, range: NSRange(location: 0, length: text.length)) {
            let hours = Int(text.substring(with: match.range(at: 1))) ?? 0
            let minutes = match.range(at: 2).location == NSNotFound ? 0 : Int(text.substring(with: match.range(at: 2))) ?? 0
            seconds.append(hours * 3600 + minutes * 60)
        }
        // On efface les heures déjà lues pour ne pas relire « 15 » de « 1 h 15 ».
        var cleaned = step
        for match in hourPattern.matches(in: step, range: NSRange(location: 0, length: text.length)).reversed() {
            if let range = Range(match.range, in: cleaned) {
                cleaned.replaceSubrange(range, with: String(repeating: " ", count: match.range.length))
            }
        }
        text = cleaned as NSString
        for match in minutePattern.matches(in: cleaned, range: NSRange(location: 0, length: text.length)) {
            seconds.append((Int(text.substring(with: match.range(at: 1))) ?? 0) * 60)
        }
        var seen = Set<Int>()
        return seconds.filter { $0 > 0 && $0 <= 12 * 3600 && seen.insert($0).inserted }.map { StepTimer(seconds: $0) }
    }

    /// Mots trop généraux pour reconnaître un ingrédient dans une étape (« blancs » de poulet, crème « fraîche »…).
    private static let genericWords: Set<String> = [
        "blanc", "cuisse", "pave", "escalope", "filet", "boite", "tranche", "sachet", "fraiche", "rape", "rapee",
        "entier", "nature", "noir", "vert", "verte", "rouge", "chimique", "vanille", "concentre", "concassee",
    ]

    /// Ingrédients cités dans une étape (pour les rappeler sous l'étape, avec leur quantité).
    static func ingredients(of step: String, in recipe: Recipe) -> [RecipeIngredient] {
        let tokens = Set(SuggestionEngine.tokens(step).map(SuggestionEngine.singular))
        return recipe.ingredients.filter { ingredient in
            guard !ingredient.pantry else { return false }
            let words = SuggestionEngine.significantWords(ingredient.name).filter { !genericWords.contains($0) }
            return words.contains { tokens.contains($0) }
        }
    }
}

/// Hasard reproductible (tests, et « même menu » tant qu'on ne demande pas de nouvelles idées).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
