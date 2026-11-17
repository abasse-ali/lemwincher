import Foundation
import UserNotifications
import BackgroundTasks

/// Notifications locales (baisses de prix) et vérification en arrière-plan.
enum Notifier {
    /// Doit correspondre à BGTaskSchedulerPermittedIdentifiers (Config/Lemwincher-Info.plist).
    static let refreshTaskID = "com.lemwincher.app.refresh"

    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func notify(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// Demande à iOS de relancer l'app en arrière-plan dans quelques heures pour vérifier les prix suivis.
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
