import XCTest
@testable import Lemwincher

/// Identité visuelle : emojis des produits sans photo, couleurs des enseignes, format des prix, apparence.
final class VisualsTests: XCTestCase {
    func testProductEmojiFromName() {
        XCTAssertEqual(ProductEmoji.emoji(for: "Œufs"), "🥚")
        XCTAssertEqual(ProductEmoji.emoji(for: "6 œufs bio"), "🥚")
        XCTAssertEqual(ProductEmoji.emoji(for: "Bananes (1 kg)"), "🍌")
        XCTAssertEqual(ProductEmoji.emoji(for: "Pommes Gala"), "🍎")
        XCTAssertEqual(ProductEmoji.emoji(for: "Pommes de terre de consommation"), "🥔", "pas une pomme")
        XCTAssertEqual(ProductEmoji.emoji(for: "Nutella"), "🍫")
        XCTAssertEqual(ProductEmoji.emoji(for: "Petites Madeleines"), "🥐")
        XCTAssertEqual(ProductEmoji.emoji(for: "Pain au chocolat x6"), "🥐", "ni pain ni chocolat")
        XCTAssertEqual(ProductEmoji.emoji(for: "Lait demi-écrémé"), "🥛")
        XCTAssertEqual(ProductEmoji.emoji(for: "Lait de coco"), "🥥")
        XCTAssertEqual(ProductEmoji.emoji(for: "Beurre doux"), "🧈")
        XCTAssertEqual(ProductEmoji.emoji(for: "Spaghetti n°5"), "🍝")
        XCTAssertEqual(ProductEmoji.emoji(for: "Maïs doux"), "🌽")
        XCTAssertEqual(ProductEmoji.emoji(for: "Thé vert"), "🍵")
    }

    func testProductEmojiAvoidsFalseMatches() {
        XCTAssertEqual(ProductEmoji.emoji(for: "Laitue iceberg"), "🥬", "« lait » ne trouve pas « laitue »")
        XCTAssertEqual(ProductEmoji.emoji(for: "Vinaigre balsamique"), "🫒", "« vin » ne trouve pas « vinaigre »")
        XCTAssertNotEqual(ProductEmoji.emoji(for: "Tarte maison"), "🌽", "« maïs » ne trouve pas « maison »")
        XCTAssertNil(ProductEmoji.emoji(for: "Kit boba"))
        XCTAssertNil(ProductEmoji.emoji(for: "   "))
    }

    func testChainStyles() throws {
        XCTAssertEqual(ChainStyle.forChain("e leclerc")?.monogram, "E")
        XCTAssertEqual(ChainStyle.forChain("carrefour city")?.monogram, "C")
        XCTAssertEqual(ChainStyle.forChain("carrefour market")?.hex, ChainStyle.forChain("carrefour")?.hex)
        XCTAssertEqual(ChainStyle.forChain("le petit casino")?.monogram, "C")
        XCTAssertEqual(ChainStyle.forChain("grand frais")?.monogram, "GF")
        XCTAssertEqual(ChainStyle.forChain("Aldi")?.monogram, "A", "un nom d'enseigne marche aussi")
        XCTAssertNil(ChainStyle.forChain("epicerie du coin"))
        XCTAssertNil(ChainStyle.forChain("lidlfoo"), "le préfixe doit être un mot entier")
        XCTAssertNil(ChainStyle.forChain(nil))

        // Chaque magasin reconnu par Chain.key retrouve son style.
        let store = Fixtures.store("NODE:1", name: "Super U Toulouse", brand: "Super U")
        XCTAssertEqual(ChainStyle.forChain(store.chainKey)?.monogram, "U")

        let rgb = try XCTUnwrap(ChainStyle.forChain("e leclerc")).rgb
        XCTAssertEqual(rgb.red, 0, accuracy: 0.001)
        XCTAssertEqual(rgb.green, 0x60 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgb.blue, 0xAA / 255.0, accuracy: 0.001)
    }

    func testPricesUseFrenchFormat() {
        let text = Fmt.price(2.35, "EUR")
        XCTAssertTrue(text.hasPrefix("2,35"), text)
        XCTAssertTrue(text.hasSuffix("€"), text)
        XCTAssertTrue(Fmt.price(1500, "EUR").contains("500,00"), Fmt.price(1500, "EUR"))
    }

    func testAppearanceSetting() throws {
        XCTAssertEqual(AppSettings().appearance, .system)
        var settings = AppSettings()
        settings.appearance = .dark
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.appearance, .dark)
        let old = try JSONDecoder().decode(AppSettings.self, from: Fixtures.json(#"{"radiusKm": 5}"#))
        XCTAssertEqual(old.appearance, .system, "ancienne sauvegarde : comme l'iPhone")
        XCTAssertEqual(AppAppearance.allCases.map(\.label), ["Comme l'iPhone", "Clair", "Sombre"])
    }
}
