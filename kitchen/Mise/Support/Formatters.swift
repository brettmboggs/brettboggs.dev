import Foundation

enum Format {
    /// "45 min", "1 hr", "1 hr 30 min".
    static func minutes(_ total: Int) -> String {
        guard total > 0 else { return "" }
        let hours = total / 60
        let minutes = total % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    /// "12:34" or "1:02:03" for a running timer.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// "Today", "Yesterday", "Last Sunday", "12 Mar".
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        if days < 7 && days > 0 {
            return "Last " + date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "Serves 4", "Makes 12 cookies".
    static func yield(servings: Int?, text: String?) -> String? {
        if let text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            let lower = text.lowercased()
            if lower.hasPrefix("serves") || lower.hasPrefix("makes") || lower.hasPrefix("yield") {
                return text
            }
            if let servings, lower == "\(servings)" || lower == "\(servings) servings" || lower == "\(servings) serving" {
                return "Serves \(servings)"
            }
            return "Makes \(text)"
        }
        if let servings, servings > 0 {
            return "Serves \(servings)"
        }
        return nil
    }

    static func timesCooked(_ count: Int) -> String {
        switch count {
        case 0: return "Never made yet"
        case 1: return "Made once"
        case 2: return "Made twice"
        default: return "Made \(count) times"
        }
    }
}

extension String {
    /// Whitespace collapsed to single spaces and trimmed.
    var collapsed: String {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var nilIfBlank: String? {
        isBlank ? nil : trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func capitalizedFirst() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
