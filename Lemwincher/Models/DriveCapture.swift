import Foundation

/// Site de courses en ligne (drive) d'une enseigne, ouvert dans le navigateur intégré.
struct DriveSite: Identifiable, Hashable {
    let id: String
    let name: String
    /// Début des clés d'enseigne concernées ("carrefour" couvre Carrefour Market, City…).
    let chainPrefix: String
    let home: String
    /// Adresse de recherche ; "{q}" est remplacé par le produit cherché.
    let searchTemplate: String

    func url(for query: String) -> URL? {
        let text = query.trimmed
        guard !text.isEmpty,
              let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?/#"))) else {
            return URL(string: home)
        }
        return URL(string: searchTemplate.replacingOccurrences(of: "{q}", with: encoded))
    }

    func matches(_ store: Store) -> Bool {
        store.chainKey?.hasPrefix(chainPrefix) == true
    }

    static let all: [DriveSite] = [
        DriveSite(id: "leclerc", name: "E.Leclerc", chainPrefix: "e leclerc",
                  home: "https://www.e.leclerc", searchTemplate: "https://www.e.leclerc/recherche?q={q}"),
        DriveSite(id: "carrefour", name: "Carrefour", chainPrefix: "carrefour",
                  home: "https://www.carrefour.fr", searchTemplate: "https://www.carrefour.fr/s?q={q}"),
        DriveSite(id: "auchan", name: "Auchan", chainPrefix: "auchan",
                  home: "https://www.auchan.fr", searchTemplate: "https://www.auchan.fr/recherche?text={q}"),
        DriveSite(id: "intermarche", name: "Intermarché", chainPrefix: "intermarche",
                  home: "https://www.intermarche.com", searchTemplate: "https://www.intermarche.com/recherche/{q}"),
        DriveSite(id: "u", name: "Courses U", chainPrefix: "super u",
                  home: "https://www.coursesu.com", searchTemplate: "https://www.coursesu.com/recherche?q={q}"),
        DriveSite(id: "lidl", name: "Lidl", chainPrefix: "lidl",
                  home: "https://www.lidl.fr", searchTemplate: "https://www.lidl.fr/q/search?q={q}"),
    ]
}

/// Un produit et son prix lus sur la page d'un site.
struct CapturedPrice: Identifiable, Hashable, Decodable {
    var name: String
    var price: Double
    var gtin: String?
    var image: String?
    var include: Bool = true

    var id: String { name + "|" + String(format: "%.2f", price) }

    private enum CodingKeys: String, CodingKey {
        case name, price, gtin, image
    }

    init(name: String, price: Double, gtin: String? = nil, image: String? = nil) {
        self.name = name
        self.price = price
        self.gtin = gtin
        self.image = image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lossyString(.name) ?? ""
        price = c.lossyDouble(.price) ?? 0
        gtin = c.lossyString(.gtin)
        image = c.lossyString(.image)
    }

    /// Produit enregistré : avec son code-barres quand le site le donne (comparable avec les autres prix).
    var product: Product {
        let digits = (gtin ?? "").filter { $0.isASCII && $0.isNumber }
        if digits.isBarcodeLike {
            return Product(code: digits, name: name, imageURL: image)
        }
        var custom = Product.custom(named: name)
        custom.imageURL = image
        return custom
    }
}

enum DriveCaptureParser {
    /// Lit le JSON renvoyé par le script : garde les prix plausibles, sans doublons.
    static func parse(_ json: String) -> [CapturedPrice] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([Lossy<CapturedPrice>].self, from: data) else { return [] }
        var seen = Set<String>()
        var result: [CapturedPrice] = []
        for item in raw.compactMap(\.value) {
            var cleaned = item
            cleaned.name = item.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard cleaned.name.count >= 3, cleaned.price >= 0.05, cleaned.price < 1000 else { continue }
            cleaned.price = (cleaned.price * 100).rounded() / 100
            if seen.insert(cleaned.id).inserted { result.append(cleaned) }
        }
        return result
    }

    /// Script exécuté dans la page affichée : lit les produits décrits pour les moteurs de recherche
    /// (JSON-LD et microdonnées schema.org), sinon les « cartes produit » visibles (nom + prix, hors prix au kilo).
    static let script = #"""
    (function () {
      var out = [];
      var seen = {};
      function add(name, price, gtin, image) {
        if (!name || price === undefined || price === null) return;
        name = String(name).replace(/\s+/g, ' ').trim();
        var p = typeof price === 'number' ? price : parseFloat(String(price).replace(/[^0-9,.]/g, '').replace(',', '.'));
        if (!(p > 0 && p < 1000) || name.length < 3) return;
        var key = name.toLowerCase() + '|' + p.toFixed(2);
        if (seen[key]) return;
        seen[key] = true;
        out.push({ name: name.slice(0, 160), price: Math.round(p * 100) / 100,
                   gtin: gtin ? String(gtin) : null, image: image ? String(image) : null });
      }
      function fromLD(node) {
        if (!node) return;
        if (Array.isArray(node)) { node.forEach(fromLD); return; }
        if (typeof node !== 'object') return;
        var type = node['@type'];
        var types = Array.isArray(type) ? type : [type];
        if (types.indexOf('Product') >= 0) {
          var offers = node.offers;
          if (Array.isArray(offers)) offers = offers[0];
          var price = offers ? (offers.price || offers.lowPrice) : null;
          var image = Array.isArray(node.image) ? node.image[0] : node.image;
          if (image && typeof image === 'object') image = image.url;
          add(node.name, price, node.gtin13 || node.gtin || node.gtin8, image);
        }
        if (Array.isArray(node.itemListElement)) {
          fromLD(node.itemListElement.map(function (e) { return (e && e.item) ? e.item : e; }));
        }
        if (node['@graph']) fromLD(node['@graph']);
      }
      document.querySelectorAll('script[type="application/ld+json"]').forEach(function (s) {
        try { fromLD(JSON.parse(s.textContent)); } catch (e) {}
      });
      document.querySelectorAll('[itemtype*="schema.org/Product"]').forEach(function (el) {
        var n = el.querySelector('[itemprop="name"]');
        var p = el.querySelector('[itemprop="price"]');
        var g = el.querySelector('[itemprop^="gtin"]');
        var i = el.querySelector('img');
        add(n && (n.getAttribute('content') || n.textContent),
            p && (p.getAttribute('content') || p.textContent),
            g && (g.getAttribute('content') || g.textContent),
            i ? (i.currentSrc || i.src) : null);
      });
      if (out.length === 0) {
        var cards = document.querySelectorAll('article, li, [class*="product" i], [data-testid*="product" i]');
        cards.forEach(function (card) {
          if (out.length >= 100) return;
          var text = card.innerText || '';
          if (text.length < 8 || text.length > 700) return;
          var re = /(\d{1,3})\s?[,.€]\s?(\d{2})\s?€?(\s?\/\s?(kg|l|kilo|litre|unité))?/gi;
          var m, chosen = null;
          while ((m = re.exec(text)) !== null) { if (!m[3]) { chosen = m; break; } }
          if (!chosen) return;
          var titleEl = card.querySelector('h1, h2, h3, h4, [class*="title" i], [class*="name" i], a[title]');
          var title = titleEl ? (titleEl.getAttribute('title') || titleEl.innerText) : null;
          var img = card.querySelector('img');
          add(title, chosen[1] + '.' + chosen[2], null, img ? (img.currentSrc || img.src) : null);
        });
      }
      return JSON.stringify(out.slice(0, 120));
    })();
    """#
}
