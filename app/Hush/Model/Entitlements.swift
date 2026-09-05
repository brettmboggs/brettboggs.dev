import Foundation
import Observation

/// What Pro unlocks.
///
/// The free tier is deliberately not crippled: every sound, every shaping
/// control, the sleep timer, bedside mode, widgets, Siri and background
/// playback are all free forever. What you pay for is depth and the alarm.
/// A free app someone recommends is worth more than a paid one they resent.
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case extraLayers
    case extraMixes
    case sunriseAlarm
    case fullJournal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extraLayers: return "Layer up to eight sounds"
        case .extraMixes: return "Save as many mixes as you like"
        case .sunriseAlarm: return "Sunrise alarm and wind-down"
        case .fullJournal: return "Every night you have logged"
        }
    }

    var detail: String {
        switch self {
        case .extraLayers:
            return "Three at a time is free. Eight is where a mix starts to sound like a place."
        case .extraMixes:
            return "Keep a shelf of them instead of three."
        case .sunriseAlarm:
            return "Wake to sound that climbs from silence over your chosen window."
        case .fullJournal:
            return "Streaks and averages across the whole history, not the last week."
        }
    }

    var symbol: String {
        switch self {
        case .extraLayers: return "square.stack.3d.up"
        case .extraMixes: return "rectangle.stack"
        case .sunriseAlarm: return "sunrise"
        case .fullJournal: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// Why the paywall is on screen. Drives the headline, so the ask always
/// answers the thing the person was actually trying to do.
enum PaywallReason: String, Identifiable, Sendable {
    case layers
    case mixes
    case alarm
    case journal
    case direct

    var id: String { rawValue }

    var headline: String {
        switch self {
        case .layers: return "Room for more"
        case .mixes: return "Keep this one"
        case .alarm: return "Wake up gently"
        case .journal: return "The whole record"
        case .direct: return "Hush Pro"
        }
    }

    var line: String {
        switch self {
        case .layers:
            return "Free mixes hold three sounds. Pro holds eight."
        case .mixes:
            return "Free keeps three saved mixes. Pro keeps as many as you make."
        case .alarm:
            return "The sunrise alarm and the wind-down schedule are part of Pro."
        case .journal:
            return "Free shows the last week. Pro shows every night."
        case .direct:
            return "One payment. Everything, forever."
        }
    }
}

@Observable
final class Entitlements {
    let store: Store

    static let freeLayers = 3
    static let proLayers = 8
    static let freeSavedMixes = 3
    static let freeJournalNights = 7

    init(store: Store) {
        self.store = store
    }

    var isPro: Bool { store.isPro }

    func isUnlocked(_ feature: ProFeature) -> Bool { isPro }

    var maximumLayers: Int { isPro ? Entitlements.proLayers : Entitlements.freeLayers }
    var maximumSavedMixes: Int { isPro ? Int.max : Entitlements.freeSavedMixes }

    /// `nil` means no limit.
    var journalNightLimit: Int? { isPro ? nil : Entitlements.freeJournalNights }
}
