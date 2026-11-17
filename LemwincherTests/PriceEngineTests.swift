import XCTest
@testable import Lemwincher

final class PriceEngineTests: XCTestCase {
    func testMedian() {
        XCTAssertEqual(ChainStats.median([3, 1, 2]), 2)
        XCTAssertEqual(ChainStats.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(ChainStats.median([]), 0)
    }

    func testLatestPerStoreKeepsNewestAndPrefersMineOnSameDay() {
        let old = Fixtures.obs(3.00, store: "NODE:1", date: Fixtures.day(0))
        let new = Fixtures.obs(3.50, store: "NODE:1", date: Fixtures.day(5))
        let other = Fixtures.obs(2.90, store: "NODE:2", date: Fixtures.day(1))
        let latest = PriceEngine.latestPerStore([old, new, other])
        XCTAssertEqual(latest.count, 2)
        XCTAssertEqual(latest.first { $0.storeKey == "NODE:1" }?.price, 3.50)

        let community = Fixtures.obs(3.10, store: "NODE:3", date: Fixtures.day(2))
        let mine = Fixtures.obs(2.95, store: "NODE:3", date: Fixtures.day(2), source: .mine)
        XCTAssertEqual(PriceEngine.latestPerStore([community, mine]).first?.source, .mine)
        XCTAssertEqual(PriceEngine.latestPerStore([mine, community]).first?.source, .mine)
    }

    func testChainEstimatesIgnorePromotionsAndUseOnePricePerStore() {
        let observations = [
            Fixtures.obs(3.00, store: "NODE:1", chain: "carrefour", date: Fixtures.day(0)),
            Fixtures.obs(3.40, store: "NODE:1", chain: "carrefour", date: Fixtures.day(3)), // plus récent
            Fixtures.obs(3.20, store: "NODE:2", chain: "carrefour"),
            Fixtures.obs(1.00, store: "NODE:4", chain: "lidl", discounted: true),            // promo ignorée
            Fixtures.obs(2.80, store: "NODE:5", chain: "lidl"),
            Fixtures.obs(9.99, store: "NODE:6", chain: nil),                                  // enseigne inconnue
        ]
        let estimates = ChainStats.estimates(from: observations)
        XCTAssertEqual(estimates.map(\.key), ["lidl", "carrefour"])
        XCTAssertEqual(estimates[0].median, 2.80, accuracy: 1e-9)
        XCTAssertEqual(estimates[1].median, 3.30, accuracy: 1e-9)
        XCTAssertEqual(estimates[1].storeCount, 2)
        XCTAssertEqual(estimates[1].name, "Carrefour")
    }

    func testFilterByCountryAndCurrency() {
        let list = [
            Fixtures.obs(1, currency: "EUR", country: "FR"),
            Fixtures.obs(2, currency: "EUR", country: "BE"),
            Fixtures.obs(3, currency: "CHF", country: "CH"),
            Fixtures.obs(4, currency: "EUR", country: nil),
        ]
        XCTAssertEqual(PriceEngine.filter(list, country: "FR", currency: "EUR").map(\.price), [1, 4])
        XCTAssertEqual(PriceEngine.filter(list, country: nil, currency: "EUR").map(\.price), [1, 2, 4])
    }

    func testBasketUsesRealPricesThenChainEstimates() {
        let nutella = ShoppingItem(product: Fixtures.nutella, quantity: 2)
        let pasta = ShoppingItem(product: Product(code: "3076820002002", name: "Pâtes"))
        let mystery = ShoppingItem(product: Product.custom(named: "Truc introuvable"))

        let lidl = Fixtures.store("NODE:10", name: "Lidl Minimes", brand: "Lidl")
        let carrefour = Fixtures.store("NODE:20", name: "Carrefour Purpan", brand: "Carrefour")

        let local: [String: [PriceObservation]] = [
            Fixtures.nutella.code: [
                Fixtures.obs(3.29, store: "NODE:10", product: Fixtures.nutella.code, chain: "lidl"),
                Fixtures.obs(3.99, store: "NODE:20", product: Fixtures.nutella.code, chain: "carrefour"),
            ],
        ]
        let estimates: [String: [ChainEstimate]] = [
            "3076820002002": [
                ChainEstimate(key: "lidl", name: "Lidl", median: 0.89, storeCount: 12, currency: "EUR", latest: Fixtures.day(0)),
                ChainEstimate(key: "carrefour", name: "Carrefour", median: 1.19, storeCount: 30, currency: "EUR", latest: Fixtures.day(0)),
            ],
        ]

        let result = PriceEngine.basket(items: [nutella, pasta, mystery],
                                        localByCode: local,
                                        estimatesByCode: estimates,
                                        candidates: [carrefour, lidl])
        XCTAssertEqual(result.stores.map(\.storeKey), ["NODE:10", "NODE:20"])
        let lidlBasket = result.stores[0]
        XCTAssertEqual(lidlBasket.lines.count, 2)
        XCTAssertEqual(lidlBasket.total, 3.29 * 2 + 0.89, accuracy: 1e-9)
        XCTAssertEqual(lidlBasket.estimateCount, 1)
        XCTAssertEqual(lidlBasket.missing.map(\.product.name), ["Truc introuvable"])

        XCTAssertEqual(result.bestSplit.count, 1)
        XCTAssertEqual(result.bestSplit.first?.storeKey, "NODE:10")
        XCTAssertEqual(result.unknown.map(\.product.name), ["Truc introuvable"])
    }

    func testCheaperAlternativesPerKilo() {
        let list = [
            Fixtures.obs(2.00, product: "A", unitQuantity: 500, unitName: "g"),   // 4,00 €/kg
            Fixtures.obs(1.50, product: "B", unitQuantity: 250, unitName: "g"),   // 6,00 €/kg
            Fixtures.obs(1.00, product: "A", unitQuantity: 500, unitName: "g"),   // 2,00 €/kg (meilleur prix de A)
            Fixtures.obs(0.50, product: "SELF", unitQuantity: 500, unitName: "g"),
            Fixtures.obs(0.80, product: "C", unitQuantity: 1, unitName: "L"),     // autre unité
            Fixtures.obs(0.10, product: "D", discounted: true, unitQuantity: 1000, unitName: "g"),
        ]
        let result = PriceEngine.cheaperAlternatives(observations: list, excluding: "SELF", unit: "kg", below: 5.0)
        XCTAssertEqual(result.map(\.obs.productCode), ["A"])
        XCTAssertEqual(result.first?.unitPrice ?? 0, 2.0, accuracy: 1e-9)
    }

    func testDecodeOpenPricesResponse() throws {
        let json = """
        {"items":[
          {"id":1,"product_code":"3017620422003","price":3.29,"price_is_discounted":false,"currency":"EUR","date":"2026-11-10",
           "location_osm_id":123,"location_osm_type":"NODE",
           "product":{"code":"3017620422003","product_name":"Nutella","brands":"Ferrero","product_quantity":"400","product_quantity_unit":"g"},
           "location":{"id":9,"osm_id":123,"osm_type":"NODE","osm_name":"Lidl","osm_brand":"Lidl",
                       "osm_display_name":"Lidl, 12, Rue Bayard, Toulouse","osm_address_city":"Toulouse",
                       "osm_address_country_code":"fr","osm_lat":43.61,"osm_lon":1.45}},
          {"id":2,"price":"2,5","product_code":"999"},
          {"id":3}
        ],"total":3}
        """
        let page = try Fixtures.snakeDecoder().decode(OPPage<OPPrice>.self, from: Fixtures.json(json))
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items[1].price, 2.5, accuracy: 1e-9)
        XCTAssertEqual(page.total, 3)

        let observations = PriceEngine.observations(from: page.items)
        XCTAssertEqual(observations.count, 1, "un prix sans magasin est ignoré")
        let obs = try XCTUnwrap(observations.first)
        XCTAssertEqual(obs.storeKey, "NODE:123")
        XCTAssertEqual(obs.chainKey, "lidl")
        XCTAssertEqual(obs.countryCode, "FR")
        XCTAssertEqual(obs.productName, "Nutella")
        XCTAssertEqual(obs.unitAmount?.unit, "kg")
        XCTAssertEqual(obs.storeAddress, "12, Rue Bayard, Toulouse")
        XCTAssertNotEqual(obs.date, .distantPast)
        XCTAssertEqual(obs.store?.id, "NODE:123")
    }

    func testPriceChangesSameStoreOnly() {
        let store = Fixtures.store("NODE:1", name: "Carrefour")
        let otherStore = Fixtures.store("NODE:2", name: "Lidl")
        let prices = [
            MyPrice(product: Fixtures.nutella, store: store, price: 3.00, currency: "EUR", date: Fixtures.day(0)),
            MyPrice(product: Fixtures.nutella, store: store, price: 3.30, currency: "EUR", date: Fixtures.day(30)),
            MyPrice(product: Fixtures.nutella, store: store, price: 2.00, currency: "EUR", date: Fixtures.day(31), isDiscounted: true),
            MyPrice(product: Fixtures.nutella, store: otherStore, price: 2.90, currency: "EUR", date: Fixtures.day(10)),
        ]
        let changes = PriceEngine.priceChanges(prices)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].storeName, "Carrefour")
        XCTAssertEqual(changes[0].percent, 10, accuracy: 1e-6)
        XCTAssertEqual(changes[0].delta, 0.30, accuracy: 1e-9)
    }
}

final class ChainIndexTests: XCTestCase {
    func testIndexComparesChainsToTheAverage() {
        var perProduct: [[PriceObservation]] = []
        for product in 0..<5 {
            let base = 2.0 + Double(product)
            let code = "P\(product)"
            var list = [
                Fixtures.obs(base * 0.9, store: "NODE:1", product: code, chain: "lidl"),
                Fixtures.obs(base, store: "NODE:2", product: code, chain: "carrefour"),
                Fixtures.obs(base * 1.1, store: "NODE:3", product: code, chain: "monoprix"),
            ]
            if product < 2 {
                list.append(Fixtures.obs(base * 0.5, store: "NODE:4", product: code, chain: "netto"))
            }
            perProduct.append(list)
        }
        let report = ChainIndexBuilder.compute(perProduct, country: "FR", currency: "EUR")
        XCTAssertEqual(report.productCount, 5)
        XCTAssertEqual(report.entries.map(\.key), ["lidl", "carrefour", "monoprix"], "Netto : pas assez de produits")
        XCTAssertEqual(report.entry(for: "lidl")?.index ?? 0, 90, accuracy: 3)
        XCTAssertEqual(report.entry(for: "monoprix")?.index ?? 0, 110, accuracy: 3)
        XCTAssertNil(report.entry(for: nil))
    }

    func testDifferenceText() {
        XCTAssertEqual(ChainIndexEntry(key: "a", name: "A", index: 94, productCount: 5).differenceText, "-6 %")
        XCTAssertEqual(ChainIndexEntry(key: "b", name: "B", index: 112.2, productCount: 5).differenceText, "+12 %")
        XCTAssertEqual(ChainIndexEntry(key: "c", name: "C", index: 100.3, productCount: 5).differenceText, "dans la moyenne")
    }
}
