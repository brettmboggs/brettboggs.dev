import AudioToolbox
import Foundation
import Observation
import UserNotifications

struct KitchenTimer: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var totalSeconds: Int
    /// When it goes off, or nil while paused.
    var endDate: Date?
    /// Seconds left at the moment it was paused.
    var pausedRemaining: Int?
    var recipeID: UUID?
    var stepIndex: Int?
    var createdAt: Date = Date()

    var isPaused: Bool { endDate == nil }

    func remaining(at now: Date = Date()) -> Int {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
    }

    func isDone(at now: Date = Date()) -> Bool {
        !isPaused && remaining(at: now) <= 0
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 1 }
        return 1 - Double(remaining()) / Double(totalSeconds)
    }
}

/// A duration spotted in a step: "bake 25 minutes".
struct DetectedTimer: Identifiable, Hashable {
    let seconds: Int
    let label: String
    var id: String { "\(seconds)-\(label)" }
}

/// Kitchen timers that keep going when the app does not. Each one is a
/// local notification, so it rings from the lock screen too.
@MainActor
@Observable
final class TimerCenter {
    static let shared = TimerCenter()

    private(set) var timers: [KitchenTimer] = []
    /// Timers that rang while the app was in front and have not been
    /// dismissed yet.
    private(set) var ringing: Set<UUID> = []

    private var ticker: Timer?
    private static let file = "timers.json"

    init() {
        timers = Persistence.load([KitchenTimer].self, from: TimerCenter.file) ?? []
        // Anything that went off while the app was gone is over.
        let now = Date()
        timers.removeAll { $0.isDone(at: now) && now.timeIntervalSince($0.endDate ?? now) > 3600 }
        for timer in timers where timer.isDone(at: now) { ringing.insert(timer.id) }
        startTicking()
    }

    var hasTimers: Bool { !timers.isEmpty }
    var running: [KitchenTimer] { timers.filter { !$0.isPaused && !$0.isDone() } }

    /// Asks once for permission to ring from the lock screen.
    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    @discardableResult
    func start(seconds: Int, label: String, recipeID: UUID? = nil, stepIndex: Int? = nil) -> KitchenTimer {
        requestPermission()
        let timer = KitchenTimer(
            label: label,
            totalSeconds: max(1, seconds),
            endDate: Date().addingTimeInterval(TimeInterval(max(1, seconds))),
            recipeID: recipeID,
            stepIndex: stepIndex
        )
        timers.append(timer)
        scheduleNotification(for: timer)
        persist()
        startTicking()
        return timer
    }

    func pause(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), !timers[index].isPaused else { return }
        let remaining = timers[index].remaining()
        timers[index].pausedRemaining = remaining
        timers[index].endDate = nil
        cancelNotification(for: id)
        persist()
    }

    func resume(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), let remaining = timers[index].pausedRemaining else { return }
        timers[index].pausedRemaining = nil
        timers[index].endDate = Date().addingTimeInterval(TimeInterval(remaining))
        scheduleNotification(for: timers[index])
        persist()
        startTicking()
    }

    func addMinute(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        if let paused = timers[index].pausedRemaining {
            timers[index].pausedRemaining = paused + 60
        } else if let end = timers[index].endDate {
            timers[index].endDate = max(end, Date()).addingTimeInterval(60)
        }
        timers[index].totalSeconds += 60
        ringing.remove(id)
        scheduleNotification(for: timers[index])
        persist()
        startTicking()
    }

    func stop(_ id: UUID) {
        timers.removeAll { $0.id == id }
        ringing.remove(id)
        cancelNotification(for: id)
        persist()
        if timers.isEmpty { stopTicking() }
    }

    func dismissRinging(_ id: UUID) {
        stop(id)
    }

    func stopAll() {
        for timer in timers { cancelNotification(for: timer.id) }
        timers.removeAll()
        ringing.removeAll()
        persist()
        stopTicking()
    }

    // MARK: Ticking

    private func startTicking() {
        guard ticker == nil, !timers.isEmpty else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        let now = Date()
        var changed = false
        for timer in timers where timer.isDone(at: now) && !ringing.contains(timer.id) {
            ringing.insert(timer.id)
            changed = true
        }
        if changed {
            AudioServicesPlaySystemSound(1005)
            Haptics.success()
        }
        if timers.allSatisfy({ $0.isPaused || $0.isDone(at: now) }) && ringing.isEmpty {
            stopTicking()
        }
    }

    // MARK: Notifications

    private func scheduleNotification(for timer: KitchenTimer) {
        cancelNotification(for: timer.id)
        guard let end = timer.endDate, end > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = timer.label.isEmpty ? "Timer" : timer.label
        content.body = "Time's up."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: timer.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification(for id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    private func persist() {
        Persistence.save(timers, to: TimerCenter.file)
    }
}

/// Finds the durations written into a step, so each can become a timer with
/// one tap or one word.
enum TimerDetector {
    private static let durationRegex = try! NSRegularExpression(
        pattern: #"(?<![\d.])(\d+(?:[.,]\d+)?|\d+ \d/\d|\d/\d|[½¼¾⅓⅔]|an|one|two|three|four|five|six|seven|eight|nine|ten|twelve|fifteen|twenty|twenty-five|thirty|forty|forty-five|fifty|sixty|ninety|half an|half)\s*(?:(?:-|–|to|or)\s*(\d+(?:[.,]\d+)?))?\s*(hours?|hrs?|minutes?|mins?|min\b|seconds?|secs?)\b"#,
        options: [.caseInsensitive]
    )

    private static let words: [String: Double] = [
        "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "twelve": 12, "fifteen": 15, "twenty": 20, "twenty-five": 25, "thirty": 30,
        "forty": 40, "forty-five": 45, "fifty": 50, "sixty": 60, "ninety": 90, "half an": 0.5, "half": 0.5,
    ]

    /// "Simmer 20 to 25 minutes" → 20 min and 25 min.
    static func detect(in text: String) -> [DetectedTimer] {
        let ns = text as NSString
        var found: [DetectedTimer] = []
        for match in durationRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let unit = ns.substring(with: match.range(at: 3)).lowercased()
            let multiplier: Double = unit.hasPrefix("h") ? 3600 : (unit.hasPrefix("s") ? 1 : 60)
            let first = ns.substring(with: match.range(at: 1)).lowercased()
            var values: [Double] = []
            if let v = words[first] ?? Fractions.parse(first) { values.append(v) }
            if match.range(at: 2).location != NSNotFound, let v = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ".")) {
                values.append(v)
            }
            for value in values {
                let seconds = Int((value * multiplier).rounded())
                guard seconds >= 5, seconds <= 24 * 3600 else { continue }
                let timer = DetectedTimer(seconds: seconds, label: label(forSeconds: seconds))
                if !found.contains(timer) { found.append(timer) }
            }
        }
        return found
    }

    static func label(forSeconds seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        if seconds % 3600 == 0 { return seconds == 3600 ? "1 hr" : "\(seconds / 3600) hr" }
        if seconds > 3600 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return "\(h) hr \(m) min"
        }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
