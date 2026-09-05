import AppIntents
import Foundation

/// What an intent wants the player to do.
enum PlaybackCommand: Sendable {
    case toggle
    case play
    case stop
    case setPlaying(Bool)
    case playMix(UUID)
    case sleepTimer(minutes: Int)
}

/// Decouples the intent declarations from the player.
///
/// Intents conforming to `AudioPlaybackIntent` are executed inside the app's
/// own process (the system launches it in the background if needed), which is
/// the only way a widget or Control Center button can start audio without
/// opening the app. But the *declarations* also have to compile into the widget
/// extension, which has none of the audio code. So the extension gets this
/// bridge with no handler attached, and the app registers the real one at
/// launch. Anything that arrives before registration is queued rather than
/// dropped, which covers a cold launch triggered by the intent itself.
final class IntentBridge {
    static let shared = IntentBridge()

    private init() {}

    private var handler: ((PlaybackCommand) async -> Void)?
    private var pending: [PlaybackCommand] = []

    func register(_ handler: @escaping (PlaybackCommand) async -> Void) {
        self.handler = handler
        let queued = pending
        pending = []
        guard !queued.isEmpty else { return }
        Task {
            for command in queued { await handler(command) }
        }
    }

    func run(_ command: PlaybackCommand) async {
        if let handler {
            await handler(command)
        } else {
            pending.append(command)
        }
    }
}

// MARK: - Entities

struct MixEntity: AppEntity, Identifiable {
    var id: UUID
    var name: String
    var summary: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Mix")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }

    static var defaultQuery = MixQuery()

    init(id: UUID, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }

    init(mix: Mix) {
        self.init(id: mix.id, name: mix.name, summary: mix.summary)
    }
}

struct MixQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [MixEntity] {
        SharedStore.readMixes()
            .filter { identifiers.contains($0.id) }
            .map(MixEntity.init(mix:))
    }

    func suggestedEntities() async throws -> [MixEntity] {
        SharedStore.readMixes().map(MixEntity.init(mix:))
    }

    func defaultResult() async -> MixEntity? {
        SharedStore.readMixes().first.map(MixEntity.init(mix:))
    }
}

// MARK: - Playback intents

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Starts or stops the current mix.")

    func perform() async throws -> some IntentResult {
        await IntentBridge.shared.run(.toggle)
        return .result()
    }
}

struct StartPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Start Sound"
    static var description = IntentDescription("Starts the current mix.")

    func perform() async throws -> some IntentResult {
        await IntentBridge.shared.run(.play)
        return .result()
    }
}

struct StopPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Stop Sound"
    static var description = IntentDescription("Stops playback and clears the sleep timer.")

    func perform() async throws -> some IntentResult {
        await IntentBridge.shared.run(.stop)
        return .result()
    }
}

/// Control Center toggles need an intent that carries the new value.
struct SetPlaybackIntent: SetValueIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Set Playback"

    @Parameter(title: "Playing")
    var value: Bool

    func perform() async throws -> some IntentResult {
        await IntentBridge.shared.run(.setPlaying(value))
        return .result()
    }
}

struct PlayMixIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play a Mix"
    static var description = IntentDescription("Starts one of your saved mixes.")

    @Parameter(title: "Mix")
    var mix: MixEntity

    init() {}

    init(mix: MixEntity) {
        self.mix = mix
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$mix)")
    }

    func perform() async throws -> some IntentResult {
        await IntentBridge.shared.run(.playMix(mix.id))
        return .result()
    }
}

struct SetSleepTimerIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Set Sleep Timer"
    static var description = IntentDescription("Sets how long sound keeps playing.")

    @Parameter(title: "Minutes", default: 45, inclusiveRange: (1, 720))
    var minutes: Int

    init() {}

    init(minutes: Int) {
        self.minutes = minutes
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Play for \(\.$minutes) minutes")
    }

    func perform() async throws -> some IntentResult {
        await IntentBridge.shared.run(.sleepTimer(minutes: minutes))
        return .result()
    }
}
