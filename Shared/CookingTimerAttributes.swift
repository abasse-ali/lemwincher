import ActivityKit
import Foundation

/// Minuteur du mode cuisine affiché dans la Dynamic Island et sur l'écran verrouillé.
/// Fichier partagé entre l'app et l'extension LemwincherWidgets.
struct CookingTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// « Étape 3 · Laissez mijoter »
        var label: String
        var start: Date
        var end: Date
    }

    var recipeName: String
    var emoji: String
}
