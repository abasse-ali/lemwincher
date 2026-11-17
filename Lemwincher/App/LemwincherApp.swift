import SwiftUI

@main
struct LemwincherApp: App {
    private let model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .tint(Color.brand)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            model.save()
            if !model.state.watchlist.isEmpty && !model.isUITest {
                Notifier.scheduleBackgroundRefresh()
            }
        }
        .backgroundTask(.appRefresh(Notifier.refreshTaskID)) {
            await LemwincherApp.refreshWatchlistInBackground()
        }
    }

    /// Lancé par iOS de temps en temps : vérifie les prix suivis et prévient en cas de baisse.
    private static func refreshWatchlistInBackground() async {
        let model = AppModel.shared
        await model.checkWatchlist(notify: true)
        model.save()
        if !model.state.watchlist.isEmpty {
            Notifier.scheduleBackgroundRefresh()
        }
    }
}
