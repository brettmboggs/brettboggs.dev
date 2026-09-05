import Foundation
import Observation

/// What happens when the sleep timer runs out.
enum TimerEndAction: String, Codable, CaseIterable, Sendable {
    case stop
    case keepPlaying

    var title: String {
        switch self {
        case .stop: return "Stop"
        case .keepPlaying: return "Fade to quiet"
        }
    }
}

@Observable
final class Settings {
    /// 0...1, applied on top of the system volume.
    var masterVolume: Double = 0.75
    /// -1 warm ... +1 bright. A single shelf pair across the whole mix.
    var tilt: Double = 0
    /// Seconds to reach full volume when playback starts.
    var fadeInSeconds: Double = 6
    /// Minutes of fade before the sleep timer's deadline.
    var fadeOutMinutes: Double = 5
    /// Last sleep timer duration in minutes. 0 means no timer.
    var timerMinutes: Int = 0
    var timerEndAction: TimerEndAction = .stop
    /// Let other audio (a podcast, a partner's app) play alongside.
    var mixWithOtherAudio: Bool = false
    /// Pause when headphones are disconnected.
    var pauseOnDisconnect: Bool = true

    // Wake
    var alarmEnabled: Bool = false
    /// Minutes past midnight.
    var alarmMinuteOfDay: Int = 7 * 60
    /// How long the sunrise ramp takes before the alarm time.
    var sunriseMinutes: Int = 15
    var alarmMixID: UUID?
    /// Days the alarm repeats. 1 = Sunday, matching Calendar's weekday.
    var alarmWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    var alarmRepeats: Bool = true

    // Wind-down
    var windDownEnabled: Bool = false
    var windDownMinuteOfDay: Int = 22 * 60 + 30
    var windDownMixID: UUID?

    // Interface
    /// Dim the whole interface after a period of no touches.
    var autoDim: Bool = true
    var autoDimSeconds: Double = 25
    var hapticsEnabled: Bool = true
    /// Mirror finished sessions into the Health app.
    var writeToHealth: Bool = false

    /// Sound ids the person starred. Surfaced as the first shelf.
    var favouriteSoundIDs: Set<String> = []

    var hasSeenWelcome: Bool = false

    // MARK: Persistence

    private static let filename = "settings.json"

    /// Every field is optional-on-read in practice because a settings file
    /// written by an older build will not have the newest keys. Decoding is
    /// already best-effort: a failure returns defaults rather than throwing.
    private struct Snapshot: Codable {
        var masterVolume: Double
        var tilt: Double
        var fadeInSeconds: Double
        var fadeOutMinutes: Double
        var timerMinutes: Int
        var timerEndAction: TimerEndAction
        var mixWithOtherAudio: Bool
        var pauseOnDisconnect: Bool
        var alarmEnabled: Bool
        var alarmMinuteOfDay: Int
        var sunriseMinutes: Int
        var alarmMixID: UUID?
        var alarmWeekdays: [Int]
        var alarmRepeats: Bool
        var windDownEnabled: Bool
        var windDownMinuteOfDay: Int
        var windDownMixID: UUID?
        var autoDim: Bool
        var autoDimSeconds: Double
        var hapticsEnabled: Bool
        var writeToHealth: Bool
        var favouriteSoundIDs: [String]
        var hasSeenWelcome: Bool
    }

    static func load() -> Settings {
        let settings = Settings()
        guard let snapshot = Persistence.load(Snapshot.self, from: filename) else {
            return settings
        }
        settings.masterVolume = snapshot.masterVolume
        settings.tilt = snapshot.tilt
        settings.fadeInSeconds = snapshot.fadeInSeconds
        settings.fadeOutMinutes = snapshot.fadeOutMinutes
        settings.timerMinutes = snapshot.timerMinutes
        settings.timerEndAction = snapshot.timerEndAction
        settings.mixWithOtherAudio = snapshot.mixWithOtherAudio
        settings.pauseOnDisconnect = snapshot.pauseOnDisconnect
        settings.alarmEnabled = snapshot.alarmEnabled
        settings.alarmMinuteOfDay = snapshot.alarmMinuteOfDay
        settings.sunriseMinutes = snapshot.sunriseMinutes
        settings.alarmMixID = snapshot.alarmMixID
        settings.alarmWeekdays = Set(snapshot.alarmWeekdays)
        settings.alarmRepeats = snapshot.alarmRepeats
        settings.windDownEnabled = snapshot.windDownEnabled
        settings.windDownMinuteOfDay = snapshot.windDownMinuteOfDay
        settings.windDownMixID = snapshot.windDownMixID
        settings.autoDim = snapshot.autoDim
        settings.autoDimSeconds = snapshot.autoDimSeconds
        settings.hapticsEnabled = snapshot.hapticsEnabled
        settings.writeToHealth = snapshot.writeToHealth
        settings.favouriteSoundIDs = Set(snapshot.favouriteSoundIDs)
        settings.hasSeenWelcome = snapshot.hasSeenWelcome
        return settings
    }

    func save() {
        let snapshot = Snapshot(
            masterVolume: masterVolume,
            tilt: tilt,
            fadeInSeconds: fadeInSeconds,
            fadeOutMinutes: fadeOutMinutes,
            timerMinutes: timerMinutes,
            timerEndAction: timerEndAction,
            mixWithOtherAudio: mixWithOtherAudio,
            pauseOnDisconnect: pauseOnDisconnect,
            alarmEnabled: alarmEnabled,
            alarmMinuteOfDay: alarmMinuteOfDay,
            sunriseMinutes: sunriseMinutes,
            alarmMixID: alarmMixID,
            alarmWeekdays: Array(alarmWeekdays).sorted(),
            alarmRepeats: alarmRepeats,
            windDownEnabled: windDownEnabled,
            windDownMinuteOfDay: windDownMinuteOfDay,
            windDownMixID: windDownMixID,
            autoDim: autoDim,
            autoDimSeconds: autoDimSeconds,
            hapticsEnabled: hapticsEnabled,
            writeToHealth: writeToHealth,
            favouriteSoundIDs: Array(favouriteSoundIDs).sorted(),
            hasSeenWelcome: hasSeenWelcome
        )
        Persistence.save(snapshot, to: Settings.filename)
    }
}
