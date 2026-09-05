import SwiftUI
import UIKit

@main
struct HushApp: App {
    @State private var player: PlayerController

    init() {
        HushApp.configureAppearance()

        let controller = PlayerController(
            settings: Settings.load(),
            library: Library.load(),
            journal: Journal.load(),
            entitlements: Entitlements()
        )
        // Intents fired from a widget or Control Center run inside this process
        // and must reach the same controller the UI is driving.
        PlaybackActions.register(controller: controller)
        _player = State(initialValue: controller)

        Haptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
        }
    }

    /// The tab bar is the one piece of chrome SwiftUI will not let the palette
    /// reach, so it gets set through the appearance proxy.
    private static func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Palette.ground)
        appearance.shadowColor = UIColor(Palette.hairline)

        let item = appearance.stackedLayoutAppearance
        item.normal.iconColor = UIColor(Palette.inkFaint)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Palette.inkFaint)]
        item.selected.iconColor = UIColor(Palette.ember)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Palette.ember)]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
