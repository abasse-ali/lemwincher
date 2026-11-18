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
