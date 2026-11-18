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

    func testSameNameDifferentPackStaysTwoProducts() {
        // Auchan : même nom et même marque, boîtes de 12 et de 6.
        let json = """
        [
          {"name": "Oeufs de poules élevées en plein air", "price": 3.19, "brand": "AUCHAN", "quantity": "12 pièces"},
          {"name": "Oeufs de poules élevées en plein air", "price": 3.19, "brand": "AUCHAN", "quantity": "6 pièces"},
          {"name": "Oeufs de poules élevées en plein air", "price": 3.19, "brand": "AUCHAN", "quantity": "6 pièces"}
        ]
        """
        let items = DriveCaptureParser.parse(json)
        XCTAssertEqual(items.map(\.quantity), ["12 pièces", "6 pièces"], "le doublon exact est retiré, pas l'autre boîte")
        XCTAssertNotEqual(items[0].id, items[1].id)
        XCTAssertNotEqual(items[0].product.code, items[1].product.code, "6 et 12 œufs : deux produits")
        XCTAssertEqual(items[1].product.quantity, "6 pièces")
        XCTAssertEqual(CapturedPrice(name: "Bananes", price: 1.99).product.code, Product.custom(named: "Bananes").code,
                       "sans marque ni contenance : le produit sans code-barres habituel")
    }

    func testLeclercOpensLeclercDrive() throws {
        let leclerc = try XCTUnwrap(DriveSite.all.first { $0.id == "leclerc" })
        XCTAssertEqual(leclerc.url(for: "œufs")?.absoluteString, "https://www.leclercdrive.fr",
                       "chaque drive a son adresse : on ouvre l'accueil pour choisir le sien")
        XCTAssertTrue(leclerc.matches(Fixtures.store("NODE:4", name: "E.Leclerc Blagnac", brand: "E.Leclerc")))
        XCTAssertTrue(leclerc.choosesStore)
    }

    func testPromotionsReadOnThePage() {
        let json = """
        [
          {"name": "Oeufs plein air x12", "price": 2.49, "brand": "AUCHAN", "promo": true, "oldPrice": 3.29},
          {"name": "Beurre doux", "price": 2.35, "promo": true, "oldPrice": null},
          {"name": "Lait demi-écrémé", "price": 0.99, "promo": false, "oldPrice": 0.89},
          {"name": "Pâtes", "price": 1.10, "oldPrice": 1.50}
        ]
        """
        let items = DriveCaptureParser.parse(json)
        XCTAssertEqual(items.map(\.promo), [true, true, false, true])
        XCTAssertEqual(items[0].oldPrice ?? 0, 3.29, accuracy: 1e-9)
        XCTAssertNil(items[1].oldPrice, "badge « promo » sans ancien prix")
        XCTAssertNil(items[2].oldPrice, "un « ancien prix » plus bas n'en est pas un")
        XCTAssertTrue(items[3].promo, "un prix barré plus élevé suffit")
    }

    func testMoreSites() throws {
        let monoprix = try XCTUnwrap(DriveSite.all.first { $0.id == "monoprix" })
        XCTAssertEqual(monoprix.url(for: "œufs")?.absoluteString, "https://courses.monoprix.fr/search?q=%C5%93ufs")
        XCTAssertTrue(monoprix.matches(Fixtures.store("NODE:1", name: "Monop'", brand: "Monop'")))
        XCTAssertTrue(monoprix.matches(Fixtures.store("NODE:2", name: "Monoprix Toulouse", brand: "Monoprix")))
        let chronodrive = try XCTUnwrap(DriveSite.all.first { $0.id == "chronodrive" })
        XCTAssertEqual(chronodrive.url(for: "lait demi écrémé")?.absoluteString,
                       "https://www.chronodrive.com/search/lait%20demi%20%C3%A9cr%C3%A9m%C3%A9")
        XCTAssertTrue(chronodrive.choosesStore)
        for id in ["picard", "naturalia", "lavieclaire"] {
            XCTAssertNotNil(DriveSite.all.first { $0.id == id }, id)
        }
        XCTAssertEqual(Set(DriveSite.all.map(\.id)).count, DriveSite.all.count)
    }

    func testStartPagesAndStoreSites() throws {
        let aldi = try XCTUnwrap(DriveSite.all.first { $0.id == "aldi" })
        XCTAssertEqual(aldi.startURL?.absoluteString, "https://www.aldi.fr/produits.html", "ses rayons")
        let lidl = try XCTUnwrap(DriveSite.all.first { $0.id == "lidl" })
        XCTAssertEqual(lidl.startURL?.absoluteString, "https://www.lidl.fr", "son accueil")

        let aldiStore = Fixtures.store("NODE:11247032479", name: "Aldi", brand: "Aldi")
        XCTAssertEqual(DriveSite.forStore(aldiStore)?.id, "aldi")
        let corner = Fixtures.store("NODE:9", name: "Épicerie du coin")
        XCTAssertNil(DriveSite.forStore(corner))

        let custom = DriveSite.custom(for: corner, url: try XCTUnwrap(URL(string: "https://epicerie.example")))
        XCTAssertEqual(custom.id, "magasin-NODE:9")
        XCTAssertEqual(custom.name, "Épicerie du coin")
        XCTAssertEqual(custom.startURL?.absoluteString, "https://epicerie.example")
        XCTAssertEqual(custom.url(for: "oeufs")?.absoluteString, "https://epicerie.example")
        XCTAssertFalse(custom.choosesStore)
        XCTAssertFalse(custom.matches(aldiStore))
    }

    func testCaptureScriptsReadEverything() {
        XCTAssertTrue(DriveCaptureParser.fullScript.contains("captureAll"))
        XCTAssertTrue(DriveCaptureParser.fullScript.hasSuffix("return await captureAll(45000);"))
        XCTAssertTrue(DriveCaptureParser.script.hasSuffix("return JSON.stringify(out);"))
        XCTAssertTrue(DriveCaptureParser.functions.contains("loadMoreButton"), "« Voir plus »")
        XCTAssertTrue(DriveCaptureParser.functions.contains("nextPage"), "pages suivantes")
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
