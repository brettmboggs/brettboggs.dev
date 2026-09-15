import Foundation

enum Meal: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    var title: String { rawValue.capitalizedFirst() }
    var order: Int { Meal.allCases.firstIndex(of: self) ?? 0 }
}

struct PlanEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// "2026-09-15": local calendar day, so it never shifts with time zones.
    var dayKey: String
    var meal: Meal = .dinner
    var recipeID: UUID?
    /// Free text when there is no recipe: "Leftovers", "Out with Dad".
    var note: String = ""

    init(id: UUID = UUID(), dayKey: String, meal: Meal = .dinner, recipeID: UUID? = nil, note: String = "") {
        self.id = id
        self.dayKey = dayKey
        self.meal = meal
        self.recipeID = recipeID
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, dayKey, meal, recipeID, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? DayKey.key(for: Date())
        meal = try c.decodeIfPresent(Meal.self, forKey: .meal) ?? .dinner
        recipeID = try c.decodeIfPresent(UUID.self, forKey: .recipeID)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }

    static var today: String { key(for: Date()) }

    /// The next `count` days starting today.
    static func upcoming(_ count: Int) -> [String] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map(key(for:))
        }
    }

    /// "Today", "Tomorrow", "Wednesday", "Sat 27 Sep".
    static func title(for key: String) -> String {
        guard let date = date(from: key) else { return key }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: date).day ?? 0
        if days > 0 && days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func shortDate(for key: String) -> String {
        guard let date = date(from: key) else { return "" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
