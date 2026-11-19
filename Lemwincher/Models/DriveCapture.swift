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
    /// Page des rayons, quand le site en a une (sinon l'accueil, d'où l'on navigue dans les rayons).
    var aislesURL: String? = nil

    /// Où ouvrir le site depuis un magasin de la carte : ses rayons, sinon son accueil.
    var startURL: URL? { URL(string: aislesURL ?? home) }

    /// Site propre d'un magasin (adresse du site dans OpenStreetMap), lu comme les autres.
    static func custom(for store: Store, url: URL) -> DriveSite {
        DriveSite(id: "magasin-" + store.id, name: store.name, chainPrefix: store.chainKey ?? "-",
                  home: url.absoluteString, searchTemplate: url.absoluteString, choosesStore: false)
    }

    /// Le site de l'enseigne d'un magasin, s'il fait partie des sites connus.
    static func forStore(_ store: Store) -> DriveSite? {
        all.first { $0.matches(store) }
    }

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
                  choosesStore: false, aislesURL: "https://www.aldi.fr/produits.html"),
        DriveSite(id: "monoprix", name: "Monoprix", chainPrefix: "monop",
                  home: "https://courses.monoprix.fr", searchTemplate: "https://courses.monoprix.fr/search?q={q}",
                  choosesStore: false),
        DriveSite(id: "chronodrive", name: "Chronodrive", chainPrefix: "chronodrive",
                  home: "https://www.chronodrive.com", searchTemplate: "https://www.chronodrive.com/search/{q}"),
        DriveSite(id: "picard", name: "Picard", chainPrefix: "picard",
                  home: "https://www.picard.fr", searchTemplate: "https://www.picard.fr/recherche?q={q}",
                  choosesStore: false),
        DriveSite(id: "naturalia", name: "Naturalia", chainPrefix: "naturalia",
                  home: "https://www.naturalia.fr", searchTemplate: "https://www.naturalia.fr/catalogsearch/result/?q={q}",
                  choosesStore: false),
        // Biocoop : les prix n'apparaissent qu'une fois le magasin choisi sur le site.
        DriveSite(id: "biocoop", name: "Biocoop", chainPrefix: "biocoop",
                  home: "https://www.biocoop.fr", searchTemplate: "https://www.biocoop.fr/catalogsearch/result/?q={q}"),
        DriveSite(id: "lavieclaire", name: "La Vie Claire", chainPrefix: "la vie claire",
                  home: "https://www.lavieclaire.com", searchTemplate: "https://www.lavieclaire.com/?s={q}",
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
    /// En promotion sur la page (prix barré ou badge « promo »), avec l'ancien prix s'il est affiché.
    var promo: Bool = false
    var oldPrice: Double?
    /// Fiche du produit sur le site (distingue deux produits de même nom et même prix : yaourt fraise / framboise).
    var link: String?
    var include: Bool = true

    /// Même nom, marque, contenance et prix = même ligne ("Œufs plein air" Auchan 6 et 12 pièces restent distincts),
    /// sauf deux fiches différentes sur le site.
    var id: String { [baseKey, link ?? ""].joined(separator: "|") }

    /// Nom, marque, contenance et prix.
    var baseKey: String {
        [brand ?? "", name, quantity ?? "", String(format: "%.2f", price)].joined(separator: "|").lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case name, price, gtin, image, brand, quantity, promo, oldPrice, link
    }

    init(name: String, price: Double, gtin: String? = nil, image: String? = nil,
         brand: String? = nil, quantity: String? = nil, promo: Bool = false, oldPrice: Double? = nil,
         link: String? = nil) {
        self.name = name
        self.price = price
        self.gtin = gtin
        self.image = image
        self.brand = brand
        self.quantity = quantity
        self.promo = promo
        self.oldPrice = oldPrice
        self.link = link
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lossyString(.name) ?? ""
        price = c.lossyDouble(.price) ?? 0
        gtin = c.lossyString(.gtin)
        image = c.lossyString(.image)
        brand = c.lossyString(.brand)?.nilIfBlank
        quantity = c.lossyString(.quantity)?.nilIfBlank
        promo = c.lossyBool(.promo) ?? false
        oldPrice = c.lossyDouble(.oldPrice)
        link = c.lossyString(.link)?.nilIfBlank
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
            // Un ancien prix n'a de sens que plus élevé que le prix affiché.
            if let old = cleaned.oldPrice, old <= cleaned.price || old >= 1000 { cleaned.oldPrice = nil }
            if cleaned.oldPrice != nil { cleaned.promo = true }
            if seen.insert(cleaned.id).inserted { result.append(cleaned) }
        }
        return distinguishTwins(result)
    }

    /// Même nom, marque, contenance et prix mais deux fiches (Aldi : « Yaourt à boire » fraise et framboise) :
    /// on ajoute le mot qui les distingue dans le nom de leur photo, sinon la référence de leur fiche.
    static func distinguishTwins(_ items: [CapturedPrice]) -> [CapturedPrice] {
        var groups: [String: [Int]] = [:]
        for (index, item) in items.enumerated() { groups[item.baseKey, default: []].append(index) }
        var result = items
        for indices in groups.values where indices.count > 1 {
            let tokens = indices.map { imageTokens(items[$0]) }
            let shared = tokens.dropFirst().reduce(Set(tokens[0])) { $0.intersection($1) }
            let hints = tokens.map { $0.filter { !shared.contains($0) }.prefix(3).joined(separator: " ") }
            let usable = !hints.contains("") && Set(hints).count == hints.count
            for (position, index) in indices.enumerated() {
                if usable {
                    result[index].name += " " + hints[position]
                } else if let reference = reference(in: items[index].link) {
                    result[index].name += " (réf. \(reference))"
                }
            }
        }
        return result
    }

    /// Mots du nom de la photo absents du nom et de la marque :
    /// « …YAOURT_A_BOIRE_SAVEUR_FRAMBOISE_MILSANI-WEB.png » → ["saveur", "framboise"].
    static func imageTokens(_ item: CapturedPrice) -> [String] {
        guard let image = item.image, let url = URL(string: image) else { return [] }
        let known = Set(SuggestionEngine.tokens([item.name, item.brand ?? ""].joined(separator: " ")))
        var seen = Set<String>()
        return SuggestionEngine.tokens(url.deletingPathExtension().lastPathComponent)
            .filter { token in
                token.count >= 3 && token.allSatisfy(\.isLetter) && !known.contains(token)
                    && !imageJunk.contains(token) && seen.insert(token).inserted
            }
    }

    private static let imageJunk: Set<String> = [
        "web", "main", "all", "png", "jpg", "jpeg", "webp", "gif", "avif", "image", "img", "images", "product",
        "products", "produit", "produits", "front", "face", "default", "large", "small", "medium", "zoom",
        "packshot", "visuel", "photo", "thumb", "thumbnail", "fra", "hd", "low", "high",
    ]

    /// « …/yaourt-a-boire-5024835.html » → « 5024835 ».
    static func reference(in link: String?) -> String? {
        guard let link, let path = URL(string: link)?.path else { return nil }
        let runs = path.split { !$0.isNumber }.filter { $0.count >= 4 }
        return runs.last.map(String.init)
    }

    /// "BEURRE DOUX" -> "Beurre doux" (les noms tout en majuscules seulement).
    static func sentenceCase(_ name: String) -> String {
        guard name.rangeOfCharacter(from: .lowercaseLetters) == nil,
              name.rangeOfCharacter(from: .uppercaseLetters) != nil else { return name }
        let lower = name.lowercased(with: Locale(identifier: "fr_FR"))
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    /// Fonctions de lecture, exécutées dans la page affichée (corps d'une fonction asynchrone,
    /// via `callAsyncJavaScript`). Elles lisent les produits décrits pour les moteurs de recherche
    /// (JSON-LD, microdonnées schema.org), les fiches produit affichées (nom, marque, prix, contenance, promo),
    /// sinon les « cartes produit » visibles. `extract(doc)` sert aussi aux pages suivantes, téléchargées à part.
    static let functions = #"""
    var LIMIT = 1000;
    var out = [];
    var seen = {};
    // Produits affichés sans prix (indisponibles, prix en magasin…) : leurs noms, pour le dire.
    var noPrice = [];
    var noPriceSeen = {};
    var base = document.baseURI;
    function clean(text) { return text ? String(text).replace(/\s+/g, ' ').trim() : ''; }
    // `link` : la fiche du produit ; `el` : son bloc dans la page. Même nom, marque, contenance et prix =
    // même produit, sauf deux fiches différentes dans deux blocs distincts (yaourt fraise / framboise).
    function add(name, price, gtin, image, brand, quantity, promo, link, el) {
      if (out.length >= LIMIT || !name || price === undefined || price === null) return;
      name = clean(name);
      var p = typeof price === 'number' ? price : parseFloat(String(price).replace(/[^0-9,.]/g, '').replace(',', '.'));
      if (!(p > 0 && p < 1000) || name.length < 3) return;
      brand = clean(brand);
      // "AUCHAN Oeufs de poules…" (marque AUCHAN) -> "Oeufs de poules…".
      if (brand && name.toLowerCase().indexOf(brand.toLowerCase() + ' ') === 0 && name.length > brand.length + 3) {
        name = name.slice(brand.length + 1).trim();
      }
      var key = [brand, name, quantity || '', p.toFixed(2)].join('|').toLowerCase();
      var entry = seen[key];
      if (entry) {
        if (!link || entry.links.indexOf(link) >= 0) return;
        for (var i = 0; i < entry.els.length; i++) {
          var other = entry.els[i];
          if (el && (other === el || other.contains(el) || el.contains(other))) return;
        }
      } else {
        entry = seen[key] = { links: [], els: [] };
      }
      if (link) entry.links.push(link);
      if (el) entry.els.push(el);
      out.push({ name: name.slice(0, 160), price: Math.round(p * 100) / 100,
                 gtin: gtin ? String(gtin) : null, image: image ? String(image) : null,
                 brand: brand && brand.length <= 40 && brand.toLowerCase() !== name.toLowerCase() ? brand : null,
                 quantity: quantity || null,
                 promo: promo ? true : false,
                 oldPrice: promo && promo.old > p ? Math.round(promo.old * 100) / 100 : null,
                 link: link || null });
    }
    // Premier prix d'un texte qui n'est pas un prix au kilo / au litre : "2.99", "2,99 €", "2€99", "1 € , 40".
    function priceIn(text) {
      var re = /(\d{1,3})\s?(?:€\s?[,.]?|[,.])\s?(\d{2})(?!\d)\s?€?(\s?\/\s?(kg|l|kilo|litre|unité|pièce))?/gi;
      var m;
      while ((m = re.exec(text || '')) !== null) { if (!m[3]) return parseFloat(m[1] + '.' + m[2]); }
      return null;
    }
    function textOf(el) { return el ? clean(el.innerText || el.textContent) : ''; }
    function letters(text) { return String(text || '').replace(/[^a-zà-ÿœæ]/gi, '').length; }
    // Texte propre d'un élément (sans celui de ses enfants).
    function ownText(el) {
      var s = '';
      for (var c = el.firstChild; c; c = c.nextSibling) { if (c.nodeType === 3) s += c.nodeValue; }
      return clean(s);
    }
    // Un prix seul : « 1,55 € », « 1.99 », « 2€99 », « 1 € , 40 » (pas « 1,55 € / kg », ni « KG = 1.85 »).
    var LONE_PRICE = /^(?:à partir de |dès |prix :? ?)?\d{1,3} ?(?:[,.] ?\d{2} ?€?|€ ?[,.]? ?\d{2})(?: ?TTC)?$/i;
    // Les prix seuls de la page (hors prix barrés) et, pour chaque bloc, combien il en contient.
    function priceIndex(doc) {
      var list = [], counts = new Map();
      var all = (doc.body || doc).querySelectorAll('*');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        if (el.children.length > 4 || /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(el.tagName)) continue;
        var raw = el.textContent || '';
        var full = raw.length <= 40 ? clean(raw) : '';
        var own = el.children.length ? ownText(el) : '';
        var lone = LONE_PRICE.test(full);
        if (lone) {
          // Le plus petit élément qui contient le prix (« <div><span>1,55 €</span></div> » -> le span).
          for (var c = 0; c < el.children.length; c++) {
            if (LONE_PRICE.test(clean(el.children[c].textContent))) { lone = false; break; }
          }
        } else if (own && LONE_PRICE.test(own)) {
          lone = true;
        }
        if (!lone || el.closest(OLD_PRICE)) continue;
        list.push(el);
        for (var a = el; a; a = a.parentElement) counts.set(a, (counts.get(a) || 0) + 1);
      }
      return { list: list, counts: counts };
    }
    var SKIP_TEXT = /^(ajouter|voir|promo|nouveau|nouveauté|offre|nutri|disponible|indisponible|en stock|rupture|bientôt|découvrir|choisir|acheter|sélectionner|retirer|livraison|retrait|drive)\b/i;
    // Nom d'un produit sans balise connue : le texte (propre) le plus long de la fiche, hors prix et boutons.
    function longestText(card) {
      var best = '', bestLetters = 0;
      var els = card.querySelectorAll('*');
      for (var i = 0; i < els.length && i < 600; i++) {
        var el = els[i];
        if (/^(SCRIPT|STYLE|NOSCRIPT|SVG|BUTTON|SELECT|OPTION|TEMPLATE)$/i.test(el.tagName)) continue;
        if (letters(ownText(el)) < 2) continue;
        var blocker = el.closest('button, select, [class*="nutri" i], [class*="rating" i], [class*="review" i]');
        if (blocker && blocker !== card && card.contains(blocker)) continue;
        var t = textOf(el);
        if (t.length < 4 || t.length > 160 || SKIP_TEXT.test(t) || /\d ?[,.] ?\d{2} ?€|€ ?\d/.test(t)) continue;
        var n = letters(t);
        if (n >= 4 && n > bestLetters) { best = t; bestLetters = n; }
      }
      if (best) return best;
      // Sinon : le texte de la photo ou du lien.
      var named = card.querySelectorAll('img[alt], a[title], a[aria-label], [aria-label]');
      for (var j = 0; j < named.length; j++) {
        var label = clean(named[j].getAttribute('alt') || named[j].getAttribute('title') || named[j].getAttribute('aria-label'));
        if (letters(label) >= 4 && !/logo|nutri|picto|marque rep|ajouter|panier/i.test(label) && letters(label) > bestLetters) {
          best = label; bestLetters = letters(label);
        }
      }
      return best || null;
    }
    // Fiche du produit : le lien le plus fréquent du bloc (photo et nom mènent à la fiche), hors panier et listes.
    function linkOf(el) {
      var links = el.querySelectorAll('a[href]'), counts = {}, best = null;
      var hrefs = [];
      for (var i = 0; i < links.length; i++) hrefs.push(links[i].getAttribute('href'));
      if (!hrefs.length && el.closest) {
        var up = el.closest('a[href]');
        if (up) hrefs.push(up.getAttribute('href'));
      }
      for (var j = 0; j < hrefs.length; j++) {
        var href = hrefs[j];
        if (!href || href === '#' || href.indexOf('javascript:') === 0 ||
            /panier|cart|basket|wishlist|favori|liste|login|connexion|compte|ajout/i.test(href)) continue;
        try { var u = new URL(href, base); u.hash = ''; href = u.href; } catch (e) { continue; }
        counts[href] = (counts[href] || 0) + 1;
        if (!best || counts[href] > counts[best]) best = href;
      }
      return best;
    }
    // Prix barrés (sélecteurs précis : « old » seul attraperait « price-holder », « bold »…).
    var OLD_PRICE = 'del, s, strike, [class*="old-price" i], [class*="oldprice" i], [class*="old_price" i], ' +
                    '[class*="price-old" i], [class*="price--old" i], [class*="price__old" i], [class*="strike" i], ' +
                    '[class*="crossed" i], [class*="barre" i], [class*="was-price" i], [class*="wasprice" i], ' +
                    '[class*="previous-price" i], [class*="price-before" i], [class*="before-price" i]';
    // Texte d'une case prix sans le prix barré (« 3,29 € 2,49 € » -> « 2,49 € »).
    function priceText(el) {
      var copy = el.cloneNode(true);
      copy.querySelectorAll(OLD_PRICE).forEach(function (x) { x.remove(); });
      return clean(copy.textContent);
    }
    // Promo : ancien prix barré plus élevé, ou badge « promo », « -30 % », « 2 + 1 offert »…
    function promoOf(tile, price) {
      var olds = tile.querySelectorAll(OLD_PRICE);
      for (var i = 0; i < olds.length; i++) {
        var old = priceIn(textOf(olds[i]));
        if (old && old > price) return { old: old };
      }
      var badges = tile.querySelectorAll('[class*="promo" i], [class*="discount" i], [class*="reduction" i], [class*="sticker" i], [class*="flag" i], [class*="badge" i]');
      for (var j = 0; j < badges.length; j++) {
        if (/promo|offert|remise|réduction|-\s?\d{1,2}\s?%|\d\s?\+\s?\d/i.test(textOf(badges[j]))) return { old: null };
      }
      return null;
    }
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
    var TILES = '[class*="product-tile" i], [class*="producttile" i], [class*="product-card" i], [class*="productcard" i], ' +
                '[class*="product-thumbnail" i], [class*="product-item" i], [class*="productitem" i], [class*="product-box" i]';
    // Contenance : écrite sur la fiche ("250 g") ou dans le nom ("Mayonnaise - 450g", "4 x 100 g"),
    // sinon déduite du prix au kilo ("KG = 9.40" pour 2,35 € -> 250 g).
    function quantityOf(tile, price, name) {
      var unitBoxes = tile.querySelectorAll('[class*="salesunit" i], [class*="sales-unit" i], [class*="quantity" i], ' +
        '[class*="packaging" i], [class*="weight" i], [class*="attribute" i], [class*="contenance" i]');
      for (var k = 0; k < unitBoxes.length; k++) {
        var m = /(\d+(?:[.,]\d+)?)\s*(kg|g|l|cl|ml|pièces?|pcs|unités?)(?![a-zà-ÿ])/i.exec(textOf(unitBoxes[k]));
        if (m) return m[1].replace(',', '.') + ' ' + m[2].toLowerCase();
      }
      var named = null;
      if (name) {
        var nameRe = /(\d{1,3}\s?[x×]\s?)?(\d+(?:[.,]\d+)?)\s?(kg|g|l|cl|ml)(?![a-zà-ÿ])/gi, mm, txt = clean(name);
        while ((mm = nameRe.exec(txt)) !== null) {
          // Pas une fourchette (« calibre 63/73g », « 53-63 g ») : le poids d'un œuf n'est pas celui de la boîte.
          var before = txt.slice(Math.max(0, mm.index - 10), mm.index);
          if (/\d\s?[\/\-–]$/.test(before) || /calibre\s?$/i.test(before)) continue;
          named = mm;
          break;
        }
      }
      if (named && parseFloat(named[2].replace(',', '.')) > 0) {
        return (named[1] ? named[1].replace(/\s/g, '').replace('×', 'x').replace('x', ' x ') : '') +
               named[2].replace(',', '.') + ' ' + named[3].toLowerCase();
      }
      var baseBox = tile.querySelector('[class*="base-price" i], [class*="baseprice" i], [class*="unit-price" i], [class*="price-per" i]');
      var unit, basePrice, b = null;
      // Dans la case du prix au kilo : "KG = 9.40" ou "1 kg = 9,40 €".
      if (baseBox) { b = /\b(kg|l)\b[^0-9]{0,8}(\d{1,4})[,.](\d{2})/i.exec(textOf(baseBox)); }
      if (b) { unit = b[1].toLowerCase(); basePrice = parseFloat(b[2] + '.' + b[3]); }
      else {
        // "9,40 €/kg", "8 € / Kilo", dans cette case ou n'importe où sur la fiche.
        b = /(\d{1,4})(?:[,.](\d{2})\s?€?|\s?€)\s?\/\s?(kg|kilo|l|litre)\b/i.exec(baseBox ? textOf(baseBox) : textOf(tile));
        if (b) { unit = /^k/i.test(b[3]) ? 'kg' : 'l'; basePrice = parseFloat(b[1] + '.' + (b[2] || '00')); }
      }
      if (!(basePrice > 0) || !(price > 0)) return null;
      var amount = Math.round(price / basePrice * 1000);
      if (amount >= 100) amount = Math.round(amount / 5) * 5;
      if (!(amount > 0)) return null;
      if (unit === 'kg') return amount >= 1000 ? (amount / 1000) + ' kg' : amount + ' g';
      return amount >= 1000 ? (amount / 1000) + ' l' : (amount % 10 === 0 ? (amount / 10) + ' cl' : amount + ' ml');
    }
    // Adresse d'une image : affichée, sinon à charger plus tard (data-src, srcset), jamais un pixel d'attente.
    function srcOf(img) {
      var candidates = [img.currentSrc, img.getAttribute('src'), img.getAttribute('data-src'),
                        img.getAttribute('data-lazy-src'),
                        (img.getAttribute('srcset') || img.getAttribute('data-srcset') || '').split(' ')[0]];
      for (var i = 0; i < candidates.length; i++) {
        var url = candidates[i];
        if (url && url.indexOf('data:') !== 0) {
          try { return new URL(url, base).href; } catch (e) { return url; }
        }
      }
      return null;
    }
    // Photo du produit : la plus grande image affichée de la fiche (pas le logo de la marque ni le Nutri-Score).
    function imageOf(el) {
      var imgs = el.querySelectorAll('img'), best = null, bestArea = 0, plain = null, first = null;
      for (var i = 0; i < imgs.length; i++) {
        var url = srcOf(imgs[i]);
        if (!url) continue;
        if (!first) first = url;
        var rect = imgs[i].getBoundingClientRect();
        var area = rect.width * rect.height;
        if (area > bestArea) { bestArea = area; best = url; }
        var hint = (imgs[i].getAttribute('alt') || '') + ' ' + (imgs[i].getAttribute('class') || '') + ' ' +
                   url.split('?')[0].split('/').pop();
        if (!plain && !/logo|nutri|picto|badge|icon|sticker|rating|score/i.test(hint)) plain = url;
      }
      return best || plain || first;
    }
    function item(name, price, gtin, image, brand, quantity, promo, link, el) {
      return { name: name, price: price, gtin: gtin, image: image, brand: brand, quantity: quantity, promo: promo,
               link: link, el: el };
    }
    // Nom d'une fiche : la balise du nom si elle est unique dans la fiche, sinon son texte le plus long.
    function nameOf(card) {
      var found = firstOf(card, NAME);
      if (found && card.querySelectorAll(found.selector).length === 1) {
        var t = textOf(found.el) || clean(found.el.getAttribute('title'));
        if (letters(t) >= 3 && !LONE_PRICE.test(t)) return t;
      }
      return longestText(card);
    }
    // Données structurées JSON-LD (Product, listes de produits, @graph).
    function fromLD(doc) {
      var items = [];
      function walk(node) {
        if (!node) return;
        if (Array.isArray(node)) { node.forEach(walk); return; }
        if (typeof node !== 'object') return;
        var type = node['@type'];
        var types = Array.isArray(type) ? type : [type];
        if (types.indexOf('Product') >= 0) {
          var offers = node.offers;
          if (Array.isArray(offers)) offers = offers[0];
          var price = offers ? (offers.price || offers.lowPrice) : null;
          var image = Array.isArray(node.image) ? node.image[0] : node.image;
          if (image && typeof image === 'object') image = image.url;
          var brand = node.brand && typeof node.brand === 'object' ? node.brand.name : node.brand;
          var url = node.url || (offers && offers.url);
          var link = null;
          if (typeof url === 'string') { try { var u = new URL(url, base); u.hash = ''; link = u.href; } catch (e) {} }
          if (price) items.push(item(node.name, price, node.gtin13 || node.gtin || node.gtin8, image, brand, null, null,
                                     link, null));
        }
        if (Array.isArray(node.itemListElement)) {
          walk(node.itemListElement.map(function (e) { return (e && e.item) ? e.item : e; }));
        }
        if (node['@graph']) walk(node['@graph']);
      }
      doc.querySelectorAll('script[type="application/ld+json"]').forEach(function (s) {
        try { walk(JSON.parse(s.textContent)); } catch (e) {}
      });
      return items;
    }
    // Microdonnées : itemprop peut contenir plusieurs mots ("name description" chez Auchan).
    function fromMicrodata(doc) {
      var items = [];
      doc.querySelectorAll('[itemtype*="schema.org/Product"]').forEach(function (el) {
        var n = el.querySelector('[itemprop~="name"]');
        var p = el.querySelector('[itemprop~="price"]');
        if (!n || !p) return;
        var g = el.querySelector('[itemprop^="gtin"]');
        var b = el.querySelector('[itemprop~="brand"]');
        var text = p.getAttribute('content') || p.textContent;
        var value = text ? parseFloat(String(text).replace(/[^0-9,.]/g, '').replace(',', '.')) : null;
        if (!(value > 0)) return;
        var u = el.querySelector('[itemprop~="url"]');
        var link = u ? (u.getAttribute('href') || u.getAttribute('content')) : null;
        if (link) { try { var l = new URL(link, base); l.hash = ''; link = l.href; } catch (e) { link = null; } }
        items.push(item(n.getAttribute('content') || n.textContent, text,
                        g && (g.getAttribute('content') || g.textContent), imageOf(el),
                        b && (b.getAttribute('content') || b.textContent), quantityOf(el, value, n.getAttribute('content') || n.textContent), promoOf(el, value),
                        link || linkOf(el), el));
      });
      return items;
    }
    // Fiches produit (Aldi, Auchan, Monoprix… et la plupart des sites) : une fiche = un seul produit.
    var tileNoPrice = [];
    function fromTiles(doc, index) {
      var items = [], accepted = [];
      tileNoPrice = [];
      doc.querySelectorAll(TILES).forEach(function (tile) {
        if (items.length >= LIMIT) return;
        // Plus de 3 prix : c'est le conteneur de la grille (titre du rayon compris), pas une fiche.
        var prices = index.counts.get(tile) || 0;
        if (prices > 3) return;
        // Un bloc à l'intérieur d'une fiche déjà lue (« La boîte », la case du prix…) n'est pas un autre produit.
        for (var k = accepted.length - 1; k >= 0; k--) { if (accepted[k].contains(tile)) return; }
        var found = firstOf(tile, NAME);
        var name = null, tagged = false;
        if (found && tile.querySelectorAll(found.selector).length === 1) {
          name = textOf(found.el) || found.el.getAttribute('title');
          tagged = true;
        } else if (prices <= 1) {
          name = longestText(tile);
        }
        if (!name) return;
        var price = null;
        for (var i = 0; i < PRICE.length && price === null; i++) {
          var boxes = tile.querySelectorAll(PRICE[i]);
          for (var j = 0; j < boxes.length && price === null; j++) { price = priceIn(priceText(boxes[j])); }
        }
        if (price === null) {
          if (tagged && prices === 0 && letters(name) >= 3) tileNoPrice.push(clean(name));
          return;
        }
        accepted.push(tile);
        var brandBox = tile.querySelector('[class*="brand" i], [itemprop~="brand"]');
        items.push(item(name, price, tile.getAttribute('data-gtin') || tile.getAttribute('data-ean'), imageOf(tile),
                        textOf(brandBox), quantityOf(tile, price, name), promoOf(tile, price), linkOf(tile), tile));
      });
      // Un bloc intérieur d'une fiche (nom et marque seuls) n'est pas un produit sans prix.
      var pricedNames = {};
      items.forEach(function (i) { pricedNames[clean(i.name).toLowerCase()] = true; });
      tileNoPrice = tileNoPrice.filter(function (n) { return !pricedNames[n.toLowerCase()]; });
      return items;
    }
    // Grilles sans classes connues (Leclerc Drive…) : les blocs répétés côte à côte qui contiennent chacun un prix.
    // On remonte de chaque prix jusqu'au bloc dont le parent compte au moins 3 enfants avec un prix : la fiche.
    function fromGrid(doc, index) {
      var items = [], cards = [], taken = new Set();
      index.list.forEach(function (priceEl) {
        for (var a = priceEl; a && a.parentElement; a = a.parentElement) {
          var parent = a.parentElement;
          if (parent === doc.documentElement || parent === doc.body) return;
          var priced = 0;
          for (var c = 0; c < parent.children.length && priced < 3; c++) {
            if (index.counts.has(parent.children[c])) priced++;
          }
          if (priced >= 3) {
            if (!taken.has(a)) { taken.add(a); cards.push({ card: a, price: priceEl }); }
            return;
          }
        }
      });
      cards.forEach(function (entry) {
        if (items.length >= LIMIT) return;
        var card = entry.card;
        if ((index.counts.get(card) || 0) > 3 || textOf(card).length > 900) return;
        var price = priceIn(textOf(entry.price));
        var name = price === null ? null : nameOf(card);
        if (!name) return;
        items.push(item(name, price, card.getAttribute('data-gtin') || card.getAttribute('data-ean'), imageOf(card),
                        textOf(card.querySelector('[class*="brand" i], [itemprop~="brand"]')),
                        quantityOf(card, price, name), promoOf(card, price), linkOf(card), card));
      });
      return items;
    }
    // Dernier recours : tout bloc court qui contient un nom et un prix.
    function fromCards(doc, index) {
      var items = [], accepted = [];
      doc.querySelectorAll('article, li, [class*="product" i], [data-testid*="product" i]').forEach(function (card) {
        if (items.length >= LIMIT) return;
        var text = textOf(card);
        if (text.length < 8 || text.length > 700 || (index.counts.get(card) || 0) > 3) return;
        for (var k = accepted.length - 1; k >= 0; k--) { if (accepted[k].contains(card)) return; }
        var price = priceIn(priceText(card));
        var name = price === null ? null : nameOf(card);
        if (!name) return;
        accepted.push(card);
        items.push(item(name, price, null, imageOf(card), textOf(card.querySelector('[class*="brand" i]')),
                        quantityOf(card, price, name), promoOf(card, price), linkOf(card), card));
      });
      return items;
    }
    // Lit une page : la méthode qui trouve le plus de produits (une seule fiche JSON-LD ne cache pas toute une grille).
    function extract(doc, url) {
      base = url || doc.baseURI || document.baseURI;
      var index = priceIndex(doc);
      var chosen = fromLD(doc).concat(fromMicrodata(doc));
      var tiles = fromTiles(doc, index);
      var tilesChosen = false;
      if (tiles.length > chosen.length) { chosen = tiles; tilesChosen = true; }
      var grid = fromGrid(doc, index);
      if (grid.length > chosen.length) { chosen = grid; tilesChosen = false; }
      if (chosen.length === 0) chosen = fromCards(doc, index);
      if (tilesChosen) {
        tileNoPrice.forEach(function (name) {
          if (!noPriceSeen[name.toLowerCase()] && noPrice.length < 50) { noPriceSeen[name.toLowerCase()] = true; noPrice.push(name); }
        });
      }
      chosen.forEach(function (i) { add(i.name, i.price, i.gtin, i.image, i.brand, i.quantity, i.promo, i.link, i.el); });
      return chosen.length;
    }
    function sleep(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
    function report() {
      try { window.webkit.messageHandlers.lemwincher.postMessage({ count: out.length }); } catch (e) {}
    }
    function stopped() { return window.__lemwincherStop === true; }
    function visible(el) { return !!(el.offsetParent || el.getClientRects().length); }
    // Bouton « Voir plus / Afficher plus / Charger plus » (jamais un lien vers une autre page).
    function loadMoreButton() {
      var words = /(voir|afficher|charger|load|show)\s*(plus|more|davantage|la suite|d'autres|tous)|plus de (produits|résultats)|produits suivants|résultats suivants/i;
      var els = document.querySelectorAll('button, [role="button"], a');
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        var label = clean(el.innerText || el.textContent || el.getAttribute('aria-label') || '');
        var cls = String(el.getAttribute('class') || '');
        if (label.length > 40 || !(words.test(label) || /load-?more|show-?more|voir-?plus/i.test(cls))) continue;
        if (!visible(el) || el.disabled || el.getAttribute('aria-disabled') === 'true') continue;
        var href = el.tagName === 'A' ? (el.getAttribute('href') || '') : '';
        if (href && href.indexOf('#') !== 0 && href.indexOf('javascript:') !== 0) continue;
        return el;
      }
      return null;
    }
    // Page suivante d'une liste paginée (lien « suivant », rel="next").
    function nextPage(doc, from) {
      var el = doc.querySelector('link[rel="next"], a[rel="next"], a[aria-label*="suivant" i], a[title*="suivant" i], ' +
                                 'a[aria-label*="next" i], [class*="pagination" i] a[class*="next" i], a[class*="next" i]');
      var href = el ? el.getAttribute('href') : null;
      if (!href || href === '#' || href.indexOf('javascript:') === 0) return null;
      try { return new URL(href, from).href; } catch (e) { return null; }
    }
    // Lit TOUS les produits : défile, touche « Voir plus » tant qu'il en vient, puis suit les pages suivantes.
    async function captureAll(maxMs) {
      window.__lemwincherStop = false;
      var start = Date.now();
      extract(document);
      report();
      var last = out.length, quiet = 0;
      while (!stopped() && Date.now() - start < maxMs && out.length < LIMIT) {
        window.scrollTo(0, document.documentElement.scrollHeight);
        await sleep(800);
        var more = loadMoreButton();
        if (more) {
          try { more.scrollIntoView({ block: 'center' }); more.click(); } catch (e) {}
          await sleep(1500);
        }
        extract(document);
        report();
        if (out.length > last) { last = out.length; quiet = 0; }
        else { quiet += 1; if ((!more && quiet >= 2) || quiet >= 4) break; }
      }
      window.scrollTo(0, 0);
      var url = nextPage(document, document.baseURI), visited = {}, pages = 0;
      while (url && !visited[url] && pages < 20 && !stopped() && Date.now() - start < maxMs + 30000 && out.length < LIMIT) {
        visited[url] = true;
        try {
          var response = await fetch(url, { credentials: 'include' });
          var doc = new DOMParser().parseFromString(await response.text(), 'text/html');
          var before = out.length;
          extract(doc, url);
          report();
          if (out.length === before) break;
          url = nextPage(doc, url);
          pages += 1;
        } catch (e) { break; }
      }
      return JSON.stringify(out);
    }
    """#

    /// Lecture de la page telle qu'elle est affichée (expression : renvoie le texte JSON).
    static let script = "(function () {\n" + functions + "\nextract(document);\nreturn JSON.stringify(out);\n})();"

    /// Structure de la page autour des deux premiers prix (balises, classes, texte de la fiche), pour le journal
    /// quand presque rien n'a été lu : de quoi adapter la lecture au site. Ni champ de saisie ni en-tête du site.
    static let structureScript = #"""
    (function () {
      function clean(t) { return t ? String(t).replace(/\s+/g, ' ').trim() : ''; }
      function desc(el) {
        var cls = clean(el.getAttribute('class')).split(' ').slice(0, 2).join('.');
        var test = el.getAttribute('data-testid');
        return el.tagName.toLowerCase() + (cls ? '.' + cls : '') + (test ? '[' + test.slice(0, 30) + ']' : '');
      }
      var re = /^\d{1,3} ?(?:[,.] ?\d{2} ?€?|€ ?[,.]? ?\d{2})$/;
      var els = document.body ? document.body.querySelectorAll('*') : [];
      var lines = ['Page : ' + els.length + ' éléments, ' + document.images.length + ' images'];
      var found = 0, lastCard = null;
      for (var i = 0; i < els.length && found < 2; i++) {
        var el = els[i];
        if (el.children.length > 4 || el.closest('header, nav, form, footer')) continue;
        if (lastCard && lastCard.contains(el)) continue;
        var raw = el.textContent || '';
        if (raw.length > 40 || !re.test(clean(raw))) continue;
        var inner = false;
        for (var c = 0; c < el.children.length; c++) { if (re.test(clean(el.children[c].textContent))) inner = true; }
        if (inner) continue;
        found += 1;
        var path = [], a = el;
        for (var k = 0; k < 8 && a && a !== document.body; k++) { path.push(desc(a) + '(' + a.children.length + ')'); a = a.parentElement; }
        lines.push('Prix « ' + clean(raw) + ' » : ' + path.join(' < '));
        var card = el;
        for (var up = 0; up < 6 && card.parentElement && card.parentElement !== document.body; up++) {
          if (clean(card.parentElement.textContent).length > 400) break;
          card = card.parentElement;
        }
        lines.push('   fiche ' + desc(card) + ' : ' + clean(card.textContent).slice(0, 240));
        lastCard = card;
      }
      if (found === 0) lines.push('Aucun prix seul trouvé (format de prix inconnu, ou page sans produits)');
      return lines.join('\n');
    })();
    """#

    /// Lecture de tous les produits : « Voir plus » et pages suivantes (45 s au plus sur la page, puis 30 s de pages).
    /// Le résultat revient par message (« done ») ; `window.__lemwincherOut` garde ce qui est lu en cas d'arrêt.
    static let fullScript = captureScript(maxMs: 45000)

    /// Même lecture, avec une durée maximale sur la page (plus courte pour les mises à jour automatiques).
    static func captureScript(maxMs: Int) -> String {
        "(function () {\n" + functions + """

        window.__lemwincherOut = out;
        function done(json) {
          try { window.webkit.messageHandlers.lemwincher.postMessage({ done: json, noPrice: noPrice }); } catch (e) {}
        }
        captureAll(\(maxMs)).then(done, function () { done(JSON.stringify(out)); });
        })();
        true;
        """
    }
}
