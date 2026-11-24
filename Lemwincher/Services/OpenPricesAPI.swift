import Foundation

// MARK: - Modèles Open Prices (https://prices.openfoodfacts.org)

struct OPPage<T: Decodable>: Decodable {
    let items: [T]
    let total: Int?

    private enum CodingKeys: String, CodingKey {
        case items, total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? c.decode([Lossy<T>].self, forKey: .items)) ?? []).compactMap(\.value)
        total = c.lossyInt(.total)
    }
}

struct OPProduct: Decodable {
    let code: String
    let productName: String?
    let brands: String?
    let quantity: String?
    let imageUrl: String?
    let priceCount: Int?
    let locationCount: Int?
    let productQuantity: Double?
    let productQuantityUnit: String?
    let categoriesTags: [String]?

    private enum CodingKeys: String, CodingKey {
        case code, productName, brands, quantity, imageUrl, priceCount, locationCount
        case productQuantity, productQuantityUnit, categoriesTags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let code = c.lossyString(.code), !code.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .code, in: c, debugDescription: "code manquant")
        }
        self.code = code
        productName = c.lossyString(.productName)
        brands = c.lossyString(.brands)
        quantity = c.lossyString(.quantity)
        imageUrl = c.lossyString(.imageUrl)
        priceCount = c.lossyInt(.priceCount)
        locationCount = c.lossyInt(.locationCount)
        productQuantity = c.lossyDouble(.productQuantity)
        productQuantityUnit = c.lossyString(.productQuantityUnit)
        categoriesTags = try? c.decodeIfPresent([String].self, forKey: .categoriesTags)
    }

    func asProduct(code override: String? = nil) -> Product {
        let finalCode = override ?? code
        return Product(code: finalCode,
                       name: productName?.nilIfBlank ?? finalCode,
                       brand: brands?.nilIfBlank,
                       quantity: quantity?.nilIfBlank,
                       imageURL: imageUrl,
                       unitQuantity: productQuantity,
                       unitName: productQuantityUnit,
                       categories: categoriesTags)
    }
}

struct OPLocation: Decodable {
    let id: Int
    let type: String?
    let osmId: Int?
    let osmType: String?
    let osmName: String?
    let osmBrand: String?
    let osmDisplayName: String?
    let osmAddressCity: String?
    let osmAddressCountryCode: String?
    let osmTagValue: String?
    let osmLat: Double?
    let osmLon: Double?
    let osmBrandLogoUrl: String?
    let priceCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, type, osmId, osmType, osmName, osmBrand, osmDisplayName, osmAddressCity
        case osmAddressCountryCode, osmTagValue, osmLat, osmLon, osmBrandLogoUrl, priceCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lossyInt(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "id manquant")
        }
        self.id = id
        type = c.lossyString(.type)
        osmId = c.lossyInt(.osmId)
        osmType = c.lossyString(.osmType)
        osmName = c.lossyString(.osmName)
        osmBrand = c.lossyString(.osmBrand)
        osmDisplayName = c.lossyString(.osmDisplayName)
        osmAddressCity = c.lossyString(.osmAddressCity)
        osmAddressCountryCode = c.lossyString(.osmAddressCountryCode)
        osmTagValue = c.lossyString(.osmTagValue)
        osmLat = c.lossyDouble(.osmLat)
        osmLon = c.lossyDouble(.osmLon)
        osmBrandLogoUrl = c.lossyString(.osmBrandLogoUrl)
        priceCount = c.lossyInt(.priceCount)
    }

    /// "Rue du Pont Mouja, Centre Ville, Nancy" à partir du nom complet OSM.
    var shortAddress: String? {
        guard let display = osmDisplayName else { return osmAddressCity }
        let parts = display.components(separatedBy: ", ")
        guard parts.count > 1 else { return osmAddressCity }
        var picked = Array(parts.dropFirst().prefix(2))
        if let city = osmAddressCity, !picked.contains(city) {
            picked.append(city)
        }
        return picked.joined(separator: ", ")
    }

    var chainKey: String? { Chain.key(brand: osmBrand, name: osmName) }

    var chainName: String? {
        guard let key = chainKey else { return nil }
        return Chain.displayName(for: key) ?? osmBrand?.nilIfBlank ?? osmName
    }

    var asStore: Store? {
        guard let type = osmType, let osmId, let lat = osmLat, let lon = osmLon else { return nil }
        return Store(id: "\(type.uppercased()):\(osmId)",
                     name: osmName?.nilIfBlank ?? osmBrand?.nilIfBlank ?? "Magasin",
                     brand: osmBrand?.nilIfBlank,
                     kind: osmTagValue,
                     address: shortAddress,
                     lat: lat,
                     lon: lon,
                     priceCount: priceCount,
                     logoURL: osmBrandLogoUrl)
    }
}

struct OPPrice: Decodable {
    let id: Int
    let productCode: String?
    let productName: String?
    let price: Double
    let priceIsDiscounted: Bool?
    /// Prix barré quand le prix est une promo.
    let priceWithoutDiscount: Double?
    let currency: String?
    let date: String?
    let locationId: Int?
    let locationOsmId: Int?
    let locationOsmType: String?
    let product: OPProduct?
    let location: OPLocation?

    private enum CodingKeys: String, CodingKey {
        case id, productCode, productName, price, priceIsDiscounted, priceWithoutDiscount, currency, date
        case locationId, locationOsmId, locationOsmType, product, location
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lossyInt(.id), let price = c.lossyDouble(.price) else {
            throw DecodingError.dataCorruptedError(forKey: .price, in: c, debugDescription: "prix manquant")
        }
        self.id = id
        self.price = price
        productCode = c.lossyString(.productCode)
        productName = c.lossyString(.productName)
        priceIsDiscounted = c.lossyBool(.priceIsDiscounted)
        priceWithoutDiscount = c.lossyDouble(.priceWithoutDiscount)
        currency = c.lossyString(.currency)
        date = c.lossyString(.date)
        locationId = c.lossyInt(.locationId)
        locationOsmId = c.lossyInt(.locationOsmId)
        locationOsmType = c.lossyString(.locationOsmType)
        product = try? c.decodeIfPresent(OPProduct.self, forKey: .product)
        location = try? c.decodeIfPresent(OPLocation.self, forKey: .location)
    }
}

struct OPSession: Decodable {
    let accessToken: String
    let userId: String?
}

struct OPCreated: Decodable {
    let id: Int
}

// MARK: - API

enum OpenPricesAPI {
    private static let base = "https://prices.openfoodfacts.org/api/v1"

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Date d'il y a `months` mois au format de l'API.
    static func since(months: Int) -> String {
        let date = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        return dayFormatter.string(from: date)
    }

    /// Prix d'un produit dans un rayon autour d'un point, les plus récents d'abord.
    static func pricesNear(productCode: String, lat: Double, lon: Double, radiusKm: Double) async throws -> [OPPrice] {
        let page: OPPage<OPPrice> = try await HTTP.get(base + "/prices", query: [
            "product_code": productCode,
            "lat": coord(lat),
            "lon": coord(lon),
            "radius_km": km(radiusKm),
            "order_by": "-date",
            "size": "100",
        ])
        return page.items
    }

    /// Prix d'un produit partout (12 derniers mois) : sert aux estimations par enseigne.
    static func nationalPrices(productCode: String, months: Int = 12, size: Int = 100) async throws -> [OPPrice] {
        let page: OPPage<OPPrice> = try await HTTP.get(base + "/prices", query: [
            "product_code": productCode,
            "date__gte": since(months: months),
            "order_by": "-date",
            "size": String(size),
        ])
        return page.items
    }

    /// Prix des produits d'une catégorie (12 derniers mois) : sert à trouver moins cher au kilo.
    static func categoryPrices(category: String, months: Int = 12) async throws -> [OPPrice] {
        let page: OPPage<OPPrice> = try await HTTP.get(base + "/prices", query: [
            "product__categories_tags__contains": category,
            "date__gte": since(months: months),
            "order_by": "-date",
            "size": "100",
        ])
        return page.items
    }

    /// Derniers prix relevés autour d'un point (tous produits).
    static func recentPricesNear(lat: Double, lon: Double, radiusKm: Double) async throws -> [OPPrice] {
        let page: OPPage<OPPrice> = try await HTTP.get(base + "/prices", query: [
            "type": "PRODUCT",
            "lat": coord(lat),
            "lon": coord(lon),
            "radius_km": km(radiusKm),
            "order_by": "-date",
            "size": "60",
        ])
        return page.items
    }

    /// Promotions relevées autour d'un point ces dernières semaines (tous produits).
    static func recentDiscountsNear(lat: Double, lon: Double, radiusKm: Double) async throws -> [OPPrice] {
        let page: OPPage<OPPrice> = try await HTTP.get(base + "/prices", query: [
            "type": "PRODUCT",
            "price_is_discounted": "true",
            "lat": coord(lat),
            "lon": coord(lon),
            "radius_km": km(radiusKm),
            "date__gte": since(months: 1),
            "order_by": "-date",
            "size": "100",
        ])
        return page.items
    }

    /// Prix relevés dans un magasin.
    static func pricesAt(store: Store) async throws -> [OPPrice] {
        var query = ["type": "PRODUCT", "order_by": "-date", "size": "100"]
        if let type = store.osmType, let osmId = store.osmId {
            query["location_osm_type"] = type
            query["location_osm_id"] = String(osmId)
        } else {
            query["lat"] = coord(store.lat)
            query["lon"] = coord(store.lon)
            query["radius_km"] = "0.08"
        }
        let page: OPPage<OPPrice> = try await HTTP.get(base + "/prices", query: query)
        return page.items
    }

    /// Recherche de produits par nom (seulement ceux qui ont au moins un prix).
    static func searchProducts(_ text: String) async throws -> [OPProduct] {
        let page: OPPage<OPProduct> = try await HTTP.get(base + "/products", query: [
            "product_name__like": text,
            "price_count__gte": "1",
            "order_by": "-price_count",
            "size": "40",
        ])
        return page.items
    }

    /// Produits de grandes marques relevés dans le plus de magasins (panier de référence du classement).
    static func widespreadProducts(limit: Int) async throws -> [OPProduct] {
        let page: OPPage<OPProduct> = try await HTTP.get(base + "/products", query: [
            "order_by": "-location_count",
            "size": String(limit),
        ])
        return page.items
    }

    static func product(code: String) async throws -> OPProduct {
        let safe = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        return try await HTTP.get(base + "/products/code/" + safe)
    }

    /// Magasins connus d'Open Prices autour d'un point (avec leur nombre de prix).
    static func locationsNear(lat: Double, lon: Double, radiusKm: Double) async throws -> [OPLocation] {
        let page: OPPage<OPLocation> = try await HTTP.get(base + "/locations/nearby", query: [
            "lat": coord(lat),
            "lon": coord(lon),
            "radius_km": km(radiusKm),
            "size": "100",
        ])
        return page.items
    }

    // MARK: Contribution (compte Open Food Facts)

    /// Connexion avec un compte Open Food Facts : renvoie un jeton de session.
    static func login(username: String, password: String) async throws -> OPSession {
        guard let url = URL(string: base + "/auth") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(["username": username, "password": password]).data(using: .utf8)
        return try await HTTP.send(request, snakeCase: true)
    }

    /// Envoie la photo (étiquette ou ticket) qui sert de preuve au prix.
    static func uploadProof(token: String, jpeg: Data, store: Store, date: Date, currency: String) async throws -> Int {
        guard let url = URL(string: base + "/proofs/upload") else { throw URLError(.badURL) }
        let boundary = "LemwincherBoundary\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        appendField("type", "PRICE_TAG")
        appendField("date", dayFormatter.string(from: date))
        appendField("currency", currency)
        if let type = store.osmType, let osmId = store.osmId {
            appendField("location_osm_type", type)
            appendField("location_osm_id", String(osmId))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"etiquette.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let created: OPCreated = try await HTTP.send(request, snakeCase: true)
        return created.id
    }

    private struct NewPrice: Encodable {
        let product_code: String
        let price: Double
        let price_is_discounted: Bool
        let currency: String
        let date: String
        let location_osm_id: Int
        let location_osm_type: String
        let proof_id: Int
        let type: String
    }

    /// Publie un prix (avec sa preuve) sur Open Prices.
    static func createPrice(token: String, entry: MyPrice, proofID: Int) async throws -> Int {
        guard let url = URL(string: base + "/prices") else { throw URLError(.badURL) }
        guard let osmType = entry.store.osmType, let osmId = entry.store.osmId else { throw URLError(.badURL) }
        let payload = NewPrice(product_code: entry.product.code,
                               price: entry.price,
                               price_is_discounted: entry.isDiscounted,
                               currency: entry.currency,
                               date: dayFormatter.string(from: entry.date),
                               location_osm_id: osmId,
                               location_osm_type: osmType,
                               proof_id: proofID,
                               type: "PRODUCT")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        let created: OPCreated = try await HTTP.send(request, snakeCase: true)
        return created.id
    }

    // MARK: Outils

    private static func coord(_ value: Double) -> String { String(format: "%.5f", value) }
    private static func km(_ value: Double) -> String { String(format: "%.2f", value) }

    private static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}

// MARK: - Open Food Facts (fiche produit de secours)

enum OpenFoodFactsAPI {
    private struct Response: Decodable {
        let product: OFFProduct?
    }

    private struct OFFProduct: Decodable {
        let productName: String?
        let productNameFr: String?
        let brands: String?
        let quantity: String?
        let imageFrontSmallUrl: String?
        let imageSmallUrl: String?
        let productQuantity: Double?
        let productQuantityUnit: String?
        let categoriesTags: [String]?

        private enum CodingKeys: String, CodingKey {
            case productName, productNameFr, brands, quantity, imageFrontSmallUrl, imageSmallUrl
            case productQuantity, productQuantityUnit, categoriesTags
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            productName = c.lossyString(.productName)
            productNameFr = c.lossyString(.productNameFr)
            brands = c.lossyString(.brands)
            quantity = c.lossyString(.quantity)
            imageFrontSmallUrl = c.lossyString(.imageFrontSmallUrl)
            imageSmallUrl = c.lossyString(.imageSmallUrl)
            productQuantity = c.lossyDouble(.productQuantity)
            productQuantityUnit = c.lossyString(.productQuantityUnit)
            categoriesTags = try? c.decodeIfPresent([String].self, forKey: .categoriesTags)
        }
    }

    /// Bases sœurs d'Open Food Facts, même format : cosmétiques, nourriture animale, autres produits.
    static let sisterHosts = ["world.openbeautyfacts.org", "world.openpetfoodfacts.org", "world.openproductsfacts.org"]

    static func product(code: String, host: String = "world.openfoodfacts.org") async throws -> Product? {
        let safe = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        let fields = "product_name,product_name_fr,brands,quantity,image_front_small_url,image_small_url,product_quantity,product_quantity_unit,categories_tags"
        let response: Response = try await HTTP.get(
            "https://\(host)/api/v2/product/\(safe).json",
            query: ["fields": fields]
        )
        guard let p = response.product,
              let name = p.productNameFr?.nilIfBlank ?? p.productName?.nilIfBlank else { return nil }
        return Product(code: code,
                       name: name,
                       brand: p.brands?.nilIfBlank,
                       quantity: p.quantity?.nilIfBlank,
                       imageURL: p.imageFrontSmallUrl ?? p.imageSmallUrl,
                       unitQuantity: p.productQuantity,
                       unitName: p.productQuantityUnit,
                       categories: p.categoriesTags)
    }
}

/// Valeurs nutritionnelles pour 100 g (ou 100 ml).
struct Nutrition: Hashable {
    var energyKcal: Double?
    var fat: Double?
    var saturatedFat: Double?
    var carbohydrates: Double?
    var sugars: Double?
    var fiber: Double?
    var proteins: Double?
    var salt: Double?

    var isEmpty: Bool {
        [energyKcal, fat, saturatedFat, carbohydrates, sugars, fiber, proteins, salt].allSatisfy { $0 == nil }
    }

    struct Row: Hashable, Identifiable {
        let label: String
        let value: String
        /// Sous-ligne en retrait (« dont sucres »).
        let indent: Bool

        var id: String { label }
    }

    /// Lignes du tableau : « Matières grasses · 31 g », avec les sous-lignes en retrait.
    var rows: [Row] {
        func grams(_ value: Double?) -> String? {
            value.map { String(format: $0 < 10 ? "%.1f g" : "%.0f g", $0).replacingOccurrences(of: ".", with: ",") }
        }
        let all: [(String, String?, Bool)] = [
            ("Énergie", energyKcal.map { String(format: "%.0f kcal", $0) }, false),
            ("Matières grasses", grams(fat), false),
            ("dont acides gras saturés", grams(saturatedFat), true),
            ("Glucides", grams(carbohydrates), false),
            ("dont sucres", grams(sugars), true),
            ("Fibres", grams(fiber), false),
            ("Protéines", grams(proteins), false),
            ("Sel", grams(salt), false),
        ]
        return all.compactMap { row in row.1.map { Row(label: row.0, value: $0, indent: row.2) } }
    }
}

/// Fiche d'un produit (Open Food Facts) : notes, description, ingrédients, nutrition, porc éventuel.
struct ProductFacts: Hashable {
    /// "a" … "e"
    let nutriScore: String?
    /// 1 … 4
    let nova: Int?
    /// "a" … "e"
    let ecoScore: String?
    let allergens: [String]
    let labels: [String]
    /// Dénomination : « Pâte à tartiner aux noisettes et au cacao ».
    var genericName: String? = nil
    var ingredientsText: String? = nil
    var origins: String? = nil
    var conservation: String? = nil
    var nutrition = Nutrition()
    /// La liste d'ingrédients révèle du porc (graisse de porc, bacon, jambon…).
    var containsPork = false
    /// Gélatine sans origine précisée (souvent porcine).
    var unspecifiedGelatin = false
    /// Additifs (« E330 », « E471 »…).
    var additives: [String] = []
    /// Analyse des ingrédients par Open Food Facts : végan / végétarien (nil : inconnu).
    var isVegan: Bool? = nil
    var isVegetarian: Bool? = nil
    /// Enseignes où le produit est vendu (d'après les contributeurs), lieu de fabrication, catégorie.
    var stores: String? = nil
    var manufacturingPlaces: String? = nil
    var category: String? = nil

    /// Additifs qui peuvent être d'origine animale (porc possible), sauf produit végan.
    var possiblyAnimalAdditives: [String] {
        isVegan == true ? [] : additives.filter(Additives.isPossiblyAnimal)
    }

    var isEmpty: Bool {
        nutriScore == nil && nova == nil && ecoScore == nil && allergens.isEmpty && labels.isEmpty
            && genericName == nil && ingredientsText == nil && nutrition.isEmpty && !containsPork
            && additives.isEmpty && stores == nil
    }

    var hasDescription: Bool {
        genericName != nil || ingredientsText != nil || origins != nil || conservation != nil || !nutrition.isEmpty
            || !additives.isEmpty || stores != nil || manufacturingPlaces != nil || category != nil
    }

    private static let allergenNames: [String: String] = [
        "en:milk": "lait", "en:gluten": "gluten", "en:eggs": "œufs", "en:nuts": "fruits à coque",
        "en:peanuts": "arachides", "en:soybeans": "soja", "en:fish": "poisson", "en:crustaceans": "crustacés",
        "en:molluscs": "mollusques", "en:celery": "céleri", "en:mustard": "moutarde", "en:sesame-seeds": "sésame",
        "en:sulphur-dioxide-and-sulphites": "sulfites", "en:lupin": "lupin",
    ]

    private static let labelNames: [String: String] = [
        "en:organic": "Bio", "fr:ab-agriculture-biologique": "AB", "en:eu-organic": "Bio européen",
        "en:vegan": "Vegan", "en:vegetarian": "Végétarien", "en:no-gluten": "Sans gluten",
        "en:fair-trade": "Commerce équitable", "en:made-in-france": "Fabriqué en France",
        "fr:fabrique-en-france": "Fabriqué en France", "en:french-meat": "Viande française",
        "fr:label-rouge": "Label Rouge", "en:no-palm-oil": "Sans huile de palme", "en:palm-oil-free": "Sans huile de palme",
        "en:pdo": "AOP", "en:pgi": "IGP", "fr:bleu-blanc-coeur": "Bleu-Blanc-Cœur",
    ]

    init(nutriScore: String?, nova: Int?, ecoScore: String?, allergenTags: [String], labelTags: [String]) {
        let grades = Set(["a", "b", "c", "d", "e"])
        let nutri = nutriScore?.lowercased()
        let eco = ecoScore?.lowercased()
        self.nutriScore = nutri.flatMap { grades.contains($0) ? $0 : nil }
        self.ecoScore = eco.flatMap { grades.contains($0) ? $0 : nil }
        self.nova = nova.flatMap { (1...4).contains($0) ? $0 : nil }
        var seenAllergens = Set<String>()
        allergens = allergenTags.compactMap { ProductFacts.allergenNames[$0] }.filter { seenAllergens.insert($0).inserted }
        var seenLabels = Set<String>()
        labels = labelTags.compactMap { ProductFacts.labelNames[$0] }.filter { seenLabels.insert($0).inserted }
    }
}

extension OpenFoodFactsAPI {
    struct FactsResponse: Decodable {
        let product: FactsProduct?
    }

    /// Champs Open Food Facts, lus avec leurs noms d'origine (« generic_name_fr »).
    struct FactsProduct: Decodable {
        let nutriscoreGrade: String?
        let novaGroup: Int?
        let ecoscoreGrade: String?
        let environmentalScoreGrade: String?
        let allergensTags: [String]?
        let labelsTags: [String]?
        let ingredientsTags: [String]?
        let genericName: String?
        let ingredientsText: String?
        let origins: String?
        let conservation: String?
        let nutrition: Nutrition
        let additivesTags: [String]?
        let analysisTags: [String]?
        let stores: String?
        let manufacturingPlaces: String?
        let categories: String?

        private enum CodingKeys: String, CodingKey {
            case nutriscoreGrade = "nutriscore_grade", novaGroup = "nova_group", ecoscoreGrade = "ecoscore_grade"
            case environmentalScoreGrade = "environmental_score_grade", allergensTags = "allergens_tags"
            case labelsTags = "labels_tags", ingredientsTags = "ingredients_tags"
            case genericNameFr = "generic_name_fr", genericName = "generic_name"
            case ingredientsTextFr = "ingredients_text_fr", ingredientsText = "ingredients_text"
            case origins, originsFr = "origins_fr"
            case conservationFr = "conservation_conditions_fr", conservation = "conservation_conditions"
            case nutriments
            case additivesTags = "additives_tags", analysisTags = "ingredients_analysis_tags"
            case stores, manufacturingPlaces = "manufacturing_places", categories
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nutriscoreGrade = c.lossyString(.nutriscoreGrade)
            novaGroup = c.lossyInt(.novaGroup)
            ecoscoreGrade = c.lossyString(.ecoscoreGrade)
            environmentalScoreGrade = c.lossyString(.environmentalScoreGrade)
            allergensTags = try? c.decodeIfPresent([String].self, forKey: .allergensTags)
            labelsTags = try? c.decodeIfPresent([String].self, forKey: .labelsTags)
            ingredientsTags = try? c.decodeIfPresent([String].self, forKey: .ingredientsTags)
            genericName = FactsProduct.text(c.lossyString(.genericNameFr)) ?? FactsProduct.text(c.lossyString(.genericName))
            ingredientsText = FactsProduct.text(c.lossyString(.ingredientsTextFr)) ?? FactsProduct.text(c.lossyString(.ingredientsText))
            origins = FactsProduct.text(c.lossyString(.originsFr)) ?? FactsProduct.text(c.lossyString(.origins))
            conservation = FactsProduct.text(c.lossyString(.conservationFr)) ?? FactsProduct.text(c.lossyString(.conservation))
            var nutrition = Nutrition()
            if let n = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .nutriments) {
                nutrition.energyKcal = n.lossyDouble(AnyCodingKey("energy-kcal_100g"))
                nutrition.fat = n.lossyDouble(AnyCodingKey("fat_100g"))
                nutrition.saturatedFat = n.lossyDouble(AnyCodingKey("saturated-fat_100g"))
                nutrition.carbohydrates = n.lossyDouble(AnyCodingKey("carbohydrates_100g"))
                nutrition.sugars = n.lossyDouble(AnyCodingKey("sugars_100g"))
                nutrition.fiber = n.lossyDouble(AnyCodingKey("fiber_100g"))
                nutrition.proteins = n.lossyDouble(AnyCodingKey("proteins_100g"))
                nutrition.salt = n.lossyDouble(AnyCodingKey("salt_100g"))
            }
            self.nutrition = nutrition
            additivesTags = try? c.decodeIfPresent([String].self, forKey: .additivesTags)
            analysisTags = try? c.decodeIfPresent([String].self, forKey: .analysisTags)
            stores = FactsProduct.text(c.lossyString(.stores))
            manufacturingPlaces = FactsProduct.text(c.lossyString(.manufacturingPlaces))
            categories = FactsProduct.text(c.lossyString(.categories))
        }

        /// Texte propre : espaces normalisés, « _lait_ » (allergène souligné par OFF) -> « lait ».
        static func text(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let cleaned = raw.replacingOccurrences(of: "_", with: "")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return cleaned.isEmpty ? nil : cleaned
        }

        var facts: ProductFacts {
            var facts = ProductFacts(nutriScore: nutriscoreGrade,
                                     nova: novaGroup,
                                     ecoScore: environmentalScoreGrade ?? ecoscoreGrade,
                                     allergenTags: allergensTags ?? [],
                                     labelTags: labelsTags ?? [])
            facts.genericName = genericName
            facts.ingredientsText = ingredientsText
            facts.origins = origins
            facts.conservation = conservation
            facts.nutrition = nutrition
            let ingredients = ingredientsTags ?? []
            facts.containsPork = DietFilter.porkIngredients(ingredients)
            facts.unspecifiedGelatin = !facts.containsPork && DietFilter.unspecifiedGelatin(ingredients)
            var seenAdditives = Set<String>()
            facts.additives = (additivesTags ?? []).compactMap(Additives.code(fromTag:))
                .filter { seenAdditives.insert($0).inserted }
            let analysis = Set((analysisTags ?? []).map { $0.lowercased() })
            if analysis.contains("en:vegan") { facts.isVegan = true }
            if analysis.contains("en:non-vegan") { facts.isVegan = false }
            if analysis.contains("en:vegetarian") || analysis.contains("en:vegan") { facts.isVegetarian = true }
            if analysis.contains("en:non-vegetarian") { facts.isVegetarian = false }
            facts.stores = stores
            facts.manufacturingPlaces = manufacturingPlaces
            // « Petit-déjeuners, Produits à tartiner, Pâtes à tartiner aux noisettes » -> la plus précise.
            if let last = categories?.split(separator: ",").last {
                facts.category = String(last).trimmed.nilIfBlank
            }
            return facts
        }
    }

    /// Notes, description, ingrédients, nutrition et porc éventuel d'un produit.
    static func facts(code: String) async throws -> ProductFacts? {
        let safe = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        let fields = ["nutriscore_grade", "nova_group", "ecoscore_grade", "environmental_score_grade", "allergens_tags",
                      "labels_tags", "ingredients_tags", "generic_name_fr", "generic_name", "ingredients_text_fr",
                      "ingredients_text", "origins", "origins_fr", "conservation_conditions_fr",
                      "conservation_conditions", "nutriments", "additives_tags", "ingredients_analysis_tags",
                      "stores", "manufacturing_places", "categories"].joined(separator: ",")
        let response: FactsResponse = try await HTTP.get(
            "https://world.openfoodfacts.org/api/v2/product/\(safe).json",
            query: ["fields": fields, "lc": "fr"],
            snakeCase: false
        )
        guard let facts = response.product?.facts else { return nil }
        return facts.isEmpty ? nil : facts
    }
}

enum ProductLookup {
    /// Nom, marque, photo, contenance et catégories d'un produit à partir de son code-barres :
    /// Open Prices, Open Food Facts, puis les bases sœurs (cosmétiques, animaux, autres produits).
    static func lookup(code: String) async -> Product? {
        if let p = try? await OpenPricesAPI.product(code: code), p.productName?.nilIfBlank != nil {
            let product = p.asProduct(code: code)
            Log.success(.products, "Fiche trouvée : \(product.name)", details: "\(code) · Open Prices")
            return product
        }
        if let found = try? await OpenFoodFactsAPI.product(code: code) {
            Log.success(.products, "Fiche trouvée : \(found.name)", details: "\(code) · Open Food Facts")
            return found
        }
        for host in OpenFoodFactsAPI.sisterHosts {
            if let found = try? await OpenFoodFactsAPI.product(code: code, host: host) {
                Log.success(.products, "Fiche trouvée : \(found.name)", details: "\(code) · \(host)")
                return found
            }
        }
        Log.warning(.products, "Produit inconnu des bases Open Food Facts : \(code)")
        return nil
    }
}
