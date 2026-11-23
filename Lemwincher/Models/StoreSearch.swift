import Foundation
import MapKit

/// Recherche de magasins sur la carte d'« Autour de moi » : d'abord parmi les magasins connus (nom, enseigne,
/// adresse), puis sur Plans pour un magasin plus loin ou absent d'OpenStreetMap.
enum StoreSearch {
    /// « leclerc blagnac », « inter », « lidl purpan » : chaque mot doit commencer un mot du nom, de l'enseigne
    /// ou de l'adresse. Du plus proche au plus loin.
    static func matches(_ stores: [Store], query: String, reference: CLLocation?) -> [Store] {
        let words = SuggestionEngine.tokens(query)
        guard !words.isEmpty else { return [] }
        let found = stores.filter { store in
            let text = [store.name, store.brand ?? "", store.chainName ?? "", store.address ?? ""].joined(separator: " ")
            let tokens = SuggestionEngine.tokens(text)
            return words.allSatisfy { word in tokens.contains { $0.hasPrefix(word) } }
        }
        return byDistance(found, from: reference)
    }

    /// Supermarchés trouvés par Plans pour cette recherche (dans un rayon d'environ 25 km), sans ceux déjà connus.
    static func apple(query: String, near reference: CLLocation?, excluding known: [Store]) async -> [Store] {
        let text = query.trimmed
        guard text.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket])
        if let reference {
            request.region = MKCoordinateRegion(center: reference.coordinate,
                                                latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        let stores = response.mapItems.map { item in
            StoreFinder.appleStore(name: item.name ?? "Magasin", address: item.placemark.title,
                                   coordinate: item.placemark.coordinate)
        }
        return byDistance(newStores(stores, excluding: known), from: reference)
    }

    /// Sans les magasins déjà connus : même enseigne à moins de 150 m, ou n'importe lequel à moins de 40 m.
    static func newStores(_ found: [Store], excluding known: [Store]) -> [Store] {
        var kept: [Store] = []
        for store in found {
            let duplicate = (known + kept).contains { other in
                let distance = other.location.distance(from: store.location)
                return distance < 40 || (distance < 150 && other.chainKey != nil && other.chainKey == store.chainKey)
            }
            if !duplicate { kept.append(store) }
        }
        return kept
    }

    static func byDistance(_ stores: [Store], from reference: CLLocation?) -> [Store] {
        stores.sorted { ($0.distance(from: reference) ?? .infinity) < ($1.distance(from: reference) ?? .infinity) }
    }
}
