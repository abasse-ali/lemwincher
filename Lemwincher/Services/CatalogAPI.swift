import Foundation

/// Catalogue complet des produits vendus en France (recherche Open Food Facts),
/// et produits qui ont des prix relevés (Open Prices).
enum CatalogAPI {
    private static let searchURL = "https://search.openfoodfacts.org/search"
    private static let fields = "code,product_name,product_name_fr,brands,quantity,image_front_small_url,nutriscore_grade,categories_tags"

    /// Recherche par texte et/ou rayon. Sans texte : les produits les plus scannés d'abord.
    static func search(text: String?, rayon: Rayon?, page: Int, pageSize: Int = 30) async throws -> CatalogPage {
        var parts: [String] = []
        let cleaned = (text ?? "")
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .trimmed
        if !cleaned.isEmpty { parts.append(cleaned) }
        if let rayon { parts.append("categories_tags:\"\(rayon.tag)\"") }
        parts.append("countries_tags:\"en:france\"")

        var query = [
            "q": parts.joined(separator: " "),
            "page": String(max(page, 1)),
            "page_size": String(pageSize),
            "langs": "fr",
            "fields": fields,
        ]
        if cleaned.isEmpty {
            query["sort_by"] = "-unique_scans_n"
        }
        let response: CatalogResponse = try await HTTP.get(searchURL, query: query)
        // Doublons possibles entre pages : on les retire à l'affichage.
        return CatalogPage(items: response.hits,
                           total: response.count,
                           page: response.page,
                           pageCount: min(response.pageCount, 100))
    }
}

extension OpenPricesAPI {
    /// Produits d'un rayon qui ont au moins un prix relevé, les plus relevés d'abord.
    static func pricedProducts(category: String, nameContains text: String?, page: Int,
                               size: Int = 30) async throws -> (products: [OPProduct], hasMore: Bool) {
        var query = [
            "categories_tags__contains": category,
            "price_count__gte": "1",
            "order_by": "-price_count",
            "size": String(size),
            "page": String(max(page, 1)),
        ]
        if let text = text?.trimmed, !text.isEmpty {
            query["product_name__like"] = text
        }
        let result: OPPage<OPProduct> = try await HTTP.get("https://prices.openfoodfacts.org/api/v1/products", query: query)
        let total = result.total ?? 0
        return (result.items, page * size < total)
    }
}
