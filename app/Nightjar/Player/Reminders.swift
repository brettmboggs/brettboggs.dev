import Foundation
import UserNotifications

/// Every local notification the app sends. There are three kinds and none of
/// them are marketing: the alarm's backup, the bedtime nudge you asked for,
/// and a heads-up before a free week becomes a charge.
///
/// The alarm itself is driven in-process, which works because the app stays
/// alive all night playing audio. If playback stopped, or iOS reclaimed the
/// process anyway, the scheduled notification is what still fires.
enum Reminders {
    private static let alarmPrefix = "nightjar.alarm."
    private static let bedtimeID = "nightjar.bedtime"
    private static let trialID = "nightjar.trial"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Alarm

    /// Replaces every scheduled alarm with the current configuration.
    static func rescheduleAlarm(settings: Settings) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let stale = existing.map(\.identifier).filter { $0.hasPrefix(alarmPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard settings.alarmEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Morning"
        content.body = "Time to get up."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let hour = settings.alarmMinuteOfDay / 60
        let minute = settings.alarmMinuteOfDay % 60

        if settings.alarmRepeats && !settings.alarmWeekdays.isEmpty {
            for weekday in settings.alarmWeekdays.sorted() {
                var components = DateComponents()
                components.hour = hour
                components.minute = minute
                components.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(alarmPrefix)w\(weekday)", content: content, trigger: trigger
                )
                try? await center.add(request)
            }
        } else {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components, repeats: settings.alarmRepeats
            )
            let request = UNNotificationRequest(
                identifier: "\(alarmPrefix)daily", content: content, trigger: trigger
            )
            try? await center.add(request)
        }
    }

    // MARK: - Bedtime

    /// A quiet nudge fifteen minutes before the bedtime they chose.
    static func rescheduleBedtime(settings: Settings) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [bedtimeID])
        guard settings.bedtimeReminderEnabled else { return }

        let minuteOfDay = (settings.bedtimeMinuteOfDay - 15 + 24 * 60) % (24 * 60)
        var components = DateComponents()
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60

        let content = UNMutableNotificationContent()
        content.title = "Bed in fifteen"
        content.body = "Lights down. The mix is ready when you are."
        content.sound = nil
        content.interruptionLevel = .passive

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: bedtimeID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Trial

    static func scheduleTrialEnding(at date: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [trialID])

        let content = UNMutableNotificationContent()
        content.title = "Your free week ends in two days"
        content.body = "Nightjar Plus renews after that. Cancel any time in Settings if it is not for you."
        content.sound = nil
        content.interruptionLevel = .passive

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: trialID, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
