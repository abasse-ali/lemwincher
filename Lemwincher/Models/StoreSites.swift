import Foundation

/// La page du site d'une enseigne retenue pour un magasin : son drive choisi, le dernier rayon consulté.
/// Le site se rouvre directement là depuis ce magasin, et les prix lus sur ce site lui sont rattachés d'office.
struct StoreSitePage: Codable, Equatable, Identifiable {
    var store: Store
    var siteID: String
    var siteName: String
    var url: String
    var title: String?
    var updated: Date

    var id: String { store.id + "|" + siteID }

    /// « Frites et potatoes » plutôt que « Frites et potatoes - Leclerc Drive Blagnac » ; « Recherche « œufs » ».
    var displayTitle: String {
        guard let link = URL(string: url) else { return siteName }
        let title = TrackedPage.displayTitle(pageTitle: title, url: link, siteName: siteName)
        let first = title.components(separatedBy: CharacterSet(charactersIn: "|–—")).first ?? title
        let short = first.replacingOccurrences(of: " - " + siteName, with: "", options: .caseInsensitive).trimmed
        return short.isEmpty ? siteName : short
    }

    /// Seulement les pages du site lui-même, hors connexion, compte, panier, paiement et vérification anti-robot.
    static func isWorthRemembering(_ url: URL, on site: DriveSite) -> Bool {
        guard url.scheme?.lowercased().hasPrefix("http") == true,
              let host = url.host?.lowercased(),
              let siteHost = URL(string: site.home)?.host?.lowercased(),
              sameDomain(host, siteHost) else { return false }
        // L'accueil du site (ou sa page des rayons) ne dit rien du magasin : on garde la page retenue.
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty && (url.query ?? "").isEmpty { return false }
        if let start = site.startURL, start.host?.lowercased() == host,
           start.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == path { return false }
        let text = (url.path + "?" + (url.query ?? "")).lowercased()
        let excluded = ["login", "connexion", "identification", "compte", "account", "panier", "cart", "checkout",
                        "paiement", "payment", "captcha", "commande", "mot-de-passe", "password", "logout",
                        "deconnexion", "inscription", "signin", "signup"]
        return !excluded.contains { text.contains($0) }
    }

    /// « m-courses.leclercdrive.fr » et « www.leclercdrive.fr » : le même site.
    static func sameDomain(_ a: String, _ b: String) -> Bool {
        func base(_ host: String) -> String { host.split(separator: ".").suffix(2).joined(separator: ".") }
        return base(a) == base(b)
    }
}
