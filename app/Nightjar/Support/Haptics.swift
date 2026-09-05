import UIKit

enum Haptics {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notice = UINotificationFeedbackGenerator()

    static func tap(enabled: Bool) {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.6)
    }

    static func success(enabled: Bool) {
        guard enabled else { return }
        notice.notificationOccurred(.success)
    }

    /// One distinct touch per phase, so the pattern can be followed with the
    /// eyes closed. Inhale is a firm tap, exhale a soft one, holds barely there.
    static func breath(_ kind: BreathPhase.Kind, enabled: Bool) {
        guard enabled else { return }
        switch kind {
        case .inhale: rigid.impactOccurred(intensity: 0.8)
        case .topUp: light.impactOccurred(intensity: 0.7)
        case .holdFull, .holdEmpty: light.impactOccurred(intensity: 0.35)
        case .exhale: soft.impactOccurred(intensity: 0.9)
        }
    }

    static func prepare() {
        soft.prepare()
        light.prepare()
        rigid.prepare()
        notice.prepare()
    }
}
