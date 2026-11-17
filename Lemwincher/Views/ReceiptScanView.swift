import SwiftUI
import UIKit

/// Ticket de caisse en photo -> liste d'articles et de prix à ajouter à « Mes prix ».
struct ReceiptScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var processing = false
    @State private var items: [ReceiptItem] = []
    @State private var detectedTotal: Double? = nil
    @State private var storeID = ""
    @State private var date = Date()
    @State private var message: String? = nil
    @State private var storeHint: String? = nil
    @State private var addToBudget = true

    /// Montant du ticket : le total lu, sinon la somme des articles cochés.
    private var receiptAmount: Double { detectedTotal ?? includedTotal }

    private var storeChoices: [Store] { model.storesByDistance() }

    private var selectedStore: Store? { storeChoices.first { $0.id == storeID } }

    private var includedItems: [ReceiptItem] { items.filter(\.include) }

    private var includedTotal: Double {
        includedItems.reduce(0) { $0 + $1.price * Double($1.quantity) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if items.isEmpty {
                    introSection
                } else {
                    storeSection
                    itemsSection
                    Section {
                        Toggle(isOn: $addToBudget) {
                            Label("Ajouter \(Fmt.price(receiptAmount, model.settings.currency)) au budget du mois",
                                  systemImage: "eurosign.circle")
                        }
                    } footer: {
                        Text("La dépense apparaîtra dans l'onglet Budget.")
                    }
                    Section {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Reprendre une photo", systemImage: "camera")
                        }
                    }
                }
            }
            .navigationTitle("Ticket de caisse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { save() }
                        .disabled(selectedStore == nil || includedItems.isEmpty)
                }
            }
            .overlay {
                if processing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Lecture du ticket…")
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image {
                        Task { await process(image) }
                    }
                }
                .ignoresSafeArea()
            }
            .onAppear {
                if storeID.isEmpty, let here = model.storeAtCurrentPosition() {
                    storeID = here.id
                }
            }
        }
    }

    // MARK: Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Ajoutez tous les prix d'un coup", systemImage: "doc.text.viewfinder")
                    .font(.headline)
                Text("Photographiez votre ticket de caisse bien à plat, en entier et bien éclairé. Lemwincher lit les articles et leurs prix ; vous vérifiez, puis les prix sont ajoutés à « Mes prix » et le montant à votre budget du mois.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showCamera = true
                } label: {
                    Label("Photographier le ticket", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(Color.orange)
                }
            }
            .padding(.vertical, 6)
        } footer: {
            Text("La lecture se fait sur l'iPhone : la photo n'est envoyée nulle part.")
        }
    }

    private var storeSection: some View {
        Section {
            Picker("Magasin", selection: $storeID) {
                Text("Choisir…").tag("")
                ForEach(storeChoices) { store in
                    Text(store.name).tag(store.id)
                }
            }
            .pickerStyle(.navigationLink)
            DatePicker("Date des achats", selection: $date, in: ...Date(), displayedComponents: .date)
        } header: {
            Text("Magasin et date")
        } footer: {
            if let storeHint {
                Text(storeHint)
            }
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach($items) { $item in
                ReceiptItemRow(item: $item, currency: model.settings.currency)
            }
            .onDelete { offsets in items.remove(atOffsets: offsets) }
        } header: {
            Text("\(includedItems.count) article\(includedItems.count > 1 ? "s" : "") reconnu\(includedItems.count > 1 ? "s" : "")")
        } footer: {
            Text(totalText)
        }
    }

    private var totalText: String {
        let currency = model.settings.currency
        var text = "Total des articles cochés : \(Fmt.price(includedTotal, currency))."
        if let detectedTotal {
            text += " Total du ticket : \(Fmt.price(detectedTotal, currency))."
        }
        return text + " Corrigez les noms si besoin (ils servent à retrouver le produit) et décochez ce qui n'est pas un article."
    }

    // MARK: Actions

    @MainActor
    private func process(_ image: UIImage) async {
        processing = true
        message = nil
        let pieces = await TextRecognizer.recognize(image)
        let rows = ReceiptParser.rows(from: pieces)
        let found = ReceiptParser.items(fromRows: rows)
        detectedTotal = ReceiptParser.total(fromRows: rows)
        processing = false
        if found.isEmpty {
            message = "Aucun article reconnu. Reprenez la photo de plus près, ticket bien à plat."
            return
        }
        items = found
        // Enseigne écrite en haut du ticket -> magasin le plus proche de cette enseigne.
        if let key = ReceiptParser.chainKey(fromRows: rows),
           let store = storeChoices.first(where: { $0.chainKey == key }) {
            if storeID.isEmpty || selectedStore?.chainKey != key {
                storeID = store.id
            }
            storeHint = "Enseigne lue sur le ticket : \(Chain.displayName(for: key) ?? key). Vérifiez le magasin."
        }
    }

    private func save() {
        guard let store = selectedStore else { return }
        for item in includedItems where !item.name.trimmed.isEmpty {
            model.addMyPrice(MyPrice(product: .custom(named: item.name),
                                     store: store,
                                     price: item.price,
                                     currency: model.settings.currency,
                                     date: date))
        }
        if addToBudget && receiptAmount > 0 {
            model.addExpense(Expense(amount: (receiptAmount * 100).rounded() / 100,
                                     date: date,
                                     storeName: store.name,
                                     storeID: store.id,
                                     chainKey: store.chainKey,
                                     category: .groceries,
                                     note: "Ticket de caisse",
                                     itemCount: includedItems.reduce(0) { $0 + $1.quantity }))
        }
        dismiss()
    }
}

struct ReceiptItemRow: View {
    @Binding var item: ReceiptItem
    let currency: String

    var body: some View {
        HStack(spacing: 10) {
            Button {
                item.include.toggle()
            } label: {
                Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.include ? Color.brand : Color.secondary)
            }
            .buttonStyle(.plain)
            TextField("Nom de l'article", text: $item.name)
                .foregroundStyle(item.include ? Color.primary : Color.secondary)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.price(item.price, currency)).monospacedDigit()
                if item.quantity > 1 {
                    Text("× \(item.quantity)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
