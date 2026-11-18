import XCTest
import CoreLocation
@testable import Lemwincher

/// Produits précis proposés sous un article de la liste ("Œufs" -> "6 œufs plein air").
final class SuggestionTests: XCTestCase {
    func testNormalizationHandlesLigatures() {
        XCTAssertEqual(SuggestionEngine.normalize("Œufs Frais"), "oeufs frais")
        XCTAssertEqual(SuggestionEngine.tokens("6 Œufs plein-air"), ["6", "oeufs", "plein", "air"])
        XCTAssertEqual(SuggestionEngine.key("  Œufs  "), "oeufs")
        XCTAssertEqual(SuggestionEngine.searchVariants("oeufs"), ["oeuf", "œuf"])
        XCTAssertEqual(SuggestionEngine.searchVariants("Œufs"), ["œuf", "oeuf"])
        XCTAssertEqual(SuggestionEngine.searchVariants("lait"), ["lait"])
        XCTAssertEqual(SuggestionEngine.searchVariants("Pâtes complètes"), ["pâte", "pate"])
        XCTAssertEqual(SuggestionEngine.searchVariants("1 kg de riz"), ["riz"])
        XCTAssertEqual(SuggestionEngine.significantWords("Bananes (1 kg)"), ["banane"])
        XCTAssertEqual(SuggestionEngine.significantWords("Pack de 6 x 1,5 L eau"), ["eau"])
        XCTAssertEqual(SuggestionEngine.catalogText("Bananes (1 kg)"), "Bananes")
        XCTAssertEqual(SuggestionEngine.singular("noix"), "noix")
    }

    func testRelevance() {
        XCTAssertEqual(SuggestionEngine.relevance(name: "4 œufs plein air", query: "oeuf"), 3)
        XCTAssertEqual(SuggestionEngine.relevance(name: "10 oeufs frais", query: "Œufs"), 3)
        XCTAssertEqual(SuggestionEngine.relevance(name: "Viande hachée pur bœuf", query: "oeuf"), 0, "bœuf n'est pas un œuf")
        XCTAssertEqual(SuggestionEngine.relevance(name: "Lait demi-écrémé", query: "lait"), 3)
        XCTAssertEqual(SuggestionEngine.relevance(name: "Chocolat au lait", query: "lait"), 2)
        XCTAssertEqual(SuggestionEngine.relevance(name: "Lait demi-écrémé", query: "lait entier"), 0)
        XCTAssertEqual(SuggestionEngine.relevance(name: "Bananes", query: "banane"), 3)
        XCTAssertEqual(SuggestionEngine.relevance(name: "Banane", query: "Bananes (1 kg)"), 3)
        XCTAssertEqual(SuggestionEngine.relevance(name: "Bananes", query: ""), 0)
    }

    func testBestOfferPrefersRealLocalPrices() throws {
        let home = CLLocation(latitude: 43.6045, longitude: 1.4433)
        let observations = [
            Fixtures.obs(2.49, store: "NODE:1", chain: "carrefour city", lat: 43.6050, lon: 1.4440),   // à 80 m
            Fixtures.obs(2.19, store: "NODE:2", chain: "lidl", lat: 43.6100, lon: 1.4500),             // à ~800 m
            Fixtures.obs(1.50, store: "NODE:3", chain: "lidl", lat: 45.7600, lon: 4.8300),             // Lyon : trop loin
        ]
        let offer = try XCTUnwrap(SuggestionEngine.bestOffer(observations: observations, reference: home,
                                                             radiusMeters: 8000, country: "FR", currency: "EUR",
                                                             nearbyChains: [:]))
        XCTAssertEqual(offer.price, 2.19, accuracy: 1e-9)
        XCTAssertTrue(offer.isLocal)
        XCTAssertEqual(offer.storeName, "Magasin NODE:2")
        XCTAssertNotNil(offer.distance)
    }

    func testBestOfferFallsBackToARealPriceFromTheSameChain() throws {
        let home = CLLocation(latitude: 43.6045, longitude: 1.4433)
        let far = [
            Fixtures.obs(1.80, store: "NODE:10", chain: "e leclerc", lat: 48.85, lon: 2.35),
            Fixtures.obs(2.60, store: "NODE:11", chain: "monoprix", lat: 48.86, lon: 2.34),
            Fixtures.obs(2.70, store: "NODE:12", chain: "monoprix", lat: 48.87, lon: 2.33),
        ]
        let monoprixNearby = ["monoprix": Fixtures.store("NODE:99", name: "Monoprix Capitole", brand: "Monoprix",
                                                          lat: 43.6050, lon: 1.4440)]
        let nearbyOffer = try XCTUnwrap(SuggestionEngine.bestOffer(observations: far, reference: home, radiusMeters: 8000,
                                                                   country: "FR", currency: "EUR",
                                                                   nearbyChains: monoprixNearby))
        // Vrai prix relevé dans le magasin Monoprix le plus proche (pas une moyenne).
        XCTAssertFalse(nearbyOffer.isLocal)
        XCTAssertEqual(nearbyOffer.storeName, "Magasin NODE:11")
        XCTAssertEqual(nearbyOffer.price, 2.60, accuracy: 1e-9)
        XCTAssertEqual(nearbyOffer.date, Fixtures.day(0))

        let anywhere = try XCTUnwrap(SuggestionEngine.bestOffer(observations: far, reference: home, radiusMeters: 8000,
                                                                country: "FR", currency: "EUR", nearbyChains: [:]))
        XCTAssertEqual(anywhere.storeName, "Magasin NODE:10", "le relevé du magasin le plus proche")
        XCTAssertEqual(anywhere.price, 1.80, accuracy: 1e-9)

        XCTAssertNil(SuggestionEngine.bestOffer(observations: [], reference: home, radiusMeters: 8000,
                                                country: "FR", currency: "EUR", nearbyChains: [:]))
    }

    func testSortedPutsPricedFirst() {
        func suggestion(_ code: String, _ price: Double?) -> ProductSuggestion {
            ProductSuggestion(product: Product(code: code, name: code),
                              offer: price.map { PriceOffer(price: $0, currency: "EUR", storeName: "X", distance: nil,
                                                            date: Fixtures.day(0), isLocal: true) },
                              nutriScore: nil)
        }
        let sorted = SuggestionEngine.sorted([suggestion("A", nil), suggestion("B", 3.0), suggestion("C", 1.5)])
        XCTAssertEqual(sorted.map(\.id), ["C", "B", "A"])
    }

    func testChainReferenceIsARealNearbyRecentPrice() throws {
        let home = CLLocation(latitude: 43.6045, longitude: 1.4433)
        let list = [
            Fixtures.obs(3.10, store: "NODE:1", chain: "lidl", date: Fixtures.day(1), lat: 43.61, lon: 1.45),     // Toulouse, ancien
            Fixtures.obs(3.30, store: "NODE:2", chain: "lidl", date: Fixtures.day(9), lat: 43.62, lon: 1.40),     // Toulouse, récent
            Fixtures.obs(2.50, store: "NODE:3", chain: "lidl", date: Fixtures.day(10), lat: 48.85, lon: 2.35),    // Paris, très récent
        ]
        let estimate = try XCTUnwrap(ChainStats.estimates(from: list, near: home).first)
        XCTAssertEqual(estimate.reference?.storeKey, "NODE:2", "le plus récent à moins de 30 km")
        XCTAssertEqual(estimate.displayPrice, 3.30, accuracy: 1e-9)
        XCTAssertEqual(estimate.median, 3.10, accuracy: 1e-9, "la médiane reste disponible pour les statistiques")

        let noLocation = try XCTUnwrap(ChainStats.estimates(from: list).first)
        XCTAssertEqual(noLocation.reference?.storeKey, "NODE:3", "sans position : le plus récent")
    }

    func testBasketUsesChosenProduct() {
        var item = ShoppingItem(product: .custom(named: "Œufs"))
        item.choice = Product(code: "3270190024309", name: "6 œufs plein air")
        XCTAssertEqual(item.pricedProduct.code, "3270190024309")

        let store = Fixtures.store("NODE:5", name: "Lidl", brand: "Lidl")
        let local = ["3270190024309": [Fixtures.obs(2.19, store: "NODE:5", product: "3270190024309", chain: "lidl")]]
        let result = PriceEngine.basket(items: [item], localByCode: local, estimatesByCode: [:], candidates: [store])
        XCTAssertEqual(result.stores.first?.total ?? 0, 2.19, accuracy: 1e-9)
        XCTAssertTrue(result.unknown.isEmpty)

        // Sans choix, l'article générique n'a pas de prix.
        let generic = ShoppingItem(product: .custom(named: "Œufs"))
        XCTAssertEqual(PriceEngine.basket(items: [generic], localByCode: local, estimatesByCode: [:], candidates: [store]).unknown.count, 1)
    }

    func testOldListItemsDecodeWithoutChoice() throws {
        let json = #"{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "product": {"code": "custom:oeufs", "name": "Œufs"}, "quantity": 1, "checked": false}"#
        let item = try JSONDecoder().decode(ShoppingItem.self, from: Fixtures.json(json))
        XCTAssertNil(item.choice)
        XCTAssertEqual(item.pricedProduct.code, "custom:oeufs")
    }
}
