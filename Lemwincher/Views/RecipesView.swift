import SwiftUI

/// Onglet « Recettes » : idées (selon votre liste), composer un plat, menu de la semaine.
struct RecipesView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case ideas = "Idées"
        case compose = "Composer"
        case week = "Menu"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .ideas
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .ideas: RecipeIdeasView()
                case .compose: ComposeDishView()
                case .week: WeekMenuView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Affichage", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityIdentifier("recipesMode")
            }
            .navigationTitle("Recettes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .topBarTrailing) { DietMenu() }
            }
            .appDestinations()
        }
    }
}

// MARK: - Idées

struct RecipeIdeasView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter: IdeaFilter = .all

    enum IdeaFilter: Hashable, Identifiable {
        case all, course(RecipeCourse), quick, cheap, vegetarian, favorites

        var id: String { label }

        var label: String {
            switch self {
            case .all: return "Tout"
            case .course(let course): return course.label
            case .quick: return "≤ 20 min"
            case .cheap: return "Économique"
            case .vegetarian: return "Végétarien"
            case .favorites: return "Favoris"
            }
        }

        var symbol: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .course(.main): return "fork.knife"
            case .course(.starter): return "leaf"
            case .course(.dessert): return "birthday.cake"
            case .course(.breakfast): return "sun.max"
            case .quick: return "bolt"
            case .cheap: return "eurosign.circle"
            case .vegetarian: return "carrot"
            case .favorites: return "star"
            }
        }

        static let choices: [IdeaFilter] = [.all, .course(.main), .course(.starter), .course(.dessert),
                                             .course(.breakfast), .quick, .cheap, .vegetarian, .favorites]
    }

    var body: some View {
        let recipes = model.recipes
        let listNames = model.listNames
        let fromList = Array(RecipeEngine.suggested(recipes, listNames: listNames).prefix(8))
        let shown = filtered(RecipeEngine.search(recipes, query: query))

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if query.trimmed.isEmpty {
                    DietBanner()
                    if !fromList.isEmpty {
                        RecipeCarousel(title: "Avec ce qu'il y a dans votre liste",
                                       subtitle: "Les recettes qui utilisent le plus d'articles de « Ma liste ».",
                                       recipes: fromList, listNames: listNames)
                    } else {
                        RecipeCarousel(title: "Idées du jour",
                                       subtitle: "Ajoutez des articles à « Ma liste » : l'app vous proposera des recettes avec.",
                                       recipes: dailyPicks(recipes), listNames: listNames)
                    }
                }
                filterChips
                Text(shown.count == 1 ? "1 recette" : "\(shown.count) recettes")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(shown) { recipe in
                    NavigationLink(value: recipe) {
                        RecipeCard(recipe: recipe,
                                   have: RecipeEngine.matchCount(recipe, listNames: listNames),
                                   favorite: model.isFavorite(recipe: recipe.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recipeCard")
                }
                if shown.isEmpty {
                    ContentUnavailableView {
                        Label(filter == .favorites ? "Aucun favori" : "Aucune recette", systemImage: "fork.knife")
                    } description: {
                        Text(filter == .favorites
                             ? "Touchez ☆ en haut d'une recette pour la retrouver ici."
                             : "Essayez un autre mot, ou composez votre plat dans « Composer ».")
                    }
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $query, prompt: "Un plat ou un ingrédient (poulet, courgette…)")
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IdeaFilter.choices) { item in
                    Button {
                        withAnimation(.snappy) { filter = item }
                    } label: {
                        Label(item.label, systemImage: item.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(filter == item ? Color.brand : Color(.secondarySystemGroupedBackground),
                                        in: Capsule())
                            .foregroundStyle(filter == item ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func filtered(_ recipes: [Recipe]) -> [Recipe] {
        switch filter {
        case .all: return recipes
        case .course(let course): return recipes.filter { $0.course == course }
        case .quick: return recipes.filter(\.isQuick)
        case .cheap: return recipes.filter { $0.tags.contains(.cheap) }
        case .vegetarian: return recipes.filter(\.isVegetarian)
        case .favorites: return recipes.filter { model.isFavorite(recipe: $0.id) }
        }
    }

    /// Six plats qui changent chaque jour.
    private func dailyPicks(_ recipes: [Recipe]) -> [Recipe] {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var rng = SeededGenerator(seed: UInt64(day))
        return Array(recipes.filter { $0.course == .main }.shuffled(using: &rng).prefix(6))
    }
}

// MARK: - Composants

/// Couleurs des recettes selon le type de plat.
extension RecipeCourse {
    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .main: colors = [Color(red: 0.98, green: 0.55, blue: 0.24), Color(red: 0.89, green: 0.27, blue: 0.24)]
        case .starter: colors = [Color(red: 0.30, green: 0.78, blue: 0.47), Color(red: 0.09, green: 0.55, blue: 0.48)]
        case .dessert: colors = [Color(red: 0.96, green: 0.45, blue: 0.62), Color(red: 0.62, green: 0.32, blue: 0.85)]
        case .breakfast: colors = [Color(red: 1.00, green: 0.80, blue: 0.30), Color(red: 0.98, green: 0.55, blue: 0.24)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct RecipeEmojiBadge: View {
    let emoji: String
    let course: RecipeCourse
    var size: CGFloat = 64

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(course.gradient.opacity(0.9), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Petite pastille d'information (« ⏱ 35 min »).
struct InfoPill: View {
    let text: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

/// Recette dans la liste : badge, nom, phrase d'accroche, durée, et ce que vous avez déjà.
struct RecipeCard: View {
    let recipe: Recipe
    var have: Int = 0
    var favorite = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RecipeEmojiBadge(emoji: recipe.emoji, course: recipe.course)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(recipe.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(recipe.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // Pastilles qui passent à la ligne plutôt que d'être coupées.
                FlowLayout(spacing: 10) {
                    InfoPill(text: RecipeFormat.duration(recipe.minutes), symbol: "clock")
                    if recipe.isVegetarian {
                        InfoPill(text: "Végétarien", symbol: "leaf.fill", tint: .green)
                    } else if recipe.tags.contains(.cheap) {
                        InfoPill(text: "Économique", symbol: "eurosign.circle", tint: Color.brand)
                    }
                    if have > 0 {
                        InfoPill(text: "\(have)/\(recipe.shoppingIngredients.count) dans la liste",
                                 symbol: "cart.fill", tint: Color.brand)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Bandeau horizontal de grandes cartes colorées.
struct RecipeCarousel: View {
    let title: String
    let subtitle: String
    let recipes: [Recipe]
    let listNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeTile(recipe: recipe, have: RecipeEngine.matchCount(recipe, listNames: listNames))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

struct RecipeTile: View {
    let recipe: Recipe
    var have: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(recipe.emoji).font(.system(size: 44))
                Spacer()
                if have > 0 {
                    Text("\(have)/\(recipe.shoppingIngredients.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.25), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Text(recipe.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Label(RecipeFormat.duration(recipe.minutes), systemImage: "clock")
                .font(.caption.weight(.semibold))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 200, height: 170, alignment: .topLeading)
        .background(recipe.course.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

/// « Sans porc » / « Végétarien » : rappel de ce qui est filtré.
struct DietBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        if settings.noPork || settings.vegetarian {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.brand)
                Text([settings.noPork ? "Sans porc" : nil, settings.vegetarian ? "Végétarien" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                Text("· recettes et produits filtrés")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Menu « Mon alimentation » (en haut à droite de l'onglet Recettes).
struct DietMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var bindable = model
        Menu {
            Section("Mon alimentation") {
                Toggle("Sans porc", isOn: $bindable.state.settings.noPork)
                Toggle("Végétarien", isOn: $bindable.state.settings.vegetarian)
            }
            Section("Je cuisine d'habitude pour") {
                Picker("Personnes", selection: $bindable.state.settings.defaultServings) {
                    ForEach([1, 2, 4, 6], id: \.self) { count in
                        Text(count == 1 ? "1 personne" : "\(count) personnes").tag(count)
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Mon alimentation")
    }
}

/// Roue dentée ⚙︎ qui ouvre les réglages.
struct SettingsButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Réglages")
        .accessibilityIdentifier("settingsButton")
    }
}

/// Choix du nombre de personnes (1 le plus souvent, parfois 2 ou 4).
struct ServingsPicker: View {
    @Binding var people: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach([1, 2, 4, 6], id: \.self) { count in
                Button {
                    withAnimation(.snappy) { people = count }
                } label: {
                    VStack(spacing: 2) {
                        Text("\(count)").font(.title3.bold())
                        Text("pers.").font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(people == count ? Color.brand : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(people == count ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(count == 1 ? "1 personne" : "\(count) personnes")
                .accessibilityAddTraits(people == count ? .isSelected : [])
            }
        }
    }
}
