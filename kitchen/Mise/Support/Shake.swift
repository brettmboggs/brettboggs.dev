import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("dev.brettboggs.mise.shake")
}

/// Shaking the phone on the Tonight screen picks a dinner. UIKit delivers
/// shakes to the first responder chain and stops at the window, so the window
/// is where they are caught and turned into a notification the view can hear.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
