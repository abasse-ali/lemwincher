import Foundation

/// Rappel de produit publié sur RappelConso (site officiel du gouvernement).
struct Recall: Identifiable, Hashable {
    let id: String
    /// Code-barres concerné (sans les zéros de tête), quand la fiche en donne un.
    let gtin: String?
    let title: String
    let brand: String?
    let subcategory: String?
    let reason: String?
    let risks: String?
    let advice: [String]
    let imageURL: String?
    let pageURL: String?
    let published: Date?
    let zone: String?
    let distributors: String?
    let compensation: String?
    /// Lots concernés : "Lot 26113 b · date de durabilité minimale 2027-05-31".
    let lots: [String]
    let endDate: Date?

    /// La procédure de rappel est toujours en cours.
    func isActive(at now: Date = Date()) -> Bool {
        guard let endDate else { return true }
        return endDate >= Calendar.current.startOfDay(for: now)
    }

    /// "Cocktail de fruits de mer 500g".
    static func sentenceCase(_ text: String) -> String {
        let trimmed = text.trimmed
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    /// "ocean sea" -> "Ocean Sea".
    static func titleCase(_ text: String) -> String {
        text.trimmed.split(separator: " ").map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }.joined(separator: " ")
    }

    /// Lit le champ "identification_produits" ("gtin$lot$type de date$date$|gtin$…").
    static func lots(from identification: String) -> [String] {
        identification
            .split(separator: "|")
            .compactMap { entry -> String? in
                let parts = entry.split(separator: "$").map { String($0).trimmed }.filter { !$0.isEmpty }
                guard parts.count >= 2 else { return nil }
                var pieces = ["Lot \(parts[1])"]
                if parts.count >= 4 {
                    pieces.append("\(parts[2]) \(Recall.frenchDate(parts[3]))")
                } else if parts.count == 3 {
                    pieces.append(parts[2])
                }
                return pieces.joined(separator: " · ")
            }
    }

    /// "2027-05-31" -> "31/05/2027" (texte inchangé sinon).
    static func frenchDate(_ text: String) -> String {
        let parts = text.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4 else { return text }
        return "\(parts[2])/\(parts[1])/\(parts[0])"
    }

    /// Code-barres sans zéros de tête (le jeu de données les stocke comme des nombres).
    static func normalizedGTIN(_ code: String) -> String {
        let digits = code.filter { $0.isASCII && $0.isNumber }
        let stripped = digits.drop { $0 == "0" }
        return stripped.isEmpty ? digits : String(stripped)
    }
}

// MARK: - Décodage (data.economie.gouv.fr, jeux "rappelconso-v2-gtin-…")

struct RecallResponse: Decodable {
    let recalls: [Recall]

    private enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let records = (try? c.decode([Lossy<RecallRecord>].self, forKey: .results)) ?? []
        recalls = records.compactMap { $0.value?.recall }
    }
}

struct RecallRecord: Decodable {
    let recall: Recall?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parseDate(_ text: String?) -> Date? {
        guard let text = text?.nilIfBlank else { return nil }
        if let date = FuelRecord.isoFormatter.date(from: text) { return date }
        return dayFormatter.date(from: String(text.prefix(10)))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        func text(_ key: String) -> String? { c.lossyString(AnyCodingKey(key))?.nilIfBlank }

        guard let id = text("numero_fiche") ?? c.lossyInt(AnyCodingKey("id")).map(String.init) else {
            recall = nil
            return
        }
        let title = text("libelle") ?? text("modeles_ou_references") ?? "Produit rappelé"

        // "identification_produits" : tableau (jeu "espaces") ou texte séparé par des "$" (jeu "trie").
        var identification = ""
        if let list = try? c.decodeIfPresent([String].self, forKey: AnyCodingKey("identification_produits")) {
            identification = list.joined(separator: "$")
        } else if let raw = text("identification_produits") {
            identification = raw
        }
        var gtin: String? = nil
        if let number = c.lossyInt(AnyCodingKey("gtin")) {
            gtin = String(number)
        } else if let first = identification.split(separator: "$").first {
            let candidate = String(first).replacingOccurrences(of: "|", with: "").trimmed
            if candidate.isBarcodeLike { gtin = Recall.normalizedGTIN(candidate) }
        }

        let advice = (text("conduites_a_tenir_par_le_consommateur") ?? "")
            .split(separator: "|")
            .map { Recall.sentenceCase(String($0)) }
            .filter { !$0.isEmpty }
        let image = text("liens_vers_les_images")?
            .split(whereSeparator: { $0 == " " || $0 == "|" })
            .first
            .map(String.init)

        recall = Recall(id: id,
                        gtin: gtin,
                        title: Recall.sentenceCase(title),
                        brand: text("marque_produit").map(Recall.titleCase),
                        subcategory: text("sous_categorie_produit").map(Recall.sentenceCase),
                        reason: text("motif_rappel").map(Recall.sentenceCase),
                        risks: text("risques_encourus").map(Recall.sentenceCase),
                        advice: advice,
                        imageURL: image,
                        pageURL: text("lien_vers_la_fiche_rappel"),
                        published: RecallRecord.parseDate(text("date_publication")),
                        zone: text("zone_geographique_de_vente"),
                        distributors: text("distributeurs").map(Recall.sentenceCase),
                        compensation: text("modalites_de_compensation").map(Recall.sentenceCase),
                        lots: Recall.lots(from: identification),
                        endDate: RecallRecord.parseDate(text("date_de_fin_de_la_procedure_de_rappel")))
    }
}
