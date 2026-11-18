import SwiftUI
import UniformTypeIdentifiers

/// "Mes prix" (dans l'onglet Budget) : les prix que j'ai relevés en magasin, et leur évolution.
struct MyPricesContent: View {
    @Environment(AppModel.self) private var model
    @State private var showAddPrice = false
    @State private var showReceipt = false
    @State private var filter = ""

    private var entries: [MyPrice] {
        let all = model.state.myPrices.sorted { $0.date > $1.date }
        let q = filter.trimmed
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.product.name.localizedCaseInsensitiveContains(q) || $0.store.name.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        let entries = self.entries
        List {
                if model.state.myPrices.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun prix relevé", systemImage: "tag")
                    } description: {
                        Text("En magasin, touchez + : le magasin est détecté automatiquement, scannez un produit ou photographiez l'étiquette, et enchaînez avec le suivant. Après vos courses, photographiez le ticket de caisse pour tout ajouter d'un coup.")
                    } actions: {
                        Button("Relever un prix") { showAddPrice = true }
                            .buttonStyle(.borderedProminent)
                        Button("Scanner un ticket de caisse") { showReceipt = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    if filter.trimmed.isEmpty {
                        statsSection
                        changesSection
                    }
                    Section {
                        ForEach(entries) { entry in
                            NavigationLink(value: entry.product) {
                                MyPriceRow(entry: entry)
                            }
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { entries[$0].id })
                            model.deleteMyPrices(ids: ids)
                        }
                    } header: {
                        Text("Mes relevés")
                    } footer: {
                        Text("\(entries.count) relevé\(entries.count > 1 ? "s" : ""), enregistrés sur cet iPhone. Balayez vers la gauche pour supprimer.")
                    }
                }
            }
            .navigationTitle("Mes prix")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, prompt: "Produit ou magasin")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !model.state.myPrices.isEmpty {
                        ShareLink(item: CSVExport(text: Backup.csv(model.state.myPrices)),
                                  preview: SharePreview("Mes relevés de prix (CSV)")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    Menu {
                        Button {
                            showAddPrice = true
                        } label: {
                            Label("Relever un prix", systemImage: "tag")
                        }
                        Button {
                            showReceipt = true
                        } label: {
                            Label("Scanner un ticket de caisse", systemImage: "doc.text.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addPriceMenu")
                }
            }
            .sheet(isPresented: $showAddPrice) {
                AddPriceView()
            }
            .sheet(isPresented: $showReceipt) {
                ReceiptScanView()
            }
    }

    // MARK: Statistiques

    private var statsSection: some View {
        let prices = model.state.myPrices
        let products = Set(prices.map(\.product.code)).count
        let stores = Set(prices.map(\.store.id)).count
        let shared = prices.filter { $0.sharedPriceID != nil }.count
        let thisMonth = prices.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.count
        return Section {
            HStack(spacing: 0) {
                StatTile(value: "\(prices.count)", label: "relevés")
                StatTile(value: "\(products)", label: "produits")
                StatTile(value: "\(stores)", label: "magasins")
                StatTile(value: "\(shared)", label: "partagés")
            }
            .padding(.vertical, 4)
        } footer: {
            Text("\(thisMonth) relevé\(thisMonth > 1 ? "s" : "") ce mois-ci. Merci : chaque prix partagé sur Open Prices aide vos voisins à payer moins cher.")
        }
    }

    @ViewBuilder
    private var changesSection: some View {
        let changes = PriceEngine.priceChanges(model.state.myPrices).filter { abs($0.percent) >= 0.5 }
        if !changes.isEmpty {
            Section {
                ForEach(changes.prefix(6)) { change in
                    NavigationLink(value: change.product) {
                        PriceChangeRow(change: change)
                    }
                }
            } header: {
                Text("Évolution de vos prix")
            } footer: {
                Text("Même produit, même magasin : premier et dernier prix relevés (hors promotions).")
            }
        }
    }
}

/// Fichier CSV partagé (Excel, Numbers, e-mail…).
struct CSVExport: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.text.utf8)
        }
        .suggestedFileName("lemwincher-releves.csv")
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PriceChangeRow: View {
    let change: PriceChange

    var body: some View {
        let up = change.delta > 0
        HStack(spacing: 12) {
            ProductThumb(url: change.product.imageURL, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(change.product.name).lineLimit(1)
                Text(Fmt.join(change.storeName,
                              "\(Fmt.price(change.first, change.currency)) → \(Fmt.price(change.last, change.currency))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Label(Fmt.percent(change.percent), systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(up ? Color.red : Color.brand)
        }
    }
}

struct MyPriceRow: View {
    let entry: MyPrice

    var body: some View {
        HStack(spacing: 12) {
            ProductThumb(url: entry.product.imageURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.product.name).lineLimit(2)
                Text(Fmt.join(entry.store.name, Fmt.day(entry.date), entry.source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.price(entry.price, entry.currency))
                    .font(.headline.monospacedDigit())
                if entry.isDiscounted { PromoBadge() }
                if entry.sharedPriceID != nil {
                    Label("Partagé", systemImage: "globe")
                        .font(.caption2)
                        .foregroundStyle(Color.brand)
                }
            }
        }
    }
}
