import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

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
