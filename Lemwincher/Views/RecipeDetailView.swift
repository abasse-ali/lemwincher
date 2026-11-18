import SwiftUI

/// Fiche recette : quantités pour 1, 2, 4 ou 6 personnes, ingrédients reliés à « Ma liste »,
/// étapes, mode cuisine pas à pas et vrais prix des courses.
struct RecipeDetailView: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe

    /// 0 : pas encore choisi (on prend le réglage « je cuisine d'habitude pour »).
    @State private var chosenPeople = 0
    @State private var cooking = false
    @State private var addedMessage: String?
    @State private var prices: [String: ProductSuggestion] = [:]
    @State private var priceMissing: Set<String> = []
    @State private var pricing = false

    private var people: Int { chosenPeople == 0 ? model.settings.defaultServings : chosenPeople }
    private var isComposed: Bool { recipe.id.hasPrefix("compose:") }

    var body: some View {
        let scale = recipe.scale(for: people)
        let listNames = model.listNames
        let missing = RecipeEngine.missing(recipe, listNames: listNames)

        List {
            Section {
                hero
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                ServingsPicker(people: Binding(get: { people }, set: { chosenPeople = $0 }))
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                Button {
                    cooking = true
                } label: {
                    Label("Cuisiner pas à pas", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brand)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("startCooking")
            } header: {
                Text("Pour combien de personnes ?")
            }

            ingredientsSection(scale: scale, listNames: listNames, missing: missing)

            Section {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.brand)
                            .frame(width: 28, height: 28)
                            .background(Color.brand.opacity(0.14), in: Circle())
                        Text(step)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Préparation · \(RecipeFormat.duration(recipe.minutes))")
            }

            pricesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: recipe.shareText(people: people)) {
                    Image(systemName: "square.and.arrow.up")
                }
                if !isComposed {
                    Button {
                        model.toggleFavorite(recipe: recipe.id)
                    } label: {
                        Image(systemName: model.isFavorite(recipe: recipe.id) ? "star.fill" : "star")
                            .foregroundStyle(model.isFavorite(recipe: recipe.id) ? Color.yellow : Color.accentColor)
                    }
                    .accessibilityLabel(model.isFavorite(recipe: recipe.id) ? "Retirer des favoris" : "Ajouter aux favoris")
                }
            }
        }
        .fullScreenCover(isPresented: $cooking) {
            CookingModeView(recipe: recipe, people: people)
        }
        .sensoryFeedback(.success, trigger: addedMessage)
    }

    // MARK: En-tête

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(recipe.emoji).font(.system(size: 60))
                Spacer()
                Text(recipe.course.singular)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.25), in: Capsule())
            }
            Text(recipe.name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(recipe.summary)
                .font(.subheadline)
                .opacity(0.92)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 14) {
                Label(RecipeFormat.duration(recipe.minutes), systemImage: "clock")
                Label("\(recipe.steps.count) étapes", systemImage: "list.number")
                if recipe.isVegetarian {
                    Label("Végétarien", systemImage: "leaf.fill")
                } else if model.settings.noPork {
                    Label("Sans porc", systemImage: "checkmark.seal.fill")
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(recipe.course.gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: Ingrédients

    @ViewBuilder
    private func ingredientsSection(scale: Double, listNames: [String], missing: [RecipeIngredient]) -> some View {
        Section {
            ForEach(recipe.ingredients) { ingredient in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                        if ingredient.pantry {
                            Text("Dans vos placards").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(ingredient.amount(scale: scale))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !ingredient.pantry {
                        if RecipeEngine.isInList(ingredient.shopping, listNames: listNames) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.brand)
                                .accessibilityLabel("Déjà dans ma liste")
                        } else {
                            Button {
                                let added = model.addIngredients([ingredient.shopping])
                                if added > 0 { addedMessage = "« \(ingredient.shopping) » ajouté à Ma liste" }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.brand)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Ajouter \(ingredient.shopping) à ma liste")
                        }
                    }
                }
            }
            if !missing.isEmpty {
                Button {
                    let added = model.addIngredients(missing.map(\.shopping))
                    addedMessage = added == 1 ? "1 article ajouté à Ma liste" : "\(added) articles ajoutés à Ma liste"
                } label: {
                    Label(missing.count == 1 ? "Ajouter l'ingrédient manquant à ma liste"
                                             : "Ajouter les \(missing.count) ingrédients manquants à ma liste",
                          systemImage: "cart.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("addMissingIngredients")
            }
            if let addedMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label(addedMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.brand)
                    Button("Voir ma liste →") { model.selectedTab = .list }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Ingrédients pour \(people) personne\(people > 1 ? "s" : "")")
        } footer: {
            Text(missing.isEmpty
                 ? "Vous avez tout dans « Ma liste »."
                 : "✓ = déjà dans « Ma liste ». Les articles ajoutés vous proposeront les vrais produits et leurs prix.")
        }
    }

    // MARK: Prix réels

    @ViewBuilder
    private var pricesSection: some View {
        let shopping = uniqueShopping
        let found = shopping.compactMap { prices[$0] }
        let total = found.compactMap { $0.offer?.price }.reduce(0, +)
        Section {
            if prices.isEmpty && priceMissing.isEmpty && !pricing {
                Button {
                    Task { await findPrices() }
                } label: {
                    Label("Chercher les vrais prix près de chez moi", systemImage: "eurosign.circle")
                        .font(.subheadline.weight(.semibold))
                }
            }
            ForEach(shopping, id: \.self) { name in
                if let suggestion = prices[name], let offer = suggestion.offer {
                    HStack(spacing: 10) {
                        ProductThumb(url: suggestion.product.imageURL, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.product.name).font(.subheadline).lineLimit(1)
                            Text(Fmt.join(name, offer.storeName, Fmt.day(offer.date)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(Fmt.price(offer.price, offer.currency))
                            .font(.subheadline.bold().monospacedDigit())
                            .fixedSize()
                    }
                } else if priceMissing.contains(name) {
                    HStack {
                        Text(name).font(.subheadline)
                        Spacer()
                        Text("prix non relevé").font(.caption).foregroundStyle(.tertiary)
                    }
                } else if pricing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(name).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if !found.isEmpty && !pricing {
                HStack {
                    Text("Total des courses").bold()
                    Spacer()
                    Text(Fmt.price(total, model.settings.currency)).bold().monospacedDigit()
                }
            }
        } header: {
            Text("Ce que coûtent les courses")
        } footer: {
            Text("Vrais prix relevés (Open Prices et vos relevés), le moins cher trouvé pour chaque ingrédient. Un paquet de chaque, même si la recette n'en utilise qu'une partie. Les articles du placard ne sont pas comptés.")
        }
    }

    private var uniqueShopping: [String] {
        var names: [String] = []
        for ingredient in recipe.shoppingIngredients where !names.contains(ingredient.shopping) {
            names.append(ingredient.shopping)
        }
        return names
    }

    /// Pour chaque ingrédient : le produit le moins cher avec un vrai prix relevé (sans porc si demandé).
    @MainActor
    private func findPrices() async {
        pricing = true
        defer { pricing = false }
        for name in uniqueShopping {
            await model.loadSuggestions(for: name)
            let items = SuggestionEngine.merge(personal: model.personalSuggestions(for: name),
                                               remote: model.suggestionResults(for: name).items)
            if let best = items.first(where: { $0.offer != nil && model.dietAllows($0.product) }) {
                prices[name] = best
            } else {
                priceMissing.insert(name)
            }
        }
    }
}
