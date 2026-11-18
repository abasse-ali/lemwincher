import Foundation

/// Un élément pour composer son plat : féculent, protéine, légume ou saveur.
struct DishPart: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case base, protein, vegetable, flavor

        var title: String {
            switch self {
            case .base: return "Féculent"
            case .protein: return "Protéine"
            case .vegetable: return "Légumes"
            case .flavor: return "Saveur"
            }
        }
    }

    let id: String
    let kind: Kind
    let name: String
    let emoji: String
    /// Ingrédients pour 1 personne.
    let ingredients: [RecipeIngredient]
    /// Ce qu'on fait avec (une étape de la recette).
    let step: String
    let minutes: Int
    /// Pour le nom du plat : « au curry et lait de coco ».
    var title: String = ""

    var isVegetarian: Bool { !ingredients.contains { DietFilter.isMeatOrFish($0.name) } }
}

enum DishComposer {
    private typealias I = RecipeIngredient

    static let bases: [DishPart] = [
        DishPart(id: "riz", kind: .base, name: "Riz", emoji: "🍚", ingredients: [I("Riz", 75, "g")],
                 step: "Faites cuire le riz 12 min dans une grande casserole d'eau bouillante salée, puis égouttez-le.", minutes: 15),
        DishPart(id: "pates", kind: .base, name: "Pâtes", emoji: "🍝", ingredients: [I("Pâtes", 100, "g")],
                 step: "Faites cuire les pâtes al dente dans une grande casserole d'eau bouillante salée.", minutes: 12),
        DishPart(id: "semoule", kind: .base, name: "Semoule", emoji: "🥣", ingredients: [I("Semoule", 70, "g"), I("Beurre", 5, "g")],
                 step: "Versez sur la semoule le même volume d'eau bouillante salée, couvrez 5 min, puis égrainez-la à la fourchette avec le beurre.", minutes: 8),
        DishPart(id: "pommes-de-terre", kind: .base, name: "Pommes de terre", emoji: "🥔",
                 ingredients: [I("Pommes de terre", 250, "g")],
                 step: "Coupez les pommes de terre en cubes et faites-les rôtir 30 min au four à 200 °C avec un filet d'huile et du sel.", minutes: 35),
        DishPart(id: "quinoa", kind: .base, name: "Quinoa", emoji: "🌾", ingredients: [I("Quinoa", 70, "g")],
                 step: "Rincez le quinoa et faites-le cuire 12 min dans deux fois son volume d'eau salée.", minutes: 15),
        DishPart(id: "pain", kind: .base, name: "Pain", emoji: "🥖", ingredients: [I("Pain", 0.25)],
                 step: "Coupez le pain en tranches, à servir avec le plat.", minutes: 1),
    ]

    static let proteins: [DishPart] = [
        DishPart(id: "poulet", kind: .protein, name: "Poulet", emoji: "🍗",
                 ingredients: [I("Blancs de poulet", 150, "g", shop: "Poulet")],
                 step: "Coupez le poulet en dés et faites-le dorer 8 min dans une poêle avec un filet d'huile ; salez.", minutes: 10),
        DishPart(id: "boeuf", kind: .protein, name: "Bœuf haché", emoji: "🥩", ingredients: [I("Bœuf haché", 125, "g")],
                 step: "Faites dorer le bœuf haché 6 min dans une poêle chaude en l'égrainant ; salez et poivrez.", minutes: 8),
        DishPart(id: "dinde", kind: .protein, name: "Dinde", emoji: "🦃",
                 ingredients: [I("Escalopes de dinde", 1)],
                 step: "Coupez la dinde en lanières et faites-la dorer 6 min dans un filet d'huile ; salez.", minutes: 8),
        DishPart(id: "saumon", kind: .protein, name: "Saumon", emoji: "🐟", ingredients: [I("Pavés de saumon", 1, shop: "Saumon")],
                 step: "Faites cuire le saumon 4 min côté peau puis 2 min de l'autre côté, à feu moyen ; salez.", minutes: 8),
        DishPart(id: "thon", kind: .protein, name: "Thon", emoji: "🥫", ingredients: [I("Thon en boîte", 70, "g")],
                 step: "Égouttez et émiettez le thon ; ajoutez-le en fin de cuisson pour qu'il reste moelleux.", minutes: 2),
        DishPart(id: "crevettes", kind: .protein, name: "Crevettes", emoji: "🦐", ingredients: [I("Crevettes", 100, "g")],
                 step: "Faites sauter les crevettes 3 min à feu vif dans un filet d'huile.", minutes: 4),
        DishPart(id: "oeufs", kind: .protein, name: "Œufs", emoji: "🥚", ingredients: [I("Œufs", 2)],
                 step: "Faites cuire les œufs au plat 4 min, à poser sur le plat au moment de servir.", minutes: 5),
        DishPart(id: "pois-chiches", kind: .protein, name: "Pois chiches", emoji: "🫘", ingredients: [I("Pois chiches", 120, "g")],
                 step: "Rincez les pois chiches et faites-les revenir 5 min à la poêle pour qu'ils soient dorés.", minutes: 6),
        DishPart(id: "lentilles", kind: .protein, name: "Lentilles corail", emoji: "🟠", ingredients: [I("Lentilles corail", 60, "g")],
                 step: "Faites cuire les lentilles corail 12 min dans trois fois leur volume d'eau, puis égouttez.", minutes: 14),
        DishPart(id: "tofu", kind: .protein, name: "Tofu", emoji: "🧈", ingredients: [I("Tofu", 100, "g")],
                 step: "Coupez le tofu en cubes et faites-le dorer 8 min sur toutes les faces.", minutes: 9),
    ]

    static let vegetables: [DishPart] = [
        DishPart(id: "courgette", kind: .vegetable, name: "Courgettes", emoji: "🥒", ingredients: [I("Courgettes", 150, "g")],
                 step: "", minutes: 8),
        DishPart(id: "carotte", kind: .vegetable, name: "Carottes", emoji: "🥕", ingredients: [I("Carottes", 100, "g")],
                 step: "", minutes: 12),
        DishPart(id: "poivron", kind: .vegetable, name: "Poivrons", emoji: "🫑", ingredients: [I("Poivrons", 0.5)],
                 step: "", minutes: 10),
        DishPart(id: "tomate", kind: .vegetable, name: "Tomates", emoji: "🍅", ingredients: [I("Tomates", 1)],
                 step: "", minutes: 5),
        DishPart(id: "champignon", kind: .vegetable, name: "Champignons", emoji: "🍄", ingredients: [I("Champignons", 80, "g")],
                 step: "", minutes: 6),
        DishPart(id: "epinards", kind: .vegetable, name: "Épinards", emoji: "🥬", ingredients: [I("Épinards", 100, "g")],
                 step: "", minutes: 3),
        DishPart(id: "brocoli", kind: .vegetable, name: "Brocoli", emoji: "🥦", ingredients: [I("Brocoli", 120, "g")],
                 step: "", minutes: 8),
        DishPart(id: "haricots-verts", kind: .vegetable, name: "Haricots verts", emoji: "🫛", ingredients: [I("Haricots verts", 120, "g")],
                 step: "", minutes: 10),
        DishPart(id: "aubergine", kind: .vegetable, name: "Aubergine", emoji: "🍆", ingredients: [I("Aubergines", 0.5)],
                 step: "", minutes: 12),
        DishPart(id: "oignon", kind: .vegetable, name: "Oignons", emoji: "🧅", ingredients: [I("Oignons", 0.5)],
                 step: "", minutes: 6),
    ]

    static let flavors: [DishPart] = [
        DishPart(id: "curry-coco", kind: .flavor, name: "Curry coco", emoji: "🥥",
                 ingredients: [I("Lait de coco", 100, "ml"), I("Curry", 1, "c. à café")],
                 step: "Ajoutez le curry, remuez 1 min, puis versez le lait de coco et laissez mijoter 8 min.", minutes: 9,
                 title: "au curry et lait de coco"),
        DishPart(id: "tomate-basilic", kind: .flavor, name: "Tomate basilic", emoji: "🍅",
                 ingredients: [I("Tomates concassées", 100, "g"), I("Basilic", shop: "Basilic")],
                 step: "Ajoutez les tomates concassées et laissez mijoter 10 min ; parsemez de basilic au moment de servir.", minutes: 10,
                 title: "à la tomate et au basilic"),
        DishPart(id: "creme-moutarde", kind: .flavor, name: "Crème moutarde", emoji: "🥛",
                 ingredients: [I("Crème fraîche", 50, "ml"), I("Moutarde", 1, "c. à café")],
                 step: "Ajoutez la crème et la moutarde, mélangez et laissez épaissir 3 min à feu doux.", minutes: 4,
                 title: "à la crème moutardée"),
        DishPart(id: "citron-herbes", kind: .flavor, name: "Citron herbes", emoji: "🍋",
                 ingredients: [I("Citrons", 0.25), I("Persil", shop: "Persil")],
                 step: "Hors du feu, arrosez de jus de citron et parsemez de persil ciselé.", minutes: 1,
                 title: "au citron et aux herbes"),
        DishPart(id: "soja-gingembre", kind: .flavor, name: "Soja gingembre", emoji: "🥢",
                 ingredients: [I("Sauce soja", 1, "c. à soupe"), I("Gingembre", shop: "Gingembre")],
                 step: "Ajoutez la sauce soja et un peu de gingembre râpé, faites sauter 2 min à feu vif.", minutes: 2,
                 title: "sauce soja et gingembre"),
        DishPart(id: "ras-el-hanout", kind: .flavor, name: "Ras el hanout", emoji: "🌶️",
                 ingredients: [I("Ras el hanout", 0.5, "c. à café"), I("Tomates concassées", 50, "g")],
                 step: "Ajoutez le ras el hanout, les tomates concassées et un peu d'eau ; laissez mijoter 10 min.", minutes: 10,
                 title: "aux épices ras el hanout"),
        DishPart(id: "pesto", kind: .flavor, name: "Pesto", emoji: "🌿", ingredients: [I("Pesto", 30, "g")],
                 step: "Hors du feu, mélangez avec le pesto.", minutes: 1,
                 title: "au pesto"),
    ]

    static func parts(_ kind: DishPart.Kind, vegetarian: Bool = false) -> [DishPart] {
        let list: [DishPart]
        switch kind {
        case .base: list = bases
        case .protein: list = proteins
        case .vegetable: list = vegetables
        case .flavor: list = flavors
        }
        return vegetarian ? list.filter(\.isVegetarian) : list
    }

    /// « Poulet au curry et lait de coco, avec riz, courgettes et carottes ».
    static func name(base: DishPart?, protein: DishPart?, vegetables: [DishPart], flavor: DishPart?) -> String {
        let main = protein?.name ?? (vegetables.isEmpty ? "Assiette" : "Poêlée de légumes")
        let head = [main, flavor?.title].compactMap { $0?.nilIfBlank }.joined(separator: " ")
        var sides = [base?.name.lowercased()].compactMap { $0 }
        if protein != nil || base != nil {
            sides += vegetables.map { $0.name.lowercased() }
        }
        guard !sides.isEmpty else { return head }
        let list = sides.count == 1 ? sides[0] : sides.dropLast().joined(separator: ", ") + " et " + sides.last!
        return head + ", avec " + list
    }

    /// Le plat composé, sous forme de recette complète (ingrédients pour `servings` personnes, étapes, durée).
    static func compose(base: DishPart?, protein: DishPart?, vegetables: [DishPart], flavor: DishPart?,
                        servings: Int) -> Recipe? {
        let picked = [base, protein, flavor].compactMap { $0 } + vegetables
        guard !picked.isEmpty else { return nil }
        var ingredients: [RecipeIngredient] = []
        for part in picked {
            for ingredient in part.ingredients where !ingredients.contains(where: { $0.name == ingredient.name }) {
                ingredients.append(ingredient)
            }
        }
        ingredients.append(I("Huile d'olive", 0.5, "c. à soupe", pantry: true))
        ingredients.append(I("Sel, poivre", pantry: true))

        var steps: [String] = []
        if let base { steps.append(base.step) }
        let vegetableMinutes = vegetables.map(\.minutes).max() ?? 0
        if !vegetables.isEmpty {
            let names = vegetables.map { $0.name.lowercased() }
            let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " et " + names.last!
            steps.append("Lavez et coupez \(list) en morceaux, puis faites-les revenir \(vegetableMinutes) min dans une grande poêle avec un filet d'huile ; salez et poivrez.")
        }
        if let protein {
            steps.append(vegetables.isEmpty ? protein.step : protein.step + " Ajoutez-le aux légumes.")
        }
        if let flavor { steps.append(flavor.step) }
        switch base?.id {
        case "riz": steps.append("Servez bien chaud sur le riz.")
        case "pates": steps.append("Mélangez avec les pâtes égouttées et servez bien chaud.")
        case "semoule": steps.append("Servez bien chaud sur la semoule.")
        case "pommes-de-terre": steps.append("Servez bien chaud avec les pommes de terre rôties.")
        case "quinoa": steps.append("Servez bien chaud sur le quinoa.")
        case "pain": steps.append("Servez bien chaud, avec le pain.")
        default: steps.append("Servez bien chaud.")
        }

        let cooking = vegetableMinutes + (protein?.minutes ?? 0) + (flavor?.minutes ?? 0)
        let minutes = max(base?.minutes ?? 0, cooking) + 5
        let id = "compose:" + picked.map(\.id).joined(separator: "+")
        let vegetarian = picked.allSatisfy(\.isVegetarian)
        return Recipe(id: id,
                      name: name(base: base, protein: protein, vegetables: vegetables, flavor: flavor),
                      emoji: protein?.emoji ?? vegetables.first?.emoji ?? base?.emoji ?? "🍽️",
                      course: .main,
                      minutes: minutes,
                      servings: 1,
                      tags: vegetarian ? [.light] : [],
                      protein: protein?.id,
                      summary: "Votre plat, composé sur mesure.",
                      ingredients: ingredients,
                      steps: steps)
    }

    /// Une idée au hasard : un féculent, une protéine, deux légumes et une saveur.
    static func surprise<G: RandomNumberGenerator>(vegetarian: Bool, using rng: inout G)
        -> (base: DishPart?, protein: DishPart?, vegetables: [DishPart], flavor: DishPart?) {
        let base = parts(.base).randomElement(using: &rng)
        let protein = parts(.protein, vegetarian: vegetarian).randomElement(using: &rng)
        let vegetables = Array(parts(.vegetable).shuffled(using: &rng).prefix(2))
        let flavor = parts(.flavor).randomElement(using: &rng)
        return (base, protein, vegetables, flavor)
    }
}
