import SwiftUI

/// Présentation au premier lancement.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0

    private struct Page {
        let icon: String
        let color: Color
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(icon: "cart.fill", color: Color.brand,
             title: "Payez moins cher vos courses",
             text: "Parcourez des centaines de milliers de produits par rayon, faites votre liste (« Œufs » vous propose les vrais produits et leur prix), et l'app vous dit où acheter au meilleur prix."),
        Page(icon: "eurosign.circle.fill", color: Color.purple,
             title: "Tenez votre budget",
             text: "Fixez votre budget courses du mois (100 € par exemple). Lemwincher vous dit ce qu'il reste, combien vous pouvez dépenser par jour, et vous prévient avant de dépasser."),
        Page(icon: "chart.bar.fill", color: Color.blue,
             title: "Des prix réels, partout en France",
             text: "Uniquement de vrais prix, relevés en magasin par des milliers de consommateurs (Open Prices), avec le magasin et la date. Quand personne n'a relevé un produit près de chez vous, l'app montre le prix relevé dans le magasin de la même enseigne le plus proche."),
        Page(icon: "fuelpump.fill", color: Color.orange,
             title: "Carburant, rappels et alertes",
             text: "Trouvez la station la moins chère (prix officiels), soyez prévenu si un produit de votre liste est rappelé, et suivez les produits dont vous attendez une baisse de prix."),
        Page(icon: "location.fill", color: Color.brand,
             title: "Autour de vous",
             text: "Autorisez la localisation pour trouver les magasins proches. Vous pourrez aussi indiquer l'adresse de votre domicile dans Réglages. Vos données restent sur votre iPhone."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
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
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboardingNext")

                Button("Passer la présentation") { finish() }
                    .font(.subheadline)
                    .opacity(page < pages.count - 1 ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .interactiveDismissDisabled()
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: page.icon)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 130, height: 130)
                .background(page.color.gradient, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
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
