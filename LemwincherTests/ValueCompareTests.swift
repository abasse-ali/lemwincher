import XCTest
@testable import Lemwincher

/// « Comparer » : nombre de pièces, poids, classement au kilo ou à la pièce, tri des produits proposés.
final class ValueCompareTests: XCTestCase {
    func testPieceCounts() {
        XCTAssertEqual(PackSize.pieceCount(in: "10 Steak haché surgelé"), 10)
        XCTAssertEqual(PackSize.pieceCount(in: "2 steaks hachés"), 2)
        XCTAssertEqual(PackSize.pieceCount(in: "12 œufs de poules élevées au sol"), 12)
        XCTAssertEqual(PackSize.pieceCount(in: "Oeufs frais x6"), 6)
        XCTAssertEqual(PackSize.pieceCount(in: "Yaourt nature 4x125g"), 4)
        XCTAssertEqual(PackSize.pieceCount(in: "Lot de 3 pizzas"), 3)
        XCTAssertEqual(PackSize.pieceCount(in: "Steak haché 15% MG 10 pièces"), 10)
        XCTAssertNil(PackSize.pieceCount(in: "500 g de farine"), "un poids n'est pas un nombre de pièces")
        XCTAssertNil(PackSize.pieceCount(in: "100 % pur jus d'orange"))
        XCTAssertNil(PackSize.pieceCount(in: "Steak haché 5% MG"))
        XCTAssertNil(PackSize.pieceCount(in: "Coca-Cola 1,5 L"))
        XCTAssertNil(PackSize.pieceCount(in: nil))
    }

    func testPackSizeReadsWeightAndCount() {
        let pack = PackSize.parse(name: "10 steaks hachés surgelés", quantity: "10 x 100 g")
        XCTAssertEqual(pack.count, 10)
        XCTAssertEqual(pack.amount?.value ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(pack.amount?.unit, "kg")
        XCTAssertEqual(pack.text, "10 pièces · 1 kg")
        XCTAssertEqual(PackSize.parse(name: "Beurre doux", quantity: "250 g").text, "250 g")
        XCTAssertEqual(PackSize.parse(name: "Lait demi-écrémé 6 x 1 L", quantity: nil).text, "6 pièces · 6 L")
        XCTAssertEqual(PackSize.parse(name: "Eau minérale", quantity: "33 cl").text, "33 cl")
        XCTAssertNil(PackSize.parse(name: "Kit boba", quantity: nil).text)
    }

    /// L'exemple : 10 steaks à 7,99 € contre 2 steaks à 3,99 €.
    func testStepsExampleRanksPerPiece() throws {
        let ten = ValueItem(id: "a", product: .custom(named: "10 Steak haché surgelé"), price: 7.99, currency: "EUR")
        let two = ValueItem(id: "b", product: .custom(named: "2 steaks hachés"), price: 3.99, currency: "EUR")
        XCTAssertEqual(ValueCompare.defaultBasis([two, ten]), .piece, "poids inconnu : à la pièce")
        let ranking = ValueCompare.rank([two, ten], basis: .piece)
        XCTAssertEqual(ranking.ranked.map(\.id), ["a", "b"])
        XCTAssertEqual(try XCTUnwrap(ten.unitPrice(.piece)), 0.799, accuracy: 1e-9)
        XCTAssertEqual(ranking.extraPercent(two), 150, "2,00 € contre 0,80 € la pièce")
        let summary = try XCTUnwrap(ValueCompare.summary(ranking))
        XCTAssertTrue(summary.contains("60 % moins cher à la pièce"), summary)
        XCTAssertTrue(summary.hasPrefix("« 10 Steak haché surgelé »"), summary)
    }

    func testWeightComesFirstWhenKnown() {
        // Des steaks de 100 g et de 125 g : au kilo, c'est le paquet de 2 le plus avantageux.
        let ten = ValueItem(id: "a", product: .custom(named: "10 steaks hachés"), price: 7.99, currency: "EUR",
                            pack: PackSize.parse(name: "10 steaks hachés", quantity: "10 x 100 g"))
        let two = ValueItem(id: "b", product: .custom(named: "2 steaks hachés"), price: 1.80, currency: "EUR",
                            pack: PackSize.parse(name: "2 steaks hachés", quantity: "2 x 125 g"))
        let unknown = ValueItem(id: "c", product: .custom(named: "Steak haché"), price: 2.50, currency: "EUR")
        let items = [ten, two, unknown]
        XCTAssertEqual(ValueCompare.defaultBasis(items), .kilo, "au kilo quand le poids est connu")
        XCTAssertEqual(ValueCompare.availableBases(items), [.kilo, .piece])
        let ranking = ValueCompare.rank(items, basis: .kilo)
        XCTAssertEqual(ranking.ranked.map(\.id), ["b", "a"], "7,20 €/kg contre 7,99 €/kg")
        XCTAssertEqual(ranking.others.map(\.id), ["c"])
        XCTAssertEqual(ValueCompare.rank(items, basis: .piece).ranked.map(\.id), ["a", "b"], "mais à la pièce, le paquet de 10")
        XCTAssertEqual(ValueCompare.unitPriceText(7.2, basis: .kilo, currency: "EUR"), Fmt.price(7.2, "EUR") + "/kg")
        XCTAssertNil(ValueCompare.defaultBasis([unknown]))
    }

    func testSuggestionsSortedByValue() {
        func suggestion(_ code: String, _ name: String, _ quantity: String?, _ price: Double?) -> ProductSuggestion {
            var product = Product(code: code, name: name)
            product.quantity = quantity
            let offer = price.map { PriceOffer(price: $0, currency: "EUR", storeName: "Aldi", distance: 500,
                                               date: Date(), isLocal: true) }
            return ProductSuggestion(product: product, offer: offer, nutriScore: nil)
        }
        let list = [
            suggestion("1", "Oeufs plein air x6", nil, 1.89),
            suggestion("2", "30 oeufs de poules", nil, 6.99),
            suggestion("3", "12 oeufs bio", nil, 3.99),
            suggestion("4", "Oeufs extra-frais", nil, 2.10),
            suggestion("5", "Oeufs de caille", nil, nil),
        ]
        XCTAssertEqual(SuggestionEngine.valueBasis(list), .piece)
        // 0,233 € (30) < 0,315 € (6) < 0,333 € (12) ; puis prix sans nombre ; puis sans prix.
        XCTAssertEqual(SuggestionEngine.sortedByValue(list).map(\.id), ["2", "1", "3", "4", "5"])
    }

    func testGenericQueryForSimilarProducts() {
        XCTAssertEqual(ValueCompare.genericQuery(for: "10 Steak haché surgelé 15 % MG"), "Steak haché")
        XCTAssertEqual(ValueCompare.genericQuery(for: "6 œufs bio"), "œufs")
        XCTAssertEqual(ValueCompare.genericQuery(for: "Lait demi-écrémé 1 L"), "Lait demi-écrémé")
    }

    func testManualEntriesAreSavedAndCompared() throws {
        let entry = ManualCompareEntry(name: "2 steaks hachés", quantity: nil, price: 3.99, currency: "EUR",
                                       storeName: "Lidl")
        XCTAssertTrue(entry.item.isManual)
        XCTAssertEqual(entry.item.pack.count, 2)
        XCTAssertTrue(entry.item.place?.hasPrefix("Lidl") == true)

        var state = PersistedState()
        state.compareEntries = [entry]
        state.settings.suggestionSort = .value
        let restored = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.compareEntries, [entry])
        XCTAssertEqual(restored.settings.suggestionSort, .value)
        let old = try JSONDecoder().decode(PersistedState.self, from: Fixtures.json(#"{"shoppingList": []}"#))
        XCTAssertTrue(old.compareEntries.isEmpty)
        XCTAssertEqual(old.settings.suggestionSort, .price)
    }

    func testAmountText() {
        XCTAssertEqual(UnitAmount(quantity: 1500, unit: "g")?.text, "1,5 kg")
        XCTAssertEqual(UnitAmount(quantity: 250, unit: "g")?.text, "250 g")
        XCTAssertEqual(UnitAmount(quantity: 75, unit: "cl")?.text, "75 cl")
        XCTAssertEqual(UnitAmount(quantity: 2, unit: "l")?.text, "2 L")
    }
}

/// Journal de l'app (Réglages › Journal).
final class AppLogTests: XCTestCase {
    func testRepeatedEventsAreGroupedAndListIsCapped() {
        let log = AppLog(fileURL: nil)
        let start = Fixtures.day(0)
        log.add(.error, .network, "prices.openfoodfacts.org : erreur 502", date: start)
        log.add(.error, .network, "prices.openfoodfacts.org : erreur 502", date: start.addingTimeInterval(20))
        log.add(.error, .network, "prices.openfoodfacts.org : erreur 502", date: start.addingTimeInterval(40))
        XCTAssertEqual(log.entries.count, 1, "même erreur dans la minute : ×3")
        XCTAssertEqual(log.entries.first?.count, 3)
        log.add(.success, .stores, "95 magasins", date: start.addingTimeInterval(50))
        log.add(.error, .network, "prices.openfoodfacts.org : erreur 502", date: start.addingTimeInterval(55))
        XCTAssertEqual(log.entries.count, 3, "répétée après un autre événement : nouvelle ligne")
        XCTAssertEqual(log.entries.first?.message, "prices.openfoodfacts.org : erreur 502", "le plus récent en premier")

        for index in 0..<(AppLog.maxEntries + 20) {
            log.add(.info, .app, "événement \(index)", date: start.addingTimeInterval(Double(100 + index * 120)))
        }
        XCTAssertEqual(log.entries.count, AppLog.maxEntries)
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testProblemsAndExportText() {
        let log = AppLog(fileURL: nil)
        let now = Date()
        log.add(.warning, .sites, "Site Leclerc Drive : aucun prix lisible sur la page",
                details: "leclercdrive.fr/recherche\nRéponse du script : []", date: now.addingTimeInterval(-60))
        log.add(.error, .network, "overpass-api.de : erreur 504", date: now.addingTimeInterval(-30 * 3600))
        log.add(.success, .sites, "Site Aldi : 26 prix enregistrés pour Aldi Toulouse", date: now)
        XCTAssertEqual(log.recentProblems(now: now), 1, "seulement les dernières 24 h")

        let text = log.exportText(appVersion: "1.5.0 (60)", system: "18.1", device: "iPhone15,4", now: now)
        XCTAssertTrue(text.hasPrefix("Journal Lemwincher 1.5.0 (60) · iOS 18.1 · iPhone15,4"), text)
        XCTAssertTrue(text.contains("3 événements (1 erreur, 1 alerte)"), text)
        XCTAssertTrue(text.contains("✓ [Sites des enseignes] Site Aldi : 26 prix enregistrés pour Aldi Toulouse"), text)
        XCTAssertTrue(text.contains("      leclercdrive.fr/recherche"), "détails indentés")
        let lines = text.components(separatedBy: "\n")
        let aldi = lines.firstIndex { $0.contains("Site Aldi") } ?? -1
        let leclerc = lines.firstIndex { $0.contains("Leclerc Drive") } ?? -1
        XCTAssertLessThan(aldi, leclerc, "du plus récent au plus ancien")
    }

    func testJournalIsSavedOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = [LogEntry(date: Fixtures.day(0), level: .success, category: .tracked, message: "Rayon mis à jour")]
        try JSONEncoder().encode(entries).write(to: url)
        let log = AppLog(fileURL: url)
        XCTAssertEqual(log.entries.map(\.message), ["Rayon mis à jour"])
    }

    func testURLsAreLoggedWithoutParameters() {
        let url = URL(string: "https://prices.openfoodfacts.org/api/v1/prices?location_osm_lat=43.6&product_code=123")
        XCTAssertEqual(Log.describe(url), "prices.openfoodfacts.org/api/v1/prices")
        XCTAssertEqual(Log.describe(nil), "adresse inconnue")
    }

    func testCaptureChangesText() {
        let aldi = Fixtures.store("NODE:7", name: "Aldi Toulouse", brand: "Aldi")
        let beurre = CapturedPrice(name: "Beurre doux", price: 2.35, brand: "MILSANI®", quantity: "250 g")
        let first = CaptureUpdater.apply([beurre], to: [], store: aldi, currency: "EUR", source: "site Aldi")
        XCTAssertEqual(CaptureUpdater.changesText(first.updates), "1 nouveau")
        var cheaper = beurre
        cheaper.price = 2.19
        let next = CaptureUpdater.apply([cheaper], to: first.prices, store: aldi, currency: "EUR", source: "site Aldi")
        XCTAssertEqual(CaptureUpdater.changesText(next.updates), "1 baisse")
        XCTAssertEqual(CaptureUpdater.changesText([]), "aucun prix")
    }
}
