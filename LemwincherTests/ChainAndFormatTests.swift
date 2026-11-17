import XCTest
@testable import Lemwincher

final class ChainTests: XCTestCase {
    func testNormalizeFoldsAccentsAndPunctuation() {
        XCTAssertEqual(Chain.normalize("Centre Commercial E.Leclerc"), "centre commercial e leclerc")
        XCTAssertEqual(Chain.normalize("  Intermarché  SUPER "), "intermarche super")
    }

    func testBrandAliases() {
        XCTAssertEqual(Chain.key(brand: "Leclerc", name: nil), "e leclerc")
        XCTAssertEqual(Chain.key(brand: "E.Leclerc", name: nil), "e leclerc")
        XCTAssertEqual(Chain.key(brand: "Intermarché Super", name: nil), "intermarche")
        XCTAssertEqual(Chain.key(brand: "Aldi Nord", name: nil), "aldi")
    }

    func testLongestKnownPrefixWins() {
        XCTAssertEqual(Chain.key(brand: nil, name: "Carrefour Market Toulouse Minimes"), "carrefour market")
        XCTAssertEqual(Chain.key(brand: nil, name: "Carrefour Toulouse Purpan"), "carrefour")
        XCTAssertEqual(Chain.key(brand: "Carrefour City", name: "Carrefour City Capitole"), "carrefour city")
    }

    func testIgnoredPrefixes() {
        XCTAssertEqual(Chain.key(brand: nil, name: "Centre Commercial E.Leclerc Blagnac"), "e leclerc")
        XCTAssertEqual(Chain.key(brand: nil, name: "Hypermarché Auchan Gramont"), "auchan")
    }

    func testUnknownNamesAreNotChains() {
        XCTAssertNil(Chain.key(brand: nil, name: "Épicerie du coin"))
        XCTAssertNil(Chain.key(brand: nil, name: nil))
        XCTAssertNil(Chain.key(brand: "   ", name: nil))
        // Une marque inconnue reste une enseigne à part entière.
        XCTAssertEqual(Chain.key(brand: "Super Marché Local", name: nil), "super marche local")
    }

    func testDisplayNamesAndLogos() {
        XCTAssertEqual(Chain.displayName(for: "intermarche"), "Intermarché")
        XCTAssertEqual(Chain.displayName(for: "e leclerc"), "E.Leclerc")
        XCTAssertNil(Chain.displayName(for: "inconnu"))
        XCTAssertEqual(Chain.logoURL(brand: "Carrefour Market")?.hasSuffix("/stores/carrefour-market.png"), true)
        XCTAssertNil(Chain.logoURL(brand: "  "))
    }

    func testStoreChainProperties() {
        let store = Fixtures.store("NODE:42", name: "Carrefour Market Minimes", brand: nil)
        XCTAssertEqual(store.chainKey, "carrefour market")
        XCTAssertEqual(store.chainName, "Carrefour Market")
        XCTAssertEqual(store.osmType, "NODE")
        XCTAssertEqual(store.osmId, 42)
        XCTAssertTrue(store.isSupermarket)
        XCTAssertNil(Fixtures.store("apple:43.6,1.4").osmId)
        XCTAssertFalse(Fixtures.store("NODE:1", kind: "convenience").isSupermarket)
    }

    func testStoreContactLinks() {
        var store = Fixtures.store("NODE:1")
        store.phone = "+33 5 61 00 00 00; +33 5 61 11 11 11"
        store.website = "www.exemple.fr"
        XCTAssertEqual(store.phoneURL?.absoluteString, "tel:+33561000000")
        XCTAssertEqual(store.websiteURL?.absoluteString, "https://www.exemple.fr")
        store.website = "http://magasin.fr"
        XCTAssertEqual(store.websiteURL?.absoluteString, "http://magasin.fr")
    }
}

final class UnitAmountTests: XCTestCase {
    func testGramsAndCentilitres() throws {
        let grams = try XCTUnwrap(UnitAmount(quantity: 400, unit: "g"))
        XCTAssertEqual(grams.unit, "kg")
        XCTAssertEqual(grams.value, 0.4, accuracy: 1e-9)
        XCTAssertEqual(grams.unitPrice(2.0), 5.0, accuracy: 1e-9)

        let bottle = try XCTUnwrap(UnitAmount(quantity: 150, unit: "cl"))
        XCTAssertEqual(bottle.unit, "L")
        XCTAssertEqual(bottle.value, 1.5, accuracy: 1e-9)

        XCTAssertEqual(UnitAmount(quantity: 500, unit: " ML ")?.value ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(UnitAmount(quantity: 2, unit: "kg")?.value ?? 0, 2, accuracy: 1e-9)
    }

    func testInvalidAmounts() {
        XCTAssertNil(UnitAmount(quantity: 6, unit: "pièces"))
        XCTAssertNil(UnitAmount(quantity: 0, unit: "g"))
        XCTAssertNil(UnitAmount(quantity: nil, unit: "g"))
        XCTAssertNil(UnitAmount(quantity: 100, unit: nil))
    }

    func testCustomProducts() {
        XCTAssertEqual(Product.customCode(for: "  Riz   Parfumé "), "custom:riz parfume")
        let product = Product.custom(named: "  Bananes ")
        XCTAssertTrue(product.isCustom)
        XCTAssertEqual(product.name, "Bananes")
        XCTAssertEqual(Product.custom(named: "BANANES").code, product.code)
        XCTAssertFalse(Fixtures.nutella.isCustom)
        XCTAssertEqual(Fixtures.nutella.normalizedAmount?.unit, "kg")
    }
}

final class FormattingTests: XCTestCase {
    func testBarcodeDetection() {
        XCTAssertTrue("3017620422003".isBarcodeLike)
        XCTAssertTrue("12345670".isBarcodeLike)
        XCTAssertFalse("301762".isBarcodeLike)
        XCTAssertFalse("30176204220a3".isBarcodeLike)
        XCTAssertFalse("123456789012345".isBarcodeLike)
    }

    func testBlankStrings() {
        XCTAssertNil("   ".nilIfBlank)
        XCTAssertEqual(" a ".nilIfBlank, " a ")
        XCTAssertEqual("  lait \n".trimmed, "lait")
    }

    func testDistance() {
        XCTAssertEqual(Fmt.distance(234), "230 m")
        XCTAssertEqual(Fmt.distance(1540), "1,5 km")
        XCTAssertEqual(Fmt.distance(12_345), "12,3 km")
    }

    func testJoinFuelAndPercent() {
        XCTAssertEqual(Fmt.join("a", nil, "", "b"), "a · b")
        XCTAssertEqual(Fmt.fuel(1.849), "1,849 €")
        XCTAssertEqual(Fmt.percent(8.4), "+8 %")
        XCTAssertEqual(Fmt.percent(-12.6), "-13 %")
        XCTAssertEqual(Fmt.percent(0.2), "0 %")
    }

    func testRelativeTimes() {
        let now = Date()
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-30), now: now), "à l'instant")
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-25 * 60), now: now), "il y a 25 min")
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-3 * 3600 - 60), now: now), "il y a 3 h")
        XCTAssertEqual(Fmt.day(.distantPast), "date inconnue")
        XCTAssertEqual(Fmt.day(Date()), "aujourd'hui")
    }
}
