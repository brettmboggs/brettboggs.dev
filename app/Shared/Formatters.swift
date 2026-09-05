import Foundation

enum Format {
    /// "1:24:05" or "24:05". Used for counters that tick.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "7h 20m", "45m". Used for durations that are read, not watched.
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    /// Minutes past midnight to a locale-correct "10:30 PM".
    static func timeOfDay(minuteOfDay: Int) -> String {
        var components = DateComponents()
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        let date = Calendar.current.date(from: components) ?? Date()
        return timeFormatter.string(from: date)
    }

    static func timeOfDay(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func dayAndTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today · \(timeFormatter.string(from: date))" }
        if calendar.isDateInYesterday(date) { return "Yesterday · \(timeFormatter.string(from: date))" }
        return dayFormatter.string(from: date)
    }

    /// "S M T W T F S" initials for the alarm repeat row.
    static func weekdayInitial(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "?" }
        return symbols[index]
    }

    static func weekdaySummary(_ weekdays: Set<Int>) -> String {
        if weekdays.isEmpty { return "Once" }
        if weekdays == Set(1...7) { return "Every day" }
        if weekdays == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if weekdays == Set([1, 7]) { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted()
            .compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
            .joined(separator: " ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM · j:mm")
        return formatter
    }()
}
