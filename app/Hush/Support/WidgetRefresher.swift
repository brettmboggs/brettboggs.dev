import Foundation
import WidgetKit

/// Widget reloads are metered by the system, and the player publishes state
/// every second. Coalesce so a full night costs a couple of hundred reloads
/// instead of thirty thousand.
enum WidgetRefresher {
    private static var lastReload: Date = .distantPast
    private static let minimumInterval: TimeInterval = 30

    static func reload(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReload) >= minimumInterval else { return }
        lastReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }
}
