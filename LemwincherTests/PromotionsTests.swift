import XCTest
import CoreLocation
@testable import Lemwincher

/// Section « Promos autour de vous » de l'accueil.
final class PromotionsTests: XCTestCase {
    private let toulouse = CLLocation(latitude: 43.6045, longitude: 1.4433)
    private let now = Fixtures.day(20)

    private func deals(_ observations: [PriceObservation]) -> [PromoDeal] {
        PromoFinder.deals(in: observations, reference: toulouse, radius: 8_000, now: now)
    }

    func testRecentNearbyPromosWithTheirUsualPrice() throws {
        let found = deals([
            // Prix habituel relevé avant la promo, dans le même magasin.
            Fixtures.obs(3.00, store: "NODE:1", product: "111", date: Fixtures.day(10)),
            Fixtures.obs(2.40, store: "NODE:1", product: "111", date: Fixtures.day(18), discounted: true),
            // Promo sans prix habituel connu.
            Fixtures.obs(1.50, store: "NODE:2", product: "222", date: Fixtures.day(19), discounted: true),
            // Trop ancienne (plus de 14 jours).
            Fixtures.obs(0.99, store: "NODE:3", product: "333", date: Fixtures.day(1), discounted: true),
            // Trop loin (Lyon).
            Fixtures.obs(0.89, store: "NODE:4", product: "444", date: Fixtures.day(19), discounted: true,
                         lat: 45.7600, lon: 4.8300),
            // Pas une promo.
            Fixtures.obs(0.79, store: "NODE:5", product: "555", date: Fixtures.day(19)),
        ])
        XCTAssertEqual(found.map(\.product.code), ["111", "222"], "la plus forte remise d'abord")
        XCTAssertEqual(found.first?.discountPercent, 20)
        XCTAssertEqual(try XCTUnwrap(found.first?.regularPrice), 3.00, accuracy: 1e-9)
        XCTAssertNil(found.last?.discountPercent)
    }

    func testPromoEndedWhenANormalPriceIsSeenAfterIt() {
        let found = deals([
            Fixtures.obs(2.40, store: "NODE:1", product: "111", date: Fixtures.day(15), discounted: true),
            Fixtures.obs(3.00, store: "NODE:1", product: "111", date: Fixtures.day(18)),
        ])
        XCTAssertTrue(found.isEmpty)
    }

    func testMyPricesComeFirstAndKeepTheCrossedOutPrice() throws {
        let store = Fixtures.store("NODE:9", name: "Aldi Toulouse", brand: "Aldi")
        let promo = CapturedPrice(name: "Frites", price: 1.49, promo: true, oldPrice: 1.99)
        let captured = CaptureUpdater.apply([promo], to: [], store: store, currency: "EUR",
                                            source: "site Aldi", now: Fixtures.day(19))
        XCTAssertEqual(try XCTUnwrap(captured.prices.first?.oldPrice), 1.99, accuracy: 1e-9, "prix barré du site")

        let code = try XCTUnwrap(captured.prices.first?.product.code)
        let mine = PriceEngine.observations(from: captured.prices)
        let community = Fixtures.obs(1.59, store: "NODE:9", product: code, date: Fixtures.day(19), discounted: true)
        let found = deals(mine + [community])
        XCTAssertEqual(found.count, 1, "un seul produit par magasin")
        XCTAssertTrue(try XCTUnwrap(found.first).isMine, "mon relevé passe avant celui de la communauté")
        XCTAssertEqual(found.first?.discountPercent, 25)
    }

    func testCommunityCrossedOutPriceIsRead() throws {
        let json = """
        {"items": [{"id": 1, "product_code": "3017620422003", "price": 2.99, "price_is_discounted": true,
                    "price_without_discount": 3.79, "currency": "EUR", "date": "2026-11-20",
                    "location_osm_id": 42, "location_osm_type": "NODE"}], "total": 1}
        """
        let page = try Fixtures.snakeDecoder().decode(OPPage<OPPrice>.self, from: Fixtures.json(json))
        let obs = try XCTUnwrap(PriceEngine.observations(from: page.items).first)
        XCTAssertTrue(obs.isDiscounted)
        XCTAssertEqual(try XCTUnwrap(obs.regularPrice), 3.79, accuracy: 1e-9)
    }
}
