import Foundation
import CoreLocation

/// Une promotion à montrer sur l'accueil : le produit, son prix promo, son prix habituel s'il est connu, le magasin.
struct PromoDeal: Identifiable, Hashable {
    let observation: PriceObservation
    /// Prix barré, sinon dernier prix sans promo relevé dans le même magasin.
    let regularPrice: Double?
    let distance: Double?

    var id: String { observation.storeKey + "|" + observation.productCode }
    var product: Product { observation.product }
    var price: Double { observation.price }
    var currency: String { observation.currency }
    var storeName: String { observation.storeName }
    var date: Date { observation.date }
    /// Relevé par l'utilisateur (site d'une enseigne, en magasin) plutôt que par la communauté.
    var isMine: Bool { observation.source == .mine }

    /// 24 (pour « -24 % ») si le prix habituel est connu.
    var discountPercent: Int? {
        guard let regularPrice, regularPrice > price + 0.005 else { return nil }
        return Int(((regularPrice - price) / regularPrice * 100).rounded())
    }
}

/// Promotions relevées récemment autour de soi : mes relevés (sites des enseignes, magasins) et la communauté.
enum PromoFinder {
    static func deals(in observations: [PriceObservation], reference: CLLocation?, radius: Double,
                      now: Date = Date(), maxAgeDays: Int = 14) -> [PromoDeal] {
        let limit = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)

        // Dernier prix sans promo de chaque produit dans chaque magasin (pour le prix habituel).
        var regular: [String: PriceObservation] = [:]
        for obs in observations where !obs.isDiscounted {
            let key = obs.storeKey + "|" + obs.productCode
            if let known = regular[key], known.date >= obs.date { continue }
            regular[key] = obs
        }

        var byID: [String: PromoDeal] = [:]
        for obs in observations where obs.isDiscounted && obs.date >= limit && obs.price > 0 {
            let distance = obs.distance(from: reference)
            if let distance, distance > radius { continue }
            // Mes relevés hors de la zone (sans position) restent : je sais où est le magasin.
            if distance == nil && obs.source != .mine { continue }
            let key = obs.storeKey + "|" + obs.productCode
            // Un prix normal relevé après la promo : elle est finie.
            if let after = regular[key], after.date > obs.date { continue }
            let usual = obs.regularPrice ?? regular[key].flatMap { $0.price > obs.price ? $0.price : nil }
            let deal = PromoDeal(observation: obs, regularPrice: usual, distance: distance)
            if let known = byID[deal.id] {
                // Mes relevés passent avant ceux de la communauté, puis le plus récent.
                if known.isMine && !deal.isMine { continue }
                if known.isMine == deal.isMine && known.date >= deal.date { continue }
            }
            byID[deal.id] = deal
        }

        // Les plus fortes remises d'abord, puis les plus proches.
        return byID.values.sorted { a, b in
            let pa = a.discountPercent ?? -1, pb = b.discountPercent ?? -1
            if pa != pb { return pa > pb }
            let da = a.distance ?? .infinity, db = b.distance ?? .infinity
            if da != db { return da < db }
            return a.product.name.localizedCaseInsensitiveCompare(b.product.name) == .orderedAscending
        }
    }
}
