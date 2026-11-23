import XCTest
import CoreLocation
@testable import Lemwincher

/// Recherche de magasins sur la carte : magasins connus, puis résultats de Plans sans doublons.
final class StoreSearchTests: XCTestCase {
    func testSearchKnownStoresByNameChainAndAddress() {
        var blagnac = Fixtures.store("NODE:1", name: "E.Leclerc Blagnac", brand: "E.Leclerc", lat: 43.64, lon: 1.39)
        blagnac.address = "Allée Émile Zola, Blagnac"
        let lidl = Fixtures.store("NODE:2", name: "Lidl", brand: "Lidl", lat: 43.61, lon: 1.43)
        let inter = Fixtures.store("NODE:3", name: "Intermarché Super", brand: "Intermarché", lat: 43.60, lon: 1.44)
        let city = Fixtures.store("NODE:4", name: "Carrefour City", brand: "Carrefour City", lat: 43.6045, lon: 1.4433)
        let stores = [blagnac, lidl, inter, city]
        let home = CLLocation(latitude: 43.6045, longitude: 1.4433)

        XCTAssertEqual(StoreSearch.matches(stores, query: "leclerc", reference: home).map(\.id), ["NODE:1"])
        XCTAssertEqual(StoreSearch.matches(stores, query: "inter", reference: home).map(\.id), ["NODE:3"], "début de mot")
        XCTAssertEqual(StoreSearch.matches(stores, query: "Leclerc  Blagnac", reference: home).map(\.id), ["NODE:1"])
        XCTAssertEqual(StoreSearch.matches(stores, query: "zola", reference: home).map(\.id), ["NODE:1"], "par l'adresse")
        XCTAssertEqual(StoreSearch.matches(stores, query: "carrefour", reference: home).map(\.id), ["NODE:4"])
        XCTAssertTrue(StoreSearch.matches(stores, query: "auchan", reference: home).isEmpty)
        XCTAssertTrue(StoreSearch.matches(stores, query: "  ", reference: home).isEmpty)
        XCTAssertEqual(StoreSearch.byDistance([blagnac, city, lidl], from: home).map(\.id), ["NODE:4", "NODE:2", "NODE:1"],
                       "du plus proche au plus loin")
    }

    func testPlansResultsLeaveOutKnownStores() {
        let known = [Fixtures.store("NODE:1", name: "Lidl", brand: "Lidl", lat: 43.6100, lon: 1.4300)]
        // Le même Lidl vu par Plans, à une cinquantaine de mètres : déjà connu.
        let sameLidl = StoreFinder.appleStore(name: "Lidl", address: nil,
                                              coordinate: CLLocationCoordinate2D(latitude: 43.6105, longitude: 1.4302))
        // Un autre magasin à côté (autre enseigne, à plus de 40 m) : gardé.
        let aldi = StoreFinder.appleStore(name: "Aldi", address: nil,
                                          coordinate: CLLocationCoordinate2D(latitude: 43.6104, longitude: 1.4301))
        let farLidl = StoreFinder.appleStore(name: "Lidl", address: nil,
                                             coordinate: CLLocationCoordinate2D(latitude: 43.70, longitude: 1.50))
        let kept = StoreSearch.newStores([sameLidl, aldi, farLidl, farLidl], excluding: known)
        XCTAssertEqual(kept.map(\.name), ["Aldi", "Lidl"], "sans le Lidl connu ni le doublon")
        XCTAssertTrue(aldi.id.hasPrefix("apple:"))
    }
}
