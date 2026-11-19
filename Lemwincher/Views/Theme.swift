import SwiftUI

// MARK: - Identité visuelle : couleurs, logo, enseignes

extension Color {
    /// Vert Lemwincher (catalogue d'images : plus lumineux en mode sombre).
    static let brand = Color("Brand")
    /// Jaune citron du logo (pastilles, favoris).
    static let lemon = Color("Lemon")

    /// Couleur d'une enseigne (Leclerc bleu, Auchan rouge…).
    init(chain style: ChainStyle) {
        let rgb = style.rgb
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Apparence choisie dans les Réglages.
extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Le logo de l'app (le citron), aux coins arrondis comme sur l'écran d'accueil.
struct BrandLogo: View {
    var size: CGFloat = 96

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: size * 0.09, y: size * 0.05)
            .accessibilityLabel("Lemwincher")
    }
}

/// Initiale d'une enseigne sur sa couleur (« E » bleu pour E.Leclerc).
struct ChainMonogram: View {
    let style: ChainStyle
    var size: CGFloat = 40

    var body: some View {
        Text(style.monogram)
            .font(.system(size: size * (style.monogram.count > 1 ? 0.36 : 0.5), weight: .heavy))
            .foregroundStyle(Color.white)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .background(Color(chain: style).gradient)
            .accessibilityHidden(true)
    }
}

// MARK: - Design « Liquid Glass » (iOS 26)

/// Fond maillé aux couleurs de Lemwincher (verts et touche de citron), pour les cartes « héros ».
struct BrandMesh: View {
    /// Couleur dominante (vert par défaut ; orange ou rouge quand le budget déborde).
    var tint: Color = .brand
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let deep = tint.mix(with: .black, by: dark ? 0.68 : 0.42)
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.55, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.55],
                [0, 1], [0.45, 1], [1, 1],
            ],
            colors: [
                deep, tint.opacity(0.95), tint,
                tint.opacity(0.9), tint, Color.lemon.opacity(dark ? 0.55 : 0.7),
                deep, deep.opacity(0.9), tint.opacity(0.85),
            ]
        )
    }
}

/// Carte « héros » : fond maillé, coins très arrondis, texte blanc (budget, liste, bonnes affaires).
struct HeroCard<Content: View>: View {
    var tint: Color = .brand
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandMesh(tint: tint), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.28), radius: 18, y: 8)
    }
}

/// Tuile « bento » : icône sur pastille colorée, titre et sous-titre, fond de carte.
struct BentoTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Puce de filtre en verre (teintée en vert quand elle est choisie).
struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(Color.brand).interactive() : .regular.interactive(), in: Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// Bouton principal d'un écran : verre teinté du vert Lemwincher, grande taille.
    func primaryGlassButton() -> some View {
        buttonStyle(.glassProminent)
            .tint(Color.brand)
            .controlSize(.large)
    }

    /// Ligne de liste sans fond ni marges (cartes héros, tuiles bento).
    func clearListRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

/// Espace de noms des transitions « zoom » (une carte de recette s'agrandit jusqu'à la recette).
extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID? = nil
}

extension View {
    /// Source d'une transition zoom (carte, vignette) quand l'écran en a une.
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Écran ouvert par une transition zoom depuis sa carte.
    @ViewBuilder
    func zoomDestination(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

/// Bouton d'action en tuile : icône au-dessus, texte court en dessous (fiche produit).
struct ActionTileLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(height: 24)
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
