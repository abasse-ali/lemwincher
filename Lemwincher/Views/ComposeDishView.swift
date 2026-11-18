import SwiftUI

/// « Composer » : on choisit un féculent, une protéine, des légumes et une saveur ;
/// l'app en fait une recette complète (ingrédients, étapes, durée, courses).
struct ComposeDishView: View {
    @Environment(AppModel.self) private var model
    @State private var base: DishPart? = DishComposer.bases.first
    @State private var protein: DishPart? = DishComposer.proteins.first
    @State private var vegetables: [DishPart] = Array(DishComposer.vegetables.prefix(2))
    @State private var flavor: DishPart? = DishComposer.flavors.first
    @State private var rolls = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        let vegetarian = model.settings.vegetarian
        let usableProtein = (vegetarian && protein?.isVegetarian == false) ? nil : protein
        let recipe = DishComposer.compose(base: base, protein: usableProtein, vegetables: vegetables,
                                          flavor: flavor, servings: 1)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                resultCard(recipe)

                Button {
                    var rng = SystemRandomNumberGenerator()
                    let idea = DishComposer.surprise(vegetarian: vegetarian, using: &rng)
                    withAnimation(.snappy) {
                        base = idea.base
                        protein = idea.protein
                        vegetables = idea.vegetables
                        flavor = idea.flavor
                        rolls += 1
                    }
                } label: {
                    Label("Surprenez-moi", systemImage: "dice.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(Color.brand)
                .sensoryFeedback(.impact, trigger: rolls)
                .accessibilityIdentifier("surpriseDish")

                partGrid(.base, parts: DishComposer.parts(.base), selected: base.map { [$0] } ?? []) { part in
                    base = base == part ? nil : part
                }
                partGrid(.protein, parts: DishComposer.parts(.protein, vegetarian: vegetarian),
                         selected: usableProtein.map { [$0] } ?? []) { part in
                    protein = protein == part ? nil : part
                }
                partGrid(.vegetable, parts: DishComposer.parts(.vegetable), selected: vegetables,
                         hint: "jusqu'à 4") { part in
                    if let index = vegetables.firstIndex(of: part) {
                        vegetables.remove(at: index)
                    } else if vegetables.count < 4 {
                        vegetables.append(part)
                    }
                }
                partGrid(.flavor, parts: DishComposer.parts(.flavor), selected: flavor.map { [$0] } ?? []) { part in
                    flavor = flavor == part ? nil : part
                }
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func resultCard(_ recipe: Recipe?) -> some View {
        if let recipe {
            NavigationLink(value: recipe) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(recipe.emoji).font(.system(size: 48))
                        Spacer()
                        Label(RecipeFormat.duration(recipe.minutes), systemImage: "clock")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                    Text("Votre plat")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .opacity(0.85)
                    Text(recipe.name)
                        .font(.title3.bold())
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Voir la recette, les quantités et les prix")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.top, 2)
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RecipeCourse.main.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("composedDish")
        } else {
            ContentUnavailableView("Composez votre plat", systemImage: "frying.pan",
                                   description: Text("Choisissez au moins un élément ci-dessous."))
        }
    }

    private func partGrid(_ kind: DishPart.Kind, parts: [DishPart], selected: [DishPart], hint: String? = nil,
                          toggle: @escaping (DishPart) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title).font(.title3.bold())
                if let hint {
                    Text(hint).font(.footnote).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(parts) { part in
                    let isOn = selected.contains(part)
                    Button {
                        withAnimation(.snappy) { toggle(part) }
                    } label: {
                        VStack(spacing: 6) {
                            Text(part.emoji).font(.system(size: 30))
                            Text(part.name)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .background(isOn ? Color.brand.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isOn ? Color.brand : Color.clear, lineWidth: 2)
                        }
                        .overlay(alignment: .topTrailing) {
                            if isOn {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.brand)
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(part.name)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }
}

/// « Menu » : les plats de la semaine, une autre idée pour un jour, et toutes les courses en un geste.
struct WeekMenuView: View {
    @Environment(AppModel.self) private var model
    @State private var count = 5
    @State private var cheapFirst = true
    @State private var message: String?

    var body: some View {
        let menu = model.weekMenu
        let missing = RecipeEngine.shoppingNames(for: menu, listNames: model.listNames)

        List {
            Section {
                Stepper(value: $count, in: 2...7) {
                    Label("\(count) repas", systemImage: "calendar")
                }
                Toggle(isOn: $cheapFirst) {
                    Label("Économiques d'abord", systemImage: "eurosign.circle")
                }
                .tint(Color.brand)
                Button {
                    generate()
                } label: {
                    Label(menu.isEmpty ? "Proposer un menu" : "Proposer un autre menu", systemImage: "sparkles")
                        .font(.headline)
                }
                .accessibilityIdentifier("generateMenu")
            } footer: {
                Text("Des plats variés (poulet, bœuf, poisson, œufs, légumineuses…), \(model.settings.noPork ? "sans porc, " : "")pour \(model.settings.defaultServings) personne\(model.settings.defaultServings > 1 ? "s" : "") par défaut.")
            }

            if !menu.isEmpty {
                Section {
                    ForEach(Array(menu.enumerated()), id: \.element.id) { index, recipe in
                        NavigationLink(value: recipe) {
                            HStack(spacing: 12) {
                                VStack(spacing: 0) {
                                    Text(dayName(index))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.brand)
                                        .textCase(.uppercase)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(width: 58, alignment: .leading)
                                RecipeEmojiBadge(emoji: recipe.emoji, course: recipe.course, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(RecipeFormat.duration(recipe.minutes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                replace(recipe)
                            } label: {
                                Label("Autre idée", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(Color.brand)
                        }
                    }
                } header: {
                    Text("Votre semaine")
                } footer: {
                    Text("Glissez un plat vers la gauche pour une autre idée.")
                }

                Section {
                    Button {
                        let added = model.addIngredients(missing)
                        message = added == 0 ? "Tout est déjà dans votre liste." : "\(added) article\(added > 1 ? "s" : "") ajouté\(added > 1 ? "s" : "") à Ma liste."
                    } label: {
                        Label(missing.isEmpty ? "Tout est déjà dans votre liste"
                                              : "Ajouter les courses de la semaine (\(missing.count) articles)",
                              systemImage: "cart.badge.plus")
                            .font(.headline)
                    }
                    .disabled(missing.isEmpty)
                    .accessibilityIdentifier("addWeekShopping")
                    if let message {
                        HStack {
                            Label(message, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.brand)
                            Spacer()
                            Button("Voir ma liste") { model.selectedTab = .list }
                                .buttonStyle(.borderless)
                        }
                        .font(.subheadline)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView("Pas encore de menu", systemImage: "calendar.badge.plus",
                                           description: Text("Touchez « Proposer un menu » : l'app choisit des plats variés et prépare la liste de courses."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .sensoryFeedback(.success, trigger: message)
    }

    private func generate() {
        var rng = SystemRandomNumberGenerator()
        let menu = RecipeEngine.weekMenu(from: model.recipes, count: count, cheapFirst: cheapFirst, using: &rng)
        withAnimation(.snappy) {
            model.state.weekMenu = menu.map(\.id)
            message = nil
        }
    }

    private func replace(_ recipe: Recipe) {
        var rng = SystemRandomNumberGenerator()
        let menu = model.weekMenu
        guard let other = RecipeEngine.replacement(for: recipe, in: menu, from: model.recipes, using: &rng),
              let index = model.state.weekMenu.firstIndex(of: recipe.id) else { return }
        withAnimation(.snappy) {
            model.state.weekMenu[index] = other.id
        }
    }

    /// « Aujourd'hui », « Demain », puis « Samedi »…
    private func dayName(_ offset: Int) -> String {
        if offset == 0 { return "Ce soir" }
        if offset == 1 { return "Demain" }
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR"))).capitalized
    }
}
