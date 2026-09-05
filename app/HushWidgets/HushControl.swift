import AppIntents
import SwiftUI
import WidgetKit

// Control Center toggle. This is the newest API surface in the project; if a
// future SDK moves it, this one file is safe to delete without touching
// anything else.

struct PlaybackValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        SharedStore.readSnapshot().isPlaying
    }
}

struct HushControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedStore.controlKind,
            provider: PlaybackValueProvider()
        ) { isPlaying in
            ControlWidgetToggle(
                "Hush",
                isOn: isPlaying,
                action: SetPlaybackIntent()
            ) { on in
                Label(
                    on ? "Playing" : "Off",
                    systemImage: on ? "waveform" : "moon.zzz"
                )
            }
            .tint(Palette.ember)
        }
        .displayName("Hush")
        .description("Start or stop sleep sound.")
    }
}
