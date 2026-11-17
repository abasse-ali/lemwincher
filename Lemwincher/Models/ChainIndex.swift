import Foundation

/// Position d'une enseigne dans le classement des prix (100 = prix moyen des enseignes).
struct ChainIndexEntry: Codable, Identifiable, Hashable {
    let key: String
    let name: String
    let index: Double
    let productCount: Int

    var id: String { key }

    /// "-6 %" / "+12 %" par rapport à la moyenne.
    var differenceText: String {
        let delta = Int((index - 100).rounded())
        if delta == 0 { return "dans la moyenne" }
        return delta < 0 ? "\(delta) %" : "+\(delta) %"
    }
}

struct ChainIndexReport: Codable {
    let date: Date
    let country: String
    let currency: String
    let productCount: Int
    let entries: [ChainIndexEntry]

    func entry(for key: String?) -> ChainIndexEntry? {
        guard let key else { return nil }
        return entries.first { $0.key == key }
    }
}

/// Classement des enseignes : on compare le prix médian de produits de grandes marques
/// (Nutella, Barilla, St Michel…) relevés dans tout le pays au cours des 12 derniers mois.
enum ChainIndexBuilder {
    static let minProductsPerChain = 4

    static func build(country: String?, currency: String) async throws -> ChainIndexReport {
        let products = try await OpenPricesAPI.widespreadProducts(limit: 40)
        let codes = products.map(\.code)
        var perProduct: [[PriceObservation]] = []

        // Par lots de 6 requêtes simultanées pour ménager le serveur.
        var start = 0
        while start < codes.count {
            let batch = Array(codes[start..<min(start + 6, codes.count)])
            start += 6
            let results = await withTaskGroup(of: [PriceObservation].self, returning: [[PriceObservation]].self) { group in
                for code in batch {
                    group.addTask {
                        let prices = (try? await OpenPricesAPI.nationalPrices(productCode: code, months: 12, size: 80)) ?? []
                        return PriceEngine.observations(from: prices)
                    }
                }
                var collected: [[PriceObservation]] = []
                for await observations in group {
                    collected.append(observations)
                }
                return collected
            }
            perProduct.append(contentsOf: results)
            try Task.checkCancellation()
        }
        return compute(perProduct, country: country, currency: currency)
    }

    static func compute(_ perProduct: [[PriceObservation]], country: String?, currency: String) -> ChainIndexReport {
        var logRatios: [String: [Double]] = [:]
        var names: [String: String] = [:]
        var usedProducts = 0

        for observations in perProduct {
            let usable = PriceEngine.filter(observations, country: country, currency: currency)
            let estimates = ChainStats.estimates(from: usable)
            guard estimates.count >= 2 else { continue }
            let reference = ChainStats.median(estimates.map(\.median))
            guard reference > 0 else { continue }
            usedProducts += 1
            for estimate in estimates where estimate.median > 0 {
                logRatios[estimate.key, default: []].append(log(estimate.median / reference))
                names[estimate.key] = estimate.name
            }
        }

        let entries: [ChainIndexEntry] = logRatios.compactMap { key, values in
            guard values.count >= minProductsPerChain else { return nil }
            let mean = values.reduce(0, +) / Double(values.count)
            return ChainIndexEntry(key: key,
                                   name: names[key] ?? key,
                                   index: exp(mean) * 100,
                                   productCount: values.count)
        }
        return ChainIndexReport(date: Date(),
                                country: country ?? "",
                                currency: currency,
                                productCount: usedProducts,
                                entries: entries.sorted { $0.index < $1.index })
    }
}
