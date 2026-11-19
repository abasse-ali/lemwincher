import SwiftUI

/// Ouverture de l'éditeur : nouvelle recette (ou copie à personnaliser) ou modification d'une des miennes.
struct MyRecipeEditorRequest: Identifiable {
    let id = UUID()
    let recipe: MyRecipe
    let isNew: Bool
}

/// Écrire ou modifier une de mes recettes : nom, image, type, durée, personnes, ingrédients et étapes.
/// Une recette copiée (site, note, message) peut être collée : l'app en remplit les ingrédients et les étapes.
struct MyRecipeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let original: MyRecipe
    private let isNew: Bool
    private let onSaved: (MyRecipe) -> Void

    @State private var name: String
    @State private var emoji: String
    @State private var summary: String
    @State private var course: RecipeCourse
    @State private var minutes: Int
    @State private var servings: Int
    @State private var tags: Set<RecipeTag>
    @State private var ingredients: [IngredientDraft]
    @State private var steps: [StepDraft]
    @State private var showImport = false
    @State private var confirmCancel = false
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case name
        case ingredient(UUID)
        case step(UUID)
    }

    /// Ligne d'ingrédient en cours d'écriture (quantité en texte : « 1,5 », « ½ »).
    struct IngredientDraft: Identifiable, Equatable {
        var id = UUID()
        var name = ""
        var quantity = ""
        var unit = ""
        var pantry = false
        var shopping: String? = nil
    }

    struct StepDraft: Identifiable, Equatable {
        var id = UUID()
        var text = ""
    }

    /// Images proposées pour une recette.
    static let emojis = ["🍽️", "🍝", "🍲", "🥘", "🍛", "🍜", "🍗", "🥩", "🍖", "🐟", "🦐", "🍳", "🥚", "🥗", "🥙",
                         "🌮", "🌯", "🍕", "🥪", "🍔", "🥧", "🍚", "🥟", "🫕", "🥦", "🥕", "🍅", "🥔", "🍄", "🧀",
                         "🥞", "🧇", "🥐", "🍰", "🎂", "🍮", "🍪", "🍫", "🍎", "🍓", "🍋", "🥤", "☕️"]

    init(recipe: MyRecipe, isNew: Bool, onSaved: @escaping (MyRecipe) -> Void = { _ in }) {
        original = recipe
        self.isNew = isNew
        self.onSaved = onSaved
        _name = State(initialValue: recipe.name)
        _emoji = State(initialValue: recipe.emoji)
        _summary = State(initialValue: recipe.summary)
        _course = State(initialValue: recipe.course)
        _minutes = State(initialValue: recipe.minutes)
        _servings = State(initialValue: recipe.servings)
        _tags = State(initialValue: Set(recipe.tags))
        _ingredients = State(initialValue: recipe.ingredients.map(Self.draft(from:)))
        _steps = State(initialValue: recipe.steps.map { StepDraft(text: $0) })
    }

    private static func draft(from item: MyIngredient) -> IngredientDraft {
        let shown = MyIngredient.editable(item.quantity, unit: item.unit)
        return IngredientDraft(name: item.name, quantity: shown.text, unit: shown.unit, pantry: item.pantry,
                               shopping: item.shopping)
    }

    /// La recette telle qu'elle serait enregistrée.
    private var built: MyRecipe {
        var recipe = original
        recipe.name = name.trimmed
        recipe.emoji = emoji.trimmed.nilIfBlank ?? "🍽️"
        recipe.summary = summary.trimmed
        recipe.course = course
        recipe.minutes = minutes
        recipe.servings = servings
        recipe.tags = RecipeTag.allCases.filter { tags.contains($0) }
        recipe.ingredients = ingredients.compactMap { draft in
            let name = draft.name.trimmed
            guard !name.isEmpty else { return nil }
            let quantity = MyIngredient.parseQuantity(draft.quantity)
            return MyIngredient(name: name, quantity: quantity, unit: quantity == nil ? "" : draft.unit,
                                shopping: draft.shopping, pantry: draft.pantry)
        }
        recipe.steps = steps.map { $0.text.trimmed }.filter { !$0.isEmpty }
        return recipe
    }

    private var hasChanges: Bool { built.contentSignature != original.contentSignature }

    var body: some View {
        NavigationStack {
            Form {
                if isNew { importSection }
                headerSection
                detailsSection
                ingredientsSection
                stepsSection
                if !isNew { importSection }
            }
            .navigationTitle(isNew ? "Nouvelle recette" : "Modifier la recette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if hasChanges { confirmCancel = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmed.isEmpty)
                        .accessibilityIdentifier("saveMyRecipe")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focus = nil }
                }
            }
            .confirmationDialog("Abandonner cette recette ?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Abandonner les modifications", role: .destructive) { dismiss() }
                Button("Continuer à écrire", role: .cancel) {}
            }
            .interactiveDismissDisabled(hasChanges)
            .sheet(isPresented: $showImport) {
                RecipeImportSheet { result in apply(result) }
            }
        }
    }

    // MARK: Sections

    private var importSection: some View {
        Section {
            Button {
                showImport = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coller une recette").font(.headline).foregroundStyle(.primary)
                        Text("Copiée d'un site, d'une note ou d'un message : l'app remplit les ingrédients et les étapes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("importRecipeText")
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                RecipeEmojiBadge(emoji: emoji.trimmed.nilIfBlank ?? "🍽️", course: course, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nom de la recette", text: $name, axis: .vertical)
                        .font(.title3.bold())
                        .lineLimit(1...3)
                        .focused($focus, equals: .name)
                        .accessibilityIdentifier("myRecipeName")
                    TextField("Une phrase pour donner envie (facultatif)", text: $summary, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...3)
                }
            }
            .padding(.vertical, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Self.emojis, id: \.self) { item in
                        Button {
                            emoji = item
                        } label: {
                            Text(item)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(emoji == item ? Color.brand.opacity(0.25) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Image \(item)")
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
        } footer: {
            Text("Touchez une image pour votre recette.")
        }
    }

    private var detailsSection: some View {
        Section {
            Picker("Type de plat", selection: $course) {
                ForEach(RecipeCourse.allCases) { item in
                    Text(item == .breakfast ? "Petit-déj" : item.singular).tag(item)
                }
            }
            .pickerStyle(.segmented)
            Stepper(value: $minutes, in: 5...600, step: 5) {
                Label("Durée : \(RecipeFormat.duration(minutes))", systemImage: "clock")
            }
            Stepper(value: $servings, in: 1...12) {
                Label("Pour \(servings) personne\(servings > 1 ? "s" : "")", systemImage: "person.2")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(RecipeTag.allCases, id: \.self) { tag in
                            GlassChip(title: tag.label, selected: tags.contains(tag)) {
                                if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } footer: {
            Text("Les quantités sont écrites pour \(servings) personne\(servings > 1 ? "s" : "") : l'app les recalcule pour 1, 2, 4 ou 6.")
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach($ingredients) { $item in
                IngredientEditorRow(item: $item, focus: $focus)
            }
            .onDelete { ingredients.remove(atOffsets: $0) }
            .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }
            Button {
                let draft = IngredientDraft()
                ingredients.append(draft)
                focus = .ingredient(draft.id)
            } label: {
                Label("Ajouter un ingrédient", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("addIngredient")
        } header: {
            HStack {
                Text("Ingrédients (\(ingredients.filter { !$0.name.trimmed.isEmpty }.count))")
                Spacer()
                EditButton()
                    .font(.caption.weight(.semibold))
                    .textCase(nil)
            }
        } footer: {
            Text("« Placard » : déjà à la maison (sel, huile…), pas ajouté à la liste de courses. Sans quantité : « à votre goût ». Glissez une ligne vers la gauche pour la supprimer ; « Modifier » pour changer l'ordre.")
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach($steps) { $step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\((steps.firstIndex { $0.id == step.id } ?? 0) + 1)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.brand)
                        .frame(width: 26, height: 26)
                        .background(Color.brand.opacity(0.14), in: Circle())
                    TextField("Décrivez l'étape (ex. : faites cuire 20 min)", text: $step.text, axis: .vertical)
                        .lineLimit(2...8)
                        .focused($focus, equals: .step(step.id))
                        .accessibilityIdentifier("stepText")
                }
                .padding(.vertical, 2)
            }
            .onDelete { steps.remove(atOffsets: $0) }
            .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            Button {
                let draft = StepDraft()
                steps.append(draft)
                focus = .step(draft.id)
            } label: {
                Label("Ajouter une étape", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("addStep")
        } header: {
            HStack {
                Text("Étapes (\(steps.filter { !$0.text.trimmed.isEmpty }.count))")
                Spacer()
                EditButton()
                    .font(.caption.weight(.semibold))
                    .textCase(nil)
            }
        } footer: {
            Text("Écrivez les durées (« cuire 20 min ») : en mode cuisine, un minuteur vous sera proposé à cette étape.")
        }
    }

    // MARK: Actions

    /// Remplit la recette avec ce qui a été lu dans le texte collé (sans effacer ce qui est déjà écrit).
    private func apply(_ result: RecipeTextParser.Result) {
        if let parsed = result.name, name.trimmed.isEmpty {
            name = parsed
            if emoji == "🍽️", let guess = ProductEmoji.emoji(for: parsed) { emoji = guess }
        }
        if let people = result.servings { servings = min(max(people, 1), 12) }
        if let total = result.minutes { minutes = min(max((total + 4) / 5 * 5, 5), 600) }
        if !result.ingredients.isEmpty {
            ingredients = ingredients.filter { !$0.name.trimmed.isEmpty } + result.ingredients.map(Self.draft(from:))
        }
        if !result.steps.isEmpty {
            steps = steps.filter { !$0.text.trimmed.isEmpty } + result.steps.map { StepDraft(text: $0) }
        }
    }

    private func save() {
        let recipe = built
        model.saveMyRecipe(recipe)
        onSaved(recipe)
        dismiss()
    }
}

/// Une ligne d'ingrédient : nom, quantité, unité, « placard ».
private struct IngredientEditorRow: View {
    @Binding var item: MyRecipeEditor.IngredientDraft
    var focus: FocusState<MyRecipeEditor.Field?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ingrédient (ex. : Farine)", text: $item.name)
                .focused(focus, equals: .ingredient(item.id))
                .accessibilityIdentifier("ingredientName")
            HStack(spacing: 8) {
                TextField("Qté", text: $item.quantity)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Quantité")
                Picker("Unité", selection: $item.unit) {
                    ForEach(MyIngredient.units, id: \.self) { unit in
                        Text(MyIngredient.unitLabel(unit)).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                Toggle(isOn: $item.pantry) {
                    Label("Placard", systemImage: "cabinet")
                        .labelStyle(.titleAndIcon)
                }
                .toggleStyle(.button)
                .font(.caption.weight(.semibold))
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }
}

/// Coller une recette (texte d'un site, d'une note…) et voir ce que l'app en a compris.
private struct RecipeImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: (RecipeTextParser.Result) -> Void
    @State private var text = ""

    var body: some View {
        let result = RecipeTextParser.parse(text)
        NavigationStack {
            Form {
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.joined(separator: "\n")
                    }
                    .tint(Color.brand)
                    TextEditor(text: $text)
                        .font(.callout)
                        .frame(minHeight: 220)
                        .accessibilityIdentifier("importRecipeTextField")
                } footer: {
                    Text("Collez le texte d'une recette. Les lignes « 200 g de farine » ou « 2 œufs » deviennent des ingrédients ; les phrases (« 1. Préchauffez le four… ») deviennent des étapes.")
                }
                if !text.trimmed.isEmpty {
                    Section("Ce que l'app a compris") {
                        LabeledContent("Nom", value: result.name ?? "—")
                        LabeledContent("Personnes", value: result.servings.map(String.init) ?? "—")
                        LabeledContent("Durée", value: result.minutes.map { RecipeFormat.duration($0) } ?? "—")
                        LabeledContent("Ingrédients", value: "\(result.ingredients.count)")
                        LabeledContent("Étapes", value: "\(result.steps.count)")
                    }
                }
            }
            .navigationTitle("Coller une recette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remplir") {
                        onImport(result)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(result.isEmpty)
                    .accessibilityIdentifier("applyImport")
                }
            }
        }
    }
}
