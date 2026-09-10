import AppIntents
import Foundation

// MARK: - A mix, as something Siri can name

struct MixEntity: AppEntity, Identifiable {
    let id: UUID
    let name: String
    let detail: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Mix" }
    static var defaultQuery = MixQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(_ mix: Mix) {
        id = mix.id
        name = mix.name
        detail = mix.summary
    }
}

/// `EntityStringQuery` rather than plain `EntityQuery`, because the useful
/// version of this is saying the name out loud rather than picking from a
/// list: "Play Long Rain on Slumbio".
struct MixQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MixEntity] {
        PlayerController.shared.library.allMixes
            .filter { identifiers.contains($0.id) }
            .map(MixEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [MixEntity] {
        let needle = string.lowercased()
        return PlayerController.shared.library.allMixes
            .filter { $0.name.lowercased().contains(needle) }
            .map(MixEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [MixEntity] {
        PlayerController.shared.library.allMixes.prefix(12).map(MixEntity.init)
    }
}

// MARK: - Breathing patterns

enum BreathPatternChoice: String, AppEnum {
    case fourSevenEight
    case box
    case coherent
    case longExhale
    case sigh
    case custom

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Pattern" }

    static var caseDisplayRepresentations: [BreathPatternChoice: DisplayRepresentation] = [
        .fourSevenEight: "4 · 7 · 8",
        .box: "Box",
        .coherent: "Coherent",
        .longExhale: "Long Exhale",
        .sigh: "Physiological Sigh",
        .custom: "Your Own",
    ]

    var patternID: String {
        switch self {
        case .fourSevenEight: return "478"
        case .box: return "box"
        case .coherent: return "coherent"
        case .longExhale: return "long-exhale"
        case .sigh: return "sigh"
        case .custom: return "custom"
        }
    }
}

// MARK: - The intents

/// The whole app in one sentence, so it is the one worth saying.
struct StartWindDownIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Wind Down"
    static var description = IntentDescription(
        "Runs a breathing session, then your mix, then the sleep timer."
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The default routine is free; only editing it belongs to Plus, so
        // there is nothing to gate here.
        let player = PlayerController.shared
        player.startRoutine()
        return .result(dialog: "Winding down.")
    }
}

struct PlayMixIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Sleep Sounds"
    static var description = IntentDescription("Starts a mix, and the sleep timer with it.")
    static var openAppWhenRun = true

    @Parameter(title: "Mix")
    var mix: MixEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$mix)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = PlayerController.shared
        if let mix, let found = player.library.allMixes.first(where: { $0.id == mix.id }) {
            player.load(found)
        }
        guard !player.currentMix.isEmpty else {
            return .result(dialog: "There is nothing in the mix yet.")
        }
        player.play()
        return .result(dialog: "Playing \(player.currentMix.name).")
    }
}

struct StartBreathingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Breathing"
    static var description = IntentDescription("Opens a breathing session and runs it.")
    static var openAppWhenRun = true

    @Parameter(title: "Pattern", default: .fourSevenEight)
    var pattern: BreathPatternChoice

    @Parameter(title: "Minutes", default: 4, inclusiveRange: (2, 15))
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Breathe \(\.$pattern) for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let player = PlayerController.shared
        let chosen = BreathPattern.named(pattern.patternID, custom: player.settings.customBreath)
        guard player.plan.allows(chosen) else {
            return .result(dialog: "\(chosen.name) is part of Slumbio Plus.")
        }
        player.startBreath(chosen, minutes: minutes)
        return .result(dialog: "\(chosen.name), \(minutes) minutes.")
    }
}

struct SetSleepTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Set the Sleep Timer"
    static var description = IntentDescription("Sets how long the sound runs for.")

    @Parameter(title: "Minutes", default: 45, inclusiveRange: (0, 480))
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set the sleep timer to \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PlayerController.shared.setTimer(minutes: minutes)
        if minutes == 0 {
            return .result(dialog: "Sleep timer off.")
        }
        return .result(dialog: "Sleep timer set to \(minutes) minutes.")
    }
}

/// No `openAppWhenRun`: stopping should not throw a lit screen at someone who
/// is already in bed.
struct StopSlumbioIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Slumbio"
    static var description = IntentDescription("Stops the sound and ends any session.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PlayerController.shared.stopEverything()
        return .result(dialog: "Stopped.")
    }
}

// MARK: - What Siri offers without being asked

struct SlumbioShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWindDownIntent(),
            phrases: [
                "Start wind down in \(.applicationName)",
                "Wind down with \(.applicationName)",
                "\(.applicationName) wind down",
            ],
            shortTitle: "Wind Down",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: PlayMixIntent(),
            phrases: [
                "Play sleep sounds in \(.applicationName)",
                "Play \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Play",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: StartBreathingIntent(),
            phrases: [
                "Start breathing in \(.applicationName)",
                "Breathe with \(.applicationName)",
            ],
            shortTitle: "Breathe",
            systemImageName: "wind"
        )
        AppShortcut(
            intent: SetSleepTimerIntent(),
            phrases: [
                "Set the \(.applicationName) sleep timer",
                "Set a sleep timer in \(.applicationName)",
            ],
            shortTitle: "Sleep Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StopSlumbioIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Turn off \(.applicationName)",
            ],
            shortTitle: "Stop",
            systemImageName: "stop.fill"
        )
    }
}
