import Foundation
import CoreLocation
@testable import Lemwincher

/// Données de test communes.
enum Fixtures {
    /// Calendrier fixe (Paris) pour des tests indépendants du simulateur.
    static let paris: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }()

    /// Date à Paris. Le 16 novembre 2026 est un lundi.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Jour fixe (secondes entières, pour les comparaisons après encodage ISO 8601).
    static func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_780_000_000 + Double(offset) * 86_400)
    }

    static func obs(_ price: Double,
                    store: String = "NODE:1",
                    product: String = "3017620422003",
                    chain: String? = "carrefour",
                    date: Date = Fixtures.day(0),
                    discounted: Bool = false,
                    currency: String = "EUR",
                    country: String? = "FR",
                    source: PriceObservation.Source = .community,
                    unitQuantity: Double? = nil,
                    unitName: String? = nil,
                    lat: Double? = 43.6045,
                    lon: Double? = 1.4433,
                    id: String = UUID().uuidString) -> PriceObservation {
        PriceObservation(id: id,
                         productCode: product,
                         productName: "Produit \(product)",
                         brand: nil,
                         quantity: nil,
                         imageURL: nil,
                         unitQuantity: unitQuantity,
                         unitName: unitName,
                         categories: nil,
                         price: price,
                         currency: currency,
                         date: date,
                         isDiscounted: discounted,
                         storeKey: store,
                         storeName: "Magasin \(store)",
                         storeAddress: nil,
                         lat: lat,
                         lon: lon,
                         chainKey: chain,
                         chainName: chain.flatMap { Chain.displayName(for: $0) } ?? chain,
                         countryCode: country,
                         source: source)
    }

    static func store(_ id: String,
                      name: String = "Magasin",
                      brand: String? = nil,
                      kind: String? = "supermarket",
                      lat: Double = 43.6045,
                      lon: Double = 1.4433) -> Store {
        Store(id: id, name: name, brand: brand, kind: kind, address: nil,
              lat: lat, lon: lon, priceCount: nil, logoURL: nil)
    }

    static let nutella = Product(code: "3017620422003", name: "Nutella", brand: "Ferrero", quantity: "400 g",
                                 imageURL: nil, unitQuantity: 400, unitName: "g", categories: nil)

    static func json(_ text: String) -> Data { Data(text.utf8) }

    static func snakeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
