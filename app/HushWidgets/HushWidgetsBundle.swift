import SwiftUI
import WidgetKit

@main
struct HushWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MixWidget()
        SleepTimerLiveActivity()
        HushControl()
    }
}
