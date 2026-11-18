import Foundation

/// Emoji d'un produit courant (« Œufs » → 🥚) : vignette des produits sans photo (liste, rayons).
enum ProductEmoji {
    /// Mots-clés (minuscules, sans accents) → emoji, essayés dans l'ordre : les expressions précises passent
    /// avant les mots seuls (« pain au chocolat » avant « chocolat » et « pain », « lait de coco » avant « lait »).
    /// Un mot-clé trouve les mots qui commencent par lui (« oeuf » → « oeufs ») ; terminé par une espace,
    /// il doit être le mot entier (« lait » ne doit pas trouver « laitue », ni « mais » « maison »).
    private static let table: [(keys: [String], emoji: String)] = [
        (["croissant", "viennoiserie", "pain au chocolat", "pains au chocolat", "madeleine", "brioche"], "🥐"),
        (["pomme de terre", "pommes de terre", "patate", "frites", "puree"], "🥔"),
        (["pate a tartiner", "nutella", "nocciolata", "chocolat", "cacao"], "🍫"),
        (["lait de coco", "noix de coco", "coco"], "🥥"),
        (["huile", "vinaigre", "olive"], "🫒"),
        (["jus", "nectar", "smoothie"], "🧃"),
        (["eau ", "eaux ", "cristaline", "evian", "volvic"], "💧"),
        (["cafe", "expresso", "capsule"], "☕"),
        (["the ", "thes ", "infusion", "tisane"], "🍵"),
        (["soda", "cola", "limonade", "sirop"], "🥤"),
        (["biere", "vin ", "vins ", "cidre"], "🍷"),
        (["oeuf"], "🥚"),
        (["yaourt", "yogourt", "skyr", "fromage blanc", "petit suisse", "petits suisses", "creme dessert"], "🥣"),
        (["lait ", "laits "], "🥛"),
        (["beurre", "margarine"], "🧈"),
        (["fromage", "emmental", "comte", "camembert", "mozzarella", "gruyere", "raclette", "chevre",
          "parmesan", "brie", "roquefort", "feta", "cheddar"], "🧀"),
        (["creme"], "🥛"),
        (["pain", "baguette", "biscotte"], "🥖"),
        (["cereale", "muesli", "granola", "flocons d avoine", "porridge"], "🥣"),
        (["biscuit", "cookie", "gateau", "gaufre", "galette"], "🍪"),
        (["confiture", "miel", "pate de fruit"], "🍯"),
        (["pates", "spaghetti", "tagliatelle", "penne", "fusilli", "macaroni", "coquillette", "lasagne", "ravioli"], "🍝"),
        (["riz"], "🍚"),
        (["semoule", "couscous", "boulgour", "quinoa", "farine"], "🌾"),
        (["lentille", "pois chiche", "haricot rouge", "haricots rouges", "flageolet"], "🫘"),
        (["poulet", "volaille", "dinde", "cuisse", "aiguillette"], "🍗"),
        (["boeuf", "steak", "viande", "agneau", "veau", "merguez", "kebab", "hache"], "🥩"),
        (["saumon", "poisson", "cabillaud", "colin", "thon", "sardine", "maquereau", "truite", "merlu"], "🐟"),
        (["crevette", "gambas", "fruits de mer"], "🦐"),
        (["pizza"], "🍕"),
        (["sandwich", "wrap", "burger", "hamburger"], "🥪"),
        (["soupe", "veloute", "bouillon"], "🍲"),
        (["glace", "sorbet", "esquimau"], "🍦"),
        (["sel ", "poivre", "epice", "curry", "paprika", "cumin"], "🧂"),
        (["sucre"], "🍬"),
        (["ketchup", "mayonnaise", "moutarde", "sauce", "pesto", "conserve", "boite"], "🥫"),
        (["banane"], "🍌"),
        (["pomme", "compote"], "🍎"),
        (["poire"], "🍐"),
        (["orange", "clementine", "mandarine"], "🍊"),
        (["citron"], "🍋"),
        (["fraise"], "🍓"),
        (["framboise", "myrtille", "fruits rouges", "cerise"], "🍒"),
        (["raisin"], "🍇"),
        (["peche", "abricot", "nectarine"], "🍑"),
        (["melon", "pasteque"], "🍈"),
        (["ananas"], "🍍"),
        (["kiwi"], "🥝"),
        (["mangue"], "🥭"),
        (["avocat"], "🥑"),
        (["tomate"], "🍅"),
        (["carotte"], "🥕"),
        (["courgette", "concombre", "cornichon"], "🥒"),
        (["aubergine"], "🍆"),
        (["poivron"], "🫑"),
        (["piment"], "🌶️"),
        (["brocoli", "chou fleur"], "🥦"),
        (["salade", "laitue", "epinard", "chou", "mache", "roquette", "poireau"], "🥬"),
        (["champignon"], "🍄"),
        (["oignon", "echalote"], "🧅"),
        (["ail "], "🧄"),
        (["mais "], "🌽"),
        (["haricot vert", "haricots verts", "petits pois", "petit pois"], "🫛"),
        (["noix", "noisette", "amande", "cacahuete", "pistache"], "🥜"),
        (["papier toilette", "essuie tout", "mouchoir"], "🧻"),
        (["lessive", "liquide vaisselle", "nettoyant", "eponge", "javel"], "🧽"),
        (["savon", "gel douche", "shampooing", "shampoing", "dentifrice", "deodorant"], "🧴"),
        (["couche", "lingette"], "👶"),
        (["croquette", "patee", "litiere"], "🐾"),
    ]

    /// Emoji du produit, ou nil si son nom ne dit rien de connu.
    static func emoji(for name: String) -> String? {
        let words = SuggestionEngine.tokens(name)
        guard !words.isEmpty else { return nil }
        let text = " " + words.joined(separator: " ") + " "
        for entry in table where entry.keys.contains(where: { text.contains(" " + $0) }) {
            return entry.emoji
        }
        return nil
    }
}

/// Couleur et initiale d'une enseigne : épingles de la carte, logo de secours quand l'image ne charge pas.
struct ChainStyle: Equatable {
    /// 1 ou 2 lettres (« E », « C », « GF »).
    let monogram: String
    /// Couleur de l'enseigne, en hexadécimal (« 0060AA »).
    let hex: String

    /// Familles d'enseignes : préfixe de la clé normalisée (`Chain.key`) → style.
    private static let known: [(prefix: String, style: ChainStyle)] = [
        ("e leclerc", ChainStyle(monogram: "E", hex: "0060AA")),
        ("carrefour", ChainStyle(monogram: "C", hex: "1A4C9C")),
        ("my auchan", ChainStyle(monogram: "A", hex: "E3001B")),
        ("auchan", ChainStyle(monogram: "A", hex: "E3001B")),
        ("intermarche", ChainStyle(monogram: "I", hex: "D50032")),
        ("super u", ChainStyle(monogram: "U", hex: "164194")),
        ("hyper u", ChainStyle(monogram: "U", hex: "164194")),
        ("u express", ChainStyle(monogram: "U", hex: "164194")),
        ("marche u", ChainStyle(monogram: "U", hex: "164194")),
        ("utile", ChainStyle(monogram: "U", hex: "164194")),
        ("lidl", ChainStyle(monogram: "L", hex: "0050AA")),
        ("aldi", ChainStyle(monogram: "A", hex: "1B3D8F")),
        ("netto", ChainStyle(monogram: "N", hex: "E2001A")),
        ("leader price", ChainStyle(monogram: "LP", hex: "00843D")),
        ("geant casino", ChainStyle(monogram: "C", hex: "D6001C")),
        ("le petit casino", ChainStyle(monogram: "C", hex: "D6001C")),
        ("casino", ChainStyle(monogram: "C", hex: "D6001C")),
        ("monoprix", ChainStyle(monogram: "M", hex: "E2001A")),
        ("monop", ChainStyle(monogram: "M", hex: "E2001A")),
        ("franprix", ChainStyle(monogram: "F", hex: "F07D00")),
        ("spar", ChainStyle(monogram: "S", hex: "00843D")),
        ("vival", ChainStyle(monogram: "V", hex: "E30613")),
        ("proxi", ChainStyle(monogram: "P", hex: "E30613")),
        ("coccinelle", ChainStyle(monogram: "C", hex: "E30613")),
        ("cora", ChainStyle(monogram: "C", hex: "E30613")),
        ("match", ChainStyle(monogram: "M", hex: "E30613")),
        ("g20", ChainStyle(monogram: "G", hex: "E30613")),
        ("colruyt", ChainStyle(monogram: "C", hex: "E85D04")),
        ("grand frais", ChainStyle(monogram: "GF", hex: "4E9A2F")),
        ("biocoop", ChainStyle(monogram: "B", hex: "6FA82B")),
        ("bio c bon", ChainStyle(monogram: "B", hex: "7DB443")),
        ("naturalia", ChainStyle(monogram: "N", hex: "5E9E2B")),
        ("la vie claire", ChainStyle(monogram: "V", hex: "4FA33B")),
        ("so bio", ChainStyle(monogram: "S", hex: "5E9E2B")),
        ("picard", ChainStyle(monogram: "P", hex: "0094D8")),
        ("chronodrive", ChainStyle(monogram: "C", hex: "F39200")),
        ("metro", ChainStyle(monogram: "M", hex: "003D7D")),
        ("promocash", ChainStyle(monogram: "P", hex: "E30613")),
        ("action", ChainStyle(monogram: "A", hex: "0071B9")),
        ("costco", ChainStyle(monogram: "C", hex: "E31837")),
    ]

    /// Les préfixes longs d'abord (« le petit casino » avant « casino »).
    private static let byLongestPrefix = known.sorted { $0.prefix.count > $1.prefix.count }

    /// Style d'une enseigne connue (clé de `Chain.key`, ou nom d'enseigne), sinon nil.
    static func forChain(_ key: String?) -> ChainStyle? {
        guard let key = key?.nilIfBlank else { return nil }
        let normalized = Chain.normalize(key)
        return byLongestPrefix.first { normalized == $0.prefix || normalized.hasPrefix($0.prefix + " ") }?.style
    }

    /// Composantes RGB (0…1) de la couleur.
    var rgb: (red: Double, green: Double, blue: Double) {
        let value = UInt32(hex, radix: 16) ?? 0x808080
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}
