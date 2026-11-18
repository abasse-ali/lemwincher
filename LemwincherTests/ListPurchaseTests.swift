import XCTest
@testable import Lemwincher

/// « Ma liste » : cocher un article = acheté = une dépense du mois.
final class ListPurchaseTests: XCTestCase {
    private let eggs = ShoppingItem(product: .custom(named: "Œufs"), quantity: 2)
    private let milk = ShoppingItem(product: .custom(named: "Lait"))
    private let aldi = Fixtures.store("NODE:7", name: "Aldi Toulouse", brand: "Aldi")
    private let lidl = Fixtures.store("NODE:8", name: "Lidl Minimes", brand: "Lidl")
    private let leclerc = Fixtures.store("NODE:9", name: "E.Leclerc Blagnac", brand: "E.Leclerc")

    private func line(_ item: ShoppingItem, _ price: Double, at store: Store) -> BasketLine {
        BasketLine(item: item, price: price, currency: "EUR", isEstimate: false, storeKey: store.id, storeName: store.name)
    }

    /// Meilleur magasin : Aldi (les deux produits) ; Lidl n'a que les œufs, moins chers.
    private var basket: BasketResult {
        BasketResult(stores: [
            StoreBasket(storeKey: aldi.id, storeName: aldi.name, store: aldi,
                        lines: [line(eggs, 2.29, at: aldi), line(milk, 0.99, at: aldi)]),
            StoreBasket(storeKey: lidl.id, storeName: lidl.name, store: lidl,
                        lines: [line(eggs, 1.95, at: lidl)], missing: [milk]),
        ])
    }

    func testPriceWhereYouAre() throws {
        let quote = basket.purchaseQuote(for: eggs.id, here: lidl)
        XCTAssertEqual(try XCTUnwrap(quote.unitPrice), 1.95, accuracy: 1e-9)
        XCTAssertEqual(quote.store?.id, lidl.id)
    }

    func testUnknownPriceWhereYouAreIsAskedWithAHint() throws {
        let quote = basket.purchaseQuote(for: milk.id, here: lidl)
        XCTAssertNil(quote.unitPrice, "pas de prix du lait chez Lidl : on demande le montant")
        XCTAssertEqual(quote.storeName, "Lidl Minimes")
        XCTAssertEqual(try XCTUnwrap(quote.hint), 0.99, accuracy: 1e-9, "pré-rempli avec le prix connu ailleurs")

        let elsewhere = basket.purchaseQuote(for: eggs.id, here: leclerc)
        XCTAssertNil(elsewhere.unitPrice)
        XCTAssertEqual(try XCTUnwrap(elsewhere.hint), 1.95, accuracy: 1e-9, "le prix connu le plus bas")
    }

    func testWithoutPositionTheBestStoreOfTheBasketIsUsed() throws {
        let quote = basket.purchaseQuote(for: eggs.id, here: nil)
        XCTAssertEqual(try XCTUnwrap(quote.unitPrice), 2.29, accuracy: 1e-9)
        XCTAssertEqual(quote.store?.id, aldi.id)
    }

    func testCheapestStoreWhenTheBestStoreLacksTheProduct() throws {
        let cheese = ShoppingItem(product: .custom(named: "Comté"))
        var result = basket
        result.stores[1].lines.append(line(cheese, 4.50, at: lidl))
        let quote = result.purchaseQuote(for: cheese.id, here: nil)
        XCTAssertEqual(try XCTUnwrap(quote.unitPrice), 4.50, accuracy: 1e-9)
        XCTAssertEqual(quote.storeName, "Lidl Minimes")

        let unknown = result.purchaseQuote(for: UUID(), here: nil)
        XCTAssertNil(unknown.unitPrice)
        XCTAssertNil(unknown.hint)
        XCTAssertNil(unknown.store)
    }

    func testPurchaseExpense() {
        var item = eggs
        item.choice = Product(code: "custom:6 oeufs bio picota", name: "6 œufs bio")
        let date = Fixtures.day(3)
        let expense = BudgetEngine.purchase(of: item, amount: 4.579, storeName: nil, store: aldi, date: date)
        XCTAssertEqual(expense.amount, 4.58, accuracy: 1e-9, "au centime")
        XCTAssertEqual(expense.storeName, "Aldi Toulouse")
        XCTAssertEqual(expense.storeID, aldi.id)
        XCTAssertEqual(expense.chainKey, "aldi")
        XCTAssertEqual(expense.category, .groceries)
        XCTAssertEqual(expense.note, "2 × 6 œufs bio", "le produit choisi, pas l'article générique")
        XCTAssertEqual(expense.itemCount, 2)
        XCTAssertEqual(expense.date, date)

        let typed = BudgetEngine.purchase(of: milk, amount: 1.2, storeName: "Marché", store: nil)
        XCTAssertEqual(typed.storeName, "Marché")
        XCTAssertNil(typed.storeID)
        XCTAssertEqual(typed.note, "Lait")
    }

    func testQuantityChangeRescalesTheExpense() {
        let expense = BudgetEngine.purchase(of: eggs, amount: 4.58, storeName: nil, store: aldi)
        let three = BudgetEngine.rescaled(expense, from: 2, to: 3, name: "Œufs")
        XCTAssertEqual(three.amount, 6.87, accuracy: 1e-9)
        XCTAssertEqual(three.itemCount, 3)
        XCTAssertEqual(three.note, "3 × Œufs")
        XCTAssertEqual(three.id, expense.id, "même dépense, mise à jour")
        let one = BudgetEngine.rescaled(three, from: 3, to: 1, name: "Œufs")
        XCTAssertEqual(one.amount, 2.29, accuracy: 1e-9)
        XCTAssertEqual(one.note, "Œufs")
        XCTAssertEqual(BudgetEngine.rescaled(expense, from: 0, to: 3, name: "Œufs"), expense)
    }

    func testOldListItemsHaveNoExpense() throws {
        let json = #"{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "product": {"code": "custom:lait", "name": "Lait"}, "quantity": 1, "checked": true}"#
        let item = try JSONDecoder().decode(ShoppingItem.self, from: Fixtures.json(json))
        XCTAssertTrue(item.checked)
        XCTAssertNil(item.expenseID)

        var linked = item
        linked.expenseID = UUID()
        let data = try JSONEncoder().encode(linked)
        XCTAssertEqual(try JSONDecoder().decode(ShoppingItem.self, from: data).expenseID, linked.expenseID)
    }
}
