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
    case recorded, rain, water, wind, fire, living, machines, places, tones, noise

    public var title: String {
        switch self {
        case .recorded: return "Recordings"
        case .rain: return "Rain"
        case .water: return "Water"
        case .wind: return "Wind"
        case .fire: return "Fire"
        case .living: return "Living"
        case .machines: return "Machines"
        case .places: return "Places"
        case .tones: return "Tones"
        case .noise: return "Noise"
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
        case .living: return 5
        case .machines: return 6
        case .places: return 7
        case .tones: return 8
        case .noise: return 9
        }
    }
}

/// Static description of one synthesizable texture.
///
/// Most sounds are generated a sample at a time by the matching case in
/// `TextureFactory`, so the `id` here is load-bearing: it is the key the
/// audio engine switches on.
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
    /// Linear gain applied before the slider, so the slider means the same
    /// loudness on every sound. Measured, not guessed: see tools/measure.
    public let trim: Double
    /// Free sounds work forever without paying. Everything else is in Plus,
    /// and can be previewed for a while before the ask.
    public let isFree: Bool

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
        source: SoundSource = .synth,
        isFree: Bool = false,
        trim: Double = 1
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
        self.isFree = isFree
        self.trim = trim
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
            defaultTone: 0.45, defaultMotion: 0.5,
            isFree: true,
            trim: 2.60
        ),
        SoundKind(
            id: "rain.heavy", name: "Downpour", family: .rain,
            blurb: "The kind that empties the street.", symbol: "cloud.heavyrain",
            toneLabel: "Body", motionLabel: "Surge",
            defaultTone: 0.4, defaultMotion: 0.45,
            isFree: true,
            trim: 1.40
        ),
        SoundKind(
            id: "rain.roof", name: "Rain on a Roof", family: .rain,
            blurb: "Tin, a porch, somewhere dry.", symbol: "house",
            toneLabel: "Metal", motionLabel: "Drips",
            defaultTone: 0.55, defaultMotion: 0.55,
            trim: 0.73
        ),
        SoundKind(
            id: "storm", name: "Thunderstorm", family: .rain,
            blurb: "Rain with weather behind it.", symbol: "cloud.bolt.rain",
            toneLabel: "Distance", motionLabel: "Frequency",
            defaultTone: 0.65, defaultMotion: 0.4,
            trim: 1.11
        ),
        SoundKind(
            id: "ocean", name: "Ocean", family: .water,
            blurb: "Long sets, coarse sand.", symbol: "water.waves",
            toneLabel: "Foam", motionLabel: "Swell",
            defaultTone: 0.45, defaultMotion: 0.5,
            isFree: true,
            trim: 1.03
        ),
        SoundKind(
            id: "stream", name: "Creek", family: .water,
            blurb: "Shallow water over rock.", symbol: "drop",
            toneLabel: "Depth", motionLabel: "Burble",
            defaultTone: 0.5, defaultMotion: 0.5,
            isFree: true,
            trim: 1.51
        ),
        SoundKind(
            id: "wind.plain", name: "Open Wind", family: .wind,
            blurb: "Nothing to break it up.", symbol: "wind",
            toneLabel: "Height", motionLabel: "Gusts",
            defaultTone: 0.4, defaultMotion: 0.45,
            isFree: true,
            trim: 1.56
        ),
        SoundKind(
            id: "wind.trees", name: "Wind in Pines", family: .wind,
            blurb: "Needles, high up.", symbol: "tree",
            toneLabel: "Canopy", motionLabel: "Gusts",
            defaultTone: 0.6, defaultMotion: 0.5,
            trim: 1.76
        ),
        SoundKind(
            id: "fire", name: "Campfire", family: .fire,
            blurb: "Low and popping.", symbol: "flame",
            toneLabel: "Coals", motionLabel: "Crackle",
            defaultTone: 0.45, defaultMotion: 0.5,
            isFree: true,
            trim: 1.06
        ),
        SoundKind(
            id: "crickets", name: "Crickets", family: .living,
            blurb: "August, after dark.", symbol: "moon.stars",
            toneLabel: "Pitch", motionLabel: "Density",
            defaultTone: 0.5, defaultMotion: 0.4, defaultLevel: 0.5,
            isFree: true,
            trim: 4.63
        ),
        SoundKind(
            id: "cabin", name: "Room Tone", family: .places,
            blurb: "An old house holding still.", symbol: "square.split.bottomrightquarter",
            toneLabel: "Air", motionLabel: "Drift",
            defaultTone: 0.4, defaultMotion: 0.35,
            isFree: true,
            trim: 0.59
        ),
        SoundKind(
            id: "fan", name: "Box Fan", family: .machines,
            blurb: "Oscillating, on medium.", symbol: "fan",
            toneLabel: "Motor", motionLabel: "Blades",
            defaultTone: 0.5, defaultMotion: 0.4,
            isFree: true,
            trim: 1.42
        ),
        SoundKind(
            id: "airliner", name: "Cabin Pressure", family: .machines,
            blurb: "Row 27, somewhere over Kansas.", symbol: "airplane",
            toneLabel: "Hull", motionLabel: "Turbulence",
            defaultTone: 0.4, defaultMotion: 0.3,
            trim: 0.46
        ),
        SoundKind(
            id: "train", name: "Night Train", family: .machines,
            blurb: "Rails, and the gaps between them.", symbol: "tram",
            toneLabel: "Car", motionLabel: "Clatter",
            defaultTone: 0.45, defaultMotion: 0.5,
            trim: 0.61
        ),
        SoundKind(
            id: "thunder.distant", name: "Distant Thunder", family: .rain,
            blurb: "Weather that stayed away.", symbol: "cloud.bolt",
            toneLabel: "Distance", motionLabel: "Frequency",
            defaultTone: 0.35, defaultMotion: 0.4, defaultLevel: 0.6,
            trim: 2.67
        ),
        SoundKind(
            id: "waterfall", name: "Waterfall", family: .water,
            blurb: "Heavy water, close up.", symbol: "arrow.down.to.line",
            toneLabel: "Spray", motionLabel: "Surge",
            defaultTone: 0.42, defaultMotion: 0.45, defaultLevel: 0.72,
            trim: 0.23
        ),
        SoundKind(
            id: "blizzard", name: "Blizzard", family: .wind,
            blurb: "Snow takes the top end with it.", symbol: "snowflake",
            toneLabel: "Height", motionLabel: "Gusts",
            defaultTone: 0.4, defaultMotion: 0.5, defaultLevel: 0.68,
            trim: 1.07
        ),
        SoundKind(
            id: "frogs", name: "Frogs", family: .living,
            blurb: "A pond, well after dark.", symbol: "leaf",
            toneLabel: "Pitch", motionLabel: "Density",
            defaultTone: 0.45, defaultMotion: 0.4, defaultLevel: 0.5,
            trim: 5.09
        ),
        SoundKind(
            id: "birds", name: "Dawn Chorus", family: .living,
            blurb: "Made for waking, not for sleeping.", symbol: "bird",
            toneLabel: "Pitch", motionLabel: "Density",
            defaultTone: 0.5, defaultMotion: 0.45, defaultLevel: 0.45,
            trim: 7.94
        ),
        SoundKind(
            id: "purr", name: "Purring", family: .living,
            blurb: "A cat that has decided to stay.", symbol: "pawprint",
            toneLabel: "Size", motionLabel: "Rumble",
            defaultTone: 0.45, defaultMotion: 0.55, defaultLevel: 0.6,
            trim: 1.21
        ),
        SoundKind(
            id: "heartbeat", name: "Womb", family: .living,
            blurb: "Sixty beats, and the sound around them.", symbol: "heart",
            toneLabel: "Depth", motionLabel: "Rate",
            defaultTone: 0.45, defaultMotion: 0.35, defaultLevel: 0.7,
            trim: 0.74
        ),
        SoundKind(
            id: "fan.oscillating", name: "Oscillating Fan", family: .machines,
            blurb: "Turning away, and back.", symbol: "arrow.trianglehead.2.clockwise",
            toneLabel: "Motor", motionLabel: "Sweep",
            defaultTone: 0.5, defaultMotion: 0.45, defaultLevel: 0.7,
            trim: 0.70
        ),
        SoundKind(
            id: "ac", name: "Air Conditioner", family: .machines,
            blurb: "The window unit, on low.", symbol: "snowflake.circle",
            toneLabel: "Air", motionLabel: "Compressor",
            defaultTone: 0.45, defaultMotion: 0.4, defaultLevel: 0.7,
            trim: 0.37
        ),
        SoundKind(
            id: "washer", name: "Washing Machine", family: .machines,
            blurb: "Mid cycle, through a wall.", symbol: "washer",
            toneLabel: "Motor", motionLabel: "Cycle",
            defaultTone: 0.45, defaultMotion: 0.4, defaultLevel: 0.68,
            trim: 1.12
        ),
        SoundKind(
            id: "dryer", name: "Tumble Dryer", family: .machines,
            blurb: "Something in there goes around.", symbol: "dryer",
            toneLabel: "Heat", motionLabel: "Tumble",
            defaultTone: 0.42, defaultMotion: 0.4, defaultLevel: 0.68,
            trim: 0.59
        ),
        SoundKind(
            id: "cafe", name: "Coffee Shop", family: .places,
            blurb: "Voices, never words.", symbol: "cup.and.saucer",
            toneLabel: "Room", motionLabel: "Bustle",
            defaultTone: 0.45, defaultMotion: 0.45, defaultLevel: 0.55,
            trim: 3.28
        ),
        SoundKind(
            id: "highway", name: "Distant Highway", family: .places,
            blurb: "Far enough that cars are weather.", symbol: "road.lanes",
            toneLabel: "Distance", motionLabel: "Traffic",
            defaultTone: 0.35, defaultMotion: 0.4, defaultLevel: 0.65,
            trim: 0.66
        ),
        SoundKind(
            id: "clock", name: "Mantel Clock", family: .places,
            blurb: "One second, then the next.", symbol: "clock",
            toneLabel: "Wood", motionLabel: "Tempo",
            defaultTone: 0.45, defaultMotion: 0.4, defaultLevel: 0.45,
            trim: 6.97
        ),
        SoundKind(
            id: "chimes", name: "Wind Chimes", family: .tones,
            blurb: "The wind decides when.", symbol: "wind.snow",
            toneLabel: "Tuning", motionLabel: "Breeze",
            defaultTone: 0.45, defaultMotion: 0.35, defaultLevel: 0.5,
            trim: 6.69
        ),
        SoundKind(
            id: "bowl", name: "Singing Bowl", family: .tones,
            blurb: "Struck, then left alone.", symbol: "circle.circle",
            toneLabel: "Pitch", motionLabel: "Shimmer",
            defaultTone: 0.4, defaultMotion: 0.4, defaultLevel: 0.55,
            trim: 7.36
        ),
        SoundKind(
            id: "noise.white", name: "White", family: .noise,
            blurb: "Flat, bright, total.", symbol: "waveform",
            toneLabel: "Tilt", motionLabel: "Width",
            defaultTone: 0.5, defaultMotion: 0.5, defaultLevel: 0.5,
            isFree: true,
            trim: 2.07
        ),
        SoundKind(
            id: "noise.pink", name: "Pink", family: .noise,
            blurb: "Even energy per octave.", symbol: "waveform.path",
            toneLabel: "Tilt", motionLabel: "Width",
            defaultTone: 0.5, defaultMotion: 0.5, defaultLevel: 0.6,
            isFree: true,
            trim: 0.76
        ),
        SoundKind(
            id: "noise.brown", name: "Brown", family: .noise,
            blurb: "Deep. Most people mean this one.", symbol: "waveform.path.ecg",
            toneLabel: "Tilt", motionLabel: "Width",
            defaultTone: 0.5, defaultMotion: 0.5, defaultLevel: 0.75,
            isFree: true,
            trim: 1.13
        ),
    ]

    private static let index: [String: SoundKind] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    public static func kind(for id: String) -> SoundKind? { index[id] }

    /// Every sound backed by a bundled file.
    public static var recordings: [SoundKind] { all.filter(\.isRecording) }

    public static var free: [SoundKind] { all.filter(\.isFree) }
    public static var plusOnly: [SoundKind] { all.filter { !$0.isFree } }

    /// Library shelves, ordered.
    public static var shelves: [(family: SoundFamily, sounds: [SoundKind])] {
        Dictionary(grouping: all, by: \.family)
            .sorted { $0.key.rank < $1.key.rank }
            .map { (family: $0.key, sounds: $0.value) }
    }
}
