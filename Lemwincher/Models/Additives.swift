import Foundation

/// Additifs alimentaires (codes E) : nom en clair et origine possiblement animale.
enum Additives {
    /// "en:e322i" -> "E322i".
    static func code(fromTag tag: String) -> String? {
        let raw = tag.split(separator: ":").last.map(String.init) ?? tag
        guard let first = raw.first, first == "e" || first == "E", raw.count >= 4,
              raw.dropFirst().first?.isNumber == true else { return nil }
        return "E" + raw.dropFirst()
    }

    /// Code de base, sans sous-catégorie : "E322i" -> "E322", "E472e" -> "E472".
    static func baseCode(_ code: String) -> String {
        "E" + code.dropFirst().prefix { $0.isNumber }
    }

    /// Additifs qui peuvent être fabriqués à partir de graisses ou de tissus animaux (porc possible),
    /// sauf mention « végétal » sur l'emballage.
    static let possiblyAnimal: Set<String> = [
        "E120", "E441", "E470", "E471", "E472", "E473", "E474", "E475", "E476", "E477", "E478", "E479",
        "E481", "E482", "E483", "E491", "E492", "E493", "E494", "E495", "E542", "E570", "E572", "E631",
        "E635", "E904", "E913", "E920", "E921", "E966", "E1105",
    ]

    static func isPossiblyAnimal(_ code: String) -> Bool {
        possiblyAnimal.contains(baseCode(code))
    }

    /// Noms des additifs les plus courants.
    static let names: [String: String] = [
        "E100": "curcumine", "E101": "riboflavine", "E120": "carmin (cochenille)", "E129": "rouge allura",
        "E133": "bleu brillant", "E140": "chlorophylles", "E141": "complexes cuivre-chlorophylles",
        "E150a": "caramel ordinaire", "E150c": "caramel ammoniacal", "E150d": "caramel au sulfite d'ammonium",
        "E160a": "caroténoïdes", "E160b": "rocou", "E160c": "extrait de paprika", "E162": "rouge de betterave",
        "E170": "carbonate de calcium", "E171": "dioxyde de titane",
        "E200": "acide sorbique", "E202": "sorbate de potassium", "E211": "benzoate de sodium",
        "E220": "dioxyde de soufre", "E223": "disulfite de sodium", "E224": "disulfite de potassium",
        "E250": "nitrite de sodium", "E251": "nitrate de sodium", "E252": "nitrate de potassium",
        "E260": "acide acétique", "E262": "acétates de sodium", "E270": "acide lactique",
        "E282": "propionate de calcium", "E290": "dioxyde de carbone", "E296": "acide malique",
        "E300": "acide ascorbique (vitamine C)", "E301": "ascorbate de sodium", "E306": "tocophérols (vitamine E)",
        "E316": "érythorbate de sodium", "E322": "lécithines", "E325": "lactate de sodium",
        "E330": "acide citrique", "E331": "citrates de sodium", "E333": "citrates de calcium",
        "E334": "acide tartrique", "E338": "acide phosphorique", "E339": "phosphates de sodium",
        "E340": "phosphates de potassium", "E341": "phosphates de calcium", "E392": "extraits de romarin",
        "E401": "alginate de sodium", "E406": "agar-agar", "E407": "carraghénanes", "E410": "farine de caroube",
        "E412": "gomme guar", "E414": "gomme arabique", "E415": "gomme xanthane", "E418": "gomme gellane",
        "E420": "sorbitol", "E422": "glycérol", "E440": "pectines", "E441": "gélatine",
        "E450": "diphosphates", "E451": "triphosphates", "E452": "polyphosphates", "E460": "cellulose",
        "E461": "méthylcellulose", "E464": "hydroxypropylméthylcellulose", "E466": "carboxyméthylcellulose",
        "E471": "mono- et diglycérides d'acides gras", "E472": "esters de mono- et diglycérides",
        "E475": "esters polyglycériques d'acides gras", "E476": "polyricinoléate de polyglycérol",
        "E481": "stéaroyl-2-lactylate de sodium", "E491": "monostéarate de sorbitane", "E500": "carbonates de sodium",
        "E501": "carbonates de potassium", "E503": "carbonates d'ammonium", "E508": "chlorure de potassium",
        "E509": "chlorure de calcium", "E516": "sulfate de calcium", "E524": "hydroxyde de sodium",
        "E551": "dioxyde de silicium", "E570": "acides gras", "E575": "glucono-delta-lactone",
        "E621": "glutamate monosodique", "E627": "guanylate disodique", "E631": "inosinate disodique",
        "E635": "ribonucléotides disodiques", "E900": "diméthylpolysiloxane", "E901": "cire d'abeille",
        "E903": "cire de carnauba", "E904": "shellac", "E920": "L-cystéine", "E950": "acésulfame K",
        "E951": "aspartame", "E952": "cyclamate", "E954": "saccharine", "E955": "sucralose",
        "E960": "glycosides de stéviol", "E965": "maltitol", "E966": "lactitol", "E1105": "lysozyme",
        "E1400": "dextrine", "E1404": "amidon oxydé", "E1412": "phosphate de diamidon",
        "E1414": "phosphate de diamidon acétylé", "E1420": "amidon acétylé", "E1422": "adipate de diamidon acétylé",
        "E1442": "phosphate de diamidon hydroxypropylé", "E1450": "octényle succinate d'amidon sodique",
        "E1520": "propylène glycol",
    ]

    /// « E471 (mono- et diglycérides d'acides gras) ».
    static func label(_ code: String) -> String {
        if let name = names[code] ?? names[baseCode(code)] {
            return "\(code) (\(name))"
        }
        return code
    }
}
