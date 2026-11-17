import Foundation

/// Décide quand prévenir l'utilisateur d'une baisse de prix sur un produit suivi.
enum WatchEvaluator {
    struct Outcome {
        var item: WatchItem
        /// Texte de la notification, ou nil s'il n'y a rien à signaler.
        var alert: String?
    }

    /// Les relevés plus anciens ne comptent plus pour le "meilleur prix actuel".
    static let maxAge: TimeInterval = 60 * 24 * 3600

    /// Met à jour le meilleur prix connu autour de soi (dernier prix de chaque magasin)
    /// et signale une baisse, ou un prix passé sous l'objectif fixé.
    static func evaluate(_ item: WatchItem, observations: [PriceObservation], now: Date = Date()) -> Outcome {
        var updated = item
        updated.lastChecked = now
        let recent = observations.filter { $0.date == .distantPast || now.timeIntervalSince($0.date) <= maxAge }
        guard let best = PriceEngine.latestPerStore(recent).min(by: { $0.price < $1.price }) else {
            return Outcome(item: updated, alert: nil)
        }

        let previous = item.bestPrice
        updated.bestPrice = best.price
        updated.bestStoreName = best.storeName
        updated.bestDate = best.date

        let priceText = Fmt.price(best.price, best.currency)
        if let previous, best.price < previous - 0.005 {
            updated.previousBestPrice = previous
            updated.hasNewDrop = true
            return Outcome(item: updated,
                           alert: "\(item.product.name) : \(priceText) chez \(best.storeName) (au lieu de \(Fmt.price(previous, best.currency))).")
        }
        if let target = item.targetPrice, best.price <= target + 0.0001, (previous ?? .infinity) > target + 0.0001 {
            updated.hasNewDrop = true
            return Outcome(item: updated,
                           alert: "\(item.product.name) est à \(priceText) chez \(best.storeName) : sous votre prix cible.")
        }
        return Outcome(item: updated, alert: nil)
    }
}
