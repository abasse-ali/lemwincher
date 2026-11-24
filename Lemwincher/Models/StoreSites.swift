import Foundation
import CryptoKit
import WebKit

extension Store {
    /// Identifiant de la mémoire du navigateur propre à ce magasin (toujours le même pour un magasin).
    var siteDataID: UUID {
        let b = Array(SHA256.hash(data: Data(("lemwincher-site:" + id).utf8)))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], (b[6] & 0x0F) | 0x50, b[7],
                           (b[8] & 0x3F) | 0x80, b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

/// Mémoire du navigateur (cookies, magasin choisi sur le site, connexion) : une par magasin.
/// Les drives retiennent le magasin choisi dans leurs cookies : avec une mémoire commune, choisir
/// Leclerc Saint-Orens remplaçait Leclerc Blagnac. Chaque magasin garde désormais le sien.
enum SiteData {
    static func store(for store: Store?) -> WKWebsiteDataStore {
        guard let store else { return .default() }
        return WKWebsiteDataStore(forIdentifier: store.siteDataID)
    }

    /// Oublie ce que les sites retiennent pour ce magasin (drive choisi, connexion).
    static func forget(_ store: Store) {
        WKWebsiteDataStore.remove(forIdentifier: store.siteDataID) { _ in }
        UserDefaults.standard.removeObject(forKey: seededKey(store))
    }

    private static func seededKey(_ store: Store) -> String { "siteDataSeeded." + store.siteDataID.uuidString }

    /// Première utilisation de la mémoire d'un magasin : si elle est vide, elle reprend les cookies de l'ancienne
    /// mémoire commune (drive déjà choisi, connexion), pour que ses rayons suivis continuent d'être lus.
    @MainActor
    static func prepare(_ store: Store?) async {
        guard let store, !UserDefaults.standard.bool(forKey: seededKey(store)) else { return }
        UserDefaults.standard.set(true, forKey: seededKey(store))
        let target = WKWebsiteDataStore(forIdentifier: store.siteDataID).httpCookieStore
        guard await target.allCookies().isEmpty else { return }
        for cookie in await WKWebsiteDataStore.default().httpCookieStore.allCookies() {
            await target.setCookie(cookie)
        }
    }
}

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
                        "deconnexion", "inscription", "signin", "signup", "erreur", "error", "404", "maintenance",
                        "introuvable", "notfound"]
        return !excluded.contains { text.contains($0) }
    }

    private static let drivePattern = try! NSRegularExpression(pattern: #"/magasin-(\d+)"#, options: [.caseInsensitive])

    /// Numéro du drive écrit dans l'adresse (Leclerc Drive : « …/magasin-143111-143111/rayon/… » -> « 143111 ») :
    /// la page dit elle-même de quel magasin elle montre les prix.
    static func driveKey(of url: URL) -> String? {
        let path = url.path
        let ns = path as NSString
        guard let match = drivePattern.firstMatch(in: path, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    var driveKey: String? { URL(string: url).flatMap(Self.driveKey(of:)) }

    /// « m-courses.leclercdrive.fr » et « www.leclercdrive.fr » : le même site.
    static func sameDomain(_ a: String, _ b: String) -> Bool {
        func base(_ host: String) -> String { host.split(separator: ".").suffix(2).joined(separator: ".") }
        return base(a) == base(b)
    }
}
