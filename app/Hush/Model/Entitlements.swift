import Foundation
import Observation

/// Every feature that could ever sit behind a purchase asks here first.
///
/// Nothing is gated today: the app ships free and fully unlocked. The point of
/// this type is that turning a feature into a paid one later means adding a
/// case and wiring StoreKit into `isUnlocked`, not auditing the whole codebase
/// for places that assumed everything was free.
enum ProFeature: String, CaseIterable, Sendable {
    case unlimitedLayers
    case customMixes
    case alarm
    case fullLibrary
    case journal
}

@Observable
final class Entitlements {
    /// Flip to `false` and implement `isUnlocked` against StoreKit to gate.
    private(set) var isPro: Bool = true

    func isUnlocked(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        switch feature {
        case .fullLibrary, .journal: return true
        case .unlimitedLayers, .customMixes, .alarm: return false
        }
    }

    /// Free-tier ceiling, honoured only when `isPro` is false.
    var maximumLayers: Int {
        isUnlocked(.unlimitedLayers) ? 8 : 2
    }
}
