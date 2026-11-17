import XCTest
import CoreGraphics
@testable import Lemwincher

final class AmountTests: XCTestCase {
    private func values(_ text: String) -> [Double] {
        Amounts.values(in: text).map { ($0 * 100).rounded() / 100 }
    }

    func testPriceFormats() {
        XCTAssertEqual(values("2,49 €"), [2.49])
        XCTAssertEqual(values("2€49"), [2.49])
        XCTAssertEqual(values("€ 12.90"), [12.90])
        XCTAssertEqual(values("Prix au kg : 8,23 €"), [8.23])
        XCTAssertEqual(values("2 x 1,20   2,40"), [1.20, 2.40])
    }

    func testNotPrices() {
        XCTAssertEqual(values("12.05.2026"), [])
        XCTAssertEqual(values("0,750 L"), [])
        XCTAssertEqual(values("1,5 kg"), [])
        XCTAssertEqual(values("NUTELLA 400G"), [])
    }
}

final class PriceTagParserTests: XCTestCase {
    private func piece(_ text: String, height: CGFloat, y: CGFloat = 0.5) -> RecognizedText {
        RecognizedText(text: text, box: CGRect(x: 0.1, y: y, width: 0.6, height: height))
    }

    func testBiggestPriceWinsOverUnitPrice() {
        let tag = [
            piece("NUTELLA 400G", height: 0.05, y: 0.8),
            piece("3,29 €", height: 0.20, y: 0.5),
            piece("Prix au kg : 8,23 €", height: 0.04, y: 0.2),
        ]
        XCTAssertEqual(PriceTagParser.bestPrice(in: tag) ?? 0, 3.29, accuracy: 1e-9)
    }

    func testUnitPriceWhenItIsTheOnlyPrice() {
        let tag = [piece("BANANES", height: 0.05), piece("1,99 € le kg", height: 0.2)]
        XCTAssertEqual(PriceTagParser.bestPrice(in: tag) ?? 0, 1.99, accuracy: 1e-9)
        XCTAssertNil(PriceTagParser.bestPrice(in: [piece("PROMO", height: 0.3)]))
    }

    func testUnitPriceLineDetection() {
        XCTAssertTrue(PriceTagParser.isUnitPriceLine("8,23 €/KG"))
        XCTAssertTrue(PriceTagParser.isUnitPriceLine("Le litre : 1,10 €"))
        XCTAssertTrue(PriceTagParser.isUnitPriceLine("1,10 €/L"))
        XCTAssertFalse(PriceTagParser.isUnitPriceLine("3,29 €"))
        XCTAssertFalse(PriceTagParser.isUnitPriceLine("NUTELLA 1KG"))
    }

    func testEANChecksum() {
        XCTAssertTrue(PriceTagParser.isValidEAN("3017620422003"))
        XCTAssertFalse(PriceTagParser.isValidEAN("3017620422004"))
        XCTAssertTrue(PriceTagParser.isValidEAN("12345670"))
        XCTAssertFalse(PriceTagParser.isValidEAN("12345"))
        XCTAssertFalse(PriceTagParser.isValidEAN("301762042200a"))
    }

    func testBarcodeDigitsOnTag() {
        let tag = [piece("3 017620 422003", height: 0.03), piece("3,29", height: 0.2)]
        XCTAssertEqual(PriceTagParser.barcode(in: tag), "3017620422003")
        XCTAssertNil(PriceTagParser.barcode(in: [piece("1234567890123", height: 0.03)]))
    }
}

final class ReceiptParserTests: XCTestCase {
    private let rows = [
        "CARREFOUR MARKET",
        "TOULOUSE MINIMES",
        "LAIT DEMI ECREME 1L    0,95",
        "NUTELLA 400G    3,29 A",
        "YAOURT NATURE X4",
        "2 x 1,20    2,40",
        "BANANES",
        "0,512 kg x 2,99 €/kg    1,53",
        "REMISE FIDELITE    -0,50",
        "TOTAL    8,17",
        "CB    8,17",
        "MERCI DE VOTRE VISITE",
    ]

    func testItemsFromReceipt() {
        let items = ReceiptParser.items(fromRows: rows)
        XCTAssertEqual(items.map(\.name), ["Lait demi ecreme 1l", "Nutella 400g", "Yaourt nature x4", "Bananes"])
        XCTAssertEqual(items.map { ($0.price * 100).rounded() / 100 }, [0.95, 3.29, 1.20, 1.53])
        XCTAssertEqual(items.map(\.quantity), [1, 1, 2, 1])
        XCTAssertTrue(items.allSatisfy(\.include))
    }

    func testTotalAndChain() {
        XCTAssertEqual(ReceiptParser.total(fromRows: rows) ?? 0, 8.17, accuracy: 1e-9)
        XCTAssertEqual(ReceiptParser.chainKey(fromRows: rows), "carrefour market")
        XCTAssertNil(ReceiptParser.chainKey(fromRows: ["BOULANGERIE DU COIN", "PAIN 1,20"]))
    }

    func testQuantityLineWithoutPendingNameUpdatesPreviousItem() {
        let items = ReceiptParser.items(fromRows: ["COCA COLA 1,5L    1,89", "3 X 1,89    5,67"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.quantity, 3)
        XCTAssertEqual(items.first?.price ?? 0, 1.89, accuracy: 1e-9)
    }

    func testRowsAreGroupedByLine() {
        // Origine en bas à gauche : y plus grand = plus haut sur le ticket.
        let pieces = [
            RecognizedText(text: "0,95", box: CGRect(x: 0.75, y: 0.701, width: 0.1, height: 0.02)),
            RecognizedText(text: "LAIT 1L", box: CGRect(x: 0.05, y: 0.70, width: 0.3, height: 0.02)),
            RecognizedText(text: "3,29", box: CGRect(x: 0.75, y: 0.65, width: 0.1, height: 0.02)),
            RecognizedText(text: "NUTELLA", box: CGRect(x: 0.05, y: 0.652, width: 0.3, height: 0.02)),
            RecognizedText(text: "CARREFOUR", box: CGRect(x: 0.3, y: 0.9, width: 0.4, height: 0.03)),
        ]
        XCTAssertEqual(ReceiptParser.rows(from: pieces), ["CARREFOUR", "LAIT 1L  0,95", "NUTELLA  3,29"])
    }
}
