import Foundation
import CoreLocation

/// Cherche les produits précis qui correspondent à un article générique de la liste, avec leur meilleur prix.
enum SuggestionService {
    struct Context {
        let reference: CLLocation?
        let radiusMeters: Double
        let country: String?
        let currency: String
        let nearbyChains: [String: Store]
    }

    /// Produits qui ont des prix relevés (Open Prices), triés par pertinence puis par prix.
    static func pricedSuggestions(for query: String, context: Context, limit: Int = 8) async -> [ProductSuggestion] {
        var products: [OPProduct] = []
        for variant in SuggestionEngine.searchVariants(query) {
            products += (try? await OpenPricesAPI.searchProducts(variant)) ?? []
        }
        struct Candidate {
            let product: OPProduct
            let score: Int
        }
        var seen = Set<String>()
        var candidates: [Candidate] = []
        for product in products where seen.insert(product.code).inserted {
            let score = SuggestionEngine.relevance(name: product.productName ?? "", query: query)
            if score > 0 { candidates.append(Candidate(product: product, score: score)) }
        }
        candidates.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return (a.product.priceCount ?? 0) > (b.product.priceCount ?? 0)
        }
        let ranked: [OPProduct] = candidates.prefix(limit).map { $0.product }

        let suggestions = await withTaskGroup(of: ProductSuggestion.self, returning: [ProductSuggestion].self) { group in
            for item in ranked {
                group.addTask {
                    let prices = (try? await OpenPricesAPI.nationalPrices(productCode: item.code, months: 12, size: 50)) ?? []
                    let offer = SuggestionEngine.bestOffer(observations: PriceEngine.observations(from: prices),
                                                           reference: context.reference,
                                                           radiusMeters: context.radiusMeters,
                                                           country: context.country,
                                                           currency: context.currency,
                                                           nearbyChains: context.nearbyChains)
                    return ProductSuggestion(product: item.asProduct(), offer: offer, nutriScore: nil)
                }
            }
            var collected: [ProductSuggestion] = []
            for await suggestion in group {
                collected.append(suggestion)
            }
            return collected
        }
        return SuggestionEngine.sorted(suggestions)
    }
}
