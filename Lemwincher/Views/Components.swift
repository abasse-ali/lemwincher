import SwiftUI
import UIKit

// MARK: - Formats, extensions (couleurs et logo : Theme.swift)

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : self }
    /// 8 à 14 chiffres : EAN-8, UPC, EAN-13, GTIN-14.
    var isBarcodeLike: Bool { (8...14).contains(count) && allSatisfy { $0.isASCII && $0.isNumber } }
}

extension Error {
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

enum Fmt {
    /// Format français quelle que soit la langue de l'iPhone : « 2,35 € », « 1 500 KMF ».
    private static let french = Locale(identifier: "fr_FR")

    static func price(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).locale(french))
    }

    /// « 1,5 », « 33 », « 0,25 » (2 décimales au plus).
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(french))
    }

    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int((meters / 10).rounded()) * 10) m"
        }
        return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func day(_ date: Date) -> String {
        if date == .distantPast { return "date inconnue" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "hier" }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: Date())).day ?? 0
        if days > 1 && days < 31 { return "il y a \(days) j" }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Assemble les morceaux non vides avec " · ".
    static func join(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Prix d'un carburant au litre : "1,849 €".
    static func fuel(_ value: Double) -> String {
        String(format: "%.3f", value).replacingOccurrences(of: ".", with: ",") + " €"
    }

    /// "à l'instant", "il y a 25 min", "il y a 3 h", puis la date.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "à l'instant" }
        if seconds < 3600 { return "il y a \(Int(seconds / 60)) min" }
        if seconds < 24 * 3600 { return "il y a \(Int(seconds / 3600)) h" }
        return day(date)
    }

    /// Relevé de plus de 3 mois : le prix a pu changer depuis.
    static func isOld(_ date: Date, now: Date = Date()) -> Bool {
        date != .distantPast && now.timeIntervalSince(date) > 90 * 24 * 3600
    }

    /// "+8 %", "-12 %".
    static func percent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded) %" : "\(rounded) %"
    }
}

// MARK: - Navigation commune

extension View {
    /// Destinations partagées par tous les onglets : fiche magasin et comparatif produit.
    func appDestinations() -> some View {
        self
            .navigationDestination(for: Store.self) { store in
                StoreDetailView(store: store)
            }
            .navigationDestination(for: Product.self) { product in
                ProductCompareView(product: product)
            }
            .navigationDestination(for: Rayon.self) { rayon in
                RayonView(rayon: rayon)
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .navigationDestination(for: TrackedPageRoute.self) { route in
                TrackedPageView(pageID: route.id)
            }
            .navigationDestination(for: ValueCompareRoute.self) { route in
                ValueCompareView(initialQuery: route.query)
            }
    }
}

// MARK: - Petits composants

/// Photo d'un produit sur fond blanc (les photos des fiches sont prises sur fond blanc : elles restent
/// nettes en mode sombre) ; sans photo, un emoji d'après son nom (🥚 Œufs, 🍌 Bananes) ou un panier.
struct ProductThumb: View {
    let url: String?
    var size: CGFloat = 44
    /// Nom du produit, pour l'emoji de remplacement.
    var name: String? = nil

    var body: some View {
        ZStack {
            if let url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        ZStack {
                            Color.white
                            image.resizable().scaledToFit().padding(size * 0.06)
                        }
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let emoji = name.flatMap({ ProductEmoji.emoji(for: $0) }) {
                Text(emoji)
                    .font(.system(size: size * 0.52))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "basket")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Logo d'un magasin sur fond blanc ; s'il manque, l'initiale de l'enseigne sur sa couleur,
/// sinon une vitrine verte.
struct StoreLogo: View {
    let url: String?
    var size: CGFloat = 40
    var systemImage: String = "storefront.fill"
    /// Enseigne (clé de `Chain.key` ou nom) : son initiale et sa couleur quand le logo manque.
    var chainKey: String? = nil

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
    }

    var body: some View {
        ZStack {
            if let url, let logoURL = URL(string: url) {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        ZStack {
                            Color.white
                            image.resizable().scaledToFit().padding(size * 0.1)
                        }
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    @ViewBuilder
    private var fallback: some View {
        if let style = ChainStyle.forChain(chainKey) {
            ChainMonogram(style: style, size: size)
        } else {
            ZStack {
                Color.brand.opacity(0.14)
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Color.brand)
            }
        }
    }
}

/// "Ouvert · ferme à 20h" en vert, "Fermé · ouvre à 8h30" en rouge.
struct OpenStatusLabel: View {
    let hours: OpeningHours

    var body: some View {
        let now = Date()
        let open = hours.status(at: now).isOpen
        HStack(spacing: 3) {
            Image(systemName: "clock")
            Text(hours.statusText(at: now))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(open ? Color.brand : Color.red)
        .lineLimit(1)
    }
}

/// Lettre de score (Nutri-Score, Éco-Score) sur fond coloré.
struct GradeBadge: View {
    let title: String
    let grade: String

    private var color: Color { GradeBadge.color(for: grade) }

    static func color(for grade: String) -> Color {
        switch grade.lowercased() {
        case "a": return Color(red: 0.0, green: 0.52, blue: 0.25)
        case "b": return Color(red: 0.52, green: 0.74, blue: 0.17)
        case "c": return Color(red: 0.98, green: 0.78, blue: 0.0)
        case "d": return Color(red: 0.93, green: 0.48, blue: 0.0)
        default: return Color(red: 0.89, green: 0.18, blue: 0.12)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(grade.uppercased())
                .font(.title3.bold())
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Groupe NOVA (1 = brut … 4 = ultra-transformé).
struct NovaBadge: View {
    let group: Int

    private var color: Color {
        switch group {
        case 1: return Color(red: 0.0, green: 0.52, blue: 0.25)
        case 2: return Color(red: 0.98, green: 0.78, blue: 0.0)
        case 3: return Color(red: 0.93, green: 0.48, blue: 0.0)
        default: return Color(red: 0.89, green: 0.18, blue: 0.12)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(group)")
                .font(.title3.bold())
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("NOVA")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Nutri-Score, NOVA, Éco-Score, labels et allergènes d'un produit.
struct ProductFactsView: View {
    let facts: ProductFacts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if let grade = facts.nutriScore {
                    GradeBadge(title: "Nutri-Score", grade: grade)
                }
                if let nova = facts.nova {
                    NovaBadge(group: nova)
                }
                if let grade = facts.ecoScore {
                    GradeBadge(title: "Éco-Score", grade: grade)
                }
            }
            if !facts.labels.isEmpty {
                Label(facts.labels.joined(separator: " · "), systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brand)
            }
            if !facts.allergens.isEmpty {
                Label("Allergènes : " + facts.allergens.joined(separator: ", "), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Sans porc : « Contient du porc » (rouge) ou « Contient de la gélatine » (orange, origine non précisée).
struct DietWarningBanner: View {
    let pork: Bool
    /// Le nom du produit suffit à le dire (jambon, lardons…), sinon c'est la liste d'ingrédients.
    var byName = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pork ? "exclamationmark.octagon.fill" : "info.circle.fill")
                .font(.title2)
                .foregroundStyle(pork ? Color.red : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(pork ? "Contient du porc" : "Contient de la gélatine")
                    .font(.headline)
                Text(pork
                     ? (byName ? "D'après le nom du produit." : "D'après sa liste d'ingrédients (Open Food Facts).")
                     : "Son origine n'est pas précisée : la gélatine est souvent d'origine porcine.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Description du produit : dénomination, ingrédients, origine, conservation, nutrition pour 100 g.
struct ProductDescriptionSection: View {
    let facts: ProductFacts
    @State private var showIngredients = false

    var body: some View {
        Section {
            if let category = facts.category {
                Label {
                    Text("Catégorie : ").font(.subheadline.weight(.semibold)) + Text(category).font(.subheadline)
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
            }
            if let ingredients = facts.ingredientsText {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Ingrédients", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                    Text(ingredients)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(showIngredients ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if ingredients.count > 180 {
                        Button(showIngredients ? "Réduire" : "Lire la suite") {
                            withAnimation(.snappy) { showIngredients.toggle() }
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 2)
            }
            if !facts.additives.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label(facts.additives.count == 1 ? "1 additif" : "\(facts.additives.count) additifs",
                          systemImage: "flask")
                        .font(.subheadline.weight(.semibold))
                    Text(facts.additives.map(Additives.label).joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
            if let origins = facts.origins {
                Label {
                    Text("Origine : ").font(.subheadline.weight(.semibold)) + Text(origins).font(.subheadline)
                } icon: {
                    Image(systemName: "globe.europe.africa")
                }
            }
            if let places = facts.manufacturingPlaces {
                Label {
                    Text("Fabriqué à : ").font(.subheadline.weight(.semibold)) + Text(places).font(.subheadline)
                } icon: {
                    Image(systemName: "building.2")
                }
            }
            if let stores = facts.stores {
                Label {
                    Text("Vendu chez : ").font(.subheadline.weight(.semibold)) + Text(stores).font(.subheadline)
                } icon: {
                    Image(systemName: "cart")
                }
            }
            if let conservation = facts.conservation {
                Label {
                    Text(conservation).font(.subheadline)
                } icon: {
                    Image(systemName: "thermometer.snowflake")
                }
            }
            if !facts.nutrition.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Valeurs nutritionnelles pour 100 g", systemImage: "chart.bar.doc.horizontal")
                        .font(.subheadline.weight(.semibold))
                        .padding(.bottom, 2)
                    ForEach(facts.nutrition.rows) { row in
                        HStack {
                            Text(row.label)
                                .font(row.indent ? .footnote : .subheadline)
                                .foregroundStyle(row.indent ? Color.secondary : Color.primary)
                                .padding(.leading, row.indent ? 14 : 0)
                            Spacer()
                            Text(row.value)
                                .font(.subheadline.monospacedDigit())
                        }
                        if row.label != facts.nutrition.rows.last?.label {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Description")
        } footer: {
            Text("Source : Open Food Facts, base collaborative. Vérifiez l'emballage en cas d'allergie.")
        }
    }
}

/// Ligne d'alerte : icône colorée, titre, explication.
struct AlertRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// En haut de la fiche d'un produit (après un scan) : rappel en cours (défaut, contamination, intoxication),
/// porc, gélatine, additifs d'origine animale possible, promotions relevées, ou « aucun rappel ».
struct ProductAlertsSection: View {
    @Environment(AppModel.self) private var model
    let product: Product
    let facts: ProductFacts?
    /// Prix relevés autour de soi (Open Prices et vos relevés), pour repérer les promos.
    let observations: [PriceObservation]

    var body: some View {
        let recall = model.recall(for: product.code)
        let noPork = model.settings.noPork
        let porkByName = DietFilter.isPork(name: product.name, categories: product.categories)
        let pork = porkByName || facts?.containsPork == true
        let gelatin = facts?.unspecifiedGelatin == true
        let animalAdditives = facts?.possiblyAnimalAdditives ?? []
        let promos = Array(PriceEngine.promotions(in: observations).prefix(3))
        let checked = !product.isCustom && model.recallChecked(product.code)

        if recall != nil || (noPork && (pork || gelatin || !animalAdditives.isEmpty)) || !promos.isEmpty || checked {
            Section {
                if let recall {
                    RecallBanner(recall: recall)
                }
                if noPork && (pork || gelatin) {
                    DietWarningBanner(pork: pork, byName: porkByName)
                }
                if noPork && !pork && !animalAdditives.isEmpty {
                    AlertRow(symbol: "info.circle.fill", tint: .orange,
                             title: "Additifs parfois d'origine animale",
                             text: animalAdditives.map(Additives.label).joined(separator: ", ")
                                + " : souvent végétaux, ils peuvent aussi venir de graisses animales (porc possible). Cherchez la mention « d'origine végétale » sur l'emballage.")
                }
                ForEach(promos) { promo in
                    let obs = promo.observation
                    AlertRow(symbol: "tag.fill", tint: .pink,
                             title: "Promo : \(Fmt.price(obs.price, obs.currency)) chez \(obs.storeName)"
                                + (promo.discountPercent.map { " (−\($0) %)" } ?? ""),
                             text: Fmt.join("Relevée \(Fmt.day(obs.date))",
                                            promo.regularPrice.map { "prix habituel \(Fmt.price($0, obs.currency))" }))
                }
                if recall == nil && checked {
                    AlertRow(symbol: "checkmark.shield.fill", tint: .green,
                             title: "Aucun rappel en cours",
                             text: "Vérifié sur RappelConso, le site officiel des rappels de produits (défauts, contaminations, risques d'intoxication).")
                }
                if noPork && !pork && facts?.isVegetarian == true {
                    AlertRow(symbol: "leaf.fill", tint: .green,
                             title: "Sans viande",
                             text: "D'après sa liste d'ingrédients : donc sans porc.")
                }
            } header: {
                Text("Alertes et vérifications")
            }
        }
    }
}

/// Avertissement rouge : produit rappelé.
struct RecallBanner: View {
    let recall: Recall
    var productName: String? = nil

    var body: some View {
        NavigationLink {
            RecallDetailView(recall: recall)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text(productName.map { "Rappel : \($0)" } ?? "Ce produit fait l'objet d'un rappel")
                        .font(.headline)
                        .foregroundStyle(Color.red)
                    if let reason = recall.reason {
                        Text(reason).font(.caption).lineLimit(3)
                    }
                    if let risks = recall.risks {
                        Label(risks, systemImage: "cross.case.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.red)
                            .lineLimit(3)
                    }
                    Text("Vérifiez le lot sur l'emballage. Touchez pour les détails et la conduite à tenir.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct PromoBadge: View {
    var body: some View {
        Text("PROMO")
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.orange)
    }
}

struct EstimateBadge: View {
    var body: some View {
        Text("ESTIMÉ")
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.blue)
    }
}

/// Indice de prix d'une enseigne : vert si moins cher que la moyenne, orange sinon.
struct ChainIndexBadge: View {
    let entry: ChainIndexEntry

    var body: some View {
        let cheaper = entry.index < 99.5
        let pricier = entry.index > 100.5
        let color: Color = cheaper ? Color.brand : (pricier ? Color.orange : Color.secondary)
        Text(entry.differenceText)
            .font(.caption.bold().monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct ProductRow: View {
    let product: Product
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ProductThumb(url: product.imageURL, size: 44, name: product.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).lineLimit(2)
                let details = Fmt.join(product.brand, product.quantity)
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(Color.brand)
                }
            }
        }
    }
}

/// Une ligne "produit – magasin – prix".
struct ObservationRow: View {
    let obs: PriceObservation
    var showStore: Bool = true
    var distance: Double? = nil

    var body: some View {
        HStack(spacing: 12) {
            ProductThumb(url: obs.imageURL, size: 44, name: obs.productName)
            VStack(alignment: .leading, spacing: 2) {
                Text(obs.productName).lineLimit(2)
                Text(Fmt.join(showStore ? Optional(obs.storeName) : obs.brand,
                              distance.map { Fmt.distance($0) },
                              Fmt.day(obs.date)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.price(obs.price, obs.currency))
                    .font(.headline.monospacedDigit())
                if let unitPrice = obs.unitPriceText {
                    Text(unitPrice).font(.caption2).foregroundStyle(.secondary)
                }
                if obs.isDiscounted { PromoBadge() }
                if obs.source == .mine {
                    Image(systemName: "person.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Une ligne du comparatif d'un produit entre magasins.
struct CompareRow: View {
    let obs: PriceObservation
    let rank: Int
    let distance: Double?
    let cheapest: Bool
    var favorite: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.bold())
                .frame(width: 26, height: 26)
                .background(cheapest ? Color.brand : Color(.tertiarySystemFill), in: Circle())
                .foregroundStyle(cheapest ? Color.white : Color.primary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(obs.storeName).font(.headline).lineLimit(1)
                    if favorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.yellow)
                    }
                }
                HStack(spacing: 4) {
                    Text(Fmt.join(distance.map { Fmt.distance($0) }, Fmt.day(obs.date), obs.unitPriceText))
                    if obs.source == .mine {
                        Image(systemName: "person.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.price(obs.price, obs.currency))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(cheapest ? Color.brand : Color.primary)
                if obs.isDiscounted {
                    PromoBadge()
                } else if cheapest {
                    Text("Le moins cher").font(.caption2.bold()).foregroundStyle(Color.brand)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Vrai prix d'un produit dans une enseigne : où et quand il a été relevé, et le magasin de l'enseigne le plus proche.
struct ChainEstimateRow: View {
    let estimate: ChainEstimate
    let nearestStore: Store?
    let distance: Double?
    let cheapest: Bool

    private var subtitle: String {
        var parts: [String] = []
        if let reference = estimate.reference {
            let old = Fmt.isOld(reference.date) ? " · ancien relevé" : ""
            parts.append("relevé chez \(reference.storeName) · \(Fmt.day(reference.date))\(old)")
        }
        if let store = nearestStore, store.id != estimate.reference?.storeKey {
            let distanceText: String? = distance.map { Fmt.distance($0) }
            parts.append("près de chez vous : " + Fmt.join(store.name, distanceText))
        }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 12) {
            StoreLogo(url: nearestStore?.displayLogoURL ?? Chain.logoURL(brand: estimate.name), size: 34,
                      chainKey: nearestStore?.chainKey ?? estimate.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(estimate.name).font(.headline).lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.price(estimate.displayPrice, estimate.currency))
                    .fixedSize()
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(cheapest ? Color.brand : Color.primary)
                if cheapest {
                    Text("La moins chère").font(.caption2.bold()).foregroundStyle(Color.brand)
                }
            }
        }
    }
}

struct StoreRow: View {
    let store: Store
    let distance: Double?
    var chainEntry: ChainIndexEntry? = nil
    var favorite: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            StoreLogo(url: store.displayLogoURL, chainKey: store.chainKey)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(store.name).font(.headline).lineLimit(1)
                    if favorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.yellow)
                    }
                }
                if let address = store.address {
                    Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let hours = store.hours {
                    OpenStatusLabel(hours: hours)
                }
                HStack(spacing: 6) {
                    if let entry = chainEntry {
                        ChainIndexBadge(entry: entry)
                    }
                    if let count = store.priceCount, count > 0 {
                        // Icône collée au texte (un Label de liste réserve une large colonne d'icône).
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill")
                            Text("\(count) prix")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.brand)
                    }
                }
            }
            Spacer(minLength: 8)
            if let distance {
                Text(Fmt.distance(distance))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Écran affiché quand on n'a ni position ni domicile.
struct LocationNeededView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.locationManager.authorization
        VStack(spacing: 16) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.brand)
            if status == .denied || status == .restricted {
                Text("Localisation désactivée").font(.title3.bold())
                Text("Autorisez la localisation dans les Réglages de l'iPhone, ou indiquez l'adresse de votre domicile dans les Réglages de l'app (⚙︎ en haut à gauche).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Ouvrir les Réglages de l'iPhone") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.glassProminent)
            } else if status == .notDetermined {
                Text("Trouvez le moins cher près de chez vous").font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("Lemwincher utilise votre position pour lister les supermarchés proches et comparer leurs prix.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Autoriser la localisation") { model.locationManager.request() }
                    .buttonStyle(.glassProminent)
            } else {
                ProgressView()
                Text("Recherche de votre position…").foregroundStyle(.secondary)
                if let error = model.locationManager.lastError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
                Button("Réessayer") { model.locationManager.request() }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
