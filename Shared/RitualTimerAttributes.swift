import ActivityKit
import Foundation

/// The wait timer between steps, shown on the Lock Screen and Dynamic Island.
struct RitualTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        /// What comes after the wait ("Tretinoin").
        var nextStep: String
    }

    /// "Retinoid night"
    var title: String
    /// Hue raw value, so the activity wears the night's color.
    var hue: String
    /// Why we're waiting ("Skin should be completely dry").
    var reason: String
}
