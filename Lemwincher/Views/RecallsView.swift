import SwiftUI

/// Rappels de produits alimentaires récents dans le département (RappelConso).
struct RecallsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    private var filtered: [Recall] {
        let q = filter.trimmed
        guard !q.isEmpty else { return model.localRecalls }
        return model.localRecalls.filter { recall in
            recall.title.localizedCaseInsensitiveContains(q)
                || (recall.brand ?? "").localizedCaseInsensitiveContains(q)
                || (recall.subcategory ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private struct RecalledProduct: Identifiable {
        let product: Product
        let recall: Recall
        var id: String { product.code }
    }

    /// Produits de ma liste, suivis ou consultés qui sont rappelés.
    private var myRecalledProducts: [RecalledProduct] {
        var seen = Set<String>()
        var result: [RecalledProduct] = []
        let products = model.state.shoppingList.map(\.product) + model.state.watchlist.map(\.product) + model.state.recentProducts
        for product in products where !seen.contains(product.code) {
            seen.insert(product.code)
            if let recall = model.recall(for: product.code) {
                result.append(RecalledProduct(product: product, recall: recall))
            }
        }
        return result
    }

    var body: some View {
        let mine = myRecalledProducts
        let list = filtered
        List {
            if !mine.isEmpty {
                Section("Vos produits concernés") {
                    ForEach(mine) { entry in
                        RecallBanner(recall: entry.recall, productName: entry.product.name)
                    }
                }
            }

            Section {
                if model.recallsLoading && list.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Chargement des rappels…").foregroundStyle(.secondary)
                    }
                }
                if let error = model.recallsError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
                if !model.recallsLoading && list.isEmpty && model.recallsError == nil {
                    Text(filter.trimmed.isEmpty ? "Aucun rappel alimentaire ces 30 derniers jours." : "Aucun rappel ne correspond.")
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { recall in
                    NavigationLink {
                        RecallDetailView(recall: recall)
                    } label: {
                        RecallRow(recall: recall)
                    }
                }
            } header: {
                Text(headerText(count: list.count))
            } footer: {
                Text("Source : RappelConso, le site officiel des rappels de produits (DGCCRF / DGAL). Un rappel concerne des lots précis : vérifiez le numéro de lot et la date sur l'emballage.")
            }
        }
        .searchable(text: $filter, prompt: "Produit, marque ou rayon")
        .navigationTitle("Rappels de produits")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refreshRecalls()
            await model.checkRecalls(for: model.state.shoppingList.map(\.product.code)
                                     + model.state.watchlist.map(\.id)
                                     + model.state.recentProducts.map(\.code))
        }
        .refreshable { await model.refreshRecalls(force: true) }
    }

    private func headerText(count: Int) -> String {
        let place = model.departmentName.map { "vendus en \($0) ou dans toute la France" } ?? "en France"
        return "\(count) rappel\(count > 1 ? "s" : "") alimentaire\(count > 1 ? "s" : "") (30 jours), \(place)"
    }
}

struct RecallRow: View {
    let recall: Recall

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductThumb(url: recall.imageURL, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(recall.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(Fmt.join(recall.brand, recall.published.map { Fmt.day($0) }))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let reason = recall.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecallDetailView: View {
    let recall: Recall

    var body: some View {
        List {
            Section {
                if let url = recall.imageURL.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Color(.secondarySystemBackground)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(recall.title).font(.title3.bold())
                    if let brand = recall.brand {
                        Text(brand).foregroundStyle(.secondary)
                    }
                    if let published = recall.published {
                        Text("Rappel publié le \(published.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if let reason = recall.reason {
                Section("Motif du rappel") {
                    Text(reason)
                    if let risks = recall.risks {
                        Label(risks, systemImage: "cross.case").foregroundStyle(Color.red)
                    }
                }
            }

            if !recall.lots.isEmpty {
                Section("Lots concernés") {
                    ForEach(recall.lots, id: \.self) { lot in
                        Text(lot).font(.callout.monospacedDigit())
                    }
                }
            }

            if !recall.advice.isEmpty {
                Section("Que faire ?") {
                    ForEach(recall.advice, id: \.self) { advice in
                        Label(advice, systemImage: "checkmark.circle")
                    }
                    if let compensation = recall.compensation {
                        Label("Compensation : \(compensation)", systemImage: "eurosign.circle")
                    }
                }
            }

            Section("Où ?") {
                if let distributors = recall.distributors {
                    LabeledContent("Distributeurs", value: distributors)
                }
                if let zone = recall.zone {
                    Text("Zone de vente : " + zone.replacingOccurrences(of: "|", with: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
            }

            if let page = recall.pageURL.flatMap(URL.init(string:)) {
                Section {
                    Link(destination: page) {
                        Label("Voir la fiche officielle RappelConso", systemImage: "safari")
                    }
                }
            }
        }
        .navigationTitle("Rappel")
        .navigationBarTitleDisplayMode(.inline)
    }
}
