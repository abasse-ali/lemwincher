import XCTest
import CoreLocation
@testable import Lemwincher

final class WatchEvaluatorTests: XCTestCase {
    private let now = Fixtures.day(200)

    func testFirstCheckSetsBaselineWithoutAlert() {
        let item = WatchItem(product: Fixtures.nutella)
        let outcome = WatchEvaluator.evaluate(item, observations: [Fixtures.obs(3.49, date: now)], now: now)
        XCTAssertNil(outcome.alert)
        XCTAssertEqual(outcome.item.bestPrice, 3.49)
        XCTAssertEqual(outcome.item.lastChecked, now)
        XCTAssertFalse(outcome.item.hasNewDrop)
    }

    func testPriceDropTriggersAlert() {
        let item = WatchItem(product: Fixtures.nutella, bestPrice: 3.49)
        let observations = [
            Fixtures.obs(3.59, store: "NODE:1", date: now),
            Fixtures.obs(3.19, store: "NODE:2", date: now),
        ]
        let outcome = WatchEvaluator.evaluate(item, observations: observations, now: now)
        XCTAssertNotNil(outcome.alert)
        XCTAssertEqual(outcome.item.bestPrice, 3.19)
        XCTAssertEqual(outcome.item.previousBestPrice, 3.49)
        XCTAssertEqual(outcome.item.bestStoreName, "Magasin NODE:2")
        XCTAssertTrue(outcome.item.hasNewDrop)
    }

    func testIncreaseAndOldPricesDoNotAlert() {
        let item = WatchItem(product: Fixtures.nutella, bestPrice: 3.00)
        let outcome = WatchEvaluator.evaluate(item, observations: [
            Fixtures.obs(3.30, date: now),
            Fixtures.obs(2.00, store: "NODE:9", date: now.addingTimeInterval(-90 * 86_400)), // trop ancien
        ], now: now)
        XCTAssertNil(outcome.alert)
        XCTAssertEqual(outcome.item.bestPrice, 3.30)

        let empty = WatchEvaluator.evaluate(item, observations: [], now: now)
        XCTAssertNil(empty.alert)
        XCTAssertEqual(empty.item.bestPrice, 3.00)
    }

    func testTargetPriceReached() {
        let item = WatchItem(product: Fixtures.nutella, targetPrice: 3.20)
        let outcome = WatchEvaluator.evaluate(item, observations: [Fixtures.obs(3.15, date: now)], now: now)
        XCTAssertNotNil(outcome.alert)
        XCTAssertTrue(outcome.item.hasNewDrop)

        // Déjà sous la cible à la vérification précédente : pas de nouvelle alerte.
        let again = WatchEvaluator.evaluate(outcome.item, observations: [Fixtures.obs(3.15, date: now)], now: now)
        XCTAssertNil(again.alert)
    }
}

final class PersistenceTests: XCTestCase {
    func testOldSaveFilesStillLoad() throws {
        // Fichier d'une version précédente : pas de produits suivis, réglages incomplets, un relevé mal formé.
        let json = """
        {"settings": {"radiusKm": 5, "useHome": true, "home": {"lat": 43.6, "lon": 1.44}},
         "shoppingList": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "product": {"code": "custom:pain", "name": "Pain"},
                           "quantity": 2, "checked": false}],
         "recentProducts": "pas une liste"}
        """
        let state = try JSONDecoder().decode(PersistedState.self, from: Fixtures.json(json))
        XCTAssertEqual(state.settings.radiusKm, 5)
        XCTAssertTrue(state.settings.useHome)
        XCTAssertEqual(state.settings.fuelType, .gazole)
        XCTAssertFalse(state.settings.hasSeenOnboarding)
        XCTAssertFalse(state.settings.openNowOnly)
        XCTAssertEqual(state.shoppingList.first?.product.name, "Pain")
        XCTAssertEqual(state.shoppingList.first?.quantity, 2)
        XCTAssertTrue(state.recentProducts.isEmpty)
        XCTAssertTrue(state.watchlist.isEmpty)
        XCTAssertTrue(state.myPrices.isEmpty)
    }

    func testStateRoundTrip() throws {
        var state = PersistedState()
        state.settings.fuelType = .e10
        state.settings.favoriteStores = [Fixtures.store("NODE:1", name: "Lidl", brand: "Lidl")]
        state.watchlist = [WatchItem(product: Fixtures.nutella, targetPrice: 3, createdAt: Fixtures.day(1))]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testMinimalWatchItem() throws {
        let json = #"{"product": {"code": "3017620422003", "name": "Nutella"}}"#
        let item = try JSONDecoder().decode(WatchItem.self, from: Fixtures.json(json))
        XCTAssertEqual(item.id, "3017620422003")
        XCTAssertNil(item.bestPrice)
        XCTAssertFalse(item.hasNewDrop)
    }

    func testStoreWithoutNewFieldsDecodes() throws {
        let json = #"{"id": "NODE:1", "name": "Lidl", "lat": 43.6, "lon": 1.44}"#
        let store = try JSONDecoder().decode(Store.self, from: Fixtures.json(json))
        XCTAssertNil(store.openingHours)
        XCTAssertNil(store.phone)
        XCTAssertNil(store.hours)
    }
}

final class BackupTests: XCTestCase {
    private func sampleState() -> PersistedState {
        var state = PersistedState()
        let store = Fixtures.store("NODE:7", name: "Carrefour; Minimes", brand: "Carrefour")
        state.myPrices = [
            MyPrice(product: Fixtures.nutella, store: store, price: 3.29, currency: "EUR", date: Fixtures.day(3)),
            MyPrice(product: .custom(named: "Pain \"tradition\""), store: store, price: 1.2, currency: "EUR",
                    date: Fixtures.day(4), isDiscounted: true),
        ]
        state.shoppingList = [ShoppingItem(product: Fixtures.nutella)]
        state.settings.favoriteStores = [store]
        state.watchlist = [WatchItem(product: Fixtures.nutella, createdAt: Fixtures.day(2))]
        state.settings.home = GeoPoint(lat: 43.6, lon: 1.44)
        return state
    }

    func testExportThenRestore() throws {
        let state = sampleState()
        let data = try Backup.export(state, now: Fixtures.day(5))
        let restored = try Backup.decode(data)
        XCTAssertEqual(restored, state)
    }

    func testRawDataFileCanBeRestored() throws {
        let state = sampleState()
        let raw = try JSONEncoder().encode(state)
        XCTAssertEqual(try Backup.decode(raw), state)
    }

    func testMergeAddsOnlyNewData() throws {
        let incoming = sampleState()
        var current = PersistedState()
        current.shoppingList = [ShoppingItem(product: Fixtures.nutella, quantity: 3)]

        let summary = Backup.merge(incoming, into: &current)
        XCTAssertEqual(summary, Backup.Summary(prices: 2, listItems: 0, favorites: 1, watched: 1))
        XCTAssertEqual(current.shoppingList.first?.quantity, 3, "la liste existante est conservée")
        XCTAssertEqual(current.settings.home, incoming.settings.home)

        let again = Backup.merge(incoming, into: &current)
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(current.myPrices.count, 2)
        XCTAssertTrue(again.text.hasPrefix("Rien de nouveau"))
        XCTAssertTrue(summary.text.contains("2 relevés"))
    }

    func testCSVExport() {
        let csv = Backup.csv(sampleState().myPrices)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("date;magasin;enseigne"))
        XCTAssertTrue(lines[1].contains(";3,29;EUR;non;non"))
        XCTAssertTrue(lines[1].contains("\"Carrefour; Minimes\""), "les champs avec ; sont entre guillemets")
        XCTAssertTrue(lines[2].contains("\"Pain \"\"tradition\"\"\""))
        XCTAssertTrue(lines[2].contains(";oui;non"))
    }
}

final class StoreSourcesTests: XCTestCase {
    func testOverpassElementBecomesStore() throws {
        let json = """
        {"elements": [
          {"type": "node", "id": 101, "lat": 43.6, "lon": 1.44,
           "tags": {"shop": "supermarket", "name": "Lidl Minimes", "brand": "Lidl", "opening_hours": "Mo-Sa 08:30-20:00",
                    "contact:phone": "+33 5 61 00 00 00", "addr:housenumber": "12", "addr:street": "Rue Bayard", "addr:city": "Toulouse"}},
          {"type": "way", "id": 202, "center": {"lat": 43.61, "lon": 1.45}, "tags": {"shop": "convenience"}},
          {"type": "node", "id": 303}
        ]}
        """
        let response = try JSONDecoder().decode(OverpassResponse.self, from: Fixtures.json(json))
        let stores = response.elements.compactMap(\.asStore)
        XCTAssertEqual(stores.count, 2)
        XCTAssertEqual(stores[0].id, "NODE:101")
        XCTAssertEqual(stores[0].address, "12 Rue Bayard, Toulouse")
        XCTAssertEqual(stores[0].openingHours, "Mo-Sa 08:30-20:00")
        XCTAssertEqual(stores[0].phone, "+33 5 61 00 00 00")
        XCTAssertNotNil(stores[0].hours)
        XCTAssertEqual(stores[1].id, "WAY:202")
        XCTAssertEqual(stores[1].name, "Supérette")
    }

    /// Réponse réelle de Photon (OpenStreetMap) autour de l'Aldi de La Faourette, à Toulouse.
    func testPhotonFeaturesBecomeStoresWithOpenStreetMapIDs() throws {
        let json = """
        {"type": "FeatureCollection", "features": [
          {"type": "Feature", "geometry": {"type": "Point", "coordinates": [1.4136288, 43.5810432]},
           "properties": {"osm_type": "N", "osm_id": 11247032479, "osm_key": "shop", "osm_value": "supermarket",
                          "name": "Aldi", "street": "Place Geneviève Anthonioz De Gaulle", "city": "Toulouse"}},
          {"type": "Feature", "geometry": {"type": "Point", "coordinates": [1.4161, 43.5862]},
           "properties": {"osm_type": "W", "osm_id": 52305070, "osm_value": "supermarket", "name": "Intermarché Super",
                          "housenumber": "389", "street": "Route de Saint-Simon", "city": "Toulouse"}},
          {"type": "Feature", "geometry": {"type": "Point", "coordinates": [1.42, 43.58]},
           "properties": {"osm_type": "R", "osm_id": 777, "osm_value": "convenience"}},
          {"type": "Feature", "geometry": {"type": "Point", "coordinates": [1.42, 43.58]},
           "properties": {"osm_type": "X", "osm_id": 1, "osm_value": "supermarket", "name": "Inconnu"}},
          {"type": "Feature", "properties": {"osm_type": "N", "osm_id": 2, "name": "Sans position"}},
          "pas un objet"
        ]}
        """
        let response = try JSONDecoder().decode(PhotonResponse.self, from: Fixtures.json(json))
        let stores = response.features.compactMap(\.asStore)
        XCTAssertEqual(stores.map(\.id), ["NODE:11247032479", "WAY:52305070", "RELATION:777"],
                       "mêmes identifiants qu'Overpass et Open Prices ; type inconnu ou sans position écarté")

        let aldi = stores[0]
        XCTAssertEqual(aldi.name, "Aldi")
        XCTAssertEqual(aldi.lat, 43.5810432, accuracy: 1e-9)
        XCTAssertEqual(aldi.lon, 1.4136288, accuracy: 1e-9)
        XCTAssertTrue(aldi.isSupermarket)
        XCTAssertEqual(aldi.chainKey, "aldi")
        XCTAssertEqual(aldi.address, "Place Geneviève Anthonioz De Gaulle, Toulouse")
        XCTAssertEqual(aldi.osmId, 11_247_032_479)

        XCTAssertEqual(stores[1].address, "389 Route de Saint-Simon, Toulouse")
        XCTAssertEqual(stores[1].chainKey, "intermarche")
        XCTAssertEqual(stores[2].name, "Supérette", "sans nom : le type de commerce")
        XCTAssertFalse(stores[2].isSupermarket)
    }

    func testOverpassRelationsAreStoresToo() throws {
        let json = #"{"elements": [{"type": "relation", "id": 9, "center": {"lat": 43.6, "lon": 1.44}, "tags": {"shop": "supermarket", "name": "Auchan"}}]}"#
        let response = try JSONDecoder().decode(OverpassResponse.self, from: Fixtures.json(json))
        XCTAssertEqual(response.elements.compactMap(\.asStore).first?.id, "RELATION:9")
    }

    func testAppleMapsResultsOnlyCountKnownChainsAsSupermarkets() {
        let coordinate = CLLocationCoordinate2D(latitude: 43.6, longitude: 1.44)
        let carrefour = StoreFinder.appleStore(name: "Carrefour City Capitole", address: nil, coordinate: coordinate)
        XCTAssertTrue(carrefour.isSupermarket)
        XCTAssertEqual(carrefour.brand, "Carrefour City")
        XCTAssertEqual(carrefour.chainKey, "carrefour city")

        let teaShop = StoreFinder.appleStore(name: "Palais des Thés", address: nil, coordinate: coordinate)
        XCTAssertFalse(teaShop.isSupermarket, "un salon de thé n'est pas un supermarché")
        XCTAssertNil(teaShop.brand)
        XCTAssertTrue(teaShop.id.hasPrefix("apple:"))
    }

    func testStoreCacheValidity() {
        let here = CLLocation(latitude: 43.6045, longitude: 1.4433)
        let near = Fixtures.store("NODE:1", lat: 43.6050, lon: 1.4440)
        let far = Fixtures.store("NODE:2", lat: 43.70, lon: 1.60)
        let entry = StoreCacheEntry(lat: 43.6046, lon: 1.4434, radiusKm: 8, date: Fixtures.day(0),
                                    stores: [far, near], countryCode: "FR")

        let usable = StoreCache.usable(entry, near: here, radiusKm: 8, now: Fixtures.day(2))
        XCTAssertEqual(usable?.stores.map(\.id), ["NODE:1"], "magasin hors rayon écarté")
        XCTAssertNil(StoreCache.usable(entry, near: here, radiusKm: 8, now: Fixtures.day(60)), "trop ancien")
        XCTAssertNil(StoreCache.usable(entry, near: here, radiusKm: 12, now: Fixtures.day(1)), "rayon plus grand")
        let elsewhere = CLLocation(latitude: 45.76, longitude: 4.83)
        XCTAssertNil(StoreCache.usable(entry, near: elsewhere, radiusKm: 8, now: Fixtures.day(1)), "autre ville")
    }

    func testMergeCachedWithFreshOpenPrices() {
        let center = CLLocation(latitude: 43.6045, longitude: 1.4433)
        let cached = [Fixtures.store("NODE:1", name: "Lidl"), Fixtures.store("NODE:2", name: "Carrefour", lat: 43.61)]
        var updated = Fixtures.store("NODE:2", name: "Carrefour", lat: 43.61)
        updated.priceCount = 42
        let fresh = [updated, Fixtures.store("WAY:3", name: "Nouveau", lat: 43.62), Fixtures.store("apple:43.6,1.4")]
        let merged = StoreFinder.merge(cached: cached, fresh: fresh, center: center)
        XCTAssertEqual(merged.map(\.id), ["NODE:1", "NODE:2", "WAY:3"])
        XCTAssertEqual(merged[1].priceCount, 42)
    }
}
