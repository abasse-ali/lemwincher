import XCTest
@testable import Lemwincher

/// Rayons des sites gardés en mémoire et relus automatiquement.
final class TrackedPagesTests: XCTestCase {
    private let aldi = Fixtures.store("NODE:7", name: "Aldi Toulouse", brand: "Aldi")
    private let beurre = CapturedPrice(name: "Beurre doux", price: 2.35, brand: "MILSANI®", quantity: "250 g")
    private let oeufs = CapturedPrice(name: "6 œufs bio", price: 2.29, brand: "PICOTA®")

    func testCapturesUpdatePricesWithoutDuplicates() {
        let first = CaptureUpdater.apply([beurre, oeufs], to: [], store: aldi, currency: "EUR",
                                         source: "site Aldi", now: Fixtures.day(0))
        XCTAssertEqual(first.prices.count, 2)
        XCTAssertEqual(first.updates.map(\.kind), [.new, .new])
        XCTAssertTrue(first.prices.allSatisfy { $0.source == "site Aldi" })

        // Le lendemain, mêmes prix : pas de nouveau relevé, juste la date du jour.
        let second = CaptureUpdater.apply([beurre, oeufs], to: first.prices, store: aldi, currency: "EUR",
                                          source: "site Aldi", now: Fixtures.day(1))
        XCTAssertEqual(second.prices.count, 2)
        XCTAssertTrue(second.prices.allSatisfy { $0.date == Fixtures.day(1) })
        XCTAssertEqual(second.updates.map(\.kind), [.unchanged, .unchanged])

        // Le beurre baisse, les œufs passent en promo (même prix), un nouveau produit arrive, un autre est décoché.
        var cheaper = beurre
        cheaper.price = 2.19
        var promo = oeufs
        promo.promo = true
        let lait = CapturedPrice(name: "Lait demi-écrémé", price: 0.99, brand: "MILSANI®", quantity: "1 l")
        var skipped = CapturedPrice(name: "Pas coché", price: 1.00)
        skipped.include = false
        let third = CaptureUpdater.apply([cheaper, promo, lait, skipped], to: second.prices, store: aldi,
                                         currency: "EUR", source: "site Aldi", now: Fixtures.day(2))
        XCTAssertEqual(third.prices.count, 5, "l'historique est gardé : 2 + baisse + promo + nouveau")
        XCTAssertEqual(third.updates.count, 3)
        XCTAssertEqual(third.updates[0].kind, .changed(previous: 2.35))
        XCTAssertTrue(third.updates[0].isDrop)
        XCTAssertEqual(third.updates[1].kind, .changed(previous: 2.29))
        XCTAssertFalse(third.updates[1].isDrop)
        XCTAssertTrue(third.prices.contains { $0.isDiscounted && $0.product.code == oeufs.product.code })
        XCTAssertEqual(third.updates[2].kind, .new)

        // Autre magasin : nouveau relevé, sans toucher à ceux d'Aldi.
        let lidl = Fixtures.store("NODE:8", name: "Lidl Minimes", brand: "Lidl")
        XCTAssertEqual(CaptureUpdater.apply([beurre], to: third.prices, store: lidl, currency: "EUR",
                                            source: "site Lidl").updates.first?.kind, .new)
    }

    func testDropsSummaryForTheNotification() {
        let first = CaptureUpdater.apply([beurre, oeufs], to: [], store: aldi, currency: "EUR",
                                         source: "site Aldi", now: Fixtures.day(0))
        XCTAssertNil(CaptureUpdater.dropsSummary(first.updates, currency: "EUR", storeName: aldi.name))
        var cheaper = beurre
        cheaper.price = 2.19
        var dearer = oeufs
        dearer.price = 2.49
        let next = CaptureUpdater.apply([cheaper, dearer], to: first.prices, store: aldi, currency: "EUR",
                                        source: "site Aldi", now: Fixtures.day(1))
        XCTAssertEqual(CaptureUpdater.dropsSummary(next.updates, currency: "EUR", storeName: aldi.name),
                       "Baisse de prix chez Aldi Toulouse : Beurre doux \(Fmt.price(2.19, "EUR")) (au lieu de \(Fmt.price(2.35, "EUR")))")
        XCTAssertTrue(next.updates[1].isRise)
    }

    func testTrackedPageScheduleAndTitle() throws {
        let page = TrackedPage(url: "https://www.aldi.fr/produits/produits-laitiers/creme-beurre.html",
                               title: "Crèmes et beurres à petits prix - ALDI", siteName: "Aldi",
                               store: aldi, lastChecked: Fixtures.day(0))
        XCTAssertEqual(page.shortTitle, "Crèmes et beurres")
        XCTAssertFalse(page.isDue(now: Fixtures.day(0).addingTimeInterval(3600)), "relu il y a 1 h")
        XCTAssertTrue(page.isDue(now: Fixtures.day(1)), "relu il y a 24 h")
        var paused = page
        paused.autoUpdate = false
        XCTAssertFalse(paused.isDue(now: Fixtures.day(5)), "mise à jour automatique coupée")

        // Sauvegarde et anciennes sauvegardes.
        var state = PersistedState()
        state.trackedPages = [page]
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(restored.trackedPages.first?.url, page.url)
        XCTAssertEqual(restored.trackedPages.first?.store.id, aldi.id)
        let old = try JSONDecoder().decode(PersistedState.self, from: Fixtures.json(#"{"shoppingList": []}"#))
        XCTAssertTrue(old.trackedPages.isEmpty)
    }
}
