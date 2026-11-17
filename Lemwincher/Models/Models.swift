import Foundation
import CoreLocation

// MARK: - Position

struct GeoPoint: Codable, Hashable {
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
}

// MARK: - Magasin

struct Store: Identifiable, Codable, Hashable {
    /// "NODE:123" / "WAY:456" pour OpenStreetMap (mêmes identifiants qu'Open Prices),
    /// "apple:lat,lon" pour un magasin trouvé via Plans.
    var id: String
    var name: String
    var brand: String?
    var kind: String?
    var address: String?
    var lat: Double
    var lon: Double
    var priceCount: Int?
    var logoURL: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }

    /// Type OSM ("NODE", "WAY", "RELATION") si le magasin vient d'OpenStreetMap.
    var osmType: String? { osmParts?.type }
    var osmId: Int? { osmParts?.id }

    private var osmParts: (type: String, id: Int)? {
        let parts = id.split(separator: ":")
        guard parts.count == 2,
              ["NODE", "WAY", "RELATION"].contains(String(parts[0])),
              let number = Int(parts[1]) else { return nil }
        return (String(parts[0]), number)
    }

    /// Enseigne normalisée ("e leclerc", "carrefour market"…), si reconnue.
    var chainKey: String? { Chain.key(brand: brand, name: name) }

    /// Nom de l'enseigne à afficher.
    var chainName: String? {
        guard let key = chainKey else { return nil }
        return Chain.displayName(for: key) ?? brand ?? name
    }

    /// Supermarché / hypermarché / grossiste (par opposition aux supérettes).
    var isSupermarket: Bool {
        ["supermarket", "hypermarket", "wholesale"].contains(kind ?? "")
    }

    /// Logo d'Open Prices, sinon celui de l'enseigne dans la banque d'images d'Open Food Facts.
    var displayLogoURL: String? { logoURL ?? Chain.logoURL(brand: brand) }

    func distance(from reference: CLLocation?) -> CLLocationDistance? {
        guard let reference else { return nil }
        return location.distance(from: reference)
    }

    var directionsURL: URL? {
        let label = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&q=\(label)")
    }
}

// MARK: - Produit

struct Product: Identifiable, Codable, Hashable {
    /// Code-barres (EAN) ou "custom:<nom normalisé>" pour un produit sans code-barres.
    var code: String
    var name: String
    var brand: String?
    var quantity: String?
    var imageURL: String?
    /// Contenance chiffrée (ex. 400) et son unité (ex. "g"), pour le prix au kilo / au litre.
    var unitQuantity: Double?
    var unitName: String?
    /// Catégories Open Food Facts (ex. "en:cocoa-and-hazelnuts-spreads").
    var categories: [String]?

    var id: String { code }
    var isCustom: Bool { code.hasPrefix("custom:") }
    var hasDetails: Bool { !name.isEmpty && name != code }

    /// Contenance ramenée au kg ou au litre.
    var normalizedAmount: UnitAmount? { UnitAmount(quantity: unitQuantity, unit: unitName) }

    static func custom(named name: String) -> Product {
        Product(code: customCode(for: name), name: name.trimmed)
    }

    /// Même nom (sans tenir compte des majuscules/accents) => même produit.
    static func customCode(for name: String) -> String {
        let key = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "custom:" + key
    }
}

/// Contenance d'un produit exprimée en kg ou en litres.
struct UnitAmount: Hashable {
    let value: Double
    let unit: String

    init?(quantity: Double?, unit: String?) {
        guard let quantity, quantity > 0, let raw = unit?.trimmed.lowercased() else { return nil }
        switch raw {
        case "g", "gr", "grammes": value = quantity / 1000; self.unit = "kg"
        case "kg": value = quantity; self.unit = "kg"
        case "mg": value = quantity / 1_000_000; self.unit = "kg"
        case "ml": value = quantity / 1000; self.unit = "L"
        case "cl": value = quantity / 100; self.unit = "L"
        case "dl": value = quantity / 10; self.unit = "L"
        case "l": value = quantity; self.unit = "L"
        default: return nil
        }
    }

    func unitPrice(_ price: Double) -> Double { price / value }

    func unitPriceText(_ price: Double, currency: String) -> String {
        "\(Fmt.price(unitPrice(price), currency))/\(unit)"
    }
}

// MARK: - Données de l'utilisateur

/// Un prix relevé par l'utilisateur dans un magasin.
struct MyPrice: Identifiable, Codable, Hashable {
    var id = UUID()
    var product: Product
    var store: Store
    var price: Double
    var currency: String
    var date: Date
    var isDiscounted: Bool = false
    /// Identifiant du prix sur Open Prices s'il a été partagé.
    var sharedPriceID: Int?
}

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var product: Product
    var quantity: Int = 1
    var checked: Bool = false
}

struct AppSettings: Codable, Hashable {
    var radiusKm: Double = 8
    var useHome: Bool = false
    var home: GeoPoint?
    var homeLabel: String?
    var currency: String = AppSettings.defaultCurrency
    var supermarketsOnly: Bool = true
    var favoritesOnly: Bool = false
    var favoriteStores: [Store] = []

    static let currencies = ["EUR", "KMF", "XOF", "XAF", "MGA", "MUR", "MAD", "DZD", "TND", "CHF", "GBP", "USD", "CAD"]

    static var defaultCurrency: String {
        let code = Locale.current.currency?.identifier ?? "EUR"
        return currencies.contains(code) ? code : "EUR"
    }

    init() {}

    // Décodage tolérant : une clé manquante ne doit jamais faire perdre les données.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        radiusKm = (try? c.decode(Double.self, forKey: .radiusKm)) ?? 8
        useHome = (try? c.decode(Bool.self, forKey: .useHome)) ?? false
        home = try? c.decode(GeoPoint.self, forKey: .home)
        homeLabel = try? c.decode(String.self, forKey: .homeLabel)
        currency = (try? c.decode(String.self, forKey: .currency)) ?? AppSettings.defaultCurrency
        supermarketsOnly = (try? c.decode(Bool.self, forKey: .supermarketsOnly)) ?? true
        favoritesOnly = (try? c.decode(Bool.self, forKey: .favoritesOnly)) ?? false
        favoriteStores = (try? c.decode([Store].self, forKey: .favoriteStores)) ?? []
    }
}

/// Tout ce qui est sauvegardé sur l'iPhone.
struct PersistedState: Codable, Equatable {
    var settings = AppSettings()
    var myPrices: [MyPrice] = []
    var shoppingList: [ShoppingItem] = []
    var recentProducts: [Product] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decode(AppSettings.self, forKey: .settings)) ?? AppSettings()
        myPrices = (try? c.decode([MyPrice].self, forKey: .myPrices)) ?? []
        shoppingList = (try? c.decode([ShoppingItem].self, forKey: .shoppingList)) ?? []
        recentProducts = (try? c.decode([Product].self, forKey: .recentProducts)) ?? []
    }
}
