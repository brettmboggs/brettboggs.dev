import UIKit

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()

    static func tap() {
        light.impactOccurred(intensity: 0.7)
    }

    static func step() {
        medium.impactOccurred(intensity: 0.8)
    }

    static func success() {
        notice.notificationOccurred(.success)
    }

    static func warning() {
        notice.notificationOccurred(.warning)
    }

    static func prepare() {
        light.prepare()
        medium.prepare()
        notice.prepare()
    }
}
