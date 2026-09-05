import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Live Activity payload for a running sleep timer. Shared so the app can start
/// and update it and the widget extension can draw it.
struct SleepTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mixName: String
        var endDate: Date
        var isPlaying: Bool
        /// Set once the sunrise ramp has begun.
        var isWaking: Bool
    }

    var startedAt: Date
}
#endif
