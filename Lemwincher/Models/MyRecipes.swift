import Foundation

// MARK: - Mes recettes

/// Une recette écrite par l'utilisateur (ou une recette de l'app qu'il a personnalisée), enregistrée sur l'iPhone.
/// Partout ailleurs (quantités pour 1, 2, 4…, Ma liste, mode cuisine, prix, menu de la semaine), elle est utilisée
/// comme les autres via `recipe`.
struct MyRecipe: Codable, Identifiable, Hashable {
    static let idPrefix = "mine:"

    var id = UUID()
    var name = ""
    var emoji = "🍽️"
    var course: RecipeCourse = .main
    /// Durée totale (préparation + cuisson), hors repos.
    var minutes = 30
    /// Nombre de personnes pour lequel les quantités sont écrites.
    var servings = 2
    var tags: [RecipeTag] = []
    var summary = ""
    var ingredients: [MyIngredient] = []
    var steps: [String] = []
    /// Recette de l'app dont celle-ci est une version personnalisée.
    var basedOn: String? = nil
    var created = Date()
    var modified = Date()

    init() {}

    /// Copie modifiable d'une recette : de l'app (« Personnaliser »), composée, ou des miennes (« Dupliquer »).
    init(copying recipe: Recipe) {
        name = recipe.name
        emoji = recipe.emoji
        course = recipe.course
        minutes = recipe.minutes
        servings = recipe.servings
        tags = RecipeTag.allCases.filter { recipe.tags.contains($0) }
        summary = recipe.summary
        ingredients = recipe.ingredients.map { MyIngredient(copying: $0) }
        steps = recipe.steps
        basedOn = recipe.isMine ? nil : recipe.id
    }

    /// Lecture tolérante : une sauvegarde d'une autre version de l'app reste lisible.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? "🍽️"
        course = (try? c.decode(RecipeCourse.self, forKey: .course)) ?? .main
        minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? 30
        servings = (try? c.decode(Int.self, forKey: .servings)) ?? 2
        tags = ((try? c.decode([String].self, forKey: .tags)) ?? []).compactMap(RecipeTag.init(rawValue:))
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        ingredients = ((try? c.decode([Lossy<MyIngredient>].self, forKey: .ingredients)) ?? []).compactMap(\.value)
        steps = (try? c.decode([String].self, forKey: .steps)) ?? []
        basedOn = try? c.decode(String.self, forKey: .basedOn)
        created = (try? c.decode(Date.self, forKey: .created)) ?? Date()
        modified = (try? c.decode(Date.self, forKey: .modified)) ?? created
    }

    var recipeID: String { Self.idPrefix + id.uuidString }

    /// Contenu comparable (sans dates ni identifiants) : l'éditeur sait ainsi si quelque chose a changé.
    var contentSignature: String {
        let header = [name.trimmed, emoji, summary.trimmed, course.rawValue, "\(minutes)", "\(servings)",
                      tags.map(\.rawValue).sorted().joined(separator: ",")]
        let items = ingredients.map { item -> String in
            let amount = MyIngredient.normalized(item.quantity, unit: item.unit)
            return [item.name.trimmed, amount.quantity.map { String(format: "%.3f", $0) } ?? "", amount.unit,
                    item.pantry ? "placard" : ""].joined(separator: "|")
        }
        return (header + items + steps.map { $0.trimmed }).joined(separator: "\n")
    }

    /// La recette telle que l'app l'utilise (ingrédients sans nom ignorés, kg / L / cl ramenés en g et ml).
    var recipe: Recipe {
        var seen: [String: Int] = [:]
        let items: [RecipeIngredient] = ingredients.compactMap { item in
            let base = item.name.trimmed
            guard !base.isEmpty else { return nil }
            // Deux lignes au même nom (« Beurre » pour la pâte et pour le moule) restent deux ingrédients.
            let count = (seen[base.lowercased()] ?? 0) + 1
            seen[base.lowercased()] = count
            let name = count == 1 ? base : "\(base) (\(count))"
            let amount = MyIngredient.normalized(item.quantity, unit: item.unit)
            return RecipeIngredient(name, amount.quantity, amount.unit,
                                    shop: item.shopping?.trimmed.nilIfBlank ?? base, pantry: item.pantry)
        }
        let protein = items.first { DietFilter.isMeatOrFish($0.name) || DietFilter.isMeatOrFish($0.shopping) }
            .map { SuggestionEngine.normalize($0.shopping) }
        return Recipe(id: recipeID,
                      name: name.trimmed.nilIfBlank ?? "Ma recette",
                      emoji: emoji.trimmed.nilIfBlank ?? "🍽️",
                      course: course,
                      minutes: max(minutes, 1),
                      servings: max(servings, 1),
                      tags: Set(tags),
                      protein: protein,
                      summary: summary.trimmed.nilIfBlank ?? "Ma recette, à ma façon.",
                      ingredients: items,
                      steps: steps.map(\.trimmed).filter { !$0.isEmpty })
    }
}

/// Un ingrédient d'une de mes recettes.
struct MyIngredient: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    /// Quantité pour le nombre de personnes de la recette ; nil : « à votre goût ».
    var quantity: Double? = nil
    /// "" (pièces), "g", "kg", "ml", "cl", "L", "c. à soupe"… (kg, L et cl sont ramenés en g et ml).
    var unit = ""
    /// Article de « Ma liste » correspondant (par défaut : le nom).
    var shopping: String? = nil
    /// Sel, poivre, huile… : déjà à la maison, pas ajouté aux courses.
    var pantry = false

    init(name: String = "", quantity: Double? = nil, unit: String = "", shopping: String? = nil, pantry: Bool = false) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.shopping = shopping
        self.pantry = pantry
    }

    init(copying ingredient: RecipeIngredient) {
        name = ingredient.name
        quantity = ingredient.quantity
        unit = ingredient.unit
        shopping = ingredient.shopping == ingredient.name ? nil : ingredient.shopping
        pantry = ingredient.pantry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        quantity = try? c.decode(Double.self, forKey: .quantity)
        unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
        shopping = try? c.decode(String.self, forKey: .shopping)
        pantry = (try? c.decode(Bool.self, forKey: .pantry)) ?? false
    }

    /// Unités proposées dans l'éditeur ("" = pièces).
    static let units = ["", "g", "kg", "ml", "cl", "L", "c. à soupe", "c. à café", "gousse", "tranche", "pincée",
                        "sachet", "boîte", "brin", "feuille", "pavé", "verre", "botte", "poignée"]

    static func unitLabel(_ unit: String) -> String { unit.isEmpty ? "pièce(s)" : unit }

    /// kg, L, cl -> g, ml (l'app affiche ensuite « 1,2 kg », « 25 cl » selon la quantité).
    static func normalized(_ quantity: Double?, unit: String) -> (quantity: Double?, unit: String) {
        guard let quantity, quantity > 0 else { return (nil, "") }
        switch unit {
        case "kg": return (quantity * 1000, "g")
        case "L": return (quantity * 1000, "ml")
        case "cl": return (quantity * 10, "ml")
        default: return (quantity, unit)
        }
    }

    /// Quantité et unité à afficher dans l'éditeur (1 000 g -> « 1 » kg, 1 500 ml -> « 1,5 » L).
    static func editable(_ quantity: Double?, unit: String) -> (text: String, unit: String) {
        guard let quantity, quantity > 0 else { return ("", unit) }
        if unit == "g" && quantity >= 1000 { return (format(quantity / 1000), "kg") }
        if unit == "ml" && quantity >= 1000 { return (format(quantity / 1000), "L") }
        return (format(quantity), unit)
    }

    /// 1.5 -> « 1,5 » ; 2.0 -> « 2 ».
    static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.001 { return String(Int(rounded.rounded())) }
        return String(format: "%g", rounded).replacingOccurrences(of: ".", with: ",")
    }

    /// « 1,5 », « 1.5 », « ½ », « 1 ½ », « 1/2 », « deux » -> nombre ; nil si ce n'est pas une quantité.
    static func parseQuantity(_ raw: String) -> Double? {
        var text = raw.trimmed.lowercased()
        guard !text.isEmpty else { return nil }
        let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]
        var extra = 0.0
        if let last = text.last, let fraction = fractions[last] {
            extra = fraction
            text = String(text.dropLast()).trimmed
            if text.isEmpty { return extra }
        }
        let words: [String: Double] = ["un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6,
                                       "sept": 7, "huit": 8, "dix": 10, "douze": 12, "demi": 0.5, "demie": 0.5]
        if let word = words[text] { return word + extra }
        if text.contains("/") {
            let parts = text.split(separator: "/").map { String($0).trimmed }
            guard parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]), bottom > 0 else { return nil }
            return top / bottom + extra
        }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value + extra
    }
}

// MARK: - Image d'une recette

/// Image d'une recette d'après son nom : le premier plat nommé l'emporte
/// (« Pâtes au thon et à la crème » -> 🍝, « Crème brûlée » -> 🍮, « Gratin de pommes de terre » -> 🥘).
enum RecipeEmoji {
    private static let dishes: [(keys: Set<String>, emoji: String)] = [
        (["pates", "pate", "spaghetti", "spaghettis", "tagliatelle", "tagliatelles", "penne", "lasagne", "lasagnes",
          "macaroni", "macaronis", "coquillettes", "ravioli", "raviolis", "gnocchi", "gnocchis", "carbonara",
          "bolognaise", "linguine"], "🍝"),
        (["pizza", "pizzas"], "🍕"),
        (["burger", "burgers", "hamburger", "hamburgers"], "🍔"),
        (["sandwich", "sandwichs", "croque", "panini", "paninis"], "🥪"),
        (["tacos", "taco", "fajitas", "quesadilla"], "🌮"),
        (["wrap", "wraps", "burrito", "burritos"], "🌯"),
        (["kebab", "falafel", "falafels", "chawarma", "shawarma"], "🥙"),
        (["salade", "salades", "taboule"], "🥗"),
        (["soupe", "veloute", "potage", "bouillon", "minestrone", "pho", "ramen"], "🍲"),
        (["curry", "dahl", "dal", "colombo", "massala", "biryani"], "🍛"),
        (["riz", "risotto", "sushi", "sushis"], "🍚"),
        (["couscous", "tajine", "tagine", "paella", "gratin", "hachis", "parmentier", "moussaka", "chili",
          "blanquette", "bourguignon", "ragout", "mijote", "cassoulet"], "🥘"),
        (["quiche", "tarte", "tartes", "tourte", "feuillete", "clafoutis"], "🥧"),
        (["omelette", "oeuf", "oeufs", "brouilles"], "🍳"),
        (["crepe", "crepes", "pancake", "pancakes", "galette", "galettes"], "🥞"),
        (["gaufre", "gaufres"], "🧇"),
        (["gateau", "gateaux", "cake", "fondant", "brownie", "brownies", "moelleux", "tiramisu", "charlotte",
          "cheesecake", "muffin", "muffins", "madeleines"], "🍰"),
        (["cookie", "cookies", "biscuit", "biscuits", "sable", "sables"], "🍪"),
        (["creme", "mousse", "flan", "panna", "entremets"], "🍮"),
        (["chocolat"], "🍫"),
        (["poulet", "dinde", "volaille", "pilons", "cuisses"], "🍗"),
        (["boeuf", "steak", "steaks", "entrecote", "roti", "veau"], "🥩"),
        (["agneau", "gigot", "brochettes"], "🍖"),
        (["saumon", "cabillaud", "thon", "poisson", "colin", "merlu", "dorade", "sardines", "truite", "lieu"], "🐟"),
        (["crevette", "crevettes", "moules", "gambas", "calamars"], "🦐"),
        (["frites", "patates", "puree"], "🥔"),
        (["legumes", "ratatouille", "courgette", "courgettes", "brocoli", "brocolis", "poelee"], "🥦"),
        (["champignon", "champignons"], "🍄"),
        (["pain", "brioche", "baguette"], "🥐"),
        (["smoothie", "milkshake", "jus", "limonade"], "🥤"),
        (["fraise", "fraises"], "🍓"),
        (["citron"], "🍋"),
        (["pomme", "pommes", "compote"], "🍎"),
    ]

    static func guess(for name: String) -> String? {
        let tokens = SuggestionEngine.tokens(name)
        for (index, token) in tokens.enumerated() {
            // « pommes de terre » : la pomme de terre, pas la pomme.
            if token.hasPrefix("pomme"), tokens.dropFirst(index + 1).prefix(2).elementsEqual(["de", "terre"]) {
                return "🥔"
            }
            if let dish = dishes.first(where: { $0.keys.contains(token) }) { return dish.emoji }
        }
        return nil
    }
}

// MARK: - Recette collée (texte d'un site, d'une note…)

/// Lit une recette copiée : nom, nombre de personnes, durée, ingrédients (« 200 g de farine », « 2 œufs »,
/// « 1 c. à soupe d'huile ») et étapes (« 1. Préchauffez le four… »).
enum RecipeTextParser {
    struct Result: Equatable {
        var name: String?
        var servings: Int?
        var minutes: Int?
        var ingredients: [MyIngredient] = []
        var steps: [String] = []

        var isEmpty: Bool { name == nil && ingredients.isEmpty && steps.isEmpty }
    }

    private enum Part { case intro, ingredients, steps, ignored }

    static func parse(_ text: String) -> Result {
        var result = Result()
        var part = Part.intro
        var prep = 0, cook = 0
        var total: Int?
        let lines = text.components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty }
        for line in lines {
            let lower = SuggestionEngine.normalize(line)
            let short = line.count <= 60
            let duration = short ? RecipeEngine.timers(in: line).first.map { $0.seconds / 60 } : nil

            if short && lower.hasPrefix("ingredient") {
                part = .ingredients
                if let people = servings(in: lower) { result.servings = people }
                continue
            }
            if let duration, part != .steps,
               ["total", "prep", "cuisson", "temps", "repos"].contains(where: { lower.contains($0) }) {
                if lower.contains("total") {
                    total = duration
                } else if lower.contains("prep") {
                    prep = duration
                } else if lower.contains("cuisson") {
                    cook += duration
                }
                continue
            }
            if short && duration == nil && isHeader(lower, ["preparation", "etapes", "instructions", "deroulement",
                                                            "la recette", "methode", "recette :"]) {
                part = .steps
                continue
            }
            if short && isHeader(lower, ["ustensile", "materiel", "astuce", "conseil", "note", "commentaire",
                                         "valeurs nutritionnelles", "a propos"]) {
                part = .ignored
                continue
            }
            if part != .steps, short, result.servings == nil, let people = servings(in: lower),
               ingredient(from: line)?.quantity == nil || lower.contains("personne") {
                result.servings = people
                continue
            }

            switch part {
            case .intro:
                let item = ingredient(from: line)
                if result.name == nil && line.count <= 80 && item?.quantity == nil && !line.hasSuffix(".") {
                    result.name = title(line)
                } else if let item, item.quantity != nil, line.count <= 80 {
                    // Sans titres : une quantité en tête = un ingrédient ; une phrase = une étape.
                    result.ingredients.append(item)
                } else if line.split(separator: " ").count >= 5 {
                    result.steps.append(stepText(line))
                }
            case .ingredients:
                // « Pour la pâte : » : un sous-titre, pas un ingrédient.
                guard !line.hasSuffix(":"), let item = ingredient(from: line) else { continue }
                result.ingredients.append(item)
            case .steps:
                let step = stepText(line)
                if !step.isEmpty { result.steps.append(step) }
            case .ignored:
                continue
            }
        }
        result.minutes = total ?? (prep + cook > 0 ? prep + cook : nil)
        return result
    }

    private static func isHeader(_ lower: String, _ words: [String]) -> Bool {
        words.contains { lower.hasPrefix($0) }
    }

    private static let servingsPattern = try! NSRegularExpression(
        pattern: #"(\d{1,2})\s*(?:personnes?|pers\b|parts?|portions?|couverts?)"#, options: [.caseInsensitive])

    /// « Pour 4 personnes », « 6 parts » -> 4, 6.
    static func servings(in lower: String) -> Int? {
        let ns = lower as NSString
        guard let match = servingsPattern.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)),
              let value = Int(ns.substring(with: match.range(at: 1))), (1...24).contains(value) else { return nil }
        return value
    }

    private static let numberingPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:[-•*·–]\s*|(?:[ée]tape\s*\d{1,2}\s*[.):\-–]?\s*)|\d{1,2}\s*[.):\-–]\s+)"#,
        options: [.caseInsensitive])

    /// « 1. Préchauffez le four » -> « Préchauffez le four » ; « Étape 2 » seule -> "".
    static func stepText(_ line: String) -> String {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = numberingPattern.firstMatch(in: line, range: range) else { return line.trimmed }
        return ns.substring(from: match.range.location + match.range.length).trimmed
    }

    /// « Recette de Gâteau au chocolat - Marmiton » -> « Gâteau au chocolat ».
    static func title(_ line: String) -> String {
        var name = line.trimmed
        for prefix in ["recette de ", "recette d'", "recette d’", "recette : "] where name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        for separator in [" - ", " | ", " – "] {
            if let range = name.range(of: separator, options: .backwards),
               name[range.upperBound...].count <= 25 {
                name = String(name[..<range.lowerBound])
            }
        }
        name = name.trimmed
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Groupes : 1 quantité (« 200 », « 1 ½ », « 4 à 5 », « une »), 2 unité (« g », « c. à soupe »…), 3 nom.
    private static let ingredientPattern = try! NSRegularExpression(
        pattern: #"^(?:((?:\d+(?:[.,]\d+)?(?:\s?/\s?\d+)?(?:\s?[½¼¾])?|[½¼¾⅓⅔]|"#
            + #"(?:une?|deux|trois|quatre|cinq|six|sept|huit|dix|douze)(?![a-zà-ÿ]))"#
            + #"(?:\s?(?:à|-)\s?\d+(?:[.,]\d+)?)?)\s*"#
            + #"(?:(kg|g|gr|grammes?|mg|l|litres?|cl|dl|ml|c\.?\s?à\s?s\.?|c\.?\s?à\s?soupe|c\.?\s?à\s?c\.?|"#
            + #"c\.?\s?à\s?caf[ée]|cuill[eè]res?\s+à\s+(?:soupe|caf[ée])|cuil\.?\s+à\s+(?:soupe|caf[ée])|cs|cc|"#
            + #"gousses?|tranches?|pinc[ée]es?|sachets?|bo[iî]tes?|brins?|feuilles?|pav[ée]s?|verres?|bottes?|"#
            + #"poign[ée]es?)(?![a-zà-ÿ'’])\.?\s*)?)?"#
            + #"(?:de\s+|d['’]\s*)?(.+)$"#,
        options: [.caseInsensitive])

    /// « 200 g de farine », « 2 œufs », « 1 c. à soupe d'huile d'olive », « Sel, poivre » -> ingrédient.
    static func ingredient(from raw: String) -> MyIngredient? {
        var line = raw.trimmed
        if let first = line.first, "-•*·–".contains(first) { line = String(line.dropFirst()).trimmed }
        guard line.count >= 2, line.count <= 120 else { return nil }
        let ns = line as NSString
        guard let match = ingredientPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        var quantity = group(1).flatMap { text -> Double? in
            // « 4 à 5 » : la première valeur.
            let first = text.components(separatedBy: CharacterSet(charactersIn: "à-")).first ?? text
            return MyIngredient.parseQuantity(first)
        }
        var unit = ""
        if let raw = group(2) {
            let converted = self.unit(raw)
            unit = converted.unit
            quantity = quantity.map { $0 * converted.factor }
        }
        guard var name = group(3)?.trimmed, !name.isEmpty else { return nil }
        while let last = name.last, ".,;".contains(last) { name.removeLast() }
        name = name.trimmed
        guard name.rangeOfCharacter(from: .letters) != nil else { return nil }
        name = name.prefix(1).uppercased() + name.dropFirst()
        return MyIngredient(name: name, quantity: quantity, unit: quantity == nil ? "" : unit, pantry: isPantry(name))
    }

    /// Unité écrite -> unité de l'app et facteur (kg -> g × 1000, cl -> ml × 10…).
    static func unit(_ raw: String) -> (unit: String, factor: Double) {
        let u = SuggestionEngine.normalize(raw).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        switch u {
        case "kg": return ("g", 1000)
        case "g", "gr", "gramme", "grammes": return ("g", 1)
        case "mg": return ("g", 0.001)
        case "l", "litre", "litres": return ("ml", 1000)
        case "cl": return ("ml", 10)
        case "dl": return ("ml", 100)
        case "ml": return ("ml", 1)
        default: break
        }
        if u.hasPrefix("cas") || u == "cs" || u.contains("soupe") { return ("c. à soupe", 1) }
        if u.hasPrefix("cac") || u == "cc" || u.contains("cafe") { return ("c. à café", 1) }
        let singular = u.hasSuffix("s") ? String(u.dropLast()) : u
        let names = ["gousse": "gousse", "tranche": "tranche", "pincee": "pincée", "sachet": "sachet", "boite": "boîte",
                     "brin": "brin", "feuille": "feuille", "pave": "pavé", "verre": "verre", "botte": "botte",
                     "poignee": "poignée"]
        return (names[singular] ?? "", 1)
    }

    /// Sel, poivre, huile, eau : supposés déjà à la maison (pas l'eau de fleur d'oranger).
    static func isPantry(_ name: String) -> Bool {
        let n = SuggestionEngine.normalize(name)
        if n.hasPrefix("eau de ") { return false }
        return ["sel", "poivre", "eau", "huile"].contains { n == $0 || n.hasPrefix($0 + " ") || n.hasPrefix($0 + ",") }
    }
}
