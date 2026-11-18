import SwiftUI

/// Ouvre la fiche d'un rayon suivi (par son identifiant : la fiche suit les mises à jour).
struct TrackedPageRoute: Hashable {
    let id: UUID
}

/// Onglet Produits : les rayons des sites d'enseignes gardés en mémoire.
struct TrackedPagesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pages = model.state.trackedPages
        if !pages.isEmpty {
            Section {
                ForEach(pages) { page in
                    NavigationLink(value: TrackedPageRoute(id: page.id)) {
                        TrackedPageRow(page: page)
                    }
                    .accessibilityIdentifier("trackedPageRow")
                }
                .onDelete { offsets in
                    model.state.trackedPages.remove(atOffsets: offsets)
                }
            } header: {
                HStack {
                    Text("Mes rayons en ligne")
                    Spacer()
                    if model.trackedRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Tout mettre à jour") {
                            Task { await model.refreshTrackedPages(force: true) }
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                }
            } footer: {
                Text("Rayons capturés sur les sites des enseignes : leurs prix sont relus à l'ouverture de l'app (au plus toutes les 12 h) et vous êtes prévenu des baisses.")
            }
        }
    }
}

struct TrackedPageRow: View {
    let page: TrackedPage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.autoUpdate ? "arrow.triangle.2.circlepath.circle.fill" : "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(page.autoUpdate ? Color.brand : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.shortTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(Fmt.join(page.siteName, page.store.name,
                              page.productCodes.count == 1 ? "1 produit" : "\(page.productCodes.count) produits"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let error = page.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                        .lineLimit(2)
                } else {
                    Text("Mis à jour \(Fmt.ago(page.lastChecked))"
                         + (page.lastChanges > 0 ? " · \(page.lastChanges) changement\(page.lastChanges > 1 ? "s" : "")" : ""))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Fiche d'un rayon suivi : ses produits avec le dernier prix et sa variation, mise à jour, page.
struct TrackedPageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID

    @State private var filter = ""
    @State private var showPage = false

    private var autoUpdate: Binding<Bool> {
        Binding(get: { model.state.trackedPages.first { $0.id == pageID }?.autoUpdate ?? false },
                set: { value in
                    if let index = model.state.trackedPages.firstIndex(where: { $0.id == pageID }) {
                        model.state.trackedPages[index].autoUpdate = value
                    }
                })
    }

    var body: some View {
        if let page = model.state.trackedPages.first(where: { $0.id == pageID }) {
            let currency = model.settings.currency
            let products = model.trackedProducts(page).filter { entry in
                filter.trimmed.isEmpty || entry.latest.product.name.localizedCaseInsensitiveContains(filter.trimmed)
            }
            List {
                Section {
                    LabeledContent("Site", value: page.siteName)
                    LabeledContent("Magasin", value: page.store.name)
                    LabeledContent("Mis à jour", value: Fmt.ago(page.lastChecked))
                    if let error = page.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                    }
                    Toggle("Mise à jour automatique", isOn: autoUpdate)
                        .tint(Color.brand)
                    Button {
                        Task { await model.refreshTrackedPages(only: page.id) }
                    } label: {
                        HStack {
                            Label("Mettre à jour maintenant", systemImage: "arrow.clockwise")
                            if model.trackedRefreshing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.trackedRefreshing)
                    .accessibilityIdentifier("refreshTrackedPage")
                    Button {
                        showPage = true
                    } label: {
                        Label("Ouvrir la page", systemImage: "safari")
                    }
                }

                Section {
                    ForEach(products) { entry in
                        NavigationLink(value: entry.latest.product) {
                            TrackedProductRow(latest: entry.latest, previous: entry.previous, currency: currency)
                        }
                    }
                } header: {
                    Text(products.count == 1 ? "1 produit" : "\(products.count) produits")
                } footer: {
                    Text("Derniers prix lus sur le site, rattachés à \(page.store.name). ↓ ↑ : variation depuis la lecture précédente.")
                }

                Section {
                    Button(role: .destructive) {
                        model.state.trackedPages.removeAll { $0.id == pageID }
                        dismiss()
                    } label: {
                        Label("Ne plus suivre ce rayon", systemImage: "trash")
                    }
                } footer: {
                    Text("Les prix déjà relevés restent dans « Mes prix ».")
                }
            }
            .navigationTitle(page.shortTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, prompt: "Filtrer les produits")
            .refreshable { await model.refreshTrackedPages(only: page.id) }
            .fullScreenCover(isPresented: $showPage) {
                let site = DriveSite.all.first { $0.name == page.siteName }
                let url = URL(string: page.url)
                DriveCaptureView(query: "", preferredChain: site?.chainPrefix, startURL: url, store: page.store,
                                 customSite: site == nil ? url.map { DriveSite.custom(for: page.store, url: $0) } : nil)
            }
        } else {
            ContentUnavailableView("Rayon retiré", systemImage: "trash",
                                   description: Text("Ce rayon n'est plus suivi."))
        }
    }
}

/// Un produit d'un rayon suivi : photo, nom, dernier prix, variation.
struct TrackedProductRow: View {
    let latest: MyPrice
    let previous: MyPrice?
    let currency: String

    var body: some View {
        HStack(spacing: 10) {
            ProductThumb(url: latest.product.imageURL, size: 40, name: latest.product.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(latest.product.name)
                    .font(.subheadline)
                    .lineLimit(2)
                let details = Fmt.join(latest.product.brand, latest.product.quantity, "lu \(Fmt.ago(latest.date))")
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                if latest.isDiscounted {
                    PromoBadge()
                }
                Text(Fmt.price(latest.price, currency))
                    .font(.subheadline.bold().monospacedDigit())
                if let previous, abs(previous.price - latest.price) >= 0.005 {
                    let drop = latest.price < previous.price
                    Label(Fmt.price(abs(latest.price - previous.price), currency),
                          systemImage: drop ? "arrow.down" : "arrow.up")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(drop ? Color.green : Color.red)
                }
            }
            .fixedSize()
        }
    }
}
