import Foundation
import CoreLocation

/// Dernière liste de magasins OpenStreetMap reçue : affichée tout de suite au lancement,
/// et utilisée quand les serveurs OpenStreetMap sont saturés.
struct StoreCacheEntry: Codable {
    let lat: Double
    let lon: Double
    let radiusKm: Double
    let date: Date
    let stores: [Store]
    let countryCode: String?
}

enum StoreCache {
    static let maxAge: TimeInterval = 45 * 24 * 3600

    private static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("magasins-osm.json")
    }

    /// Magasins en cache utilisables pour cette zone (même endroit à 1 km près, rayon suffisant).
    static func load(near location: CLLocation, radiusKm: Double, now: Date = Date()) -> StoreCacheEntry? {
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(StoreCacheEntry.self, from: data) else { return nil }
        return usable(entry, near: location, radiusKm: radiusKm, now: now)
    }

    static func usable(_ entry: StoreCacheEntry, near location: CLLocation, radiusKm: Double, now: Date = Date()) -> StoreCacheEntry? {
        let center = CLLocation(latitude: entry.lat, longitude: entry.lon)
        guard now.timeIntervalSince(entry.date) < maxAge,
              entry.radiusKm + 0.01 >= radiusKm,
              center.distance(from: location) < 1000 else { return nil }
        let limit = radiusKm * 1000 + 500
        let stores = entry.stores
            .filter { $0.location.distance(from: location) <= limit }
            .sorted { $0.location.distance(from: location) < $1.location.distance(from: location) }
        return StoreCacheEntry(lat: entry.lat, lon: entry.lon, radiusKm: entry.radiusKm,
                               date: entry.date, stores: stores, countryCode: entry.countryCode)
    }

    static func save(_ entry: StoreCacheEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
