import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            StoresView()
                .tabItem { Label("Autour de moi", systemImage: "map.fill") }
            SearchView()
                .tabItem { Label("Comparer", systemImage: "magnifyingglass") }
            ShoppingListView()
                .tabItem { Label("Ma liste", systemImage: "cart.fill") }
                .badge(model.state.shoppingList.count)
            MyPricesView()
                .tabItem { Label("Mes prix", systemImage: "tag.fill") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
        }
        .onAppear { model.locationManager.request() }
        .onChange(of: model.state) { _, _ in
            model.save()
        }
    }
}
