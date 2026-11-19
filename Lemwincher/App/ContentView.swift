import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var bindable = model
        // Barre d'onglets en verre (iOS 26), qui se rétracte quand on fait défiler une liste.
        TabView(selection: $bindable.selectedTab) {
            Tab("Autour de moi", systemImage: "map.fill", value: AppTab.stores) {
                StoresView()
            }
            Tab("Produits", systemImage: "basket.fill", value: AppTab.compare) {
                SearchView()
            }
            Tab("Recettes", systemImage: "fork.knife", value: AppTab.recipes) {
                RecipesView()
            }
            Tab("Ma liste", systemImage: "cart.fill", value: AppTab.list) {
                ShoppingListView()
            }
            .badge(model.state.shoppingList.filter { !$0.checked }.count)
            Tab("Budget", systemImage: "eurosign.circle.fill", value: AppTab.budget) {
                BudgetView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
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
