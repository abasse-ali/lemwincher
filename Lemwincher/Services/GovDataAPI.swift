import Foundation

/// Données publiques de data.economie.gouv.fr : prix des carburants et rappels de produits.
enum GovDataAPI {
    private static let base = "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/"
    private static let fuelDataset = "prix-des-carburants-en-france-flux-instantane-v2"
    private static let recallsByGTIN = "rappelconso-v2-gtin-trie"
    private static let recallsBySheet = "rappelconso-v2-gtin-espaces"

    // MARK: Carburants

    /// Toutes les stations dans un rayon (jusqu'à 300).
    static func fuelStations(lat: Double, lon: Double, radiusKm: Double) async throws -> [FuelStation] {
        let point = String(format: "POINT(%.5f %.5f)", lon, lat)
        let radius = max(1, Int(radiusKm.rounded()))
        let filter = "within_distance(geom, geom'\(point)', \(radius)km)"
        var stations: [FuelStation] = []
        var offset = 0
        while true {
            let page: FuelResponse = try await HTTP.get(base + fuelDataset + "/records", query: [
                "where": filter,
                "limit": "100",
                "offset": String(offset),
            ], snakeCase: false)
            stations.append(contentsOf: page.stations)
            offset += 100
            if offset >= (page.totalCount ?? 0) || offset >= 300 { break }
        }
        return stations
    }

    // MARK: Rappels de produits

    /// Rappels (12 derniers mois) concernant ces codes-barres.
    static func recalls(forBarcodes codes: [String]) async throws -> [Recall] {
        let numbers = Array(Set(codes.filter(\.isBarcodeLike).map(Recall.normalizedGTIN))).sorted()
        guard !numbers.isEmpty else { return [] }
        var found: [Recall] = []
        var start = 0
        while start < numbers.count {
            let batch = numbers[start..<min(start + 40, numbers.count)]
            start += 40
            let filter = "gtin in (\(batch.joined(separator: ", "))) and date_publication >= \"\(day(monthsAgo: 12))\""
            let page: RecallResponse = try await HTTP.get(base + recallsByGTIN + "/records", query: [
                "where": filter,
                "order_by": "date_publication desc",
                "limit": "100",
            ], snakeCase: false)
            found.append(contentsOf: page.recalls)
        }
        return found
    }

    /// Rappels alimentaires récents vendus dans le département (ou dans toute la France).
    static func recentRecalls(department: String?, days: Int = 30) async throws -> [Recall] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var filter = "categorie_produit = \"alimentation\" and date_publication >= \"\(OpenPricesAPI.dayFormatter.string(from: since))\""
        if let department = department?.nilIfBlank {
            let term = department.lowercased().replacingOccurrences(of: "\"", with: "")
            filter += " and (search(zone_geographique_de_vente, \"\(term)\") or search(zone_geographique_de_vente, \"france entiere\"))"
        }
        let page: RecallResponse = try await HTTP.get(base + recallsBySheet + "/records", query: [
            "where": filter,
            "order_by": "date_publication desc",
            "limit": "100",
        ], snakeCase: false)
        return page.recalls
    }

    private static func day(monthsAgo months: Int) -> String {
        OpenPricesAPI.since(months: months)
    }
}
