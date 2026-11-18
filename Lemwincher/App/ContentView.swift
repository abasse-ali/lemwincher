import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var bindable = model
        TabView(selection: $bindable.selectedTab) {
            StoresView()
                .tabItem { Label("Autour de moi", systemImage: "map.fill") }
                .tag(AppTab.stores)
            SearchView()
                .tabItem { Label("Produits", systemImage: "basket.fill") }
                .tag(AppTab.compare)
            RecipesView()
                .tabItem { Label("Recettes", systemImage: "fork.knife") }
                .tag(AppTab.recipes)
            ShoppingListView()
                .tabItem { Label("Ma liste", systemImage: "cart.fill") }
                .badge(model.state.shoppingList.filter { !$0.checked }.count)
                .tag(AppTab.list)
            BudgetView()
                .tabItem { Label("Budget", systemImage: "eurosign.circle.fill") }
                .tag(AppTab.budget)
        }
        // Apparence choisie dans les Réglages (sinon celle de l'iPhone).
        .preferredColorScheme(model.settings.appearance.colorScheme)
        // Réglages : roue dentée ⚙︎ en haut des écrans (5 onglets tiennent sur l'iPhone sans « Plus »).
        .sheet(isPresented: $bindable.showSettings) {
            SettingsView(isSheet: true)
        }
        .onAppear {
            if !model.isUITest && model.state.settings.hasSeenOnboarding {
                model.locationManager.request()
            }
        }
        .onChange(of: model.state) { _, _ in
            model.save()
        }
        // Rayons suivis : relus à chaque retour dans l'app (au plus toutes les 12 h par rayon).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshTrackedPages() }
            }
        }
        .task {
            // Au lancement, après le chargement des magasins et des prix.
            try? await Task.sleep(for: .seconds(10))
            await model.refreshTrackedPages()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !model.state.settings.hasSeenOnboarding },
            set: { shown in
                if !shown { model.state.settings.hasSeenOnboarding = true }
            }
        )) {
            OnboardingView()
        }
    }
}
