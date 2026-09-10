#if DEBUG
import Foundation

/// Launch-argument hooks that put the app into a known state, so the store
/// screenshots can be captured the same way every time instead of by hand.
///
/// Debug only. `tools/shots.sh` passes these flags; none of it is compiled
/// into a release build, so the shipped binary has no path into it. That
/// matters for Guideline 2.3.1: hidden functionality that exists in the
/// submitted binary is a rejection, and this does not exist there.
enum Demo {
    private static let arguments = ProcessInfo.processInfo.arguments

    /// `-tab sounds` opens straight onto a tab.
    static var tab: String? { value(for: "-tab") }

    /// `-play` starts the saved mix, so the meter and the orb are alive.
    static var shouldPlay: Bool { arguments.contains("-play") }

    /// `-plus` reports the entitlement as held, so the store screenshots show
    /// the app the way a subscriber sees it rather than under a row of badges.
    static var forcePlus: Bool { arguments.contains("-plus") }

    /// `-sheet mixes` opens one sheet over the tab.
    static var sheet: String? { value(for: "-sheet") }

    private static func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif
