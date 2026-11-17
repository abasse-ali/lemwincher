import XCTest
@testable import Lemwincher

final class BudgetTests: XCTestCase {
    private let cal = Fixtures.paris

    private func expense(_ amount: Double, _ date: Date, chain: String? = nil,
                         category: ExpenseCategory = .groceries) -> Expense {
        Expense(amount: amount, date: date, storeName: chain.flatMap { Chain.displayName(for: $0) },
                chainKey: chain, category: category)
    }

    func testPeriodFromFirstOfMonth() {
        let period = BudgetEngine.period(containing: Fixtures.date(2026, 11, 17), startDay: 1, calendar: cal)
        XCTAssertEqual(period.start, Fixtures.date(2026, 11, 1, 0))
        XCTAssertEqual(period.end, Fixtures.date(2026, 12, 1, 0))
        XCTAssertEqual(period.days, 30)
    }

    func testPeriodStartingOnPayday() {
        // Le budget repart le 5 : le 3 janvier appartient à la période du 5 décembre.
        let period = BudgetEngine.period(containing: Fixtures.date(2027, 1, 3), startDay: 5, calendar: cal)
        XCTAssertEqual(period.start, Fixtures.date(2026, 12, 5, 0))
        XCTAssertEqual(period.end, Fixtures.date(2027, 1, 5, 0))
        XCTAssertEqual(period.days, 31)
        XCTAssertTrue(period.contains(Fixtures.date(2027, 1, 4, 23, 59)))
        XCTAssertFalse(period.contains(Fixtures.date(2027, 1, 5, 0, 1)))
        // Jour de départ trop grand : ramené au 28.
        let clamped = BudgetEngine.period(containing: Fixtures.date(2026, 2, 28), startDay: 31, calendar: cal)
        XCTAssertEqual(clamped.start, Fixtures.date(2026, 2, 28, 0))
    }

    func testSummaryOnTrack() {
        let now = Fixtures.date(2026, 11, 16, 18)
        let expenses = [
            expense(20, Fixtures.date(2026, 11, 2)),
            expense(15.5, Fixtures.date(2026, 11, 10)),
            expense(99, Fixtures.date(2026, 10, 28)),     // mois précédent
            expense(50, Fixtures.date(2026, 12, 2)),      // mois suivant
        ]
        let summary = BudgetEngine.summary(expenses: expenses, budget: 100, startDay: 1, now: now, calendar: cal)
        XCTAssertEqual(summary.spent, 35.5, accuracy: 1e-9)
        XCTAssertEqual(summary.remaining, 64.5, accuracy: 1e-9)
        XCTAssertEqual(summary.expenses.count, 2)
        XCTAssertEqual(summary.expenses.first?.amount, 15.5, "les plus récentes d'abord")
        XCTAssertEqual(summary.daysElapsed, 16)
        XCTAssertEqual(summary.daysLeft, 15)
        XCTAssertEqual(summary.dailyAllowance, 64.5 / 15, accuracy: 1e-9)
        XCTAssertEqual(summary.projected, 35.5 / 16 * 30, accuracy: 1e-9)
        XCTAssertEqual(summary.status, .ok)
    }

    func testSummaryWarningAndOver() {
        let now = Fixtures.date(2026, 11, 10)
        let pace = BudgetEngine.summary(expenses: [expense(60, Fixtures.date(2026, 11, 3))],
                                        budget: 100, startDay: 1, now: now, calendar: cal)
        XCTAssertEqual(pace.status, .warning, "60 € en 10 jours : environ 180 € en fin de mois")
        XCTAssertTrue(pace.message(currency: "EUR").contains("rythme"))

        let eighty = BudgetEngine.summary(expenses: [expense(85, Fixtures.date(2026, 11, 3))],
                                          budget: 100, startDay: 1, now: Fixtures.date(2026, 11, 28), calendar: cal)
        XCTAssertEqual(eighty.status, .warning)

        let over = BudgetEngine.summary(expenses: [expense(70, Fixtures.date(2026, 11, 3)), expense(45, Fixtures.date(2026, 11, 9))],
                                        budget: 100, startDay: 1, now: now, calendar: cal)
        XCTAssertEqual(over.status, .over)
        XCTAssertEqual(over.dailyAllowance, 0)
        XCTAssertTrue(over.message(currency: "EUR").hasPrefix("Budget dépassé"))
    }

    func testThresholds() {
        XCTAssertEqual(BudgetEngine.thresholdCrossed(before: 70, after: 85, budget: 100), 80)
        XCTAssertEqual(BudgetEngine.thresholdCrossed(before: 85, after: 101, budget: 100), 100)
        XCTAssertEqual(BudgetEngine.thresholdCrossed(before: 50, after: 120, budget: 100), 100)
        XCTAssertNil(BudgetEngine.thresholdCrossed(before: 85, after: 90, budget: 100))
        XCTAssertNil(BudgetEngine.thresholdCrossed(before: 110, after: 130, budget: 100))
        XCTAssertNil(BudgetEngine.thresholdCrossed(before: 0, after: 10, budget: 0))
    }

    func testHistoryAndCumulative() {
        let now = Fixtures.date(2026, 11, 5)
        let expenses = [
            expense(30, Fixtures.date(2026, 9, 10)),
            expense(80, Fixtures.date(2026, 10, 12)),
            expense(10, Fixtures.date(2026, 11, 1)),
            expense(5, Fixtures.date(2026, 11, 3)),
        ]
        let history = BudgetEngine.history(expenses: expenses, startDay: 1, count: 3, now: now, calendar: cal)
        XCTAssertEqual(history.map(\.total), [30, 80, 15])
        XCTAssertEqual(history.last?.period.start, Fixtures.date(2026, 11, 1, 0))

        let summary = BudgetEngine.summary(expenses: expenses, budget: 100, startDay: 1, now: now, calendar: cal)
        let points = BudgetEngine.cumulative(summary, calendar: cal)
        let spent = points.filter { $0.series == "Dépensé" }.map(\.amount)
        XCTAssertEqual(spent, [10, 10, 15, 15, 15])
        let ideal = points.filter { $0.series == "Rythme idéal" }.map(\.amount)
        XCTAssertEqual(ideal, [0, 100])
    }

    func testShares() {
        let list = [expense(30, Fixtures.date(2026, 11, 2), chain: "lidl"),
                    expense(10, Fixtures.date(2026, 11, 3), chain: "monoprix"),
                    expense(20, Fixtures.date(2026, 11, 4), chain: "lidl")]
        let shares = BudgetEngine.shares(list) { $0.storeName ?? "?" }
        XCTAssertEqual(shares.map(\.name), ["Lidl", "Monoprix"])
        XCTAssertEqual(shares[0].total, 50)
        XCTAssertEqual(shares[0].fraction, 50.0 / 60.0, accuracy: 1e-9)
        XCTAssertTrue(BudgetEngine.shares([]) { $0.note ?? "" }.isEmpty)
    }

    func testSavingsTip() {
        let report = ChainIndexReport(date: Date(), country: "FR", currency: "EUR", productCount: 30, entries: [
            ChainIndexEntry(key: "e leclerc", name: "E.Leclerc", index: 87, productCount: 30),
            ChainIndexEntry(key: "carrefour city", name: "Carrefour City", index: 114, productCount: 30),
            ChainIndexEntry(key: "monoprix", name: "Monoprix", index: 117, productCount: 30),
        ])
        let nearby = [
            "e leclerc": Fixtures.store("WAY:1", name: "E.Leclerc Blagnac", brand: "E.Leclerc"),
            "carrefour city": Fixtures.store("NODE:2", name: "Carrefour City Capitole", brand: "Carrefour City"),
        ]
        let expenses = [
            expense(57, Fixtures.date(2026, 11, 2), chain: "carrefour city"),
            expense(40, Fixtures.date(2026, 11, 5), chain: "e leclerc"),
            expense(20, Fixtures.date(2026, 11, 6), chain: "carrefour city", category: .fuel),
        ]
        let tip = BudgetEngine.savingsTip(expenses: expenses, report: report, nearbyChains: nearby)
        XCTAssertEqual(tip?.chainName, "E.Leclerc")
        XCTAssertEqual(tip?.storeName, "E.Leclerc Blagnac")
        XCTAssertEqual(tip?.saving ?? 0, 57 * (1 - 87.0 / 114.0), accuracy: 1e-9)
        XCTAssertNil(BudgetEngine.savingsTip(expenses: expenses, report: nil, nearbyChains: nearby))
        XCTAssertNil(BudgetEngine.savingsTip(expenses: [expense(40, Fixtures.date(2026, 11, 5), chain: "e leclerc")],
                                             report: report, nearbyChains: nearby))
    }

    func testExpenseDecodingAndBackup() throws {
        let json = #"{"amount": 12.5, "date": 800000000, "storeName": "Lidl", "category": "inconnue"}"#
        let decoded = try JSONDecoder().decode(Expense.self, from: Fixtures.json(json))
        XCTAssertEqual(decoded.amount, 12.5)
        XCTAssertEqual(decoded.category, .groceries, "catégorie inconnue -> courses")
        XCTAssertEqual(decoded.storeName, "Lidl")

        var incoming = PersistedState()
        incoming.expenses = [expense(10, Fixtures.day(1)), expense(20, Fixtures.day(2))]
        var current = PersistedState()
        current.expenses = [incoming.expenses[0]]
        let summary = Backup.merge(incoming, into: &current)
        XCTAssertEqual(summary.expenses, 1)
        XCTAssertEqual(current.expenses.count, 2)
        XCTAssertTrue(summary.text.contains("1 dépense"))

        // Un fichier avec une dépense illisible garde les autres.
        let state = #"{"expenses": [{"amount": 5, "date": 800000000}, {"date": 1}]}"#
        let restored = try JSONDecoder().decode(PersistedState.self, from: Fixtures.json(state))
        XCTAssertEqual(restored.expenses.count, 1)
        XCTAssertEqual(restored.settings.budgetAmount, 100)
        XCTAssertEqual(restored.settings.budgetStartDay, 1)
    }
}

final class CatalogTests: XCTestCase {
    func testQuantityParsing() throws {
        XCTAssertEqual(try XCTUnwrap(UnitAmount.parse("500 g (4 x 125 g)")).value, 0.5, accuracy: 1e-9)
        let water = try XCTUnwrap(UnitAmount.parse("6x1.5L"))
        XCTAssertEqual(water.value, 9, accuracy: 1e-9)
        XCTAssertEqual(water.unit, "L")
        XCTAssertEqual(try XCTUnwrap(UnitAmount.parse("1,5 kg")).value, 1.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(UnitAmount.parse("Lot de 2 x 500g")).value, 1.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(UnitAmount.parse("33 cl")).value, 0.33, accuracy: 1e-9)
        XCTAssertNil(UnitAmount.parse("6 œufs"))
        XCTAssertNil(UnitAmount.parse(nil))

        let product = Product(code: "1", name: "Eau", quantity: "6 x 1,5 L")
        XCTAssertEqual(product.normalizedAmount?.value ?? 0, 9, accuracy: 1e-9)
    }

    func testDecodeSearchResults() throws {
        let json = """
        {"hits": [
          {"code": "3270190024309", "product_name": "Yaourt nature", "product_name_fr": "Yaourt nature",
           "brands": ["Carrefour", "Carrefour Classic"], "quantity": "500 g (4 x 125 g)",
           "image_front_small_url": "https://images.openfoodfacts.org/x.jpg", "nutriscore_grade": "a",
           "categories_tags": ["en:dairies", "en:yogurts"]},
          {"code": "3017620422003", "product_name": "Nutella", "brands": "Ferrero, Nutella", "nutriscore_grade": "unknown"},
          {"code": "123", "product_name": "Code trop court"},
          {"code": "3000000000000"}
        ], "count": 2400, "page": 1, "page_count": 480}
        """
        let response = try Fixtures.snakeDecoder().decode(CatalogResponse.self, from: Fixtures.json(json))
        XCTAssertEqual(response.hits.count, 2)
        XCTAssertEqual(response.count, 2400)
        XCTAssertEqual(response.pageCount, 480)

        let yogurt = response.hits[0]
        XCTAssertEqual(yogurt.product.name, "Yaourt nature")
        XCTAssertEqual(yogurt.product.brand, "Carrefour")
        XCTAssertEqual(yogurt.nutriScore, "a")
        XCTAssertEqual(yogurt.product.categories, ["en:dairies", "en:yogurts"])
        XCTAssertEqual(yogurt.product.normalizedAmount?.value ?? 0, 0.5, accuracy: 1e-9)

        let nutella = response.hits[1]
        XCTAssertEqual(nutella.product.brand, "Ferrero")
        XCTAssertNil(nutella.nutriScore)
        XCTAssertNil(nutella.product.imageURL)

        let page = CatalogPage(items: response.hits, total: response.count, page: 1, pageCount: 480)
        XCTAssertTrue(page.hasMore)
    }

    func testRayonsAreUniqueAndValid() {
        let tags = Rayon.all.map(\.tag)
        XCTAssertEqual(Set(tags).count, tags.count)
        XCTAssertTrue(tags.allSatisfy { $0.hasPrefix("en:") })
        XCTAssertGreaterThanOrEqual(Rayon.all.count, 15)
    }
}
