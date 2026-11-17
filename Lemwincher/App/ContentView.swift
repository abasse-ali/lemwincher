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
            ShoppingListView()
                .tabItem { Label("Ma liste", systemImage: "cart.fill") }
                .badge(model.state.shoppingList.filter { !$0.checked }.count)
                .tag(AppTab.list)
            BudgetView()
                .tabItem { Label("Budget", systemImage: "eurosign.circle.fill") }
                .tag(AppTab.budget)
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
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
