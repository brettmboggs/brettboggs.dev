import Foundation
import Observation

/// One night's playback. Recorded locally with no permissions of any kind;
/// mirroring into Health is a separate opt-in.
struct SleepSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var start: Date
    var end: Date
    var mixName: String
    /// True when the session ended at an alarm rather than a timer or a tap.
    var endedAtAlarm: Bool

    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
}

@Observable
final class Journal {
    private(set) var sessions: [SleepSession] = []

    private static let filename = "journal.json"
    /// A year of nights is plenty and keeps the file small.
    private static let limit = 400

    static func load() -> Journal {
        let journal = Journal()
        journal.sessions = Persistence.load([SleepSession].self, from: filename) ?? []
        return journal
    }

    func record(_ session: SleepSession) {
        // Anything under two minutes was a preview, not a night.
        guard session.duration >= 120 else { return }
        sessions.append(session)
        if sessions.count > Journal.limit {
            sessions.removeFirst(sessions.count - Journal.limit)
        }
        Persistence.save(sessions, to: Journal.filename)
    }

    func clear() {
        sessions = []
        Persistence.save(sessions, to: Journal.filename)
    }

    var recent: [SleepSession] {
        sessions.sorted { $0.start > $1.start }
    }

    var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    var averageDuration: TimeInterval {
        sessions.isEmpty ? 0 : totalDuration / Double(sessions.count)
    }

    /// Consecutive calendar days ending today or yesterday.
    var streak: Int {
        guard !sessions.isEmpty else { return 0 }
        let calendar = Calendar.current
        let nights = Set(sessions.map { calendar.startOfDay(for: $0.start) })
        var day = calendar.startOfDay(for: Date())
        if !nights.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  nights.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while nights.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The mix that shows up most often.
    var favouriteMix: String? {
        guard !sessions.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for session in sessions { counts[session.mixName, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }
}
