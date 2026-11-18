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
    /// Le site affiche les prix d'un magasin choisi (drive) ; sinon les mêmes prix pour toute l'enseigne.
    var choosesStore: Bool = true

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
        // Les courses E.Leclerc sont sur Leclerc Drive (e.leclerc ne vend que la marketplace) ;
        // chaque drive a sa propre adresse : on ouvre l'accueil, où l'on choisit son drive puis on cherche.
        DriveSite(id: "leclerc", name: "Leclerc Drive", chainPrefix: "e leclerc",
                  home: "https://www.leclercdrive.fr", searchTemplate: "https://www.leclercdrive.fr"),
        DriveSite(id: "carrefour", name: "Carrefour", chainPrefix: "carrefour",
                  home: "https://www.carrefour.fr", searchTemplate: "https://www.carrefour.fr/s?q={q}"),
        DriveSite(id: "auchan", name: "Auchan", chainPrefix: "auchan",
                  home: "https://www.auchan.fr", searchTemplate: "https://www.auchan.fr/recherche?text={q}"),
        DriveSite(id: "intermarche", name: "Intermarché", chainPrefix: "intermarche",
                  home: "https://www.intermarche.com", searchTemplate: "https://www.intermarche.com/recherche/{q}"),
        DriveSite(id: "u", name: "Courses U", chainPrefix: "super u",
                  home: "https://www.coursesu.com", searchTemplate: "https://www.coursesu.com/recherche?q={q}"),
        DriveSite(id: "lidl", name: "Lidl", chainPrefix: "lidl",
                  home: "https://www.lidl.fr", searchTemplate: "https://www.lidl.fr/q/search?q={q}",
                  choosesStore: false),
        DriveSite(id: "aldi", name: "Aldi", chainPrefix: "aldi",
                  home: "https://www.aldi.fr", searchTemplate: "https://www.aldi.fr/recherche.html?query={q}",
                  choosesStore: false),
    ]

    /// Site de l'enseigne la plus proche qui en a un (pour ouvrir directement le bon site).
    static func nearest(in stores: [Store]) -> DriveSite? {
        for store in stores {
            if let site = all.first(where: { $0.matches(store) }) { return site }
        }
        return nil
    }
}

/// Un produit et son prix lus sur la page d'un site.
struct CapturedPrice: Identifiable, Hashable, Decodable {
    var name: String
    var price: Double
    var gtin: String?
    var image: String?
    /// Marque affichée sur le site ("MILSANI®").
    var brand: String?
    /// Contenance ("250 g"), lue sur la page ou déduite du prix au kilo.
    var quantity: String?
    var include: Bool = true

    /// Même nom, marque, contenance et prix = même ligne ("Œufs plein air" Auchan 6 et 12 pièces restent distincts).
    var id: String { [brand ?? "", name, quantity ?? "", String(format: "%.2f", price)].joined(separator: "|") }

    private enum CodingKeys: String, CodingKey {
        case name, price, gtin, image, brand, quantity
    }

    init(name: String, price: Double, gtin: String? = nil, image: String? = nil,
         brand: String? = nil, quantity: String? = nil) {
        self.name = name
        self.price = price
        self.gtin = gtin
        self.image = image
        self.brand = brand
        self.quantity = quantity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lossyString(.name) ?? ""
        price = c.lossyDouble(.price) ?? 0
        gtin = c.lossyString(.gtin)
        image = c.lossyString(.image)
        brand = c.lossyString(.brand)?.nilIfBlank
        quantity = c.lossyString(.quantity)?.nilIfBlank
    }

    /// Produit enregistré : avec son code-barres quand le site le donne (comparable avec les autres prix).
    var product: Product {
        let digits = (gtin ?? "").filter { $0.isASCII && $0.isNumber }
        var product = digits.isBarcodeLike ? Product(code: digits, name: name) : Product.custom(named: name)
        if !digits.isBarcodeLike, brand != nil || quantity != nil {
            // Sans code-barres, la marque et la contenance distinguent le « Beurre doux » d'une enseigne
            // de celui d'une autre, et la boîte de 6 œufs de celle de 12.
            product.code = Product.customCode(for: [name, brand, quantity].compactMap { $0 }.joined(separator: " "))
        }
        product.imageURL = image
        product.brand = brand
        product.quantity = quantity
        return product
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
            cleaned.name = sentenceCase(item.name.split(whereSeparator: \.isWhitespace).joined(separator: " "))
            guard cleaned.name.count >= 3, cleaned.price >= 0.05, cleaned.price < 1000 else { continue }
            cleaned.price = (cleaned.price * 100).rounded() / 100
            if seen.insert(cleaned.id).inserted { result.append(cleaned) }
        }
        return result
    }

    /// "BEURRE DOUX" -> "Beurre doux" (les noms tout en majuscules seulement).
    static func sentenceCase(_ name: String) -> String {
        guard name.rangeOfCharacter(from: .lowercaseLetters) == nil,
              name.rangeOfCharacter(from: .uppercaseLetters) != nil else { return name }
        let lower = name.lowercased(with: Locale(identifier: "fr_FR"))
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    /// Script exécuté dans la page affichée : lit les produits décrits pour les moteurs de recherche
    /// (JSON-LD et microdonnées schema.org), sinon les fiches produit affichées (nom, marque, prix, contenance),
    /// sinon les « cartes produit » visibles (nom + prix, hors prix au kilo).
    static let script = #"""
    (function () {
      var out = [];
      var seen = {};
      function clean(text) { return text ? String(text).replace(/\s+/g, ' ').trim() : ''; }
      function add(name, price, gtin, image, brand, quantity) {
        if (!name || price === undefined || price === null) return;
        name = clean(name);
        var p = typeof price === 'number' ? price : parseFloat(String(price).replace(/[^0-9,.]/g, '').replace(',', '.'));
        if (!(p > 0 && p < 1000) || name.length < 3) return;
        brand = clean(brand);
        // "AUCHAN Oeufs de poules…" (marque AUCHAN) -> "Oeufs de poules…".
        if (brand && name.toLowerCase().indexOf(brand.toLowerCase() + ' ') === 0 && name.length > brand.length + 3) {
          name = name.slice(brand.length + 1).trim();
        }
        var key = [brand, name, quantity || '', p.toFixed(2)].join('|').toLowerCase();
        if (seen[key]) return;
        seen[key] = true;
        out.push({ name: name.slice(0, 160), price: Math.round(p * 100) / 100,
                   gtin: gtin ? String(gtin) : null, image: image ? String(image) : null,
                   brand: brand && brand.length <= 40 && brand.toLowerCase() !== name.toLowerCase() ? brand : null,
                   quantity: quantity || null });
      }
      // Premier prix d'un texte qui n'est pas un prix au kilo / au litre : "2.99", "2,99 €", "2€99".
      function priceIn(text) {
        var re = /(\d{1,3})\s?[,.€]\s?(\d{2})(?!\d)\s?€?(\s?\/\s?(kg|l|kilo|litre|unité|pièce))?/gi;
        var m;
        while ((m = re.exec(text || '')) !== null) { if (!m[3]) return parseFloat(m[1] + '.' + m[2]); }
        return null;
      }
      function textOf(el) { return el ? clean(el.innerText || el.textContent) : ''; }
      // Premier élément non vide parmi des sélecteurs classés du plus sûr au moins sûr.
      function firstOf(root, selectors) {
        for (var i = 0; i < selectors.length; i++) {
          var list = root.querySelectorAll(selectors[i]);
          for (var j = 0; j < list.length; j++) {
            if (textOf(list[j]) || list[j].getAttribute('title')) return { el: list[j], selector: selectors[i] };
          }
        }
        return null;
      }
      var NAME = ['[class*="product-name" i]', '[class*="productname" i]', '[class*="product-title" i]',
                  '[class*="producttitle" i]', '[class*="product__title" i]', '[class*="product__name" i]',
                  '[itemprop~="name"]', 'h2', 'h3', 'h4', '[class*="title" i]',
                  '[class*="name" i]:not([class*="brand" i])', 'a[title]', 'h1'];
      var PRICE = ['[class*="label--price" i]', '[class*="current-price" i]', '[class*="currentprice" i]',
                   '[class*="price__main" i]', '[class*="price-value" i]', '[class*="sale-price" i]',
                   '[class*="price" i]:not([class*="base" i]):not([class*="old" i]):not([class*="strike" i]):not([class*="unit" i]):not([class*="price-per" i])'];
      // Contenance : écrite sur la fiche ("250 g"), sinon déduite du prix au kilo ("KG = 9.40" pour 2,35 € -> 250 g).
      function quantityOf(tile, price) {
        var unitBoxes = tile.querySelectorAll('[class*="salesunit" i], [class*="sales-unit" i], [class*="quantity" i], ' +
          '[class*="packaging" i], [class*="weight" i], [class*="attribute" i], [class*="contenance" i]');
        for (var k = 0; k < unitBoxes.length; k++) {
          var m = /(\d+(?:[.,]\d+)?)\s*(kg|g|l|cl|ml|pièces?|pcs|unités?)(?![a-zà-ÿ])/i.exec(textOf(unitBoxes[k]));
          if (m) return m[1].replace(',', '.') + ' ' + m[2].toLowerCase();
        }
        var baseBox = tile.querySelector('[class*="base-price" i], [class*="baseprice" i], [class*="unit-price" i], [class*="price-per" i]');
        var unit, base, b = null;
        // Dans la case du prix au kilo : "KG = 9.40" ou "1 kg = 9,40 €".
        if (baseBox) { b = /\b(kg|l)\b[^0-9]{0,8}(\d{1,4})[,.](\d{2})/i.exec(textOf(baseBox)); }
        if (b) { unit = b[1].toLowerCase(); base = parseFloat(b[2] + '.' + b[3]); }
        else {
          // "9,40 €/kg", dans cette case ou n'importe où sur la fiche.
          b = /(\d{1,4})[,.](\d{2})\s?€?\s?\/\s?(kg|l)\b/i.exec(baseBox ? textOf(baseBox) : textOf(tile));
          if (b) { unit = b[3].toLowerCase(); base = parseFloat(b[1] + '.' + b[2]); }
        }
        if (!(base > 0) || !(price > 0)) return null;
        var amount = Math.round(price / base * 1000);
        if (amount >= 100) amount = Math.round(amount / 5) * 5;
        if (!(amount > 0)) return null;
        if (unit === 'kg') return amount >= 1000 ? (amount / 1000) + ' kg' : amount + ' g';
        return amount >= 1000 ? (amount / 1000) + ' l' : (amount % 10 === 0 ? (amount / 10) + ' cl' : amount + ' ml');
      }
      function imageOf(el) {
        var img = el.querySelector('img');
        return img ? (img.currentSrc || img.src) : null;
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
      // Microdonnées : itemprop peut contenir plusieurs mots ("name description" chez Auchan).
      document.querySelectorAll('[itemtype*="schema.org/Product"]').forEach(function (el) {
        var n = el.querySelector('[itemprop~="name"]');
        var p = el.querySelector('[itemprop~="price"]');
        var g = el.querySelector('[itemprop^="gtin"]');
        var b = el.querySelector('[itemprop~="brand"]');
        var i = el.querySelector('img');
        var priceText = p && (p.getAttribute('content') || p.textContent);
        var value = priceText ? parseFloat(String(priceText).replace(/[^0-9,.]/g, '').replace(',', '.')) : null;
        add(n && (n.getAttribute('content') || n.textContent),
            priceText,
            g && (g.getAttribute('content') || g.textContent),
            i ? (i.currentSrc || i.src) : null,
            b && (b.getAttribute('content') || b.textContent),
            value > 0 ? quantityOf(el, value) : null);
      });
      // Fiches produit (Aldi, et la plupart des sites) : une fiche = un seul nom de produit.
      function fromTiles(selector) {
        document.querySelectorAll(selector).forEach(function (tile) {
          if (out.length >= 120) return;
          var found = firstOf(tile, NAME);
          if (!found || tile.querySelectorAll(found.selector).length !== 1) return;
          var name = textOf(found.el) || found.el.getAttribute('title');
          var price = null;
          for (var i = 0; i < PRICE.length && price === null; i++) {
            var boxes = tile.querySelectorAll(PRICE[i]);
            for (var j = 0; j < boxes.length && price === null; j++) { price = priceIn(textOf(boxes[j])); }
          }
          if (price === null) return;
          var brandBox = tile.querySelector('[class*="brand" i], [itemprop~="brand"]');
          add(name, price, tile.getAttribute('data-gtin') || tile.getAttribute('data-ean'), imageOf(tile),
              textOf(brandBox), quantityOf(tile, price));
        });
      }
      if (out.length === 0) {
        fromTiles('[class*="product-tile" i], [class*="producttile" i], [class*="product-card" i], [class*="productcard" i], ' +
                  '[class*="product-thumbnail" i], [class*="product-item" i], [class*="productitem" i], [class*="product-box" i]');
      }
      if (out.length === 0) {
        var cards = document.querySelectorAll('article, li, [class*="product" i], [data-testid*="product" i]');
        cards.forEach(function (card) {
          if (out.length >= 100) return;
          var text = card.innerText || '';
          if (text.length < 8 || text.length > 700) return;
          var price = priceIn(text);
          if (price === null) return;
          var found = firstOf(card, NAME);
          var title = found ? (found.el.getAttribute('title') || textOf(found.el)) : null;
          add(title, price, null, imageOf(card), textOf(card.querySelector('[class*="brand" i]')), quantityOf(card, price));
        });
      }
      return JSON.stringify(out.slice(0, 120));
    })();
    """#
}
