import Foundation

/// Un rayon du catalogue (catégorie Open Food Facts).
struct Rayon: Identifiable, Hashable {
    /// Catégorie Open Food Facts, ex. "en:dairies".
    let tag: String
    let name: String
    let icon: String
    /// Teinte de la tuile (0…1).
    let hue: Double

    var id: String { tag }

    static let all: [Rayon] = [
        Rayon(tag: "en:fruits-and-vegetables-based-foods", name: "Fruits et légumes", icon: "carrot.fill", hue: 0.30),
        Rayon(tag: "en:meats", name: "Viandes", icon: "flame.fill", hue: 0.0),
        Rayon(tag: "en:seafood", name: "Poissons", icon: "fish.fill", hue: 0.55),
        Rayon(tag: "en:dairies", name: "Produits laitiers", icon: "drop.fill", hue: 0.58),
        Rayon(tag: "en:cheeses", name: "Fromages", icon: "triangle.fill", hue: 0.13),
        Rayon(tag: "en:eggs", name: "Œufs", icon: "oval.fill", hue: 0.10),
        Rayon(tag: "en:breakfasts", name: "Petit-déjeuner", icon: "sun.horizon.fill", hue: 0.08),
        Rayon(tag: "en:breakfast-cereals", name: "Céréales", icon: "leaf.fill", hue: 0.16),
        Rayon(tag: "en:pastas", name: "Pâtes", icon: "fork.knife", hue: 0.12),
        Rayon(tag: "en:rices", name: "Riz", icon: "circle.grid.3x3.fill", hue: 0.15),
        Rayon(tag: "en:canned-foods", name: "Conserves", icon: "cylinder.fill", hue: 0.03),
        Rayon(tag: "en:condiments", name: "Sauces et condiments", icon: "flask.fill", hue: 0.05),
        Rayon(tag: "en:biscuits-and-cakes", name: "Biscuits et gâteaux", icon: "birthday.cake.fill", hue: 0.92),
        Rayon(tag: "en:chocolates", name: "Chocolat", icon: "square.grid.3x3.fill", hue: 0.07),
        Rayon(tag: "en:salty-snacks", name: "Apéritif", icon: "sparkles", hue: 0.11),
        Rayon(tag: "en:frozen-foods", name: "Surgelés", icon: "snowflake", hue: 0.53),
        Rayon(tag: "en:meals", name: "Plats préparés", icon: "takeoutbag.and.cup.and.straw.fill", hue: 0.04),
        Rayon(tag: "en:beverages", name: "Boissons", icon: "wineglass.fill", hue: 0.75),
        Rayon(tag: "en:waters", name: "Eaux", icon: "drop.circle.fill", hue: 0.57),
        Rayon(tag: "en:coffees", name: "Café", icon: "cup.and.saucer.fill", hue: 0.06),
        Rayon(tag: "en:baby-foods", name: "Bébé", icon: "heart.fill", hue: 0.95),
    ]
}

/// Un produit du catalogue Open Food Facts.
struct CatalogItem: Identifiable, Hashable {
    let product: Product
    /// "a" … "e", si connu.
    let nutriScore: String?

    var id: String { product.code }
}

struct CatalogPage {
    let items: [CatalogItem]
    let total: Int
    let page: Int
    let pageCount: Int

    var hasMore: Bool { page < pageCount }
}

// MARK: - Décodage de la recherche Open Food Facts (search.openfoodfacts.org)

struct CatalogResponse: Decodable {
    let hits: [CatalogItem]
    let count: Int
    let page: Int
    let pageCount: Int

    private enum CodingKeys: String, CodingKey {
        case hits, count, page, pageCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode([Lossy<CatalogHit>].self, forKey: .hits)) ?? []
        hits = raw.compactMap { $0.value?.item }
        count = c.lossyInt(.count) ?? hits.count
        page = c.lossyInt(.page) ?? 1
        pageCount = c.lossyInt(.pageCount) ?? 1
    }
}

struct CatalogHit: Decodable {
    let item: CatalogItem?

    private enum CodingKeys: String, CodingKey {
        case code, productName, productNameFr, brands, quantity, imageFrontSmallUrl, nutriscoreGrade, categoriesTags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let code = c.lossyString(.code), code.isBarcodeLike,
              let name = c.lossyString(.productNameFr)?.nilIfBlank ?? c.lossyString(.productName)?.nilIfBlank else {
            item = nil
            return
        }
        // "brands" : liste (nouvelle API) ou texte séparé par des virgules.
        var brand: String? = nil
        if let list = try? c.decodeIfPresent([String].self, forKey: .brands) {
            brand = list.first?.nilIfBlank
        } else if let text = c.lossyString(.brands) {
            brand = text.split(separator: ",").first.map { String($0).trimmed }?.nilIfBlank
        }
        let grade = c.lossyString(.nutriscoreGrade)?.lowercased()
        let product = Product(code: code,
                              name: name.trimmed,
                              brand: brand,
                              quantity: c.lossyString(.quantity)?.nilIfBlank,
                              imageURL: c.lossyString(.imageFrontSmallUrl),
                              unitQuantity: nil,
                              unitName: nil,
                              categories: try? c.decodeIfPresent([String].self, forKey: .categoriesTags))
        item = CatalogItem(product: product,
                           nutriScore: ["a", "b", "c", "d", "e"].contains(grade ?? "") ? grade : nil)
    }
}
