import SwiftUI

@main
struct MiseApp: App {
    @State private var library = Library.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Haptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .tint(.primary)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                library.flush()
            }
        }
    }
}
