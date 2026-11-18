import SwiftUI

/// Mode cuisine : une étape par écran, en gros, avec les ingrédients de l'étape, les minuteurs
/// (alerte + Dynamic Island), la lecture à voix haute et l'écran qui reste allumé.
struct CookingModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let people: Int

    /// 0 : mise en place ; 1…n : étapes ; n + 1 : bon appétit.
    @State private var page = 0
    @State private var checked: Set<String> = []
    @StateObject private var reader = StepReader()
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var lastPage: Int { recipe.steps.count + 1 }
    private var scale: Double { recipe.scale(for: people) }
    private var timers: CookingTimers { CookingTimers.shared }
    private var finishedTimers: Int { timers.items.filter { $0.isFinished(at: now) }.count }

    var body: some View {
        @Bindable var bindable = model
        VStack(spacing: 0) {
            header
            TabView(selection: $page) {
                preparation(readAloud: $bindable.state.settings.readStepsAloud)
                    .tag(0)
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    stepPage(index: index, step: step)
                        .tag(index + 1)
                }
                finish
                    .tag(lastPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            timersBar
            controls
        }
        .background(Color(.systemBackground))
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            reader.stop()
        }
        .onChange(of: page) { _, newPage in
            reader.stop()
            if model.settings.readStepsAloud, newPage >= 1, newPage <= recipe.steps.count {
                reader.read(spoken(newPage - 1))
            }
        }
        .onReceive(tick) { date in
            now = date
            timers.cleanUp(now: date)
        }
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: finishedTimers)
    }

    // MARK: En-tête

    private var pageTitle: String {
        if page == 0 { return "Avant de commencer" }
        if page == lastPage { return "Terminé" }
        return "Étape \(page) sur \(recipe.steps.count)"
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                CircleIconButton(symbol: "xmark", label: "Fermer le mode cuisine") { dismiss() }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(recipe.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(pageTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                CircleIconButton(symbol: reader.speaking ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                 label: reader.speaking ? "Arrêter la lecture" : "Lire l'étape à voix haute") {
                    if reader.speaking {
                        reader.stop()
                    } else if page >= 1 && page <= recipe.steps.count {
                        reader.read(spoken(page - 1))
                    }
                }
                .disabled(page == 0 || page == lastPage)
            }
            ProgressView(value: Double(page), total: Double(lastPage))
                .tint(Color.brand)
                .animation(.snappy, value: page)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Pages

    private func preparation(readAloud: Binding<Bool>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    RecipeEmojiBadge(emoji: recipe.emoji, course: recipe.course, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avant de commencer")
                            .font(.title2.bold())
                        Text("Pour \(people) personne\(people > 1 ? "s" : "") · \(RecipeFormat.duration(recipe.minutes))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Sortez tout ce qu'il faut. Touchez un ingrédient pour le cocher.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(recipe.ingredients) { ingredient in
                        let done = checked.contains(ingredient.id)
                        Button {
                            withAnimation(.snappy) {
                                if done { checked.remove(ingredient.id) } else { checked.insert(ingredient.id) }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(done ? Color.brand : Color.secondary)
                                Text(ingredient.name)
                                    .strikethrough(done)
                                    .foregroundStyle(done ? Color.secondary : Color.primary)
                                Spacer(minLength: 8)
                                Text(ingredient.amount(scale: scale))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if ingredient.id != recipe.ingredients.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Toggle(isOn: readAloud) {
                    Label("Lire chaque étape à voix haute", systemImage: "speaker.wave.2")
                }
                .tint(Color.brand)
                Label("L'écran reste allumé pendant que vous cuisinez.", systemImage: "sun.max")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func stepPage(index: Int, step: String) -> some View {
        let used = RecipeEngine.ingredients(of: step, in: recipe)
        let stepTimers = RecipeEngine.timers(in: step)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Étape \(index + 1)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brand)
                    .textCase(.uppercase)
                Text(step)
                    .font(.title.weight(.semibold))
                    .fontDesign(.rounded)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cookingStepText")
                if !used.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pour cette étape")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(used) { ingredient in
                                let amount = ingredient.amount(scale: scale)
                                Text(amount.isEmpty ? ingredient.name : "\(amount) · \(ingredient.name)")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.brand.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
                ForEach(stepTimers) { timer in
                    Button {
                        timers.start(seconds: timer.seconds,
                                     label: "Étape \(index + 1) · \(timer.label)",
                                     recipeName: recipe.name,
                                     emoji: recipe.emoji,
                                     alerts: !model.isUITest)
                    } label: {
                        Label("Lancer un minuteur de \(timer.label)", systemImage: "timer")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityIdentifier("startTimer")
                }
            }
            .padding(24)
        }
    }

    private var finish: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🎉").font(.system(size: 84))
            Text("Bon appétit !")
                .font(.largeTitle.bold())
            Text(recipe.name)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !recipe.id.hasPrefix("compose:") {
                let favorite = model.isFavorite(recipe: recipe.id)
                Button {
                    model.toggleFavorite(recipe: recipe.id)
                } label: {
                    Label(favorite ? "Dans vos favoris" : "Ajouter aux favoris", systemImage: favorite ? "star.fill" : "star")
                }
                .buttonStyle(.bordered)
                .tint(favorite ? .yellow : Color.brand)
            }
            Spacer()
        }
        .padding(24)
    }

    // MARK: Minuteurs et commandes

    @ViewBuilder
    private var timersBar: some View {
        let items = timers.items
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        let finished = item.isFinished(at: now)
                        HStack(spacing: 8) {
                            Image(systemName: finished ? "bell.fill" : "timer")
                                .symbolEffect(.pulse, isActive: finished)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(finished ? "Prêt !" : CookingTimers.clock(item.remaining(at: now)))
                                    .font(.headline.monospacedDigit())
                                Text(item.label)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            Button {
                                timers.cancel(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Arrêter ce minuteur")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(finished ? Color.green : Color.orange)
                        .background((finished ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 6)
            .accessibilityIdentifier("cookingTimers")
        }
    }

    private var nextTitle: String {
        if page == 0 { return "C'est parti" }
        if page < recipe.steps.count { return "Étape suivante" }
        if page == recipe.steps.count { return "Terminer la recette" }
        return "Fermer"
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                page = max(page - 1, 0)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.bordered)
            .disabled(page == 0)
            .accessibilityLabel("Étape précédente")

            Button {
                if page < lastPage { page += 1 } else { dismiss() }
            } label: {
                Text(nextTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brand)
            .accessibilityIdentifier("cookingNext")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private func spoken(_ index: Int) -> String {
        "Étape \(index + 1). " + recipe.steps[index]
    }
}

/// Bouton rond (fermer, lire à voix haute).
struct CircleIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Disposition en lignes qui passent à la ligne (pastilles d'ingrédients).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
