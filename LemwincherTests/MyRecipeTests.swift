import XCTest
@testable import Lemwincher

/// « Mes recettes » : recettes écrites ou personnalisées, enregistrées, sauvegardées, et recette collée.
final class MyRecipeTests: XCTestCase {
    func testMyRecipeBecomesARecipe() {
        var mine = MyRecipe()
        mine.name = "  Pâtes au thon "
        mine.emoji = "🍝"
        mine.servings = 2
        mine.minutes = 20
        mine.ingredients = [
            MyIngredient(name: "Pâtes", quantity: 0.25, unit: "kg"),
            MyIngredient(name: "Thon", quantity: 1, unit: "boîte"),
            MyIngredient(name: "Crème", quantity: 20, unit: "cl"),
            MyIngredient(name: "Sel, poivre", pantry: true),
            MyIngredient(name: "   "),
        ]
        mine.steps = ["Faites cuire les pâtes 10 min.", "  ", "Mélangez avec le thon et la crème."]
        let recipe = mine.recipe
        XCTAssertTrue(recipe.isMine)
        XCTAssertEqual(recipe.id, "mine:" + mine.id.uuidString)
        XCTAssertEqual(recipe.name, "Pâtes au thon")
        XCTAssertEqual(recipe.ingredients.map(\.name), ["Pâtes", "Thon", "Crème", "Sel, poivre"], "lignes vides ignorées")
        XCTAssertEqual(recipe.ingredients[0].quantity ?? 0, 250, accuracy: 1e-9, "kg -> g")
        XCTAssertEqual(recipe.ingredients[0].unit, "g")
        XCTAssertEqual(recipe.ingredients[2].quantity ?? 0, 200, accuracy: 1e-9, "cl -> ml")
        XCTAssertEqual(recipe.ingredients[2].amount(scale: recipe.scale(for: 4)), "40 cl", "recalculée pour 4")
        XCTAssertEqual(recipe.shoppingIngredients.count, 3, "le placard n'est pas acheté")
        XCTAssertEqual(recipe.steps, ["Faites cuire les pâtes 10 min.", "Mélangez avec le thon et la crème."])
        XCTAssertEqual(recipe.protein, "thon")
        XCTAssertFalse(recipe.isVegetarian)
        XCTAssertFalse(RecipeBook.all.contains { $0.isMine })

        var twice = MyRecipe()
        twice.ingredients = [MyIngredient(name: "Beurre", quantity: 100, unit: "g"),
                             MyIngredient(name: "Beurre", quantity: 10, unit: "g")]
        XCTAssertEqual(twice.recipe.ingredients.map(\.name), ["Beurre", "Beurre (2)"], "deux lignes restent distinctes")
        XCTAssertEqual(twice.recipe.name, "Ma recette", "sans nom")
    }

    func testCopyingAnAppRecipeKeepsEverything() throws {
        let original = try XCTUnwrap(RecipeBook.recipe(id: "omelette-champignons"))
        let copy = MyRecipe(copying: original)
        XCTAssertEqual(copy.basedOn, "omelette-champignons")
        let recipe = copy.recipe
        XCTAssertEqual(recipe.name, original.name)
        XCTAssertEqual(recipe.ingredients, original.ingredients)
        XCTAssertEqual(recipe.steps, original.steps)
        XCTAssertEqual(recipe.servings, original.servings)
        XCTAssertNotEqual(recipe.id, original.id)
        XCTAssertNil(MyRecipe(copying: recipe).basedOn, "dupliquer une des miennes")
        XCTAssertEqual(copy.contentSignature, MyRecipe(copying: original).contentSignature)
    }

    func testModelSavesListsAndDeletesMyRecipes() {
        let model = AppModel(arguments: ["-uitest"])
        model.state.settings.noPork = true
        var mine = MyRecipe()
        mine.name = "Gratin maison"
        mine.ingredients = [MyIngredient(name: "Pommes de terre", quantity: 1, unit: "kg")]
        model.saveMyRecipe(mine)
        let id = mine.recipeID
        XCTAssertEqual(model.recipes.first?.id, id, "mes recettes d'abord")
        XCTAssertEqual(model.recipe(id: id)?.name, "Gratin maison")
        XCTAssertEqual(model.recipe(id: "omelette-champignons")?.name, "Omelette aux champignons")

        mine.name = "Gratin dauphinois"
        model.saveMyRecipe(mine)
        XCTAssertEqual(model.state.myRecipes.count, 1, "modifiée, pas dupliquée")
        XCTAssertEqual(model.recipe(id: id)?.name, "Gratin dauphinois")
        XCTAssertNotNil(model.myRecipe(for: id))
        XCTAssertNil(model.myRecipe(for: "omelette-champignons"))

        model.toggleFavorite(recipe: id)
        model.state.weekMenu = [id]
        XCTAssertEqual(model.weekMenu.map(\.id), [id], "utilisable dans le menu de la semaine")
        model.deleteMyRecipe(mine.id)
        XCTAssertNil(model.recipe(id: id))
        XCTAssertFalse(model.isFavorite(recipe: id))
        XCTAssertTrue(model.state.weekMenu.isEmpty)
    }

    func testMyRecipesArePersistedAndBackedUp() throws {
        var state = PersistedState()
        var mine = MyRecipe()
        mine.name = "Crêpes"
        mine.course = .dessert
        mine.tags = [.cheap, .family]
        mine.ingredients = [MyIngredient(name: "Farine", quantity: 250, unit: "g"),
                            MyIngredient(name: "Lait", quantity: 0.5, unit: "L")]
        mine.steps = ["Mélangez.", "Laissez reposer 1 h."]
        state.myRecipes = [mine]
        let restored = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.myRecipes, [mine])
        let old = try JSONDecoder().decode(PersistedState.self, from: Fixtures.json(#"{"shoppingList": []}"#))
        XCTAssertTrue(old.myRecipes.isEmpty)

        var other = PersistedState()
        let summary = Backup.merge(state, into: &other)
        XCTAssertEqual(other.myRecipes.count, 1)
        XCTAssertTrue(summary.text.contains("1 recette"), summary.text)
        XCTAssertEqual(Backup.merge(state, into: &other).recipes, 0, "pas de doublon")

        let tolerant = try JSONDecoder().decode(MyRecipe.self, from: Fixtures.json(
            #"{"name": "X", "tags": ["cheap", "inconnu"], "ingredients": [{"name": "Lait"}, {"autre": 1}]}"#))
        XCTAssertEqual(tolerant.tags, [.cheap])
        XCTAssertEqual(tolerant.recipe.ingredients.map(\.name), ["Lait"])
    }

    func testQuantitiesAndUnits() {
        XCTAssertEqual(MyIngredient.parseQuantity("1,5") ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(MyIngredient.parseQuantity("½") ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(MyIngredient.parseQuantity("1 ½") ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(MyIngredient.parseQuantity("1/2") ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(MyIngredient.parseQuantity("deux") ?? 0, 2, accuracy: 1e-9)
        XCTAssertNil(MyIngredient.parseQuantity("beaucoup"))
        XCTAssertNil(MyIngredient.parseQuantity(""))
        XCTAssertEqual(MyIngredient.editable(1500, unit: "g").text, "1,5")
        XCTAssertEqual(MyIngredient.editable(1500, unit: "g").unit, "kg")
        XCTAssertEqual(MyIngredient.editable(250, unit: "g").text, "250")
        XCTAssertEqual(MyIngredient.editable(nil, unit: "").text, "")
    }

    func testPastedRecipeIsRead() {
        let text = """
        Gâteau au yaourt - Marmiton
        Pour 6 personnes
        Préparation : 10 min
        Cuisson : 35 min

        Ingrédients
        - 1 pot de yaourt nature
        - 3 œufs
        - 200 g de farine
        - 1 sachet de levure chimique
        - 10 cl d'huile
        - Une pincée de sel

        Préparation
        1. Préchauffez le four à 180 °C.
        2. Mélangez le yaourt, les œufs et le sucre.
        Étape 3
        Ajoutez la farine et la levure, puis l'huile.
        4) Versez dans un moule beurré et faites cuire 35 min.
        """
        let result = RecipeTextParser.parse(text)
        XCTAssertEqual(result.name, "Gâteau au yaourt")
        XCTAssertEqual(result.servings, 6)
        XCTAssertEqual(result.minutes, 45, "préparation + cuisson")
        XCTAssertEqual(result.ingredients.map(\.name),
                       ["Pot de yaourt nature", "Œufs", "Farine", "Levure chimique", "Huile", "Sel"])
        XCTAssertEqual(result.ingredients[2].quantity ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(result.ingredients[2].unit, "g")
        XCTAssertEqual(result.ingredients[3].unit, "sachet")
        XCTAssertEqual(result.ingredients[4].quantity ?? 0, 100, accuracy: 1e-9, "10 cl -> 100 ml")
        XCTAssertTrue(result.ingredients[4].pantry, "l'huile est au placard")
        XCTAssertTrue(result.ingredients[5].pantry)
        XCTAssertEqual(result.steps, ["Préchauffez le four à 180 °C.",
                                      "Mélangez le yaourt, les œufs et le sucre.",
                                      "Ajoutez la farine et la levure, puis l'huile.",
                                      "Versez dans un moule beurré et faites cuire 35 min."])
    }

    func testRecipeImageFollowsTheDish() {
        XCTAssertEqual(RecipeEmoji.guess(for: "Pâtes au thon et à la crème"), "🍝", "le plat d'abord, pas la crème")
        XCTAssertEqual(RecipeEmoji.guess(for: "Crème brûlée"), "🍮")
        XCTAssertEqual(RecipeEmoji.guess(for: "Gratin de pommes de terre"), "🥘")
        XCTAssertEqual(RecipeEmoji.guess(for: "Pommes de terre sautées"), "🥔")
        XCTAssertEqual(RecipeEmoji.guess(for: "Tarte aux pommes"), "🥧")
        XCTAssertEqual(RecipeEmoji.guess(for: "Saumon grillé"), "🐟")
        XCTAssertNil(RecipeEmoji.guess(for: "Recette de mamie"))
    }

    func testIngredientLines() {
        func read(_ line: String) -> (String, Double?, String, Bool)? {
            RecipeTextParser.ingredient(from: line).map { ($0.name, $0.quantity, $0.unit, $0.pantry) }
        }
        XCTAssertEqual(read("3 gousses d'ail")?.0, "Ail")
        XCTAssertEqual(read("3 gousses d'ail")?.2, "gousse")
        XCTAssertEqual(read("1 c. à soupe d'huile d'olive")?.2, "c. à soupe")
        XCTAssertEqual(read("1 cuillère à café d’extrait de vanille")?.0, "Extrait de vanille")
        XCTAssertEqual(read("4 gros oignons")?.0, "Gros oignons", "« gros » n'est pas « gr »")
        XCTAssertEqual(read("4 à 5 pommes de terre")?.1, 4)
        XCTAssertEqual(read("1 kg de pommes de terre")?.1, 1000)
        XCTAssertEqual(read("Sel, poivre")?.3, true)
        XCTAssertEqual(read("Eau de fleur d'oranger")?.3, false)
        XCTAssertNil(read("12"), "un nombre seul n'est pas un ingrédient")
    }
}
