import XCTest
import CoreLocation
@testable import Lemwincher

/// Carburants (prix-carburants.gouv.fr) et rappels (RappelConso), d'après de vraies réponses de l'API.
final class FuelTests: XCTestCase {
    private let sample = """
    {"total_count": 41, "results": [
      {"id": 31140010, "adresse": "16 AVENUE DE FRONTON", "ville": "Aucamville", "cp": "31140", "pop": "R",
       "geom": {"lon": 1.42731, "lat": 43.67109}, "gazole_prix": 2.053, "gazole_maj": "2026-11-17T00:01:00+00:00",
       "e10_prix": null, "e10_maj": null, "sp98_prix": null, "sp98_maj": null, "sp95_prix": null, "e85_prix": null,
       "gplc_prix": 1.065, "carburants_rupture_temporaire": "E10;SP98", "horaires_automate_24_24": "Non",
       "services_service": ["DAB (Distributeur automatique de billets)", "Boutique alimentaire", "Lavage automatique"]},
      {"id": 31700009, "adresse": "120 ROUTE DE GRENADE", "ville": "Blagnac", "cp": "31700", "pop": "A",
       "latitude": "4364600", "longitude": "138500", "gazole_prix": "2.063", "e10_prix": 1.905,
       "e10_maj": "2026-11-17T07:47:14+00:00", "horaires_automate_24_24": "Oui", "services_service": null},
      {"adresse": "sans identifiant"}
    ]}
    """

    func testDecodeStations() throws {
        let response = try JSONDecoder().decode(FuelResponse.self, from: Fixtures.json(sample))
        XCTAssertEqual(response.totalCount, 41)
        XCTAssertEqual(response.stations.count, 2)

        let first = response.stations[0]
        XCTAssertEqual(first.id, 31140010)
        XCTAssertEqual(first.lat, 43.67109, accuracy: 1e-6)
        XCTAssertEqual(first.price(for: .gazole)?.value ?? 0, 2.053, accuracy: 1e-9)
        XCTAssertNotNil(first.price(for: .gazole)?.updated)
        XCTAssertNil(first.price(for: .e10))
        XCTAssertEqual(first.price(for: .gplc)?.value ?? 0, 1.065, accuracy: 1e-9)
        XCTAssertEqual(first.shortages, [.e10, .sp98])
        XCTAssertEqual(first.services.count, 3)
        XCTAssertFalse(first.open24h)
        XCTAssertFalse(first.isHighway)
        XCTAssertEqual(first.fullAddress, "16 avenue de Fronton, 31140 Aucamville")

        let second = response.stations[1]
        XCTAssertEqual(second.lat, 43.646, accuracy: 1e-6, "repli sur le champ latitude")
        XCTAssertEqual(second.lon, 1.385, accuracy: 1e-6)
        XCTAssertEqual(second.price(for: .gazole)?.value ?? 0, 2.063, accuracy: 1e-9)
        XCTAssertTrue(second.open24h)
        XCTAssertTrue(second.isHighway)
        XCTAssertTrue(second.services.isEmpty)
    }

    private func station(_ id: Int, gazole: Double?, updated: Date? = nil, shortage: Bool = false,
                         lat: Double = 43.6, lon: Double = 1.44) -> FuelStation {
        var prices: [FuelType: FuelPrice] = [:]
        if let gazole { prices[.gazole] = FuelPrice(value: gazole, updated: updated) }
        return FuelStation(id: id, address: "1 RUE TEST", city: "TOULOUSE", postcode: "31000", lat: lat, lon: lon,
                           isHighway: false, open24h: false, prices: prices,
                           shortages: shortage ? [.gazole] : [], services: [])
    }

    func testRankingAverageAndSavings() {
        let now = Fixtures.day(100)
        let stations = [
            station(1, gazole: 1.95, updated: now),
            station(2, gazole: 1.80, updated: now),
            station(3, gazole: 1.70, updated: now, shortage: true),                 // en rupture
            station(4, gazole: 1.60, updated: now.addingTimeInterval(-20 * 86_400)), // prix trop ancien
            station(5, gazole: nil),
            station(6, gazole: 1.85, updated: nil),
        ]
        let ranked = FuelStats.ranked(stations, fuel: .gazole, now: now)
        XCTAssertEqual(ranked.map(\.id), [2, 6, 1])
        XCTAssertEqual(FuelStats.average(ranked, fuel: .gazole) ?? 0, 1.8666666, accuracy: 1e-5)
        XCTAssertEqual(FuelStats.savings(price: 1.80, reference: 1.90), 5.0, accuracy: 1e-6)
        XCTAssertEqual(FuelStats.savings(price: 2.00, reference: 1.90), 0)
        XCTAssertNil(FuelStats.average([], fuel: .gazole))
    }

    func testStationNames() {
        let near = station(1, gazole: 1.9, lat: 43.6000, lon: 1.4400)
        let byStore = station(2, gazole: 1.9, lat: 43.7000, lon: 1.5000)
        let unknown = station(3, gazole: 1.9, lat: 43.8000, lon: 1.6000)
        let places = [NamedPlace(name: nil, brand: "TotalEnergies", lat: 43.6005, lon: 1.4401)]
        let stores = [Fixtures.store("WAY:9", name: "E.Leclerc Blagnac", brand: "E.Leclerc", kind: "hypermarket",
                                     lat: 43.7015, lon: 1.5010)]
        let labeled = FuelStats.label([near, byStore, unknown], places: places, stores: stores)
        XCTAssertEqual(labeled[0].title, "TotalEnergies")
        XCTAssertEqual(labeled[1].title, "Station près de E.Leclerc")
        XCTAssertEqual(labeled[2].title, "Station Toulouse")
    }

    func testPrettify() {
        XCTAssertEqual(FuelStation.prettify("16 AVENUE DE FRONTON"), "16 avenue de Fronton")
        XCTAssertEqual(FuelStation.prettify("RD 902"), "RD 902")
        XCTAssertEqual(FuelStation.prettify("SAINT-JEAN"), "Saint-Jean")
        XCTAssertEqual(FuelStation.prettify("CHEMIN D'ALBI"), "Chemin d'Albi")
    }
}

final class RecallTests: XCTestCase {
    private let sheet = """
    {"total_count": 1, "results": [{
      "date_publication": "2026-11-17T18:14:06+00:00", "numero_fiche": "2026-11-0112",
      "categorie_produit": "alimentation", "sous_categorie_produit": "produits de la pêche et d'aquaculture",
      "marque_produit": "ocean sea", "modeles_ou_references": "cocktail de fruits de mer 500g",
      "identification_produits": ["4056489728153", "26113 b", "date de durabilité minimale", "2027-05-31",
                                  "|4056489728153", "26117 a", "date de durabilité minimale", "2027-05-31"],
      "zone_geographique_de_vente": "ain (01)|haute-garonne (31)",
      "distributeurs": "voir liste des magasins en pièce jointe",
      "motif_rappel": "une analyse a mis en évidence la présence de salmonelles.",
      "risques_encourus": "salmonella spp (agent responsable de la salmonellose)",
      "conduites_a_tenir_par_le_consommateur": "ne plus consommer|rapporter le produit au point de vente",
      "modalites_de_compensation": "remboursement",
      "date_de_fin_de_la_procedure_de_rappel": null,
      "liens_vers_les_images": "https://rappel.conso.gouv.fr/image/8ac4a8f6.jpg",
      "lien_vers_la_fiche_rappel": "https://rappel.conso.gouv.fr/fiche-rappel/24102/interne",
      "libelle": "cocktail de fruits de mer 500g", "id": 24102
    }]}
    """

    private let byGTIN = """
    {"results": [{"gtin": 3017620422003, "numero_fiche": "2025-01-0001", "libelle": "pâte à tartiner",
      "marque_produit": "marque test", "identification_produits": "3017620422003$L123$date limite de consommation$2025-02-01$",
      "date_publication": "2025-01-10T10:00:00+00:00", "date_de_fin_de_la_procedure_de_rappel": "2025-03-01"}]}
    """

    func testDecodeRecallSheet() throws {
        let response = try JSONDecoder().decode(RecallResponse.self, from: Fixtures.json(sheet))
        let recall = try XCTUnwrap(response.recalls.first)
        XCTAssertEqual(recall.id, "2026-11-0112")
        XCTAssertEqual(recall.title, "Cocktail de fruits de mer 500g")
        XCTAssertEqual(recall.brand, "Ocean Sea")
        XCTAssertEqual(recall.gtin, "4056489728153")
        XCTAssertEqual(recall.lots, [
            "Lot 26113 b · date de durabilité minimale 31/05/2027",
            "Lot 26117 a · date de durabilité minimale 31/05/2027",
        ])
        XCTAssertEqual(recall.advice, ["Ne plus consommer", "Rapporter le produit au point de vente"])
        XCTAssertEqual(recall.reason, "Une analyse a mis en évidence la présence de salmonelles.")
        XCTAssertEqual(recall.imageURL, "https://rappel.conso.gouv.fr/image/8ac4a8f6.jpg")
        XCTAssertNotNil(recall.published)
        XCTAssertTrue(recall.isActive())
    }

    func testDecodeRecallByBarcode() throws {
        let response = try JSONDecoder().decode(RecallResponse.self, from: Fixtures.json(byGTIN))
        let recall = try XCTUnwrap(response.recalls.first)
        XCTAssertEqual(recall.gtin, "3017620422003")
        XCTAssertEqual(recall.lots, ["Lot L123 · date limite de consommation 01/02/2025"])
        XCTAssertFalse(recall.isActive(at: Fixtures.date(2026, 11, 17)), "procédure terminée")
        XCTAssertTrue(recall.isActive(at: Fixtures.date(2025, 2, 15)))
    }

    func testBarcodeNormalization() {
        XCTAssertEqual(Recall.normalizedGTIN("0012345678905"), "12345678905")
        XCTAssertEqual(Recall.normalizedGTIN("3017620422003"), "3017620422003")
        XCTAssertEqual(Recall.frenchDate("2027-05-31"), "31/05/2027")
        XCTAssertEqual(Recall.frenchDate("bientôt"), "bientôt")
    }
}
