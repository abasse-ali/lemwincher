import SwiftUI

/// Présentation au premier lancement.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0

    private struct Page {
        /// nil : le logo de l'app (première page).
        let icon: String?
        let color: Color
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(icon: nil, color: Color.brand,
             title: "Payez moins cher vos courses",
             text: "Parcourez des centaines de milliers de produits par rayon, faites votre liste (« Œufs » vous propose les vrais produits et leur prix), et l'app vous dit où acheter au meilleur prix."),
        Page(icon: "eurosign.circle.fill", color: Color.purple,
             title: "Tenez votre budget",
             text: "Fixez votre budget courses du mois (100 € par exemple). Lemwincher vous dit ce qu'il reste, combien vous pouvez dépenser par jour, et vous prévient avant de dépasser."),
        Page(icon: "chart.bar.fill", color: Color.blue,
             title: "Des prix réels, partout en France",
             text: "Uniquement de vrais prix, relevés en magasin par des milliers de consommateurs (Open Prices), avec le magasin et la date. Quand personne n'a relevé un produit près de chez vous, l'app montre le prix relevé dans le magasin de la même enseigne le plus proche."),
        Page(icon: "fork.knife", color: Color.orange,
             title: "Des recettes, pas à pas",
             text: "Des idées de plats sans porc selon votre liste, un plat composé sur mesure, le menu de la semaine, puis la cuisine guidée étape par étape : minuteurs (même dans la Dynamic Island), lecture à voix haute, écran toujours allumé."),
        Page(icon: "location.fill", color: Color.brand,
             title: "Autour de vous",
             text: "Autorisez la localisation pour trouver les magasins et les stations-service proches. Vous pourrez aussi indiquer votre domicile dans les Réglages (⚙︎ en haut à gauche). Vos données restent sur votre iPhone."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index], active: index == page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Suivant" : "C'est parti !")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .primaryGlassButton()
                .accessibilityIdentifier("onboardingNext")

                Button("Passer la présentation") { finish() }
                    .font(.subheadline)
                    .opacity(page < pages.count - 1 ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        // Dégradé maillé de la couleur de la page (avec une touche de citron).
        .background {
            OnboardingBackdrop(color: pages[page].color)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: page)
        }
        .sensoryFeedback(.selection, trigger: page)
        .interactiveDismissDisabled()
    }

    private func pageView(_ page: Page, active: Bool) -> some View {
        VStack(spacing: 22) {
            Spacer()
            if let icon = page.icon {
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .symbolEffect(.bounce, value: active)
                    .frame(width: 130, height: 130)
                    .background(page.color.gradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: page.color.opacity(0.35), radius: 16, y: 8)
            } else {
                VStack(spacing: 14) {
                    BrandLogo(size: 136)
                        .scaleEffect(active ? 1 : 0.85)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: active)
                    Text("Lemwincher")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.brand)
                }
            }
            Text(page.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(page.text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func finish() {
        model.state.settings.hasSeenOnboarding = true
        if !model.isUITest {
            model.locationManager.request()
        }
    }
}

/// Fond de la présentation : dégradé maillé de la couleur de la page, qui s'efface vers le bas.
private struct OnboardingBackdrop: View {
    let color: Color

    var body: some View {
        let base = Color(.systemBackground)
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.42], [0.55, 0.36], [1, 0.46],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                color.opacity(0.62), color.opacity(0.4), Color.lemon.opacity(0.38),
                color.opacity(0.16), base, color.opacity(0.12),
                base, base, base,
            ]
        )
    }
}
