import SwiftUI
import Charts

/// Écrans ouverts depuis l'onglet Budget.
enum BudgetRoute: Hashable {
    case myPrices
}

/// Onglet "Budget" : budget courses du mois, dépenses, conseils, et mes relevés de prix.
struct BudgetView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddExpense = false
    @State private var editing: Expense? = nil
    @State private var showReceipt = false
    @State private var showAddPrice = false
    @State private var showSettings = false
    @State private var showDriveCapture = false

    var body: some View {
        let summary = model.budgetSummary
        let currency = model.settings.currency
        NavigationStack {
            List {
                Section {
                    // Carte héros : anneau du mois, reste à dépenser, rythme par jour.
                    HeroCard(tint: summary.status == .ok ? .brand : (summary.status == .warning ? .orange : .red)) {
                        BudgetGauge(summary: summary, currency: currency, onHero: true)
                    }
                    .accessibilityIdentifier("budgetGauge")
                    .clearListRow(top: 4, bottom: 10)
                    Button {
                        showAddExpense = true
                    } label: {
                        Label("Ajouter une dépense", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .primaryGlassButton()
                    .accessibilityIdentifier("addExpenseButton")
                    .clearListRow(top: 0, bottom: 4)
                }

                if let tip = model.savingsTip {
                    Section {
                        Label {
                            Text("En faisant ces courses chez \(tip.chainName) (\(tip.difference) par rapport à la moyenne), vous auriez économisé environ \(Fmt.price(tip.saving, currency)) ce mois-ci.")
                        } icon: {
                            Image(systemName: "lightbulb.fill").foregroundStyle(Color.yellow)
                        }
                    } footer: {
                        if let store = tip.storeName {
                            Text("Le plus proche : \(store). Estimation d'après le classement des enseignes.")
                        }
                    }
                }

                Section {
                    BudgetChart(points: BudgetEngine.cumulative(summary), budget: summary.budget, currency: currency)
                        .padding(.vertical, 6)
                } header: {
                    Text("Au fil du mois")
                } footer: {
                    Text("En vert vos dépenses cumulées, en pointillés le rythme à suivre pour finir le mois à \(Fmt.price(summary.budget, currency)).")
                }

                expensesSection(summary: summary, currency: currency)

                breakdownSection(summary: summary, currency: currency)

                historySection(currency: currency)

                Section {
                    // Lien « par valeur » : les fiches produit ouvertes depuis Mes prix restent ouvertes
                    // (avec un lien « par vue », la pile revenait en arrière quand la fiche mettait l'app à jour).
                    NavigationLink(value: BudgetRoute.myPrices) {
                        HStack {
                            Label("Mes relevés de prix", systemImage: "tag.fill")
                            Spacer()
                            Text("\(model.state.myPrices.count)").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("myPricesLink")
                } footer: {
                    Text("Les prix que vous relevez en magasin, leur évolution, et l'export CSV.")
                }
            }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Réglages du budget")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddExpense = true
                        } label: {
                            Label("Ajouter une dépense", systemImage: "eurosign.circle")
                        }
                        Button {
                            showReceipt = true
                        } label: {
                            Label("Scanner un ticket de caisse", systemImage: "doc.text.viewfinder")
                        }
                        Button {
                            showAddPrice = true
                        } label: {
                            Label("Relever un prix", systemImage: "tag")
                        }
                        Button {
                            showDriveCapture = true
                        } label: {
                            Label("Relever des prix sur un site drive", systemImage: "safari")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddExpense) {
                ExpenseEditor(expense: nil)
            }
            .sheet(item: $editing) { expense in
                ExpenseEditor(expense: expense)
            }
            .sheet(isPresented: $showReceipt) {
                ReceiptScanView()
            }
            .sheet(isPresented: $showAddPrice) {
                AddPriceView()
            }
            .sheet(isPresented: $showSettings) {
                BudgetSettingsView()
            }
            .sheet(isPresented: $showDriveCapture) {
                DriveCaptureView(query: "")
            }
            .alert("Budget", isPresented: Binding(
                get: { model.budgetAlert != nil },
                set: { if !$0 { model.budgetAlert = nil } }
            )) {
                Button("OK") { model.budgetAlert = nil }
            } message: {
                Text(model.budgetAlert ?? "")
            }
            .appDestinations()
            .navigationDestination(for: BudgetRoute.self) { route in
                switch route {
                case .myPrices: MyPricesContent()
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func expensesSection(summary: BudgetSummary, currency: String) -> some View {
        Section {
            if summary.expenses.isEmpty {
                Text("Aucune dépense ce mois-ci. Après vos courses, touchez « Ajouter une dépense », photographiez le ticket, ou utilisez « J'ai fait mes courses » dans Ma liste.")
                    .foregroundStyle(.secondary)
            }
            ForEach(summary.expenses) { expense in
                Button {
                    editing = expense
                } label: {
                    ExpenseRow(expense: expense, currency: currency)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let ids = Set(offsets.map { summary.expenses[$0].id })
                model.deleteExpenses(ids: ids)
            }
        } header: {
            Text("Dépenses du \(summary.period.start.formatted(.dateTime.day().month())) au \(lastDay(summary).formatted(.dateTime.day().month()))")
        } footer: {
            if !summary.expenses.isEmpty {
                Text("Touchez une dépense pour la modifier, balayez vers la gauche pour la supprimer.")
            }
        }
    }

    @ViewBuilder
    private func breakdownSection(summary: BudgetSummary, currency: String) -> some View {
        let byStore = BudgetEngine.shares(summary.expenses) { $0.storeName ?? "Sans magasin" }
        let byCategory = BudgetEngine.shares(summary.expenses) { $0.category.label }
        if byStore.count > 1 {
            Section("Par magasin") {
                ForEach(byStore.prefix(5)) { share in
                    ShareBar(share: share, currency: currency, icon: "storefront")
                }
            }
        }
        if byCategory.count > 1 {
            Section("Par catégorie") {
                ForEach(byCategory) { share in
                    ShareBar(share: share, currency: currency,
                             icon: ExpenseCategory.allCases.first { $0.label == share.name }?.icon ?? "circle")
                }
            }
        }
    }

    @ViewBuilder
    private func historySection(currency: String) -> some View {
        let history = BudgetEngine.history(expenses: model.state.expenses,
                                           startDay: model.settings.budgetStartDay,
                                           count: 6)
        if history.filter({ $0.total > 0 }).count >= 2 {
            Section {
                BudgetHistoryChart(history: history, budget: model.settings.budgetAmount)
                    .padding(.vertical, 6)
            } header: {
                Text("Mois précédents")
            } footer: {
                let past = history.dropLast().filter { $0.total > 0 }
                if !past.isEmpty {
                    let average = past.reduce(0) { $0 + $1.total } / Double(past.count)
                    Text("Moyenne des mois précédents : \(Fmt.price(average, currency)).")
                }
            }
        }
    }

    private func lastDay(_ summary: BudgetSummary) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: summary.period.end) ?? summary.period.end
    }
}

// MARK: - Jauge

struct BudgetGauge: View {
    let summary: BudgetSummary
    let currency: String
    /// Sur une carte héros (fond coloré) : anneau et chiffres en blanc.
    var onHero = false

    private var color: Color {
        if onHero { return .white }
        switch summary.status {
        case .ok: return Color.brand
        case .warning: return Color.orange
        case .over: return Color.red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(onHero ? Color.white.opacity(0.22) : Color(.tertiarySystemFill), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: min(summary.fraction, 1))
                        .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: onHero ? .black.opacity(0.18) : .clear, radius: 4)
                        .animation(.smooth(duration: 0.6), value: summary.fraction)
                    VStack(spacing: 0) {
                        Text("\(Int((summary.fraction * 100).rounded())) %")
                            .font(.title3.bold().monospacedDigit())
                            .contentTransition(.numericText(value: summary.fraction))
                        Text("dépensé").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.remaining >= 0 ? "Il reste" : "Dépassement")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Fmt.price(abs(summary.remaining), currency))
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(color)
                        .contentTransition(.numericText(value: summary.remaining))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(Fmt.price(summary.spent, currency)) sur \(Fmt.price(summary.budget, currency))")
                        .font(.subheadline.monospacedDigit())
                    Text(daysText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(summary.message(currency: currency))
                .font(.footnote)
                .foregroundStyle(onHero || summary.status == .ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
        }
        .padding(.vertical, 6)
    }

    private var daysText: String {
        let days = summary.daysLeft
        let plural = days > 1 ? "s" : ""
        guard summary.remaining > 0 else { return "\(days) jour\(plural) restant\(plural)" }
        return "\(days) jour\(plural) restant\(plural) · \(Fmt.price(summary.dailyAllowance, currency)) par jour"
    }
}

// MARK: - Graphiques

struct BudgetChart: View {
    let points: [BudgetPoint]
    let budget: Double
    let currency: String

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Jour", point.date),
                         y: .value("Montant", point.amount))
                    .foregroundStyle(by: .value("Courbe", point.series))
                    .lineStyle(point.series == "Rythme idéal" ? StrokeStyle(lineWidth: 1.5, dash: [5, 4]) : StrokeStyle(lineWidth: 3))
                    .interpolationMethod(point.series == "Rythme idéal" ? InterpolationMethod.linear : InterpolationMethod.stepEnd)
            }
            RuleMark(y: .value("Budget", budget))
                .foregroundStyle(Color.red.opacity(0.6))
                .annotation(position: .top, alignment: .leading) {
                    Text("Budget \(Fmt.price(budget, currency))")
                        .font(.caption2)
                        .foregroundStyle(Color.red)
                }
        }
        .chartForegroundStyleScale(["Dépensé": Color.brand, "Rythme idéal": Color.gray])
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 200)
    }
}

struct BudgetHistoryChart: View {
    let history: [PeriodTotal]
    let budget: Double

    var body: some View {
        Chart {
            ForEach(history) { item in
                BarMark(x: .value("Mois", item.period.start, unit: .month),
                        y: .value("Dépensé", item.total))
                    .foregroundStyle(item.total > budget ? Color.red : Color.brand)
                    .cornerRadius(4)
            }
            RuleMark(y: .value("Budget", budget))
                .foregroundStyle(Color.red.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(height: 160)
    }
}

// MARK: - Lignes

struct ExpenseRow: View {
    let expense: Expense
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.icon)
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Color.brand.opacity(0.85), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.storeName ?? expense.category.label).lineLimit(1)
                Text(Fmt.join(Fmt.day(expense.date),
                              expense.itemCount.map { "\($0) article\($0 > 1 ? "s" : "")" },
                              expense.note))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Fmt.price(expense.amount, currency))
                .font(.headline.monospacedDigit())
        }
        .contentShape(Rectangle())
    }
}

struct ShareBar: View {
    let share: SpendingShare
    let currency: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(share.name, systemImage: icon).lineLimit(1)
                Spacer()
                Text(Fmt.price(share.total, currency)).monospacedDigit()
                Text("\(Int((share.fraction * 100).rounded())) %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.subheadline)
            GeometryReader { proxy in
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.brand)
                            .frame(width: max(4, proxy.size.width * share.fraction))
                    }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Saisie d'une dépense

struct ExpenseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let original: Expense?
    private let prefill: Expense?
    private let initialStoreID: String
    /// Appelé après l'enregistrement (ex. retirer les produits cochés de la liste).
    private let onSaved: (() -> Void)?
    private let clearOptionLabel: String?

    @State private var amountText: String
    @State private var date: Date
    @State private var storeID: String
    @State private var category: ExpenseCategory
    @State private var note: String
    @State private var itemCount: Int?
    @State private var applyAfterSave = true

    init(expense: Expense?, prefill: Expense? = nil, clearOptionLabel: String? = nil, onSaved: (() -> Void)? = nil) {
        original = expense
        self.prefill = prefill
        self.onSaved = onSaved
        self.clearOptionLabel = clearOptionLabel
        let source = expense ?? prefill
        let amount = source.map { String(format: "%.2f", $0.amount).replacingOccurrences(of: ".", with: ",") } ?? ""
        _amountText = State(initialValue: (source?.amount ?? 0) > 0 ? amount : "")
        _date = State(initialValue: source?.date ?? Date())
        _storeID = State(initialValue: source?.storeID ?? "")
        initialStoreID = source?.storeID ?? ""
        _category = State(initialValue: source?.category ?? .groceries)
        _note = State(initialValue: source?.note ?? "")
        _itemCount = State(initialValue: source?.itemCount)
    }

    private var amount: Double? {
        let value = Double(amountText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
        guard let value, value > 0 else { return nil }
        return value
    }

    private var storeChoices: [Store] { model.storesByDistance() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.largeTitle.bold().monospacedDigit())
                            .accessibilityIdentifier("expenseAmount")
                        Text(model.settings.currency).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Montant")
                } footer: {
                    let summary = model.budgetSummary
                    if let amount, original == nil {
                        let left = summary.remaining - amount
                        Text(left >= 0
                             ? "Après cette dépense, il restera \(Fmt.price(left, model.settings.currency)) ce mois-ci."
                             : "Cette dépense dépasse le budget du mois de \(Fmt.price(-left, model.settings.currency)).")
                    }
                }

                Section {
                    Picker("Catégorie", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.label, systemImage: category.icon).tag(category)
                        }
                    }
                    Picker("Magasin", selection: $storeID) {
                        Text("Aucun").tag("")
                        ForEach(storeChoices) { store in
                            Text(store.name).tag(store.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Note (facultatif)", text: $note)
                }

                if let clearOptionLabel {
                    Section {
                        Toggle(clearOptionLabel, isOn: $applyAfterSave)
                    }
                }

                if original != nil {
                    Section {
                        Button("Supprimer cette dépense", role: .destructive) {
                            if let original { model.deleteExpenses(ids: [original.id]) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "Nouvelle dépense" : "Modifier la dépense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(amount == nil)
                }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let store = storeChoices.first { $0.id == storeID }
        var expense = original ?? prefill ?? Expense(amount: amount, date: date)
        expense.amount = amount
        expense.date = date
        expense.category = category
        if let store {
            expense.storeID = store.id
            expense.storeName = store.name
            expense.chainKey = store.chainKey
        } else if storeID.isEmpty && !initialStoreID.isEmpty {
            // L'utilisateur a choisi « Aucun » magasin.
            expense.storeID = nil
            expense.storeName = nil
            expense.chainKey = nil
        }
        expense.note = note.nilIfBlank?.trimmed
        expense.itemCount = itemCount
        if original == nil {
            model.addExpense(expense)
            if applyAfterSave { onSaved?() }
        } else {
            model.updateExpense(expense)
        }
        dismiss()
    }
}

// MARK: - Réglages du budget

struct BudgetSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

    var body: some View {
        @Bindable var bindable = model
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("100", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold().monospacedDigit())
                            .onChange(of: amountText) { _, text in
                                if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 {
                                    model.state.settings.budgetAmount = value
                                }
                            }
                        Text("\(model.settings.currency) par mois").foregroundStyle(.secondary)
                    }
                    HStack {
                        ForEach([100.0, 150, 200, 300], id: \.self) { value in
                            Button(Fmt.price(value, model.settings.currency)) {
                                amountText = String(format: "%.0f", value)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Budget courses")
                }

                Section {
                    Picker("Le budget repart le", selection: $bindable.state.settings.budgetStartDay) {
                        ForEach(1...28, id: \.self) { day in
                            Text(day == 1 ? "1er du mois" : "\(day) du mois").tag(day)
                        }
                    }
                    Toggle("Me prévenir à 80 % et à 100 %", isOn: $bindable.state.settings.budgetAlerts)
                } footer: {
                    Text("Choisissez par exemple le jour où vous recevez votre salaire. Les alertes arrivent dès qu'une dépense fait franchir le seuil.")
                }
            }
            .navigationTitle("Réglages du budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .onAppear {
                amountText = String(format: "%.0f", model.settings.budgetAmount)
            }
        }
    }
}
