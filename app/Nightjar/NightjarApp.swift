import SwiftUI

@main
struct NightjarApp: App {
    @State private var player = PlayerController.shared

    init() {
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
