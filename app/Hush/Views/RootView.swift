import SwiftUI

struct RootView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .now

    enum Tab: Hashable {
        case now, sounds, mixes, wake
    }

    var body: some View {
        @Bindable var player = player

        return ZStack {
            TabView(selection: $tab) {
                NowView()
                    .tabItem { Label("Now", systemImage: "waveform") }
                    .tag(Tab.now)

                SoundsView()
                    .tabItem { Label("Sounds", systemImage: "square.stack.3d.down.right") }
                    .tag(Tab.sounds)

                MixesView()
                    .tabItem { Label("Mixes", systemImage: "rectangle.stack") }
                    .tag(Tab.mixes)

                WakeView()
                    .tabItem { Label("Wake", systemImage: "sunrise") }
                    .tag(Tab.wake)
            }
            .tint(Palette.ember)

            if player.alarmRinging {
                AlarmOverlay()
                    .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.settle, value: player.alarmRinging)
        .sheet(item: $player.paywall) { reason in
            PaywallView(reason: reason)
        }
        .onChange(of: scenePhase) { _, phase in
            player.scenePhaseChanged(to: phase)
        }
    }
}
