import Foundation

/// One texture inside a mix, with its level and its two shaping parameters.
public struct Layer: Identifiable, Codable, Hashable, Sendable {
    public var id: String { soundID }
    public var soundID: String
    /// Linear 0...1. Mapped to a perceptual curve before it reaches the engine.
    public var level: Double
    public var tone: Double
    public var motion: Double
    /// Temporarily silenced without being removed from the mix.
    public var isMuted: Bool

    public init(soundID: String, level: Double, tone: Double, motion: Double, isMuted: Bool = false) {
        self.soundID = soundID
        self.level = level
        self.tone = tone
        self.motion = motion
        self.isMuted = isMuted
    }

    public init(kind: SoundKind) {
        self.init(
            soundID: kind.id,
            level: kind.defaultLevel,
            tone: kind.defaultTone,
            motion: kind.defaultMotion
        )
    }

    public var kind: SoundKind? { SoundCatalog.kind(for: soundID) }
    public var name: String { kind?.name ?? soundID }
}

/// A named stack of layers. Presets and user-saved mixes are the same type;
/// `isBuiltIn` only affects whether it can be deleted.
public struct Mix: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var layers: [Layer]
    public var isBuiltIn: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        layers: [Layer],
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.layers = layers
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }

    public var isEmpty: Bool { layers.isEmpty }

    /// "Light Rain · Brown" for subtitles.
    public var summary: String {
        let names = layers.compactMap { SoundCatalog.kind(for: $0.soundID)?.name }
        return names.isEmpty ? "Nothing yet" : names.joined(separator: " · ")
    }

    public func layer(for soundID: String) -> Layer? {
        layers.first { $0.soundID == soundID }
    }

    public func contains(_ soundID: String) -> Bool {
        layers.contains { $0.soundID == soundID }
    }

    /// True when every sound in the mix is on the free shelf.
    public var usesOnlyFreeSounds: Bool {
        layers.allSatisfy { SoundCatalog.kind(for: $0.soundID)?.isFree ?? false }
    }
}

// MARK: - Curated starting points

public extension Mix {
    /// Deterministic IDs so a preset keeps its identity across launches.
    private static func builtInID(_ seed: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(seed.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        var mixed = hash
        for index in 0..<16 {
            bytes[index] = UInt8(truncatingIfNeeded: mixed >> UInt64((index % 8) * 8))
            if index == 7 { mixed = hash &* 0x9e37_79b9_7f4a_7c15 }
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func make(_ name: String, _ layers: [(String, Double, Double, Double)]) -> Mix {
        Mix(
            id: builtInID(name),
            name: name,
            layers: layers.map {
                Layer(soundID: $0.0, level: $0.1, tone: $0.2, motion: $0.3)
            },
            isBuiltIn: true
        )
    }

    /// The first four use only free sounds, so a new install has somewhere
    /// good to start. The rest show what Plus opens up.
    static let presets: [Mix] = [
        make("Long Rain", [
            ("rain.light", 0.72, 0.42, 0.50),
            ("noise.brown", 0.30, 0.40, 0.50),
        ]),
        make("Deep Brown", [
            ("noise.brown", 0.82, 0.44, 0.55),
        ]),
        make("Coastline", [
            ("ocean", 0.76, 0.44, 0.52),
            ("wind.plain", 0.28, 0.34, 0.42),
        ]),
        make("Cabin", [
            ("fire", 0.62, 0.42, 0.48),
            ("cabin", 0.34, 0.36, 0.30),
        ]),
        make("Tin Roof", [
            ("rain.roof", 0.74, 0.58, 0.60),
            ("cabin", 0.34, 0.35, 0.30),
        ]),
        make("Downpour", [
            ("rain.heavy", 0.78, 0.38, 0.55),
            ("storm", 0.34, 0.72, 0.30),
        ]),
        make("Summer Porch", [
            ("crickets", 0.52, 0.50, 0.40),
            ("wind.trees", 0.36, 0.62, 0.40),
            ("rain.light", 0.22, 0.50, 0.40),
        ]),
        make("Row 27", [
            ("airliner", 0.80, 0.38, 0.28),
        ]),
        make("Night Train", [
            ("train", 0.70, 0.44, 0.50),
            ("rain.light", 0.30, 0.40, 0.45),
        ]),
        make("Creekside", [
            ("stream", 0.70, 0.50, 0.52),
            ("crickets", 0.34, 0.48, 0.34),
        ]),
        make("Recorded Brown", [
            ("rec.deep-brown", 0.82, 0.44, 0.30),
        ]),
    ]

    /// Sunrise textures are deliberately gentler than the sleep library.
    static let wakePresets: [Mix] = [
        make("Dawn Chorus", [
            ("birds", 0.46, 0.50, 0.45),
            ("wind.trees", 0.40, 0.66, 0.42),
        ]),
        make("Morning Rain", [
            ("rain.light", 0.66, 0.58, 0.50),
        ]),
        make("Tide", [
            ("ocean", 0.70, 0.56, 0.60),
        ]),
        make("Open Air", [
            ("wind.plain", 0.62, 0.52, 0.50),
        ]),
    ]

    /// What a new install hears first, chosen from what they said they wanted.
    internal static func recommended(for goal: SleepGoal) -> Mix {
        switch goal {
        case .fallAsleep: return presets[0]
        case .stayAsleep: return presets[1]
        case .windDown: return presets[3]
        case .quietMind: return presets[2]
        }
    }
}
