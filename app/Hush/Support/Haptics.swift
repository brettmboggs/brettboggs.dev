import UIKit

enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .soft)
    private static let notice = UINotificationFeedbackGenerator()

    static func tap(enabled: Bool) {
        guard enabled else { return }
        impact.impactOccurred(intensity: 0.6)
    }

    static func success(enabled: Bool) {
        guard enabled else { return }
        notice.notificationOccurred(.success)
    }

    static func prepare() {
        impact.prepare()
        notice.prepare()
    }
}
