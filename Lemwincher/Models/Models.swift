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
    /// Horaires au format OpenStreetMap ("Mo-Sa 08:30-20:00; Su 09:00-12:30"), téléphone et site, si connus.
    var openingHours: String? = nil
    var phone: String? = nil
    var website: String? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }

    /// Horaires interprétés (nil si inconnus ou dans un format non géré).
    var hours: OpeningHours? {
        guard let openingHours else { return nil }
        return OpeningHours(openingHours)
    }

    var phoneURL: URL? {
        guard let phone = phone?.nilIfBlank else { return nil }
        let digits = phone.split(separator: ";").first.map(String.init) ?? phone
        let cleaned = digits.filter { $0.isNumber || $0 == "+" }
        return cleaned.isEmpty ? nil : URL(string: "tel:" + cleaned)
    }

    var websiteURL: URL? {
        guard let website = website?.nilIfBlank?.trimmed else { return nil }
        let full = website.lowercased().hasPrefix("http") ? website : "https://" + website
        return URL(string: full)
    }

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

    /// Supermarché / hypermarché / grossiste / surgelés / bio (par opposition aux supérettes).
    var isSupermarket: Bool {
        ["supermarket", "hypermarket", "wholesale", "frozen_food", "organic"].contains(kind ?? "")
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

    /// Contenance ramenée au kg ou au litre (chiffrée, sinon lue dans le texte "500 g", "6 x 1,5 L"…).
    var normalizedAmount: UnitAmount? {
        UnitAmount(quantity: unitQuantity, unit: unitName) ?? UnitAmount.parse(quantity)
    }

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

    /// Lit une contenance écrite : "500 g (4 x 125 g)" -> 0,5 kg, "6x1.5L" -> 9 L, "1,5 kg" -> 1,5 kg.
    static func parse(_ text: String?) -> UnitAmount? {
        guard let text = text?.trimmed, !text.isEmpty else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let match = multipackPattern.firstMatch(in: text, range: range),
           let count = Double(ns.substring(with: match.range(at: 1))),
           let each = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ".")),
           count > 0, count < 100,
           let amount = UnitAmount(quantity: count * each, unit: ns.substring(with: match.range(at: 3))) {
            return amount
        }
        if let match = singlePattern.firstMatch(in: text, range: range),
           let value = Double(ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")) {
            return UnitAmount(quantity: value, unit: ns.substring(with: match.range(at: 2)))
        }
        return nil
    }

    private static let multipackPattern = try! NSRegularExpression(
        pattern: #"(\d{1,2})\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(kg|g|gr|mg|l|cl|ml|dl)\b"#,
        options: [.caseInsensitive]
    )
    private static let singlePattern = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*(kg|g|gr|mg|l|cl|ml|dl)\b"#,
        options: [.caseInsensitive]
    )

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
    /// Origine du relevé quand il ne vient pas du magasin lui-même ("site Carrefour").
    var source: String? = nil
}

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Ce que l'utilisateur a noté ("Œufs") ou un produit précis.
    var product: Product
    var quantity: Int = 1
    var checked: Bool = false
    /// Produit précis choisi sous un article générique ("6 œufs plein air Loué").
    var choice: Product? = nil
    /// Dépense créée en cochant l'article (acheté) ; retirée si on le décoche.
    var expenseID: UUID? = nil

    /// Le produit dont on compare le prix : le choix s'il existe.
    var pricedProduct: Product { choice ?? product }
}

/// Un produit dont on surveille le prix autour de soi.
struct WatchItem: Identifiable, Codable, Hashable {
    var product: Product
    /// Prix sous lequel l'utilisateur veut être prévenu (facultatif).
    var targetPrice: Double? = nil
    /// Meilleur prix connu autour de soi lors de la dernière vérification.
    var bestPrice: Double? = nil
    var bestStoreName: String? = nil
    var bestDate: Date? = nil
    var lastChecked: Date? = nil
    /// Une baisse a été trouvée et pas encore vue par l'utilisateur.
    var hasNewDrop: Bool = false
    var previousBestPrice: Double? = nil
    var createdAt: Date = Date()

    var id: String { product.code }
}

extension WatchItem {
    enum CodingKeys: String, CodingKey {
        case product, targetPrice, bestPrice, bestStoreName, bestDate, lastChecked, hasNewDrop, previousBestPrice, createdAt
    }

    // Décodage tolérant, comme pour le reste des données sauvegardées.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        product = try c.decode(Product.self, forKey: .product)
        targetPrice = try? c.decode(Double.self, forKey: .targetPrice)
        bestPrice = try? c.decode(Double.self, forKey: .bestPrice)
        bestStoreName = try? c.decode(String.self, forKey: .bestStoreName)
        bestDate = try? c.decode(Date.self, forKey: .bestDate)
        lastChecked = try? c.decode(Date.self, forKey: .lastChecked)
        hasNewDrop = (try? c.decode(Bool.self, forKey: .hasNewDrop)) ?? false
        previousBestPrice = try? c.decode(Double.self, forKey: .previousBestPrice)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
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
    var fuelType: FuelType = .gazole
    var hasSeenOnboarding: Bool = false
    var openNowOnly: Bool = false
    /// Budget courses par période (mois).
    var budgetAmount: Double = 100
    /// Jour du mois où le budget repart à zéro (1 = le 1er ; ex. 5 si la paie arrive le 5).
    var budgetStartDay: Int = 1
    var budgetAlerts: Bool = true
    /// Ne propose ni produits ni recettes au porc (lardons et jambon de dinde, chorizo de bœuf… restent).
    var noPork: Bool = true
    /// Recettes végétariennes seulement.
    var vegetarian: Bool = false
    /// Nombre de personnes proposé pour les recettes (1, 2 ou 4 le plus souvent).
    var defaultServings: Int = 1
    /// Mode cuisine : lire chaque étape à voix haute.
    var readStepsAloud: Bool = false

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
        fuelType = (try? c.decode(FuelType.self, forKey: .fuelType)) ?? .gazole
        hasSeenOnboarding = (try? c.decode(Bool.self, forKey: .hasSeenOnboarding)) ?? false
        openNowOnly = (try? c.decode(Bool.self, forKey: .openNowOnly)) ?? false
        budgetAmount = (try? c.decode(Double.self, forKey: .budgetAmount)) ?? 100
        budgetStartDay = (try? c.decode(Int.self, forKey: .budgetStartDay)) ?? 1
        budgetAlerts = (try? c.decode(Bool.self, forKey: .budgetAlerts)) ?? true
        noPork = (try? c.decode(Bool.self, forKey: .noPork)) ?? true
        vegetarian = (try? c.decode(Bool.self, forKey: .vegetarian)) ?? false
        defaultServings = min(max((try? c.decode(Int.self, forKey: .defaultServings)) ?? 1, 1), 12)
        readStepsAloud = (try? c.decode(Bool.self, forKey: .readStepsAloud)) ?? false
    }
}

/// Tout ce qui est sauvegardé sur l'iPhone.
struct PersistedState: Codable, Equatable {
    var settings = AppSettings()
    var myPrices: [MyPrice] = []
    var shoppingList: [ShoppingItem] = []
    var recentProducts: [Product] = []
    var watchlist: [WatchItem] = []
    var expenses: [Expense] = []
    /// Recettes mises en favori (identifiants).
    var favoriteRecipes: [String] = []
    /// Menu de la semaine (identifiants des recettes, dans l'ordre des jours).
    var weekMenu: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decode(AppSettings.self, forKey: .settings)) ?? AppSettings()
        myPrices = (try? c.decode([MyPrice].self, forKey: .myPrices)) ?? []
        shoppingList = (try? c.decode([ShoppingItem].self, forKey: .shoppingList)) ?? []
        recentProducts = (try? c.decode([Product].self, forKey: .recentProducts)) ?? []
        watchlist = (try? c.decode([WatchItem].self, forKey: .watchlist)) ?? []
        expenses = ((try? c.decode([Lossy<Expense>].self, forKey: .expenses)) ?? []).compactMap(\.value)
        favoriteRecipes = (try? c.decode([String].self, forKey: .favoriteRecipes)) ?? []
        weekMenu = (try? c.decode([String].self, forKey: .weekMenu)) ?? []
    }
}

/// Onglets de l'app (pour y naviguer depuis Siri ou une notification). Les réglages s'ouvrent avec ⚙︎.
enum AppTab: Hashable {
    case stores, compare, recipes, list, budget
}
