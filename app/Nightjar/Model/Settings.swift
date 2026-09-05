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

/// Asked once, on first launch. Picks the first mix and the routine defaults.
enum SleepGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case fallAsleep
    case stayAsleep
    case windDown
    case quietMind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fallAsleep: return "Fall asleep faster"
        case .stayAsleep: return "Stay asleep"
        case .windDown: return "Wind down after a long day"
        case .quietMind: return "Quiet a busy mind"
        }
    }

    var breathPatternID: String {
        switch self {
        case .fallAsleep: return "478"
        case .stayAsleep: return "long-exhale"
        case .windDown: return "box"
        case .quietMind: return "coherent"
        }
    }
}

@Observable
final class Settings {
    // Sound
    /// 0...1, applied on top of the system volume.
    var masterVolume: Double = 0.75
    /// -1 warm ... +1 bright. A single shelf pair across the whole mix.
    var tilt: Double = 0
    /// Seconds to reach full volume when playback starts.
    var fadeInSeconds: Double = 6
    /// Minutes of fade before the sleep timer's deadline.
    var fadeOutMinutes: Double = 5
    /// Last sleep timer duration in minutes. 0 means no timer.
    var timerMinutes: Int = 45
    var timerEndAction: TimerEndAction = .stop
    /// Let other audio (a podcast, a partner's app) play alongside.
    var mixWithOtherAudio: Bool = false
    /// Pause when headphones are disconnected.
    var pauseOnDisconnect: Bool = true

    // Breathing
    var breathGuideSound: Bool = true
    var breathHaptics: Bool = true
    /// Last chosen session length in minutes.
    var breathMinutes: Int = 4
    /// The custom pattern, in seconds. Inhale, hold, exhale, hold.
    var customBreath: [Double] = [4, 4, 6, 2]

    // Routine
    var routineBreathPatternID: String = "478"
    var routineBreathMinutes: Int = 3
    var routineMixID: UUID?
    var routineTimerMinutes: Int = 45

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

    // Bedtime
    var bedtimeMinuteOfDay: Int = 22 * 60 + 30
    var bedtimeReminderEnabled: Bool = false
    /// Start playback at bedtime, if the app is open.
    var windDownEnabled: Bool = false

    // Interface
    /// Dim the whole interface after a period of no touches.
    var autoDim: Bool = true
    var autoDimSeconds: Double = 25
    var hapticsEnabled: Bool = true
    var reduceGlow: Bool = false

    /// Sound ids the person starred.
    var favouriteSoundIDs: Set<String> = []

    // Progress
    var hasOnboarded: Bool = false
    var goal: SleepGoal = .fallAsleep
    /// Nights of twenty minutes or more.
    var nightsCompleted: Int = 0
    var didOfferAfterFirstNight: Bool = false
    var lastPaywallShown: Date?

    // MARK: Persistence

    private static let filename = "settings.json"

    /// Every field is optional on read, so a file written by an older build
    /// keeps its values and picks up defaults for new keys.
    private struct Snapshot: Codable {
        var masterVolume: Double?
        var tilt: Double?
        var fadeInSeconds: Double?
        var fadeOutMinutes: Double?
        var timerMinutes: Int?
        var timerEndAction: TimerEndAction?
        var mixWithOtherAudio: Bool?
        var pauseOnDisconnect: Bool?
        var breathGuideSound: Bool?
        var breathHaptics: Bool?
        var breathMinutes: Int?
        var customBreath: [Double]?
        var routineBreathPatternID: String?
        var routineBreathMinutes: Int?
        var routineMixID: UUID?
        var routineTimerMinutes: Int?
        var alarmEnabled: Bool?
        var alarmMinuteOfDay: Int?
        var sunriseMinutes: Int?
        var alarmMixID: UUID?
        var alarmWeekdays: [Int]?
        var alarmRepeats: Bool?
        var bedtimeMinuteOfDay: Int?
        var bedtimeReminderEnabled: Bool?
        var windDownEnabled: Bool?
        var autoDim: Bool?
        var autoDimSeconds: Double?
        var hapticsEnabled: Bool?
        var reduceGlow: Bool?
        var favouriteSoundIDs: [String]?
        var hasOnboarded: Bool?
        var goal: SleepGoal?
        var nightsCompleted: Int?
        var didOfferAfterFirstNight: Bool?
        var lastPaywallShown: Date?
    }

    static func load() -> Settings {
        let settings = Settings()
        guard let s = Persistence.load(Snapshot.self, from: filename) else {
            return settings
        }
        if let v = s.masterVolume { settings.masterVolume = v }
        if let v = s.tilt { settings.tilt = v }
        if let v = s.fadeInSeconds { settings.fadeInSeconds = v }
        if let v = s.fadeOutMinutes { settings.fadeOutMinutes = v }
        if let v = s.timerMinutes { settings.timerMinutes = v }
        if let v = s.timerEndAction { settings.timerEndAction = v }
        if let v = s.mixWithOtherAudio { settings.mixWithOtherAudio = v }
        if let v = s.pauseOnDisconnect { settings.pauseOnDisconnect = v }
        if let v = s.breathGuideSound { settings.breathGuideSound = v }
        if let v = s.breathHaptics { settings.breathHaptics = v }
        if let v = s.breathMinutes { settings.breathMinutes = v }
        if let v = s.customBreath, v.count == 4 { settings.customBreath = v }
        if let v = s.routineBreathPatternID { settings.routineBreathPatternID = v }
        if let v = s.routineBreathMinutes { settings.routineBreathMinutes = v }
        settings.routineMixID = s.routineMixID
        if let v = s.routineTimerMinutes { settings.routineTimerMinutes = v }
        if let v = s.alarmEnabled { settings.alarmEnabled = v }
        if let v = s.alarmMinuteOfDay { settings.alarmMinuteOfDay = v }
        if let v = s.sunriseMinutes { settings.sunriseMinutes = v }
        settings.alarmMixID = s.alarmMixID
        if let v = s.alarmWeekdays { settings.alarmWeekdays = Set(v) }
        if let v = s.alarmRepeats { settings.alarmRepeats = v }
        if let v = s.bedtimeMinuteOfDay { settings.bedtimeMinuteOfDay = v }
        if let v = s.bedtimeReminderEnabled { settings.bedtimeReminderEnabled = v }
        if let v = s.windDownEnabled { settings.windDownEnabled = v }
        if let v = s.autoDim { settings.autoDim = v }
        if let v = s.autoDimSeconds { settings.autoDimSeconds = v }
        if let v = s.hapticsEnabled { settings.hapticsEnabled = v }
        if let v = s.reduceGlow { settings.reduceGlow = v }
        if let v = s.favouriteSoundIDs { settings.favouriteSoundIDs = Set(v) }
        if let v = s.hasOnboarded { settings.hasOnboarded = v }
        if let v = s.goal { settings.goal = v }
        if let v = s.nightsCompleted { settings.nightsCompleted = v }
        if let v = s.didOfferAfterFirstNight { settings.didOfferAfterFirstNight = v }
        settings.lastPaywallShown = s.lastPaywallShown
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
            breathGuideSound: breathGuideSound,
            breathHaptics: breathHaptics,
            breathMinutes: breathMinutes,
            customBreath: customBreath,
            routineBreathPatternID: routineBreathPatternID,
            routineBreathMinutes: routineBreathMinutes,
            routineMixID: routineMixID,
            routineTimerMinutes: routineTimerMinutes,
            alarmEnabled: alarmEnabled,
            alarmMinuteOfDay: alarmMinuteOfDay,
            sunriseMinutes: sunriseMinutes,
            alarmMixID: alarmMixID,
            alarmWeekdays: Array(alarmWeekdays).sorted(),
            alarmRepeats: alarmRepeats,
            bedtimeMinuteOfDay: bedtimeMinuteOfDay,
            bedtimeReminderEnabled: bedtimeReminderEnabled,
            windDownEnabled: windDownEnabled,
            autoDim: autoDim,
            autoDimSeconds: autoDimSeconds,
            hapticsEnabled: hapticsEnabled,
            reduceGlow: reduceGlow,
            favouriteSoundIDs: Array(favouriteSoundIDs).sorted(),
            hasOnboarded: hasOnboarded,
            goal: goal,
            nightsCompleted: nightsCompleted,
            didOfferAfterFirstNight: didOfferAfterFirstNight,
            lastPaywallShown: lastPaywallShown
        )
        Persistence.save(snapshot, to: Settings.filename)
    }
}
