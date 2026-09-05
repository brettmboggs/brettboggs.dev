import SwiftUI

@main
struct NightjarApp: App {
    @State private var player: PlayerController

    init() {
        let store = Store()
        let controller = PlayerController(
            settings: Settings.load(),
            library: Library.load(),
            journal: Journal.load(),
            plan: Plan(store: store)
        )
        _player = State(initialValue: controller)
        Haptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .preferredColorScheme(.dark)
        }
    }
}
