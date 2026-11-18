import XCTest
@testable import Lemwincher

/// Sans porc : noms de produits, catégories et ingrédients Open Food Facts.
final class DietTests: XCTestCase {
    func testPorkProductsAreDetected() {
        let pork = ["Jambon blanc", "Lardons fumés", "Saucisson sec", "Pâté de campagne", "Côtes de porc",
                    "Pizza jambon fromage", "Saucisses de Strasbourg", "Knacki", "Chorizo doux", "Poitrine fumée",
                    "Rillettes du Mans", "Gélatine porcine"]
        for name in pork {
            XCTAssertTrue(DietFilter.isPork(name: name), name)
        }
    }

    func testPorkFreeVersionsAndLookalikesStay() {
        let fine = ["Jambon de dinde", "Lardons de volaille", "Chorizo de bœuf halal", "Rillettes de thon",
                    "Pâtes coquillettes", "Knacki de poulet", "Merguez", "Cèpes porcini séchés", "Poitrine de poulet",
                    "Saucisses végétales", "Pâté végétal", "Bœuf haché 5 %", "Nutella"]
        for name in fine {
            XCTAssertFalse(DietFilter.isPork(name: name), name)
        }
    }

    func testCategoriesAndIngredients() {
        XCTAssertTrue(DietFilter.isPork(name: "Plat cuisiné", categories: ["en:meals", "en:pork-meals"]))
        XCTAssertTrue(DietFilter.isPork(name: "Tranches fines", categories: ["en:hams"]))
        XCTAssertFalse(DietFilter.isPork(name: "Tranches de poulet", categories: ["en:hams"]))

        XCTAssertTrue(DietFilter.porkIngredients(["en:wheat-flour", "en:pork-fat"]))
        XCTAssertTrue(DietFilter.porkIngredients(["en:bacon"]))
        XCTAssertFalse(DietFilter.porkIngredients(["en:chicken-ham", "en:salt"]))
        XCTAssertTrue(DietFilter.unspecifiedGelatin(["en:sugar", "en:gelatin"]))
        XCTAssertFalse(DietFilter.unspecifiedGelatin(["en:sugar"]))

        let ham = Product(code: "1", name: "Jambon supérieur")
        XCTAssertFalse(DietFilter.allows(ham, noPork: true))
        XCTAssertTrue(DietFilter.allows(ham, noPork: false))
        XCTAssertTrue(DietFilter.isMeatOrFish("Blancs de poulet"))
        XCTAssertFalse(DietFilter.isMeatOrFish("Lentilles corail"))
    }
}

final class RecipeTests: XCTestCase {
    private func recipe(_ id: String) throws -> Recipe {
        try XCTUnwrap(RecipeBook.recipe(id: id), id)
    }

    func testBookIsPorkFreeAndWellFormed() {
        XCTAssertGreaterThanOrEqual(RecipeBook.all.count, 30)
        XCTAssertEqual(Set(RecipeBook.all.map(\.id)).count, RecipeBook.all.count, "identifiants uniques")
        for recipe in RecipeBook.all {
            XCTAssertFalse(recipe.containsPork, recipe.name)
            XCTAssertFalse(recipe.steps.isEmpty, recipe.name)
            XCTAssertGreaterThanOrEqual(recipe.ingredients.count, 2, recipe.name)
            XCTAssertGreaterThan(recipe.servings, 0, recipe.name)
            XCTAssertGreaterThan(recipe.minutes, 0, recipe.name)
            XCTAssertFalse(recipe.summary.isEmpty, recipe.name)
        }
        XCTAssertTrue(RecipeBook.all.contains { $0.course == .dessert })
        XCTAssertTrue(RecipeBook.all.contains { $0.course == .breakfast })
    }

    func testVegetarianDetection() throws {
        XCTAssertTrue(try recipe("dahl-lentilles").isVegetarian)
        XCTAssertTrue(try recipe("crepes").isVegetarian)
        XCTAssertFalse(try recipe("spaghetti-bolognaise").isVegetarian)
        XCTAssertFalse(try recipe("quiche-dinde").isVegetarian, "lardons de dinde = viande")
        XCTAssertFalse(try recipe("gratin-pates-thon").isVegetarian, "thon = poisson")
        let vegetarian = RecipeEngine.allowed(RecipeBook.all, noPork: true, vegetarian: true)
        XCTAssertFalse(vegetarian.isEmpty)
        XCTAssertTrue(vegetarian.allSatisfy(\.isVegetarian))
    }

    func testAmountsForOneTwoOrFourPeople() throws {
        let bolognaise = try recipe("spaghetti-bolognaise")
        let beef = try XCTUnwrap(bolognaise.ingredients.first { $0.name == "Bœuf haché" })
        XCTAssertEqual(beef.amount(scale: bolognaise.scale(for: 1)), "100 g")
        XCTAssertEqual(beef.amount(scale: bolognaise.scale(for: 2)), "200 g")
        let garlic = try XCTUnwrap(bolognaise.ingredients.first { $0.name == "Ail" })
        XCTAssertEqual(garlic.amount(scale: bolognaise.scale(for: 1)), "½ gousse")
        XCTAssertEqual(garlic.amount(scale: 1), "2 gousses")

        let omelette = try recipe("omelette-champignons")
        let eggs = try XCTUnwrap(omelette.ingredients.first { $0.name == "Œufs" })
        XCTAssertEqual(eggs.amount(scale: omelette.scale(for: 1)), "3", "recette pour 2, cuisinée pour 1")
        XCTAssertEqual(omelette.ingredients.first { $0.name == "Sel, poivre" }?.amount(scale: 1), "")

        XCTAssertEqual(RecipeFormat.amount(1200, unit: "g"), "1,2 kg")
        XCTAssertEqual(RecipeFormat.amount(500, unit: "ml"), "50 cl")
        XCTAssertEqual(RecipeFormat.amount(1000, unit: "ml"), "1 L")
        XCTAssertEqual(RecipeFormat.amount(50, unit: "ml"), "50 ml")
        XCTAssertEqual(RecipeFormat.amount(0.5, unit: "c. à soupe"), "½ c. à soupe")
        XCTAssertEqual(RecipeFormat.count(1.5), "1 ½")
        XCTAssertEqual(RecipeFormat.count(0.75), "¾")
        XCTAssertEqual(RecipeFormat.count(0.1), "¼")
        XCTAssertEqual(RecipeFormat.count(2.2), "2")
        XCTAssertEqual(RecipeFormat.count(7.4), "7")
    }

    func testDurations() {
        XCTAssertEqual(RecipeFormat.duration(35), "35 min")
        XCTAssertEqual(RecipeFormat.duration(60), "1 h")
        XCTAssertEqual(RecipeFormat.duration(75), "1 h 15")
        XCTAssertEqual(RecipeFormat.duration(65), "1 h 05")
    }

    func testTimersFoundInSteps() {
        XCTAssertEqual(RecipeEngine.timers(in: "Enfournez 1 h 15 en arrosant le poulet de son jus toutes les 20 min.").map(\.seconds),
                       [4500, 1200])
        XCTAssertEqual(RecipeEngine.timers(in: "Faites cuire les steaks hachés 2 à 4 min par face.").map(\.seconds), [120],
                       "« 2 à 4 min » : la plus courte, pour surveiller")
        XCTAssertEqual(RecipeEngine.timers(in: "Préchauffez le four à 200 °C.").count, 0)
        XCTAssertEqual(RecipeEngine.timers(in: "Réservez au moins 3 h au réfrigérateur.").map(\.seconds), [10_800])
        XCTAssertEqual(RecipeEngine.timers(in: "Faites cuire les œufs 10 min, les pommes de terre 20 min et les haricots 8 min.").map(\.seconds),
                       [600, 1200, 480])
        XCTAssertEqual(StepTimer(seconds: 4500).label, "1 h 15")
        XCTAssertEqual(StepTimer(seconds: 1200).label, "20 min")
        // Toutes les étapes du livre donnent des minuteurs raisonnables.
        for recipe in RecipeBook.all {
            for step in recipe.steps {
                XCTAssertTrue(RecipeEngine.timers(in: step).allSatisfy { $0.seconds >= 60 && $0.seconds <= 4 * 3600 }, step)
            }
        }
    }

    func testIngredientsMentionedInAStep() throws {
        let curry = try recipe("curry-poulet")
        let used = RecipeEngine.ingredients(of: "Versez le lait de coco, salez et laissez mijoter 15 min à feu doux.", in: curry)
        XCTAssertEqual(used.map(\.name), ["Lait de coco"])
        let first = RecipeEngine.ingredients(of: curry.steps[0], in: curry).map(\.name)
        XCTAssertTrue(first.contains("Blancs de poulet"))
        XCTAssertTrue(first.contains("Ail"))
        XCTAssertFalse(first.contains("Sel, poivre"), "le placard n'est pas rappelé")
    }

    func testWhatIsAlreadyInTheList() throws {
        let list = ["Œufs", "Poulet", "Riz basmati"]
        XCTAssertTrue(RecipeEngine.isInList("Œufs", listNames: list))
        XCTAssertTrue(RecipeEngine.isInList("Poulet", listNames: list))
        XCTAssertTrue(RecipeEngine.isInList("Riz", listNames: list), "« Riz basmati » couvre « Riz »")
        XCTAssertFalse(RecipeEngine.isInList("Farine", listNames: list))

        let curry = try recipe("curry-poulet")
        let missing = RecipeEngine.missing(curry, listNames: list).map(\.shopping)
        XCTAssertFalse(missing.contains("Poulet"))
        XCTAssertFalse(missing.contains("Riz"))
        XCTAssertTrue(missing.contains("Lait de coco"))
        XCTAssertEqual(RecipeEngine.matchCount(curry, listNames: list), 2)

        let suggested = RecipeEngine.suggested(RecipeBook.all, listNames: ["Œufs", "Champignons", "Persil", "Beurre"])
        XCTAssertEqual(suggested.first?.id, "omelette-champignons", "tous ses ingrédients sont dans la liste")
        XCTAssertTrue(RecipeEngine.suggested(RecipeBook.all, listNames: []).isEmpty)
    }

    func testSearchByNameOrIngredient() {
        XCTAssertTrue(RecipeEngine.search(RecipeBook.all, query: "courgette").contains { $0.id == "ratatouille" })
        XCTAssertTrue(RecipeEngine.search(RecipeBook.all, query: "Tajine").contains { $0.id == "tajine-poulet" })
        XCTAssertEqual(RecipeEngine.search(RecipeBook.all, query: "  ").count, RecipeBook.all.count)
    }

    func testWeekMenuIsVariedAndCheapFirst() {
        var rng = SeededGenerator(seed: 42)
        let menu = RecipeEngine.weekMenu(from: RecipeBook.all, count: 5, cheapFirst: true, using: &rng)
        XCTAssertEqual(menu.count, 5)
        XCTAssertTrue(menu.allSatisfy { $0.course == .main })
        XCTAssertEqual(Set(menu.map(\.id)).count, 5)
        XCTAssertEqual(Set(menu.compactMap(\.protein)).count, 5, "un ingrédient principal différent chaque jour")
        XCTAssertTrue(menu.allSatisfy { $0.tags.contains(.cheap) })

        var again = SeededGenerator(seed: 42)
        XCTAssertEqual(RecipeEngine.weekMenu(from: RecipeBook.all, count: 5, cheapFirst: true, using: &again).map(\.id),
                       menu.map(\.id), "même graine, même menu")

        let vegetarian = RecipeEngine.allowed(RecipeBook.all, noPork: true, vegetarian: true)
        var rng2 = SeededGenerator(seed: 7)
        XCTAssertTrue(RecipeEngine.weekMenu(from: vegetarian, count: 4, cheapFirst: false, using: &rng2).allSatisfy(\.isVegetarian))

        var rng3 = SeededGenerator(seed: 3)
        let other = RecipeEngine.replacement(for: menu[0], in: menu, from: RecipeBook.all, using: &rng3)
        XCTAssertNotNil(other)
        XCTAssertFalse(menu.contains(other!))
        XCTAssertEqual(other?.course, .main)
    }

    func testShoppingForSeveralRecipes() throws {
        let names = RecipeEngine.shoppingNames(for: [try recipe("spaghetti-bolognaise"), try recipe("chili-con-carne")],
                                               listNames: ["Oignons"])
        XCTAssertFalse(names.contains("Oignons"), "déjà dans la liste")
        XCTAssertEqual(names.filter { $0 == "Bœuf haché" }.count, 1, "sans doublon")
        XCTAssertEqual(names.filter { $0 == "Ail" }.count, 1)
        XCTAssertFalse(names.contains("Huile d'olive"), "placard")
        XCTAssertTrue(names.contains("Haricots rouges"))
    }

    func testShareText() throws {
        let text = try recipe("crepes").shareText(people: 2)
        XCTAssertTrue(text.hasPrefix("🥞 Crêpes — pour 2 personnes"))
        XCTAssertTrue(text.contains("• Farine : 125 g"))
        XCTAssertTrue(text.contains("1. Mélangez la farine"))
    }

    func testOldSettingsGetPorkFreeAndOnePerson() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Fixtures.json(#"{"radiusKm": 5}"#))
        XCTAssertTrue(settings.noPork)
        XCTAssertFalse(settings.vegetarian)
        XCTAssertEqual(settings.defaultServings, 1)
        let state = try JSONDecoder().decode(PersistedState.self, from: Fixtures.json(#"{"shoppingList": []}"#))
        XCTAssertTrue(state.favoriteRecipes.isEmpty)
        XCTAssertTrue(state.weekMenu.isEmpty)
    }
}

final class DishComposerTests: XCTestCase {
    private func part(_ list: [DishPart], _ id: String) throws -> DishPart {
        try XCTUnwrap(list.first { $0.id == id }, id)
    }

    func testComposedDish() throws {
        let recipe = try XCTUnwrap(DishComposer.compose(base: try part(DishComposer.bases, "riz"),
                                                        protein: try part(DishComposer.proteins, "poulet"),
                                                        vegetables: [try part(DishComposer.vegetables, "courgette"),
                                                                     try part(DishComposer.vegetables, "carotte")],
                                                        flavor: try part(DishComposer.flavors, "curry-coco"),
                                                        servings: 1))
        XCTAssertEqual(recipe.name, "Poulet au curry et lait de coco, avec riz, courgettes et carottes")
        XCTAssertEqual(recipe.steps.count, 5)
        XCTAssertEqual(recipe.minutes, 36)
        XCTAssertFalse(recipe.isVegetarian)
        XCTAssertFalse(recipe.containsPork)
        let rice = try XCTUnwrap(recipe.ingredients.first { $0.name == "Riz" })
        XCTAssertEqual(rice.amount(scale: recipe.scale(for: 2)), "150 g")
        XCTAssertTrue(recipe.ingredients.contains { $0.pantry })
        XCTAssertTrue(recipe.id.hasPrefix("compose:"))
    }

    func testVegetarianAndEmptyDishes() throws {
        let eggs = try XCTUnwrap(DishComposer.compose(base: nil, protein: try part(DishComposer.proteins, "oeufs"),
                                                      vegetables: [], flavor: nil, servings: 1))
        XCTAssertEqual(eggs.name, "Œufs")
        XCTAssertTrue(eggs.isVegetarian)
        XCTAssertNil(DishComposer.compose(base: nil, protein: nil, vegetables: [], flavor: nil, servings: 1))
        XCTAssertTrue(DishComposer.parts(.protein, vegetarian: true).allSatisfy(\.isVegetarian))
        XCTAssertFalse(DishComposer.parts(.protein, vegetarian: true).contains { $0.id == "poulet" })

        var rng = SeededGenerator(seed: 11)
        for _ in 0..<20 {
            let idea = DishComposer.surprise(vegetarian: true, using: &rng)
            XCTAssertTrue(idea.protein?.isVegetarian ?? true)
            XCTAssertEqual(idea.vegetables.count, 2)
        }
    }
}

final class AdditivesAndPromotionsTests: XCTestCase {
    func testAdditiveCodesAndNames() {
        XCTAssertEqual(Additives.code(fromTag: "en:e322i"), "E322i")
        XCTAssertEqual(Additives.code(fromTag: "en:e1105"), "E1105")
        XCTAssertNil(Additives.code(fromTag: "en:sugar"))
        XCTAssertEqual(Additives.baseCode("E472e"), "E472")
        XCTAssertTrue(Additives.isPossiblyAnimal("E471"))
        XCTAssertTrue(Additives.isPossiblyAnimal("E472e"))
        XCTAssertFalse(Additives.isPossiblyAnimal("E330"))
        XCTAssertEqual(Additives.label("E330"), "E330 (acide citrique)")
        XCTAssertEqual(Additives.label("E322i"), "E322i (lécithines)")
        XCTAssertEqual(Additives.label("E999"), "E999")
    }

    func testPromotionsFromRealReadings() {
        let now = Fixtures.day(40)
        let observations = [
            Fixtures.obs(3.29, store: "NODE:1", date: Fixtures.day(30)),
            Fixtures.obs(2.49, store: "NODE:1", date: Fixtures.day(38), discounted: true),
            Fixtures.obs(1.99, store: "NODE:2", date: Fixtures.day(39), discounted: true),
            Fixtures.obs(1.50, store: "NODE:3", date: Fixtures.day(1), discounted: true),   // trop ancienne
            Fixtures.obs(2.90, store: "NODE:4", date: Fixtures.day(39)),                     // pas en promo
        ]
        let promos = PriceEngine.promotions(in: observations, now: now)
        XCTAssertEqual(promos.map(\.observation.storeKey), ["NODE:2", "NODE:1"], "la moins chère d'abord, plus de 30 jours écartées")
        XCTAssertNil(promos[0].regularPrice)
        XCTAssertNil(promos[0].discountPercent)
        XCTAssertEqual(promos[1].regularPrice ?? 0, 3.29, accuracy: 1e-9, "prix habituel du même magasin")
        XCTAssertEqual(promos[1].discountPercent, 24)
        XCTAssertTrue(PriceEngine.promotions(in: [], now: now).isEmpty)
    }

    func testProductInformationForAScan() throws {
        let json = """
        {"product": {"additives_tags": ["en:e322", "en:e322i", "en:e471", "en:e330"],
          "ingredients_analysis_tags": ["en:palm-oil", "en:non-vegan", "en:vegetarian"],
          "stores": "Carrefour, E.Leclerc", "manufacturing_places": "Villers-Écalles, France",
          "categories": "Petit-déjeuners, Produits à tartiner, Pâtes à tartiner aux noisettes",
          "ingredients_text": "Sucre, huile de palme, noisettes"}}
        """
        let facts = try XCTUnwrap(try JSONDecoder().decode(OpenFoodFactsAPI.FactsResponse.self, from: Fixtures.json(json)).product?.facts)
        XCTAssertEqual(facts.additives, ["E322", "E322i", "E471", "E330"])
        XCTAssertEqual(facts.possiblyAnimalAdditives, ["E471"])
        XCTAssertEqual(facts.isVegan, false)
        XCTAssertEqual(facts.isVegetarian, true)
        XCTAssertEqual(facts.stores, "Carrefour, E.Leclerc")
        XCTAssertEqual(facts.manufacturingPlaces, "Villers-Écalles, France")
        XCTAssertEqual(facts.category, "Pâtes à tartiner aux noisettes")
        XCTAssertTrue(facts.hasDescription)

        let vegan = try XCTUnwrap(try JSONDecoder().decode(OpenFoodFactsAPI.FactsResponse.self, from: Fixtures.json(
            #"{"product": {"additives_tags": ["en:e471"], "ingredients_analysis_tags": ["en:vegan"]}}"#)).product?.facts)
        XCTAssertEqual(vegan.isVegan, true)
        XCTAssertTrue(vegan.possiblyAnimalAdditives.isEmpty, "végan : E471 forcément végétal")
    }
}

final class ProductDescriptionTests: XCTestCase {
    func testDescriptionAndNutrition() throws {
        let json = """
        {"product": {"nutriscore_grade": "e", "nova_group": 4,
          "generic_name_fr": "Pâte à tartiner aux noisettes et au cacao",
          "ingredients_text_fr": "Sucre, huile de palme, _noisettes_ 13 %, cacao maigre 7,4 %, _lait_ écrémé en poudre",
          "origins": "", "conservation_conditions_fr": "À conserver dans un endroit frais et sec.",
          "ingredients_tags": ["en:sugar", "en:palm-oil", "en:hazelnut"],
          "allergens_tags": ["en:milk", "en:nuts"], "labels_tags": [],
          "nutriments": {"energy-kcal_100g": 539, "fat_100g": 30.9, "saturated-fat_100g": "10.6",
                         "sugars_100g": 56.3, "proteins_100g": 6.3, "salt_100g": 0.107}}}
        """
        let response = try JSONDecoder().decode(OpenFoodFactsAPI.FactsResponse.self, from: Fixtures.json(json))
        let facts = try XCTUnwrap(response.product?.facts)
        XCTAssertEqual(facts.genericName, "Pâte à tartiner aux noisettes et au cacao")
        XCTAssertEqual(facts.ingredientsText, "Sucre, huile de palme, noisettes 13 %, cacao maigre 7,4 %, lait écrémé en poudre")
        XCTAssertNil(facts.origins, "champ vide")
        XCTAssertEqual(facts.conservation, "À conserver dans un endroit frais et sec.")
        XCTAssertEqual(facts.allergens, ["lait", "fruits à coque"])
        XCTAssertEqual(facts.nutrition.saturatedFat ?? 0, 10.6, accuracy: 1e-9, "nombre écrit en texte")
        XCTAssertEqual(facts.nutrition.rows.map(\.label),
                       ["Énergie", "Matières grasses", "dont acides gras saturés", "dont sucres", "Protéines", "Sel"])
        XCTAssertEqual(facts.nutrition.rows.map(\.value), ["539 kcal", "31 g", "11 g", "56 g", "6,3 g", "0,1 g"])
        XCTAssertTrue(facts.hasDescription)
        XCTAssertFalse(facts.containsPork)
        XCTAssertFalse(facts.unspecifiedGelatin)
    }

    func testPorkAndGelatinInIngredients() throws {
        let pork = try JSONDecoder().decode(OpenFoodFactsAPI.FactsResponse.self, from: Fixtures.json(
            #"{"product": {"ingredients_tags": ["en:wheat-flour", "en:pork-fat"], "ingredients_text": "Farine, graisse de porc"}}"#))
        XCTAssertEqual(pork.product?.facts.containsPork, true)

        let gelatin = try JSONDecoder().decode(OpenFoodFactsAPI.FactsResponse.self, from: Fixtures.json(
            #"{"product": {"ingredients_tags": ["en:sugar", "en:gelatin"], "ingredients_text": "Sucre, gélatine"}}"#))
        XCTAssertEqual(gelatin.product?.facts.containsPork, false)
        XCTAssertEqual(gelatin.product?.facts.unspecifiedGelatin, true)
    }
}
