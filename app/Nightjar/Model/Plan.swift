import Foundation
import Observation

/// What Plus adds. The free tier is a complete nightly routine on its own:
/// twelve sounds, two layers, the sleep timer, two breathing patterns, every
/// tip, bedside mode, background audio. Plus is breadth and depth.
enum PlusFeature: String, CaseIterable, Identifiable, Sendable {
    case library
    case layers
    case breath
    case routine
    case wake
    case mixes
    case journal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Every sound"
        case .layers: return "Six layers at once"
        case .breath: return "Every breathing pattern"
        case .routine: return "Wind-down routines"
        case .wake: return "Sunrise alarm"
        case .mixes: return "Unlimited saved mixes"
        case .journal: return "Your whole sleep history"
        }
    }

    var detail: String {
        switch self {
        case .library: return "All \(SoundCatalog.all.count), recordings included. Twelve are free."
        case .layers: return "Two is a sound. Six is a place."
        case .breath: return "Coherent, long exhale, the sigh, and your own."
        case .routine: return "Breathe, then sound, then the timer. One tap."
        case .wake: return "Sound that climbs from silence before the alarm."
        case .mixes: return "Keep a shelf of them instead of two."
        case .journal: return "Streaks and averages past the last week."
        }
    }

    var symbol: String {
        switch self {
        case .library: return "square.stack.3d.down.right"
        case .layers: return "square.3.layers.3d"
        case .breath: return "wind"
        case .routine: return "moon.zzz"
        case .wake: return "sunrise"
        case .mixes: return "rectangle.stack"
        case .journal: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// Why the paywall is on screen. Drives the headline, so the ask always
/// answers the thing the person was actually trying to do.
enum PaywallReason: Identifiable, Hashable, Sendable {
    case sound(String)
    case layers
    case mixes
    case breath
    case routine
    case wake
    case journal
    case firstNight
    case direct

    var id: String {
        switch self {
        case .sound(let soundID): return "sound.\(soundID)"
        case .layers: return "layers"
        case .mixes: return "mixes"
        case .breath: return "breath"
        case .routine: return "routine"
        case .wake: return "wake"
        case .journal: return "journal"
        case .firstNight: return "firstNight"
        case .direct: return "direct"
        }
    }

    var headline: String {
        switch self {
        case .sound(let soundID):
            return SoundCatalog.kind(for: soundID)?.name ?? "This sound"
        case .layers: return "Room for more"
        case .mixes: return "Keep this one"
        case .breath: return "More ways to breathe"
        case .routine: return "One tap to bed"
        case .wake: return "Wake up gently"
        case .journal: return "The whole record"
        case .firstNight: return "That was a night"
        case .direct: return "Nightjar Plus"
        }
    }

    var line: String {
        switch self {
        case .sound:
            return "Part of the full library. Twelve sounds are free, this is one of the other \(SoundCatalog.plusOnly.count)."
        case .layers:
            return "Free mixes hold two sounds. Plus holds six."
        case .mixes:
            return "Free keeps two saved mixes. Plus keeps as many as you make."
        case .breath:
            return "4-7-8 and box breathing are free. The rest come with Plus."
        case .routine:
            return "Routines chain a breathing session into your mix and the timer."
        case .wake:
            return "The sunrise alarm and the wind-down schedule are part of Plus."
        case .journal:
            return "Free shows the last week. Plus shows every night."
        case .firstNight:
            return "Everything you used tonight stays free. Plus is the rest of the shelf."
        case .direct:
            return "Every sound, every pattern, and the mornings."
        }
    }
}

@Observable
final class Plan {
    let store: Store

    static let freeLayers = 2
    static let plusLayers = 6
    static let freeSavedMixes = 2
    static let freeJournalNights = 7
    /// How long a locked sound plays before the ask.
    static let previewSeconds: TimeInterval = 45

    init(store: Store) {
        self.store = store
    }

    var isPlus: Bool { store.isPlus }

    func allows(_ kind: SoundKind) -> Bool { isPlus || kind.isFree }
    func allows(_ pattern: BreathPattern) -> Bool { isPlus || pattern.isFree }

    var maximumLayers: Int { isPlus ? Plan.plusLayers : Plan.freeLayers }
    var maximumSavedMixes: Int { isPlus ? Int.max : Plan.freeSavedMixes }

    /// `nil` means no limit.
    var journalNightLimit: Int? { isPlus ? nil : Plan.freeJournalNights }
}
