import SwiftUI
import MapKit

/// Prix des carburants autour de soi (données officielles prix-carburants.gouv.fr).
struct FuelView: View {
    @Environment(AppModel.self) private var model
    @State private var sortByDistance = false
    @State private var camera: MapCameraPosition = .automatic

    private struct MapPoint: Identifiable {
        let station: FuelStation
        let price: Double
        var id: Int { station.id }
    }

    var body: some View {
        @Bindable var bindable = model
        let fuel = model.settings.fuelType
        let reference = model.referenceLocation
        let ranked = FuelStats.ranked(model.fuelStations, fuel: fuel)
        let average = FuelStats.average(ranked, fuel: fuel)
        let list = sortByDistance ? FuelView.sortedByDistance(ranked, from: reference) : ranked

        List {
            Section {
                FuelTypePicker(selection: $bindable.state.settings.fuelType)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                map(ranked: ranked, fuel: fuel)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
            }

            if let best = ranked.first, let price = best.price(for: fuel)?.value {
                Section {
                    summary(best: best, price: price, average: average, fuel: fuel, count: ranked.count)
                }
            }

            Section {
                if model.fuelLoading && ranked.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Chargement des prix…").foregroundStyle(.secondary)
                    }
                }
                if let error = model.fuelError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
                if !model.fuelLoading && ranked.isEmpty && model.fuelError == nil {
                    Text("Aucune station ne vend du \(fuel.label) dans un rayon de \(Int(min(max(model.settings.radiusKm, 5), 20))) km (ou prix non communiqués).")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(list.enumerated()), id: \.element.id) { index, station in
                    NavigationLink {
                        FuelStationDetailView(station: station)
                    } label: {
                        FuelStationRow(station: station,
                                       fuel: fuel,
                                       distance: reference.map { station.location.distance(from: $0) },
                                       cheapest: station.id == ranked.first?.id,
                                       average: average)
                    }
                    .accessibilityIdentifier(index == 0 ? "fuelStationFirst" : "fuelStation")
                }
            } header: {
                Picker("Tri", selection: $sortByDistance) {
                    Text("Moins chères").tag(false)
                    Text("Plus proches").tag(true)
                }
                .pickerStyle(.segmented)
                .textCase(nil)
                .padding(.bottom, 4)
            } footer: {
                Text(sourceText)
            }
        }
        .navigationTitle("Carburants")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshFuel() }
        .refreshable { await model.refreshFuel(force: true) }
        .onChange(of: fuel) { _, _ in camera = .automatic }
    }

    private var sourceText: String {
        var text = "Prix officiels publiés par les stations sur prix-carburants.gouv.fr (ministère de l'Économie)"
        if let updated = model.fuelUpdated {
            text += ", chargés " + Fmt.ago(updated)
        }
        return text + ". Noms des stations : OpenStreetMap."
    }

    static func sortedByDistance(_ stations: [FuelStation], from reference: CLLocation?) -> [FuelStation] {
        guard let reference else { return stations }
        return stations.sorted { $0.location.distance(from: reference) < $1.location.distance(from: reference) }
    }

    // MARK: Carte

    private func map(ranked: [FuelStation], fuel: FuelType) -> some View {
        let points = ranked.prefix(40).compactMap { station -> MapPoint? in
            guard let price = station.price(for: fuel)?.value else { return nil }
            return MapPoint(station: station, price: price)
        }
        let low = points.map(\.price).min() ?? 0
        let high = points.map(\.price).max() ?? 0
        return Map(position: $camera) {
            UserAnnotation()
            if model.settings.useHome, let home = model.settings.home {
                Marker("Domicile", systemImage: "house.fill", coordinate: home.coordinate)
                    .tint(Color.blue)
            }
            ForEach(points) { point in
                Annotation(point.station.title, coordinate: point.station.coordinate) {
                    Text(Fmt.fuel(point.price).replacingOccurrences(of: " €", with: ""))
                        .font(.caption2.bold().monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(FuelView.color(price: point.price, low: low, high: high), in: Capsule())
                        .foregroundStyle(Color.white)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    /// Vert pour les moins chères, orange puis rouge pour les plus chères.
    static func color(price: Double, low: Double, high: Double) -> Color {
        guard high > low else { return Color.brand }
        let t = (price - low) / (high - low)
        if t < 0.34 { return Color.brand }
        if t < 0.67 { return Color.orange }
        return Color.red
    }

    // MARK: Résumé

    private func summary(best: FuelStation, price: Double, average: Double?, fuel: FuelType, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("\(fuel.label) le moins cher : \(Fmt.fuel(price))")
                    .font(.headline)
            } icon: {
                Image(systemName: "fuelpump.fill").foregroundStyle(Color.brand)
            }
            Text(Fmt.join(best.title, model.referenceLocation.map { Fmt.distance(best.location.distance(from: $0)) }))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let average {
                let saving = FuelStats.savings(price: price, reference: average)
                if saving >= 0.5 {
                    Text("Un plein de 50 L y coûte \(Fmt.price(saving, "EUR")) de moins qu'au prix moyen des \(count) stations (\(Fmt.fuel(average))).")
                        .font(.footnote)
                        .foregroundStyle(Color.brand)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Choix du carburant : boutons défilants.
struct FuelTypePicker: View {
    @Binding var selection: FuelType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FuelType.allCases) { fuel in
                    Button {
                        selection = fuel
                    } label: {
                        Text(fuel.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selection == fuel ? Color.brand : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(selection == fuel ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct FuelStationRow: View {
    let station: FuelStation
    let fuel: FuelType
    let distance: Double?
    let cheapest: Bool
    let average: Double?

    private var subtitle: String {
        let distanceText: String? = distance.map { Fmt.distance($0) }
        let updated: Date? = station.price(for: fuel)?.updated
        let updatedText: String? = updated.map { "MAJ " + Fmt.ago($0) }
        return Fmt.join(distanceText, FuelStation.prettify(station.city), updatedText)
    }

    /// "+0,045 € / -0,030 €" par rapport à la moyenne.
    static func difference(_ value: Double) -> String {
        (value > 0 ? "+" : "") + Fmt.fuel(value) + " vs moy."
    }

    var body: some View {
        HStack(spacing: 12) {
            StoreLogo(url: station.logoURL, size: 36, systemImage: "fuelpump.fill")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(station.title).font(.headline).lineLimit(1)
                    if station.isHighway {
                        Image(systemName: "road.lanes").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let price = station.price(for: fuel)?.value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.fuel(price))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(cheapest ? Color.brand : Color.primary)
                    if cheapest {
                        Text("Le moins cher").font(.caption2.bold()).foregroundStyle(Color.brand)
                    } else if let average {
                        Text(FuelStationRow.difference(price - average))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(price <= average ? Color.brand : Color.secondary)
                    }
                }
            }
        }
    }
}

/// Fiche d'une station : tous ses prix, services et itinéraire.
struct FuelStationDetailView: View {
    @Environment(AppModel.self) private var model
    let station: FuelStation

    var body: some View {
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(center: station.coordinate,
                                                                 latitudinalMeters: 800,
                                                                 longitudinalMeters: 800))) {
                    Marker(station.title, systemImage: "fuelpump.fill", coordinate: station.coordinate)
                        .tint(Color.brand)
                    UserAnnotation()
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())

                VStack(alignment: .leading, spacing: 4) {
                    Text(station.title).font(.title2.bold())
                    Text(station.fullAddress).foregroundStyle(.secondary)
                    if let reference = model.referenceLocation {
                        Label("À \(Fmt.distance(station.location.distance(from: reference)))", systemImage: "location")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if let url = station.directionsURL {
                    Link(destination: url) {
                        Label("Itinéraire avec Plans", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                }
            }

            Section("Prix au litre") {
                ForEach(FuelType.allCases) { fuel in
                    if let price = station.price(for: fuel) {
                        HStack {
                            Text(fuel.label)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.fuel(price.value)).font(.headline.monospacedDigit())
                                if station.shortages.contains(fuel) {
                                    Text("En rupture").font(.caption2.bold()).foregroundStyle(Color.red)
                                } else if let updated = price.updated {
                                    Text("MAJ " + Fmt.ago(updated)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Services") {
                if station.open24h {
                    Label("Automate carte bancaire 24 h/24", systemImage: "creditcard")
                }
                if station.isHighway {
                    Label("Station d'autoroute", systemImage: "road.lanes")
                }
                ForEach(station.services, id: \.self) { service in
                    Text(service)
                }
                if station.services.isEmpty && !station.open24h {
                    Text("Non communiqués").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(station.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Résumé affiché dans « Autour de moi » : carburant le moins cher.
struct FuelSummaryRow: View {
    let fuel: FuelType
    let best: FuelStation?
    let distance: Double?
    let loading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fuelpump.fill")
                .font(.title3)
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Carburant le moins cher").font(.headline)
                if let best {
                    Text(Fmt.join(fuel.label, best.title, distance.map { Fmt.distance($0) }))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(loading ? "Chargement des prix officiels…" : "Prix officiels des stations proches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let price = best?.price(for: fuel)?.value {
                Text(Fmt.fuel(price))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.brand)
            } else if loading {
                ProgressView()
            }
        }
    }
}
