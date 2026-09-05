import Foundation
import UserNotifications

/// Backup path for the alarm.
///
/// The primary alarm is driven in-process, which works because the app stays
/// alive all night playing audio. If playback stopped, or iOS reclaimed the
/// process anyway, these scheduled notifications are what still fires.
enum AlarmNotifications {
    private static let identifierPrefix = "hush.alarm."

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Replaces every scheduled alarm with the current configuration.
    static func reschedule(settings: Settings) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let stale = existing
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard settings.alarmEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Good morning"
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
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components, repeats: true
                )
                let request = UNNotificationRequest(
                    identifier: "\(identifierPrefix)w\(weekday)",
                    content: content,
                    trigger: trigger
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
                identifier: "\(identifierPrefix)daily",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }
}
