import Foundation

/// Everything the widget extension is allowed to know about the app.
///
/// The extension cannot reach into the running audio engine, so the app writes
/// a small snapshot into the shared App Group container on every meaningful
/// state change and the widgets read it back.
public struct PlaybackSnapshot: Codable, Sendable, Equatable {
    public var isPlaying: Bool
    public var mixName: String
    public var mixSummary: String
    public var layerCount: Int
    /// When the running sleep timer fires, if one is set.
    public var timerEnd: Date?
    /// When the next alarm fires, if one is armed.
    public var wakeAt: Date?
    public var updatedAt: Date

    public init(
        isPlaying: Bool = false,
        mixName: String = "Nothing playing",
        mixSummary: String = "",
        layerCount: Int = 0,
        timerEnd: Date? = nil,
        wakeAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.isPlaying = isPlaying
        self.mixName = mixName
        self.mixSummary = mixSummary
        self.layerCount = layerCount
        self.timerEnd = timerEnd
        self.wakeAt = wakeAt
        self.updatedAt = updatedAt
    }

    public static let placeholder = PlaybackSnapshot(
        isPlaying: true,
        mixName: "Long Rain",
        mixSummary: "Light Rain · Brown",
        layerCount: 2,
        timerEnd: Date().addingTimeInterval(45 * 60)
    )
}

/// Small, dependency-free bridge over the App Group's UserDefaults.
public enum SharedStore {
    public static let appGroupID = "group.dev.brettboggs.hush"
    public static let widgetKind = "HushMixWidget"
    public static let controlKind = "HushPlaybackControl"

    private enum Key {
        static let snapshot = "playback.snapshot"
        static let mixes = "library.mixes"
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: Snapshot

    public static func writeSnapshot(_ snapshot: PlaybackSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
    }

    public static func readSnapshot() -> PlaybackSnapshot {
        guard
            let data = defaults.data(forKey: Key.snapshot),
            let snapshot = try? decoder.decode(PlaybackSnapshot.self, from: data)
        else { return PlaybackSnapshot() }
        return snapshot
    }

    // MARK: Mix library (so widget configuration can list saved mixes)

    public static func writeMixes(_ mixes: [Mix]) {
        guard let data = try? encoder.encode(mixes) else { return }
        defaults.set(data, forKey: Key.mixes)
    }

    public static func readMixes() -> [Mix] {
        guard
            let data = defaults.data(forKey: Key.mixes),
            let mixes = try? decoder.decode([Mix].self, from: data)
        else { return Mix.presets }
        return mixes
    }
}
