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

    func testAldiTilesKeepBrandAndQuantity() throws {
        // Ce que le script lit sur aldi.fr (fiches produit, contenance déduite du prix au kilo).
        let json = """
        [
          {"name": "BEURRE DOUX", "price": 6.49, "brand": "LE HAMEAU®", "quantity": "1 kg", "image": "https://x/b.png"},
          {"name": "Beurre  doux", "price": 2.35, "brand": "MILSANI®", "quantity": "250 g"},
          {"name": "6 œufs bio de poules élevées en plein air", "price": 2.29, "brand": "PICOTA®", "quantity": null},
          {"name": "Lait chocolaté brique", "price": 2.15, "brand": " ", "quantity": "1.2 l"}
        ]
        """
        let items = DriveCaptureParser.parse(json)
        XCTAssertEqual(items.map(\.name), ["Beurre doux", "Beurre doux", "6 œufs bio de poules élevées en plein air",
                                           "Lait chocolaté brique"])
        let hameau = items[0].product
        let milsani = items[1].product
        XCTAssertEqual(hameau.brand, "LE HAMEAU®")
        XCTAssertEqual(hameau.normalizedAmount?.value ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(milsani.quantity, "250 g")
        XCTAssertEqual(milsani.normalizedAmount?.unitPrice(2.35) ?? 0, 9.40, accuracy: 1e-9, "9,40 €/kg comme sur le site")
        XCTAssertNotEqual(hameau.code, milsani.code, "deux beurres de marques différentes restent deux produits")
        XCTAssertTrue(milsani.isCustom)
        XCTAssertNil(items[2].product.quantity)
        XCTAssertNil(items[3].brand, "marque vide ignorée")
        XCTAssertEqual(items[3].product.normalizedAmount?.value ?? 0, 1.2, accuracy: 1e-9)
    }

    func testSentenceCase() {
        XCTAssertEqual(DriveCaptureParser.sentenceCase("CRÈME LÉGÈRE FOUETTÉE"), "Crème légère fouettée")
        XCTAssertEqual(DriveCaptureParser.sentenceCase("Beurre doux extra fin"), "Beurre doux extra fin")
        XCTAssertEqual(DriveCaptureParser.sentenceCase("NUTELLA 400 g"), "NUTELLA 400 g", "déjà en partie en minuscules")
        XCTAssertEqual(DriveCaptureParser.sentenceCase("1664"), "1664")
    }

    func testAldiSiteAndNearestSite() throws {
        let aldi = try XCTUnwrap(DriveSite.all.first { $0.id == "aldi" })
        XCTAssertEqual(aldi.url(for: "œufs")?.absoluteString, "https://www.aldi.fr/recherche.html?query=%C5%93ufs")
        XCTAssertFalse(aldi.choosesStore, "le site Aldi n'a pas de choix de magasin")
        XCTAssertTrue(aldi.matches(Fixtures.store("NODE:3", name: "Aldi", brand: "Aldi")))
        XCTAssertTrue(DriveSite.all.first { $0.id == "leclerc" }?.choosesStore == true)

        let stores = [
            Fixtures.store("NODE:1", name: "Épicerie du coin"),
            Fixtures.store("NODE:2", name: "Aldi Minimes", brand: "Aldi"),
            Fixtures.store("NODE:3", name: "Carrefour City", brand: "Carrefour City"),
        ]
        XCTAssertEqual(DriveSite.nearest(in: stores)?.id, "aldi", "le premier magasin (le plus proche) qui a un site")
        XCTAssertNil(DriveSite.nearest(in: [Fixtures.store("NODE:1", name: "Épicerie du coin")]))
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
