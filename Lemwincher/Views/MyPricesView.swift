import SwiftUI

/// Onglet "Mes prix" : les prix que j'ai relevés en magasin.
struct MyPricesView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddPrice = false

    private var entries: [MyPrice] {
        model.state.myPrices.sorted { $0.date > $1.date }
    }

    var body: some View {
        let entries = self.entries
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun prix relevé", systemImage: "tag")
                    } description: {
                        Text("En magasin, touchez + : le magasin est détecté automatiquement, scannez un produit, tapez le prix, et enchaînez avec le suivant. Vos relevés s'ajoutent aux prix de la communauté pour trouver le moins cher, même pour les produits sans code-barres.")
                    } actions: {
                        Button("Relever un prix") { showAddPrice = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
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
                    } footer: {
                        Text("\(entries.count) relevés, enregistrés uniquement sur cet iPhone. Balayez vers la gauche pour supprimer.")
                    }
                }
            }
            .navigationTitle("Mes prix")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddPrice = true
                    } label: {
                        Label("Relever un prix", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddPrice) {
                AddPriceView()
            }
            .appDestinations()
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
                Text(Fmt.join(entry.store.name, Fmt.day(entry.date)))
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
