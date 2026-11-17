import Foundation
import CoreLocation

/// Carburants publiés par le site officiel prix-carburants.gouv.fr.
enum FuelType: String, CaseIterable, Identifiable, Codable, Hashable {
    case gazole = "Gazole"
    case e10 = "E10"
    case sp95 = "SP95"
    case sp98 = "SP98"
    case e85 = "E85"
    case gplc = "GPLc"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gazole: return "Gazole"
        case .e10: return "SP95-E10"
        case .sp95: return "SP95"
        case .sp98: return "SP98"
        case .e85: return "E85"
        case .gplc: return "GPL"
        }
    }

    /// Préfixe des champs de l'API ("gazole_prix", "e10_maj"…).
    var apiField: String {
        switch self {
        case .gazole: return "gazole"
        case .e10: return "e10"
        case .sp95: return "sp95"
        case .sp98: return "sp98"
        case .e85: return "e85"
        case .gplc: return "gplc"
        }
    }
}

struct FuelPrice: Hashable {
    let value: Double
    let updated: Date?
}

/// Une station-service et ses prix (flux instantané du ministère de l'Économie).
struct FuelStation: Identifiable, Hashable {
    let id: Int
    let address: String
    let city: String
    let postcode: String?
    let lat: Double
    let lon: Double
    /// Station d'autoroute (souvent plus chère).
    let isHighway: Bool
    /// Paiement par carte 24 h/24.
    let open24h: Bool
    let prices: [FuelType: FuelPrice]
    /// Carburants en rupture temporaire.
    let shortages: [FuelType]
    let services: [String]
    /// Nom ou enseigne de la station (OpenStreetMap), s'il a été trouvé.
    var name: String? = nil
    var brand: String? = nil
    /// Supermarché voisin quand la station elle-même n'est pas identifiée.
    var nearbyStoreName: String? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }

    func price(for fuel: FuelType) -> FuelPrice? { prices[fuel] }

    var title: String {
        if let name = name?.nilIfBlank { return name }
        if let brand = brand?.nilIfBlank { return brand }
        if let store = nearbyStoreName { return "Station près de \(store)" }
        return "Station \(FuelStation.prettify(city))"
    }

    /// "16 avenue de Fronton, 31140 Aucamville".
    var fullAddress: String {
        let cityLine = [postcode?.nilIfBlank, FuelStation.prettify(city).nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " ")
        return [FuelStation.prettify(address).nilIfBlank, cityLine.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    var logoURL: String? { Chain.logoURL(brand: brand ?? name) }

    var directionsURL: URL? {
        URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)")
    }

    /// "16 AVENUE DE FRONTON" -> "16 avenue de Fronton".
    static func prettify(_ text: String) -> String {
        let small: Set<String> = ["de", "du", "des", "la", "le", "les", "et", "a", "au", "aux", "sur", "en", "d", "l"]
        let generic: Set<String> = ["avenue", "rue", "route", "boulevard", "chemin", "allee", "allée", "place", "impasse",
                                    "rond-point", "quai", "cours", "zone", "za", "zi", "zac", "centre", "commercial", "rd", "rn", "n", "d"]
        let words = text.lowercased().split(separator: " ").map(String.init)
        var result: [String] = []
        for (index, word) in words.enumerated() {
            if ["rd", "rn", "za", "zi", "zac", "cc"].contains(word) {
                result.append(word.uppercased())
            } else if index > 0 && (small.contains(word) || generic.contains(word)) {
                result.append(word)
            } else if word.hasPrefix("d'") || word.hasPrefix("l'") {
                result.append(String(word.prefix(2)) + capitalizeParts(String(word.dropFirst(2))))
            } else {
                result.append(capitalizeParts(word))
            }
        }
        return result.joined(separator: " ")
    }

    /// "saint-jean" -> "Saint-Jean".
    private static func capitalizeParts(_ word: String) -> String {
        word.split(separator: "-", omittingEmptySubsequences: false)
            .map { part in part.prefix(1).uppercased() + String(part.dropFirst()) }
            .joined(separator: "-")
    }
}

/// Lieu OpenStreetMap (station-service) utilisé pour nommer les stations.
struct NamedPlace: Hashable {
    let name: String?
    let brand: String?
    let lat: Double
    let lon: Double

    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
}

// MARK: - Décodage de l'API data.economie.gouv.fr

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

struct FuelResponse: Decodable {
    let totalCount: Int?
    let stations: [FuelStation]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalCount = c.lossyInt(.totalCount)
        let records = (try? c.decode([Lossy<FuelRecord>].self, forKey: .results)) ?? []
        stations = records.compactMap { $0.value?.station }
    }
}

struct FuelRecord: Decodable {
    let station: FuelStation?

    static let isoFormatter = ISO8601DateFormatter()

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.lossyInt(AnyCodingKey("id")) else {
            station = nil
            return
        }
        var lat: Double?
        var lon: Double?
        if let geom = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("geom")) {
            lat = geom.lossyDouble(AnyCodingKey("lat"))
            lon = geom.lossyDouble(AnyCodingKey("lon"))
        }
        // Repli : "latitude": "4361600" (degrés × 100 000).
        if lat == nil, let raw = c.lossyDouble(AnyCodingKey("latitude")) { lat = raw / 100_000 }
        if lon == nil, let raw = c.lossyDouble(AnyCodingKey("longitude")) { lon = raw / 100_000 }
        guard let lat, let lon, abs(lat) <= 90, abs(lon) <= 180 else {
            station = nil
            return
        }

        var prices: [FuelType: FuelPrice] = [:]
        for fuel in FuelType.allCases {
            guard let value = c.lossyDouble(AnyCodingKey(fuel.apiField + "_prix")), value > 0 else { continue }
            let updated = c.lossyString(AnyCodingKey(fuel.apiField + "_maj")).flatMap { FuelRecord.isoFormatter.date(from: $0) }
            prices[fuel] = FuelPrice(value: value, updated: updated)
        }
        let shortageText = c.lossyString(AnyCodingKey("carburants_rupture_temporaire")) ?? ""
        let shortages = shortageText.split(separator: ";").compactMap { FuelType(rawValue: String($0).trimmed) }
        let services = (try? c.decodeIfPresent([String].self, forKey: AnyCodingKey("services_service"))) ?? []

        station = FuelStation(id: id,
                              address: c.lossyString(AnyCodingKey("adresse")) ?? "",
                              city: c.lossyString(AnyCodingKey("ville")) ?? "",
                              postcode: c.lossyString(AnyCodingKey("cp")),
                              lat: lat,
                              lon: lon,
                              isHighway: c.lossyString(AnyCodingKey("pop")) == "A",
                              open24h: c.lossyString(AnyCodingKey("horaires_automate_24_24")) == "Oui",
                              prices: prices,
                              shortages: shortages,
                              services: services)
    }
}

// MARK: - Calculs

enum FuelStats {
    /// Au-delà, un prix n'est plus considéré comme à jour.
    static let maxAge: TimeInterval = 10 * 24 * 3600

    /// Stations qui vendent ce carburant (prix récent, pas en rupture), de la moins chère à la plus chère.
    static func ranked(_ stations: [FuelStation], fuel: FuelType, now: Date = Date()) -> [FuelStation] {
        stations
            .filter { station in
                guard let price = station.price(for: fuel), !station.shortages.contains(fuel) else { return false }
                guard let updated = price.updated else { return true }
                return now.timeIntervalSince(updated) <= maxAge
            }
            .sorted { ($0.price(for: fuel)?.value ?? .infinity) < ($1.price(for: fuel)?.value ?? .infinity) }
    }

    /// Prix moyen du carburant parmi les stations classées.
    static func average(_ ranked: [FuelStation], fuel: FuelType) -> Double? {
        let values = ranked.compactMap { $0.price(for: fuel)?.value }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Économie sur un plein par rapport à un prix de référence.
    static func savings(price: Double, reference: Double, liters: Double = 50) -> Double {
        max(0, (reference - price) * liters)
    }

    /// Donne un nom aux stations : station OpenStreetMap à moins de 150 m,
    /// sinon supermarché à moins de 300 m ("Station près de E.Leclerc").
    static func label(_ stations: [FuelStation], places: [NamedPlace], stores: [Store]) -> [FuelStation] {
        let supermarkets = stores.filter { $0.isSupermarket && $0.chainKey != nil }
        return stations.map { station in
            var labeled = station
            let here = station.location
            let place = places
                .map { ($0, $0.location.distance(from: here)) }
                .filter { $0.1 <= 150 && ($0.0.name?.nilIfBlank != nil || $0.0.brand?.nilIfBlank != nil) }
                .min { $0.1 < $1.1 }?.0
            if let place {
                labeled.brand = place.brand?.nilIfBlank
                labeled.name = place.name?.nilIfBlank ?? place.brand?.nilIfBlank
            } else if let store = supermarkets
                .map({ ($0, $0.location.distance(from: here)) })
                .filter({ $0.1 <= 300 })
                .min(by: { $0.1 < $1.1 })?.0 {
                labeled.nearbyStoreName = store.chainName ?? store.name
                labeled.brand = store.brand
            }
            return labeled
        }
    }
}
