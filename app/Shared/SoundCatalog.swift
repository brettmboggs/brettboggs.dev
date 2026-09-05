import Foundation

/// Where a sound comes from. Recordings and synthesis are otherwise
/// interchangeable: both end up as one voice in the same renderer.
public enum SoundSource: Codable, Hashable, Sendable {
    case synth
    /// Bundled `.m4a`, streamed and looped with a crossfade.
    case recording(resource: String)

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

/// Which shelf a texture lives on in the library.
public enum SoundFamily: String, Codable, CaseIterable, Sendable {
    case recorded, rain, water, wind, fire, noise, night, machines

    public var title: String {
        switch self {
        case .recorded: return "Recordings"
        case .rain: return "Rain"
        case .water: return "Water"
        case .wind: return "Wind"
        case .fire: return "Fire"
        case .noise: return "Noise"
        case .night: return "Night"
        case .machines: return "Machines"
        }
    }

    /// Ordering in the library. Declared explicitly so adding a case later
    /// does not silently reshuffle the shelves.
    public var rank: Int {
        switch self {
        case .recorded: return 0
        case .rain: return 1
        case .water: return 2
        case .wind: return 3
        case .fire: return 4
        case .night: return 5
        case .machines: return 6
        case .noise: return 7
        }
    }
}

/// Static description of one synthesizable texture.
///
/// There are no audio files anywhere in this app. Every sound is generated a
/// sample at a time by the matching case in `TextureVoice`, so the `id` here is
/// load-bearing: it is the key the audio engine switches on.
public struct SoundKind: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let family: SoundFamily
    public let blurb: String
    public let symbol: String
    /// What the first shaping slider does for this texture.
    public let toneLabel: String
    /// What the second shaping slider does for this texture.
    public let motionLabel: String
    public let defaultTone: Double
    public let defaultMotion: Double
    public let defaultLevel: Double
    public let source: SoundSource

    public init(
        id: String,
        name: String,
        family: SoundFamily,
        blurb: String,
        symbol: String,
        toneLabel: String = "Tone",
        motionLabel: String = "Motion",
        defaultTone: Double = 0.5,
        defaultMotion: Double = 0.5,
        defaultLevel: Double = 0.7,
        source: SoundSource = .synth
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.blurb = blurb
        self.symbol = symbol
        self.toneLabel = toneLabel
        self.motionLabel = motionLabel
        self.defaultTone = defaultTone
        self.defaultMotion = defaultMotion
        self.defaultLevel = defaultLevel
        self.source = source
    }

    public var isRecording: Bool { source.isRecording }
}

public enum SoundCatalog {
    public static let all: [SoundKind] = [
        SoundKind(
            id: "rec.brown", name: "Brown Noise", family: .recorded,
            blurb: "Recorded, not generated. Ten minutes, looped.",
            symbol: "waveform.path",
            toneLabel: "Tilt", motionLabel: "Drift",
            defaultTone: 0.5, defaultMotion: 0.3, defaultLevel: 0.72,
            source: .recording(resource: "brown-noise")
        ),
        SoundKind(
            id: "rec.deep-brown", name: "Deep Brown", family: .recorded,
            blurb: "The same room, lower and heavier.",
            symbol: "waveform.path.ecg",
            toneLabel: "Tilt", motionLabel: "Drift",
            defaultTone: 0.44, defaultMotion: 0.3, defaultLevel: 0.78,
            source: .recording(resource: "deep-brown")
        ),
        SoundKind(
            id: "rain.light", name: "Light Rain", family: .rain,
            blurb: "Steady drizzle on a window.", symbol: "cloud.drizzle",
            toneLabel: "Glass", motionLabel: "Drops",
            defaultTone: 0.45, defaultMotion: 0.5
        ),
        SoundKind(
            id: "rain.heavy", name: "Downpour", family: .rain,
            blurb: "The kind that empties the street.", symbol: "cloud.heavyrain",
            toneLabel: "Body", motionLabel: "Surge",
            defaultTone: 0.4, defaultMotion: 0.45
        ),
        SoundKind(
            id: "rain.roof", name: "Rain on a Roof", family: .rain,
            blurb: "Tin, a porch, somewhere dry.", symbol: "house",
            toneLabel: "Metal", motionLabel: "Drips",
            defaultTone: 0.55, defaultMotion: 0.55
        ),
        SoundKind(
            id: "storm", name: "Thunderstorm", family: .rain,
            blurb: "Rain with weather behind it.", symbol: "cloud.bolt.rain",
            toneLabel: "Distance", motionLabel: "Frequency",
            defaultTone: 0.65, defaultMotion: 0.4
        ),
        SoundKind(
            id: "ocean", name: "Ocean", family: .water,
            blurb: "Long sets, coarse sand.", symbol: "water.waves",
            toneLabel: "Foam", motionLabel: "Swell",
            defaultTone: 0.45, defaultMotion: 0.5
        ),
        SoundKind(
            id: "stream", name: "Creek", family: .water,
            blurb: "Shallow water over rock.", symbol: "drop",
            toneLabel: "Depth", motionLabel: "Burble",
            defaultTone: 0.5, defaultMotion: 0.5
        ),
        SoundKind(
            id: "wind.plain", name: "Open Wind", family: .wind,
            blurb: "Nothing to break it up.", symbol: "wind",
            toneLabel: "Height", motionLabel: "Gusts",
            defaultTone: 0.4, defaultMotion: 0.45
        ),
        SoundKind(
            id: "wind.trees", name: "Wind in Pines", family: .wind,
            blurb: "Needles, high up.", symbol: "tree",
            toneLabel: "Canopy", motionLabel: "Gusts",
            defaultTone: 0.6, defaultMotion: 0.5
        ),
        SoundKind(
            id: "fire", name: "Campfire", family: .fire,
            blurb: "Low and popping.", symbol: "flame",
            toneLabel: "Coals", motionLabel: "Crackle",
            defaultTone: 0.45, defaultMotion: 0.5
        ),
        SoundKind(
            id: "crickets", name: "Crickets", family: .night,
            blurb: "August, after dark.", symbol: "moon.stars",
            toneLabel: "Pitch", motionLabel: "Density",
            defaultTone: 0.5, defaultMotion: 0.4, defaultLevel: 0.5
        ),
        SoundKind(
            id: "cabin", name: "Room Tone", family: .night,
            blurb: "An old house holding still.", symbol: "square.split.bottomrightquarter",
            toneLabel: "Air", motionLabel: "Drift",
            defaultTone: 0.4, defaultMotion: 0.35
        ),
        SoundKind(
            id: "fan", name: "Box Fan", family: .machines,
            blurb: "Oscillating, on medium.", symbol: "fan",
            toneLabel: "Motor", motionLabel: "Blades",
            defaultTone: 0.5, defaultMotion: 0.4
        ),
        SoundKind(
            id: "airliner", name: "Cabin Pressure", family: .machines,
            blurb: "Row 27, somewhere over Kansas.", symbol: "airplane",
            toneLabel: "Hull", motionLabel: "Turbulence",
            defaultTone: 0.4, defaultMotion: 0.3
        ),
        SoundKind(
            id: "train", name: "Night Train", family: .machines,
            blurb: "Rails, and the gaps between them.", symbol: "tram",
            toneLabel: "Car", motionLabel: "Clatter",
            defaultTone: 0.45, defaultMotion: 0.5
        ),
        SoundKind(
            id: "noise.white", name: "White", family: .noise,
            blurb: "Flat, bright, total.", symbol: "waveform",
            toneLabel: "Tilt", motionLabel: "Width",
            defaultTone: 0.5, defaultMotion: 0.5, defaultLevel: 0.5
        ),
        SoundKind(
            id: "noise.pink", name: "Pink", family: .noise,
            blurb: "Even energy per octave.", symbol: "waveform.path",
            toneLabel: "Tilt", motionLabel: "Width",
            defaultTone: 0.5, defaultMotion: 0.5, defaultLevel: 0.6
        ),
        SoundKind(
            id: "noise.brown", name: "Brown", family: .noise,
            blurb: "Deep. Most people mean this one.", symbol: "waveform.path.ecg",
            toneLabel: "Tilt", motionLabel: "Width",
            defaultTone: 0.5, defaultMotion: 0.5, defaultLevel: 0.75
        ),
    ]

    private static let index: [String: SoundKind] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    public static func kind(for id: String) -> SoundKind? { index[id] }

    /// Every sound backed by a bundled file.
    public static var recordings: [SoundKind] { all.filter(\.isRecording) }

    /// Library shelves, ordered.
    public static var shelves: [(family: SoundFamily, sounds: [SoundKind])] {
        Dictionary(grouping: all, by: \.family)
            .sorted { $0.key.rank < $1.key.rank }
            .map { (family: $0.key, sounds: $0.value) }
    }
}
