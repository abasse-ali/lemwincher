import SwiftUI

/// Site à ouvrir dans le navigateur de l'app depuis un magasin.
enum StoreBrowserRequest: Identifiable {
    /// Site de l'enseigne (Aldi, Leclerc Drive…), ouvert sur ses rayons.
    case chain(DriveSite)
    /// Site propre du magasin (adresse connue d'OpenStreetMap).
    case website(URL)

    var id: String {
        switch self {
        case .chain(let site): return "chain:" + site.id
        case .website(let url): return "web:" + url.absoluteString
        }
    }
}

/// Boutons « Rayons et prix sur le site » d'un magasin (carte, fiche du magasin).
struct StoreSiteButtons: View {
    let store: Store
    @Binding var request: StoreBrowserRequest?
    var prominent = true

    var body: some View {
        if let site = DriveSite.forStore(store) {
            button(title: "Rayons et prix sur le site \(site.name)", symbol: "safari.fill") {
                request = .chain(site)
            }
            .accessibilityIdentifier("storeSiteButton")
        } else if let website = store.websiteURL {
            button(title: "Rayons et prix sur le site du magasin", symbol: "safari.fill") {
                request = .website(website)
            }
            .accessibilityIdentifier("storeSiteButton")
        } else {
            Label("Pas de site de courses connu pour ce magasin.", systemImage: "safari")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func button(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brand)
        } else {
            Button(action: action) {
                Label(title, systemImage: symbol)
            }
        }
    }
}

extension View {
    /// Ouvre le navigateur de l'app sur le site demandé, avec le magasin choisi d'office pour les prix.
    func storeBrowser(_ request: Binding<StoreBrowserRequest?>, store: Store) -> some View {
        fullScreenCover(item: request) { request in
            switch request {
            case .chain(let site):
                DriveCaptureView(query: "", preferredChain: site.chainPrefix, startURL: site.startURL, store: store)
            case .website(let url):
                DriveCaptureView(query: "", startURL: url, store: store,
                                 customSite: DriveSite.custom(for: store, url: url))
            }
        }
    }
}

/// Fiche rapide d'un magasin touché sur la carte : son site (rayons et prix), l'itinéraire, la fiche complète.
struct StoreQuickSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let store: Store
    let onOpenDetail: () -> Void

    @State private var browser: StoreBrowserRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                StoreLogo(url: store.displayLogoURL, size: 52, chainKey: store.chainKey)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    let details = Fmt.join(store.address,
                                           store.distance(from: model.referenceLocation).map { "à \(Fmt.distance($0))" })
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let hours = store.hours {
                        OpenStatusLabel(hours: hours)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    model.toggleFavorite(store)
                } label: {
                    Image(systemName: model.isFavorite(store) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(model.isFavorite(store) ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isFavorite(store) ? "Retirer de mes magasins" : "Ajouter à mes magasins")
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
                .accessibilityIdentifier("closeQuickSheet")
            }

            StoreSiteButtons(store: store, request: $browser)

            HStack(spacing: 10) {
                if let url = store.directionsURL {
                    Link(destination: url) {
                        Label("Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                Button(action: onOpenDetail) {
                    Label("Fiche et prix", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("storeQuickDetail")
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .storeBrowser($browser, store: store)
    }
}
