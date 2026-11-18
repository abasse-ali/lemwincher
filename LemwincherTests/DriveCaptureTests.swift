import XCTest
@testable import Lemwincher

/// Prix lus sur la page d'un site drive affichée dans le navigateur intégré.
final class DriveCaptureTests: XCTestCase {
    func testParseKeepsPlausiblePricesWithoutDuplicates() {
        let json = """
        [
          {"name": "  Nutella   400 g ", "price": 3.29, "gtin": "3017620422003", "image": "https://x/n.jpg"},
          {"name": "Nutella 400 g", "price": "3,29", "gtin": null, "image": null},
          {"name": "Œufs frais x10", "price": 2.149},
          {"name": "Ab", "price": 1.0},
          {"name": "Télévision", "price": 1299},
          {"name": "Bonbon", "price": 0.01},
          {"price": 2.5},
          "pas un objet"
        ]
        """
        let items = DriveCaptureParser.parse(json)
        XCTAssertEqual(items.map(\.name), ["Nutella 400 g", "Œufs frais x10"])
        XCTAssertEqual(items[0].price, 3.29, accuracy: 1e-9)
        XCTAssertEqual(items[1].price, 2.15, accuracy: 1e-9, "arrondi au centime")
        XCTAssertTrue(items.allSatisfy(\.include))
        XCTAssertTrue(DriveCaptureParser.parse("pas du json").isEmpty)
        XCTAssertTrue(DriveCaptureParser.parse("[]").isEmpty)
    }

    func testCapturedProductUsesBarcodeWhenAvailable() {
        let withCode = CapturedPrice(name: "Nutella 400 g", price: 3.29, gtin: "3017620422003", image: "https://x/n.jpg")
        XCTAssertEqual(withCode.product.code, "3017620422003")
        XCTAssertEqual(withCode.product.imageURL, "https://x/n.jpg")

        let withoutCode = CapturedPrice(name: "Bananes Cavendish", price: 1.99)
        XCTAssertTrue(withoutCode.product.isCustom)
        XCTAssertEqual(withoutCode.product.name, "Bananes Cavendish")
    }

    func testSiteSearchURLsAndChains() throws {
        let carrefour = try XCTUnwrap(DriveSite.all.first { $0.id == "carrefour" })
        XCTAssertEqual(carrefour.url(for: "œufs plein air")?.absoluteString,
                       "https://www.carrefour.fr/s?q=%C5%93ufs%20plein%20air")
        XCTAssertEqual(carrefour.url(for: "  ")?.absoluteString, "https://www.carrefour.fr")
        XCTAssertEqual(carrefour.url(for: "lait & café")?.absoluteString, "https://www.carrefour.fr/s?q=lait%20%26%20caf%C3%A9")
        XCTAssertTrue(carrefour.matches(Fixtures.store("NODE:1", name: "Carrefour City Capitole", brand: "Carrefour City")))
        XCTAssertFalse(carrefour.matches(Fixtures.store("NODE:2", name: "Lidl", brand: "Lidl")))
        XCTAssertEqual(Set(DriveSite.all.map(\.id)).count, DriveSite.all.count)
    }
}
