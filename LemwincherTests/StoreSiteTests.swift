import XCTest
@testable import Lemwincher

/// Chaque magasin retient sa page sur le site de l'enseigne (son drive, son dernier rayon).
final class StoreSiteTests: XCTestCase {
    func testOnlyUsefulPagesAreRemembered() throws {
        let leclerc = try XCTUnwrap(DriveSite.all.first { $0.id == "leclerc" })
        func keeps(_ text: String) throws -> Bool {
            StoreSitePage.isWorthRemembering(try XCTUnwrap(URL(string: text)), on: leclerc)
        }
        XCTAssertTrue(try keeps("https://m-courses.leclercdrive.fr/magasin-143111-143111/rayon/319790"), "le drive mobile")
        XCTAssertFalse(try keeps("https://www.leclercdrive.fr/"), "l'accueil ne dit rien du magasin")
        XCTAssertFalse(try keeps("https://m-courses.leclercdrive.fr/magasin-143111-143111/panier"))
        XCTAssertFalse(try keeps("https://secure.leclercdrive.fr/connexion?ReturnUrl=x"))
        XCTAssertFalse(try keeps("https://geo.captcha-delivery.com/interstitial/"), "un autre site")
        XCTAssertFalse(try keeps("https://www.carrefour.fr/r/frais"))

        let aldi = try XCTUnwrap(DriveSite.all.first { $0.id == "aldi" })
        XCTAssertFalse(StoreSitePage.isWorthRemembering(try XCTUnwrap(URL(string: "https://www.aldi.fr/produits.html")), on: aldi),
                       "la page des rayons de départ")
        XCTAssertTrue(StoreSitePage.isWorthRemembering(
            try XCTUnwrap(URL(string: "https://www.aldi.fr/produits/surgeles/frites.html")), on: aldi))
    }

    func testDriveNumberInTheAddressPicksTheStore() throws {
        let leclerc = try XCTUnwrap(DriveSite.all.first { $0.id == "leclerc" })
        let saintOrensPage = try XCTUnwrap(URL(string: "https://m-courses.leclercdrive.fr/magasin-123121-123121/rayon/284251"))
        XCTAssertEqual(StoreSitePage.driveKey(of: saintOrensPage), "123121")
        XCTAssertNil(StoreSitePage.driveKey(of: try XCTUnwrap(URL(string: "https://www.aldi.fr/produits/surgeles.html"))))
        XCTAssertFalse(StoreSitePage.isWorthRemembering(
            try XCTUnwrap(URL(string: "https://fd7-courses.leclercdrive.fr/PageDir/pgeWCSD002_Erreur.aspx")), on: leclerc),
                       "une page d'erreur n'est jamais retenue")

        let model = AppModel(arguments: ["-uitest"])
        let blagnac = Fixtures.store("NODE:1", name: "E.Leclerc Blagnac", brand: "E.Leclerc")
        let saintOrens = Fixtures.store("NODE:2", name: "E.Leclerc Saint-Orens", brand: "E.Leclerc")
        model.rememberSitePage(store: blagnac, site: leclerc,
                               url: try XCTUnwrap(URL(string: "https://m-courses.leclercdrive.fr/magasin-143111-143111/")),
                               title: nil)
        model.rememberSitePage(store: saintOrens, site: leclerc, url: saintOrensPage, title: nil)
        XCTAssertEqual(model.store(forDriveOf: saintOrensPage, siteID: "leclerc")?.id, "NODE:2")
        XCTAssertEqual(model.store(forDriveOf: saintOrensPage)?.id, "NODE:2", "sans site : même domaine")

        // Le drive de Saint-Orens parcouru depuis la fiche de Blagnac : retenu pour Saint-Orens, Blagnac ne bouge pas.
        model.rememberSitePage(store: blagnac, site: leclerc,
                               url: try XCTUnwrap(URL(string: "https://m-courses.leclercdrive.fr/magasin-123121-123121/rayon/9")),
                               title: "Laitages")
        XCTAssertEqual(model.sitePage(for: blagnac, siteID: "leclerc")?.driveKey, "143111")
        XCTAssertEqual(model.sitePage(for: saintOrens, siteID: "leclerc")?.displayTitle, "Laitages")
    }

    func testEachStoreHasItsOwnBrowserMemory() {
        let blagnac = Fixtures.store("NODE:1", name: "E.Leclerc Blagnac", brand: "E.Leclerc")
        let saintOrens = Fixtures.store("NODE:2", name: "E.Leclerc Saint-Orens", brand: "E.Leclerc")
        XCTAssertNotEqual(blagnac.siteDataID, saintOrens.siteDataID, "Blagnac et Saint-Orens : deux drives distincts")
        XCTAssertEqual(blagnac.siteDataID, Fixtures.store("NODE:1", name: "Autre nom").siteDataID,
                       "toujours la même mémoire pour un même magasin")
    }

    func testEachStoreKeepsItsSitePage() throws {
        let model = AppModel(arguments: ["-uitest"])
        let leclerc = try XCTUnwrap(DriveSite.all.first { $0.id == "leclerc" })
        let blagnac = Fixtures.store("NODE:1", name: "E.Leclerc Blagnac", brand: "E.Leclerc")
        let rangueil = Fixtures.store("NODE:2", name: "E.Leclerc Rangueil", brand: "E.Leclerc")
        let frites = try XCTUnwrap(URL(string: "https://m-courses.leclercdrive.fr/magasin-143111-143111/rayon/319790"))

        model.rememberSitePage(store: blagnac, site: leclerc, url: frites, title: "Frites et potatoes - Leclerc Drive")
        model.rememberSitePage(store: rangueil, site: leclerc,
                               url: try XCTUnwrap(URL(string: "https://m-courses.leclercdrive.fr/magasin-999-999/")),
                               title: nil)
        XCTAssertEqual(model.sitePage(for: blagnac, siteID: "leclerc")?.displayTitle, "Frites et potatoes")
        XCTAssertNil(model.sitePage(for: blagnac, siteID: "aldi"))

        if let index = model.state.sitePages.firstIndex(where: { $0.store.id == "NODE:1" }) {
            model.state.sitePages[index].updated = .distantPast
        }
        XCTAssertEqual(model.lastSitePage(siteID: "leclerc")?.store.id, "NODE:2", "le dernier drive utilisé")

        model.rememberSitePage(store: blagnac, site: leclerc, url: try XCTUnwrap(URL(string: "https://www.leclercdrive.fr/")),
                               title: nil)
        XCTAssertEqual(model.sitePage(for: blagnac, siteID: "leclerc")?.url, frites.absoluteString,
                       "l'accueil n'efface pas la page retenue")

        model.rememberSitePage(store: blagnac, site: leclerc,
                               url: try XCTUnwrap(URL(string: "https://m-courses.leclercdrive.fr/magasin-143111-143111/rayon/2")),
                               title: "Laitages")
        XCTAssertEqual(model.state.sitePages.filter { $0.store.id == "NODE:1" }.count, 1, "une page par magasin et par site")
        XCTAssertEqual(model.sitePage(for: blagnac, siteID: "leclerc")?.displayTitle, "Laitages")

        // Des prix enregistrés depuis une page rattachent ce site au magasin choisi.
        let aldi = try XCTUnwrap(DriveSite.all.first { $0.id == "aldi" })
        let aldiStore = Fixtures.store("NODE:3", name: "Aldi", brand: "Aldi")
        _ = model.recordCapture([CapturedPrice(name: "Frites", price: 1.5)], site: aldi, store: aldiStore,
                                pageURL: URL(string: "https://www.aldi.fr/produits/surgeles/frites.html"),
                                pageTitle: "Frites", track: false)
        XCTAssertEqual(model.lastSitePage(siteID: "aldi")?.store.id, "NODE:3")
    }
}
