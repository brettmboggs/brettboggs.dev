import AppIntents

// App Shortcuts live in the app target only. Declaring the same provider in the
// extension as well would register the phrases twice.

struct HushShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPlaybackIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Play \(.applicationName)",
            ],
            shortTitle: "Start",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: StopPlaybackIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Turn off \(.applicationName)",
            ],
            shortTitle: "Stop",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: PlayMixIntent(),
            phrases: [
                "Play a mix in \(.applicationName)",
                "Start a mix in \(.applicationName)",
            ],
            shortTitle: "Play a mix",
            systemImageName: "square.stack"
        )
        AppShortcut(
            intent: SetSleepTimerIntent(),
            phrases: [
                "Set a sleep timer in \(.applicationName)",
            ],
            shortTitle: "Sleep timer",
            systemImageName: "hourglass"
        )
    }
}
