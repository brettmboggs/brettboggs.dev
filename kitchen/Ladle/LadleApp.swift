import SwiftUI

@main
struct LadleApp: App {
    @State private var library = Library.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Haptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .tint(Ink.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                library.flush()
            }
        }
    }
}
