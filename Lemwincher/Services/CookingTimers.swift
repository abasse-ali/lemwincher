import ActivityKit
import Foundation
import Observation
import UserNotifications

/// Minuteurs du mode cuisine : alerte à la fin (même téléphone verrouillé)
/// et compte à rebours dans la Dynamic Island de l'iPhone.
@Observable
final class CookingTimers {
    static let shared = CookingTimers()

    struct Item: Identifiable, Hashable {
        let id: UUID
        let label: String
        let recipeName: String
        let start: Date
        let end: Date

        func remaining(at now: Date) -> TimeInterval { max(end.timeIntervalSince(now), 0) }
        func isFinished(at now: Date) -> Bool { now >= end }
    }

    private(set) var items: [Item] = []
    @ObservationIgnored private var activities: [UUID: Activity<CookingTimerAttributes>] = [:]

    /// Lance un minuteur ; `alerts` : notification + Dynamic Island (désactivés pendant les tests d'interface).
    @discardableResult
    func start(seconds: Int, label: String, recipeName: String, emoji: String, alerts: Bool = true) -> Item {
        let now = Date()
        let item = Item(id: UUID(), label: label, recipeName: recipeName, start: now,
                        end: now.addingTimeInterval(TimeInterval(seconds)))
        items.append(item)
        guard alerts else { return item }

        Task {
            guard await Notifier.requestPermission() else { return }
            let content = UNMutableNotificationContent()
            content.title = "⏲️ Minuteur terminé"
            content.body = "\(recipeName) : \(label)"
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(seconds, 1)), repeats: false)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: Self.notificationID(item.id), content: content, trigger: trigger))
        }

        if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = CookingTimerAttributes(recipeName: recipeName, emoji: emoji)
            let state = CookingTimerAttributes.ContentState(label: label, start: item.start, end: item.end)
            if let activity = try? Activity.request(attributes: attributes,
                                                    content: ActivityContent(state: state, staleDate: item.end),
                                                    pushType: nil) {
                activities[item.id] = activity
            }
        }
        return item
    }

    func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID(id)])
        endActivity(id, immediately: true)
        items.removeAll { $0.id == id }
    }

    /// Retire les minuteurs terminés depuis plus d'une minute (et leur compte à rebours).
    func cleanUp(now: Date = Date()) {
        for item in items where now.timeIntervalSince(item.end) > 60 {
            endActivity(item.id, immediately: false)
        }
        items.removeAll { now.timeIntervalSince($0.end) > 60 }
    }

    func cancelAll() {
        for item in items { cancel(item.id) }
    }

    private func endActivity(_ id: UUID, immediately: Bool) {
        guard let activity = activities.removeValue(forKey: id) else { return }
        Task {
            await activity.end(nil, dismissalPolicy: immediately ? .immediate : .after(Date().addingTimeInterval(120)))
        }
    }

    private static func notificationID(_ id: UUID) -> String { "cuisine-" + id.uuidString }

    /// « 4:05 », « 1:02:30 ».
    static func clock(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
