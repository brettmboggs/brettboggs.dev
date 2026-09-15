import AppIntents
import Foundation

/// The cook-mode commands, so "Hey Siri, next step in Ladle" works with the
/// hands full and the phone across the room. None of them open the app: it
/// is already open, propped against the toaster.
struct NextStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Step"
    static var description = IntentDescription("Moves to the next step of the recipe being cooked.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = CookSession.shared
        guard session.isActive else { return .result(dialog: "Nothing is cooking right now.") }
        guard session.next() else { return .result(dialog: "That was the last step.") }
        let spoken = session.spokenStep(system: Library.shared.settings.unitSystem) ?? "Next step."
        return .result(dialog: "\(spoken)")
    }
}

struct PreviousStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Step"
    static var description = IntentDescription("Goes back one step in the recipe being cooked.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = CookSession.shared
        guard session.isActive else { return .result(dialog: "Nothing is cooking right now.") }
        guard session.back() else { return .result(dialog: "This is the first step.") }
        let spoken = session.spokenStep(system: Library.shared.settings.unitSystem) ?? "Previous step."
        return .result(dialog: "\(spoken)")
    }
}

struct RepeatStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Repeat Step"
    static var description = IntentDescription("Reads the current step again.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = CookSession.shared
        guard session.isActive, let spoken = session.spokenStep(system: Library.shared.settings.unitSystem) else {
            return .result(dialog: "Nothing is cooking right now.")
        }
        return .result(dialog: "\(spoken)")
    }
}

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Kitchen Timer"
    static var description = IntentDescription("Starts a timer in Ladle.")

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 720))
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let label = CookSession.shared.recipe?.title ?? "Timer"
        TimerCenter.shared.start(seconds: minutes * 60, label: label, recipeID: CookSession.shared.recipe?.id, stepIndex: CookSession.shared.stepIndex)
        return .result(dialog: "\(minutes) minutes, starting now.")
    }
}

struct AddToShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Shopping List"
    static var description = IntentDescription("Puts something on the Ladle shopping list.")

    @Parameter(title: "Item")
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to the shopping list")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pieces = item.split(whereSeparator: { $0 == "," || $0 == ";" }).map { String($0) }
        let names = pieces.flatMap { piece -> [String] in
            piece.lowercased().contains(" and ") ? piece.components(separatedBy: " and ") : [piece]
        }.map { $0.collapsed }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return .result(dialog: "What should I add?") }
        for name in names { Library.shared.addToShopping(name) }
        if names.count == 1 { return .result(dialog: "Added \(names[0]).") }
        return .result(dialog: "Added \(names.count) things to the list.")
    }
}

struct WhatCanIMakeIntent: AppIntent {
    static var title: LocalizedStringResource = "What Can I Make"
    static var description = IntentDescription("Names recipes the pantry can cover right now.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ready = Library.shared.readyToCook.prefix(3).map(\.recipe.title)
        guard !ready.isEmpty else {
            let close = Library.shared.almostReady.first
            if let close {
                return .result(dialog: "Nothing without a shop, but \(close.recipe.title) is close. \(close.summary).")
            }
            return .result(dialog: "Nothing yet. Add what is in the kitchen to the pantry first.")
        }
        if ready.count == 1 { return .result(dialog: "You could make \(ready[0]).") }
        let list = ready.dropLast().joined(separator: ", ") + " or " + ready.last!
        return .result(dialog: "You could make \(list).")
    }
}

struct LadleShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .grayBlue }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextStepIntent(),
            phrases: [
                "Next step in \(.applicationName)",
                "\(.applicationName) next step",
                "\(.applicationName) next",
            ],
            shortTitle: "Next Step",
            systemImageName: "arrow.right"
        )
        AppShortcut(
            intent: PreviousStepIntent(),
            phrases: [
                "Previous step in \(.applicationName)",
                "Go back in \(.applicationName)",
            ],
            shortTitle: "Previous Step",
            systemImageName: "arrow.left"
        )
        AppShortcut(
            intent: RepeatStepIntent(),
            phrases: [
                "Repeat the step in \(.applicationName)",
                "\(.applicationName) repeat",
            ],
            shortTitle: "Repeat",
            systemImageName: "arrow.counterclockwise"
        )
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a timer in \(.applicationName)",
                "\(.applicationName) timer",
            ],
            shortTitle: "Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: AddToShoppingListIntent(),
            phrases: [
                "Add to my \(.applicationName) list",
                "Add to the shopping list in \(.applicationName)",
            ],
            shortTitle: "Add to List",
            systemImageName: "cart"
        )
        AppShortcut(
            intent: WhatCanIMakeIntent(),
            phrases: [
                "What can I make in \(.applicationName)",
                "Ask \(.applicationName) what's for dinner",
            ],
            shortTitle: "What Can I Make",
            systemImageName: "fork.knife"
        )
    }
}
