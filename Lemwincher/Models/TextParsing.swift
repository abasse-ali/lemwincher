import Foundation
import CoreGraphics

/// Un morceau de texte reconnu sur une photo (coordonnées normalisées 0…1, origine en bas à gauche).
struct RecognizedText: Equatable {
    let text: String
    let box: CGRect
}

/// Un montant trouvé dans un texte, avec sa position.
struct AmountMatch: Equatable {
    let value: Double
    let range: NSRange
}

enum Amounts {
    /// "2,49" "2.49 €" "2€49" "€ 2,49" — mais pas "12.05.2026", "0,750 L" ni "1,5 kg".
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,4})\s?(?:[.,]|€)\s?(\d{2})(?!\d)(?![.,]\d)"#
    )

    static func matches(in text: String) -> [AmountMatch] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let units = Int(ns.substring(with: match.range(at: 1))),
                  let cents = Int(ns.substring(with: match.range(at: 2))) else { return nil }
            return AmountMatch(value: Double(units) + Double(cents) / 100, range: match.range)
        }
    }

    static func values(in text: String) -> [Double] {
        matches(in: text).map(\.value)
    }
}

// MARK: - Étiquette de prix

enum PriceTagParser {
    /// Ligne qui donne un prix au kilo / au litre plutôt que le prix de vente.
    static func isUnitPriceLine(_ text: String) -> Bool {
        let t = " " + Chain.normalize(text) + " "
        let markers = [" kg ", " le l ", " litre ", " prix au ", " au l ", " 100 g ", " 100g ", " 100 ml ", " par kg ", " le k "]
        return markers.contains { t.contains($0) } || text.lowercased().contains("/l")
    }

    /// Prix de vente le plus probable : le plus grand texte contenant un montant
    /// (le prix au kilo, écrit en petit, est écarté s'il y a mieux).
    static func bestPrice(in pieces: [RecognizedText]) -> Double? {
        var regular: [(value: Double, size: CGFloat)] = []
        var perUnit: [(value: Double, size: CGFloat)] = []
        for piece in pieces {
            let values = Amounts.values(in: piece.text).filter { $0 >= 0.05 && $0 < 1000 }
            for value in values {
                if isUnitPriceLine(piece.text) {
                    perUnit.append((value, piece.box.height))
                } else {
                    regular.append((value, piece.box.height))
                }
            }
        }
        let pool = regular.isEmpty ? perUnit : regular
        return pool.max { a, b in a.size == b.size ? a.value < b.value : a.size < b.size }?.value
    }

    /// Code-barres EAN-13 / EAN-8 imprimé en chiffres sur l'étiquette.
    static func barcode(in pieces: [RecognizedText]) -> String? {
        for piece in pieces {
            let digits = piece.text.filter { $0.isASCII && $0.isNumber }
            if (digits.count == 13 || digits.count == 8), isValidEAN(digits) { return digits }
        }
        return nil
    }

    /// Vérifie la clé de contrôle d'un EAN-8 / EAN-13 / UPC-A.
    static func isValidEAN(_ code: String) -> Bool {
        let digits = code.compactMap { $0.wholeNumberValue }
        guard [8, 12, 13].contains(digits.count), digits.count == code.count else { return false }
        let body = digits.dropLast()
        var sum = 0
        for (index, digit) in body.reversed().enumerated() {
            sum += index % 2 == 0 ? digit * 3 : digit
        }
        let check = (10 - sum % 10) % 10
        return check == digits.last
    }
}

// MARK: - Ticket de caisse

struct ReceiptItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    /// Prix unitaire.
    var price: Double
    var quantity: Int = 1
    var include: Bool = true
}

enum ReceiptParser {
    /// Lignes à ignorer : totaux, TVA, paiement, fidélité…
    private static let ignoredWords: Set<String> = [
        "total", "totaux", "tva", "bancaire", "cb", "espece", "especes", "rendu", "payer", "montant", "paiement",
        "fidelite", "cagnotte", "remise", "avantage", "ticket", "siret", "merci", "caisse", "visa", "mastercard",
        "credit", "debit", "solde", "economie", "economies", "bon", "article", "articles", "monnaie", "tel",
        "client", "transaction", "points", "emv", "cheque", "acompte", "sous", "net", "ht", "ttc", "rembourse",
    ]

    private static let quantityPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,3})\s*[xX×*]\s*(\d{1,4})[.,](\d{2})"#
    )

    /// Regroupe les morceaux reconnus en lignes du ticket, de haut en bas, de gauche à droite.
    static func rows(from pieces: [RecognizedText]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var rows: [[RecognizedText]] = []
        for piece in sorted {
            if let reference = rows.last?.first {
                let tolerance = max(min(reference.box.height, piece.box.height) * 0.6, 0.002)
                if abs(reference.box.midY - piece.box.midY) < tolerance {
                    rows[rows.count - 1].append(piece)
                    continue
                }
            }
            rows.append([piece])
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ")
        }
    }

    /// Articles et prix d'un ticket de caisse.
    static func items(fromRows rows: [String]) -> [ReceiptItem] {
        var items: [ReceiptItem] = []
        var pendingName: String? = nil

        for row in rows {
            let normalized = Chain.normalize(row)
            let words = Set(normalized.split(separator: " ").map(String.init))
            if !words.isDisjoint(with: ignoredWords) {
                pendingName = nil
                continue
            }

            // "2 x 1,20" : quantité et prix unitaire de l'article nommé juste avant.
            let ns = row as NSString
            if let match = quantityPattern.firstMatch(in: row, range: NSRange(location: 0, length: ns.length)),
               let quantity = Int(ns.substring(with: match.range(at: 1))),
               let units = Int(ns.substring(with: match.range(at: 2))),
               let cents = Int(ns.substring(with: match.range(at: 3))),
               quantity > 0 {
                let unitPrice = Double(units) + Double(cents) / 100
                if let pending = pendingName {
                    items.append(ReceiptItem(name: pending, price: unitPrice, quantity: quantity))
                    pendingName = nil
                } else if !items.isEmpty {
                    items[items.count - 1].quantity = quantity
                    items[items.count - 1].price = unitPrice
                }
                continue
            }

            guard let amount = Amounts.matches(in: row).last else {
                if letterCount(row) >= 3 { pendingName = cleanName(row) }
                continue
            }
            // Montant négatif (remise, bon de réduction) : ignoré.
            if amount.range.location > 0 {
                let before = ns.substring(with: NSRange(location: 0, length: amount.range.location)).trimmed
                if before.hasSuffix("-") { continue }
            }
            guard amount.value > 0, amount.value < 500 else { continue }

            var name = cleanName(ns.substring(with: NSRange(location: 0, length: amount.range.location)))
            if letterCount(name) < 3 || isWeightDetail(name) {
                guard let pending = pendingName else { continue }
                name = pending
            }
            items.append(ReceiptItem(name: name, price: amount.value))
            pendingName = nil
        }
        return items
    }

    /// Montant total du ticket (le plus grand montant d'une ligne "total").
    static func total(fromRows rows: [String]) -> Double? {
        rows
            .filter { row in
                let words = Set(Chain.normalize(row).split(separator: " ").map(String.init))
                return (words.contains("total") || words.contains("payer")) && !words.contains("tva") && !words.contains("sous")
            }
            .flatMap { Amounts.values(in: $0) }
            .max()
    }

    /// Enseigne reconnue dans l'en-tête du ticket ("CARREFOUR MARKET" -> "carrefour market").
    static func chainKey(fromRows rows: [String]) -> String? {
        for row in rows.prefix(8) {
            if let key = Chain.key(brand: nil, name: row) { return key }
        }
        return nil
    }

    /// Ligne de détail d'un article pesé : "0,512 kg x 2,99 €/kg".
    private static func isWeightDetail(_ text: String) -> Bool {
        let t = Chain.normalize(text)
        return t.contains("kg") && t.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private static func letterCount(_ text: String) -> Int {
        text.filter(\.isLetter).count
    }

    /// "LAIT DEMI ECREME 1L  *" -> "Lait demi ecreme 1l".
    private static func cleanName(_ raw: String) -> String {
        var words = raw
            .replacingOccurrences(of: "€", with: " ")
            .replacingOccurrences(of: "*", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        // Code article en tête ("1234567 LAIT…").
        while let first = words.first, first.count >= 4, first.allSatisfy({ $0.isNumber }) {
            words.removeFirst()
        }
        while let last = words.last, last.uppercased() == "EUR" || (last.count == 1 && !last.first!.isNumber) {
            words.removeLast()
        }
        let joined = words.joined(separator: " ").lowercased()
        return Recall.sentenceCase(joined)
    }
}
