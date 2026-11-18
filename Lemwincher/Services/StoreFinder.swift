import Foundation
import CoreLocation
import MapKit

/// Trouve les supermarchés / supérettes autour d'un point.
/// 1. OpenStreetMap via Overpass : tous les magasins avec horaires et contacts, mêmes identifiants qu'Open Prices.
/// 2. OpenStreetMap via Photon, en même temps : les magasins les plus proches, même quand Overpass est saturé.
/// 3. Open Prices : magasins où des prix ont été relevés (nombre de prix, logo, pays).
/// 4. Plans d'Apple en secours si OpenStreetMap ne répond pas du tout.
enum StoreFinder {
    struct Result {
        var stores: [Store]
        var source: String
        var countryCode: String?
        /// Des magasins OpenStreetMap ont été reçus (Overpass ou Photon ; sinon : Open Prices / Plans seulement).
        var fromOSM: Bool = true
        /// La liste complète d'Overpass a été reçue (horaires, téléphones…) ; Photon seul ne donne que les plus proches.
        var complete: Bool = true
    }

    /// Au-delà, on ne garde que les supérettes les plus proches (tous les supermarchés sont conservés).
    private static let maxConvenienceStores = 250

    static func nearby(lat: Double, lon: Double, radiusKm: Double) async -> Result {
        async let osmTask = overpassStores(lat: lat, lon: lon, radiusMeters: Int(radiusKm * 1000))
        async let photonTask = photonStores(lat: lat, lon: lon, radiusKm: radiusKm)
        async let openPricesTask = openPricesLocations(lat: lat, lon: lon, radiusKm: radiusKm)
        let overpassResult = await osmTask
        let photonResult = await photonTask
        let openPricesResult = await openPricesTask

        var merged: [String: Store] = [:]
        // Photon d'abord, puis Overpass (plus complet : horaires, téléphone, enseigne) par-dessus.
        for store in photonResult ?? [] {
            merged[store.id] = store
        }
        for store in overpassResult ?? [] {
            merged[store.id] = store
        }
        let osmResult: [Store]? = (overpassResult == nil && photonResult == nil) ? nil : Array(merged.values)
        for location in openPricesResult {
            guard let store = location.asStore else { continue }
            if var existing = merged[store.id] {
                existing.priceCount = store.priceCount
                existing.logoURL = store.logoURL ?? existing.logoURL
                if existing.brand == nil { existing.brand = store.brand }
                merged[store.id] = existing
            } else {
                merged[store.id] = store
            }
        }

        var source = overpassResult == nil && photonResult != nil
            ? "OpenStreetMap (Photon) et Open Prices"
            : "OpenStreetMap et Open Prices"
        if osmResult == nil || merged.isEmpty {
            let appleResult = await appleStores(lat: lat, lon: lon, radiusKm: radiusKm)
            for store in appleResult {
                let duplicate = merged.values.contains { $0.location.distance(from: store.location) < 60 }
                if !duplicate { merged[store.id] = store }
            }
            source = "Plans d'Apple et Open Prices"
        }

        let center = CLLocation(latitude: lat, longitude: lon)
        let sorted = merged.values.sorted {
            $0.location.distance(from: center) < $1.location.distance(from: center)
        }
        var kept: [Store] = []
        var convenienceCount = 0
        for store in sorted {
            if store.isSupermarket || (store.priceCount ?? 0) > 0 {
                kept.append(store)
            } else if convenienceCount < maxConvenienceStores {
                kept.append(store)
                convenienceCount += 1
            }
        }

        // Pays le plus fréquent parmi les magasins Open Prices proches (ex. "FR").
        var countryCounts: [String: Int] = [:]
        for location in openPricesResult {
            if let code = location.osmAddressCountryCode?.uppercased(), !code.isEmpty {
                countryCounts[code, default: 0] += 1
            }
        }
        let country = countryCounts.max { $0.value < $1.value }?.key

        return Result(stores: kept, source: source, countryCode: country, fromOSM: osmResult != nil,
                      complete: overpassResult != nil)
    }

    /// Complète une liste en cache avec les données fraîches d'Open Prices (nombre de prix, logos, nouveaux magasins).
    static func merge(cached: [Store], fresh: [Store], center: CLLocation) -> [Store] {
        var byID: [String: Store] = [:]
        for store in cached { byID[store.id] = store }
        for store in fresh where store.osmId != nil {
            if var existing = byID[store.id] {
                existing.priceCount = store.priceCount ?? existing.priceCount
                existing.logoURL = store.logoURL ?? existing.logoURL
                byID[store.id] = existing
            } else {
                byID[store.id] = store
            }
        }
        return byID.values.sorted { $0.location.distance(from: center) < $1.location.distance(from: center) }
    }

    // MARK: Stations-service (noms)

    /// Stations-service OpenStreetMap (nom, enseigne) pour nommer les stations du site prix-carburants.
    static func fuelPlaces(lat: Double, lon: Double, radiusKm: Double) async -> [NamedPlace]? {
        let around = "(around:\(Int(radiusKm * 1000)),\(String(format: "%.6f", lat)),\(String(format: "%.6f", lon)))"
        let query = "[out:json][timeout:20];(node[\"amenity\"=\"fuel\"]\(around);way[\"amenity\"=\"fuel\"]\(around););out center tags;"
        guard let response = await overpass(query: query, timeouts: [15, 8]) else { return nil }
        return response.elements.compactMap { element -> NamedPlace? in
            guard let la = element.lat ?? element.center?.lat, let lo = element.lon ?? element.center?.lon else { return nil }
            let tags = element.tags ?? [:]
            return NamedPlace(name: tags["name"]?.nilIfBlank, brand: tags["brand"]?.nilIfBlank, lat: la, lon: lo)
        }
    }

    // MARK: OpenStreetMap

    /// Serveur principal puis un miroir ; ensuite on bascule sur le cache ou sur Plans d'Apple.
    private static let overpassEndpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    private static func overpassStores(lat: Double, lon: Double, radiusMeters: Int) async -> [Store]? {
        // Surgelés (Picard) et bio (Naturalia, La Vie Claire) en plus des supermarchés et supérettes.
        let filter = "[\"shop\"~\"^(supermarket|convenience|hypermarket|wholesale|general|frozen_food|organic)$\"]"
        let around = "(around:\(radiusMeters),\(String(format: "%.6f", lat)),\(String(format: "%.6f", lon)))"
        // Points, bâtiments et aussi « relations » (magasins dessinés comme des zones à plusieurs contours).
        let query = "[out:json][timeout:25];(node\(filter)\(around);way\(filter)\(around);relation\(filter)\(around););out center tags;"
        guard let response = await overpass(query: query, timeouts: [22, 12]) else { return nil }
        return response.elements.compactMap(\.asStore)
    }

    // MARK: Photon (OpenStreetMap, komoot)

    /// Supermarchés, hypermarchés et supérettes les plus proches (50 au plus par type), via Photon.
    /// nil si Photon ne répond pas.
    private static func photonStores(lat: Double, lon: Double, radiusKm: Double) async -> [Store]? {
        async let supermarkets = photon(tag: "shop:supermarket", lat: lat, lon: lon, radiusKm: radiusKm)
        async let hypermarkets = photon(tag: "shop:hypermarket", lat: lat, lon: lon, radiusKm: radiusKm)
        async let convenience = photon(tag: "shop:convenience", lat: lat, lon: lon, radiusKm: radiusKm)
        async let frozen = photon(tag: "shop:frozen_food", lat: lat, lon: lon, radiusKm: radiusKm)
        let lists = await [supermarkets, hypermarkets, convenience, frozen]
        if lists.allSatisfy({ $0 == nil }) { return nil }
        let center = CLLocation(latitude: lat, longitude: lon)
        return lists.compactMap { $0 }.flatMap { $0 }
            .filter { $0.location.distance(from: center) <= radiusKm * 1000 }
    }

    private static func photon(tag: String, lat: Double, lon: Double, radiusKm: Double) async -> [Store]? {
        let query = [
            "lat": String(format: "%.6f", lat),
            "lon": String(format: "%.6f", lon),
            "radius": String(Int(min(max(radiusKm, 1), 20).rounded(.up))),
            "limit": "50",
            "osm_tag": tag,
            "lang": "fr",
        ]
        guard let response: PhotonResponse = try? await HTTP.get("https://photon.komoot.io/reverse",
                                                                  query: query, snakeCase: false) else { return nil }
        return response.features.compactMap(\.asStore)
    }

    /// Envoie une requête Overpass au serveur principal, puis au miroir en cas d'échec.
    private static func overpass(query: String, timeouts: [TimeInterval]) async -> OverpassResponse? {
        let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        for (index, endpoint) in overpassEndpoints.enumerated() {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = index < timeouts.count ? timeouts[index] : 10
            do {
                let response: OverpassResponse = try await HTTP.send(request, snakeCase: false)
                return response
            } catch {
                if Task.isCancelled { return nil }
                continue
            }
        }
        return nil
    }

    // MARK: Open Prices

    private static func openPricesLocations(lat: Double, lon: Double, radiusKm: Double) async -> [OPLocation] {
        (try? await OpenPricesAPI.locationsNear(lat: lat, lon: lon, radiusKm: radiusKm)) ?? []
    }

    // MARK: Plans d'Apple

    /// Plans ne renvoie qu'une partie des commerces d'une grande zone : on cherche aussi tout près (1,5 km)
    /// pour ne jamais rater les magasins du quartier.
    @MainActor
    private static func appleStores(lat: Double, lon: Double, radiusKm: Double) async -> [Store] {
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        var found: [String: Store] = [:]
        for radius in [min(1500, radiusKm * 1000), min(radiusKm * 1000, 20_000)] {
            let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket])
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            for item in response.mapItems {
                let store = appleStore(name: item.name ?? "Magasin",
                                       address: item.placemark.title,
                                       coordinate: item.placemark.coordinate)
                found[store.id] = store
            }
        }
        return Array(found.values)
    }

    /// Plans classe dans « alimentation » aussi bien les supermarchés que les cavistes ou salons de thé :
    /// seules les enseignes reconnues comptent comme supermarchés, les autres comme petits commerces.
    static func appleStore(name: String, address: String?, coordinate c: CLLocationCoordinate2D) -> Store {
        let chain = Chain.key(brand: nil, name: name)
        return Store(id: String(format: "apple:%.5f,%.5f", c.latitude, c.longitude),
                     name: name,
                     brand: chain.flatMap { Chain.displayName(for: $0) },
                     kind: chain == nil ? "convenience" : "supermarket",
                     address: address,
                     lat: c.latitude,
                     lon: c.longitude,
                     priceCount: nil,
                     logoURL: nil)
    }
}

// MARK: - Réponse Overpass

struct OverpassResponse: Decodable {
    let elements: [Element]

    struct Center: Decodable {
        let lat: Double
        let lon: Double
    }

    struct Element: Decodable {
        let type: String
        let id: Int
        let lat: Double?
        let lon: Double?
        let center: Center?
        let tags: [String: String]?

        var asStore: Store? {
            guard let la = lat ?? center?.lat, let lo = lon ?? center?.lon else { return nil }
            let t = tags ?? [:]
            let shop = t["shop"]
            let street = [t["addr:housenumber"], t["addr:street"]].compactMap { $0 }.joined(separator: " ")
            let address = [street.nilIfBlank, t["addr:city"]].compactMap { $0 }.joined(separator: ", ")
            return Store(id: "\(type.uppercased()):\(id)",
                         name: t["name"]?.nilIfBlank ?? t["brand"]?.nilIfBlank ?? OverpassResponse.label(for: shop),
                         brand: t["brand"]?.nilIfBlank,
                         kind: shop,
                         address: address.nilIfBlank,
                         lat: la,
                         lon: lo,
                         priceCount: nil,
                         logoURL: nil,
                         openingHours: t["opening_hours"]?.nilIfBlank,
                         phone: (t["phone"] ?? t["contact:phone"])?.nilIfBlank,
                         website: (t["website"] ?? t["contact:website"])?.nilIfBlank)
        }
    }

    static func label(for shop: String?) -> String {
        switch shop {
        case "supermarket", "hypermarket": return "Supermarché"
        case "frozen_food": return "Surgelés"
        case "organic": return "Magasin bio"
        case "convenience": return "Supérette"
        case "wholesale": return "Grossiste"
        case "general": return "Épicerie"
        default: return "Commerce"
        }
    }
}

// MARK: - Réponse Photon (GeoJSON)

struct PhotonResponse: Decodable {
    let features: [Feature]

    private enum CodingKeys: String, CodingKey { case features }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        features = ((try? c.decode([Lossy<Feature>].self, forKey: .features)) ?? []).compactMap(\.value)
    }

    struct Feature: Decodable {
        let geometry: Geometry?
        let properties: Properties

        var asStore: Store? {
            guard let coordinates = geometry?.coordinates, coordinates.count >= 2,
                  let id = properties.osmId,
                  let type = PhotonResponse.osmType(properties.osmType) else { return nil }
            let lon = coordinates[0]
            let lat = coordinates[1]
            let name = properties.name?.nilIfBlank
            let chain = Chain.key(brand: nil, name: name)
            let street = [properties.housenumber, properties.street].compactMap { $0?.nilIfBlank }.joined(separator: " ")
            let address = [street.nilIfBlank, properties.city?.nilIfBlank].compactMap { $0 }.joined(separator: ", ")
            return Store(id: "\(type):\(id)",
                         name: name ?? OverpassResponse.label(for: properties.osmValue),
                         brand: chain.flatMap { Chain.displayName(for: $0) },
                         kind: properties.osmValue,
                         address: address.nilIfBlank,
                         lat: lat,
                         lon: lon,
                         priceCount: nil,
                         logoURL: nil)
        }
    }

    struct Geometry: Decodable {
        /// [longitude, latitude]
        let coordinates: [Double]
    }

    struct Properties: Decodable {
        let osmType: String?
        let osmId: Int?
        let osmValue: String?
        let name: String?
        let housenumber: String?
        let street: String?
        let city: String?

        private enum CodingKeys: String, CodingKey {
            case osmType = "osm_type", osmId = "osm_id", osmValue = "osm_value", name, housenumber, street, city
        }

        // Lecture tolérante : un champ inattendu ne doit pas faire perdre tous les magasins.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            osmType = c.lossyString(.osmType)
            osmId = c.lossyInt(.osmId)
            osmValue = c.lossyString(.osmValue)
            name = c.lossyString(.name)
            housenumber = c.lossyString(.housenumber)
            street = c.lossyString(.street)
            city = c.lossyString(.city)
        }
    }

    /// "N" / "W" / "R" -> identifiants OpenStreetMap de l'app (mêmes qu'Overpass et Open Prices).
    static func osmType(_ code: String?) -> String? {
        switch code?.uppercased() {
        case "N": return "NODE"
        case "W": return "WAY"
        case "R": return "RELATION"
        default: return nil
        }
    }
}
