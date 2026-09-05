import Foundation

/// The app-side half of the intents: turns a `PlaybackCommand` into real
/// playback. Lives only in the app target, and is wired to `IntentBridge` once
/// at launch.
enum PlaybackActions {

    static func register(controller: PlayerController) {
        IntentBridge.shared.register { command in
            await MainActor.run {
                apply(command, to: controller)
            }
        }
    }

    private static func apply(_ command: PlaybackCommand, to player: PlayerController) {
        switch command {
        case .toggle:
            player.toggle()

        case .play:
            player.play()

        case .stop:
            player.stopEverything()

        case .setPlaying(let shouldPlay):
            if shouldPlay {
                player.play()
            } else {
                player.stopEverything()
            }

        case .playMix(let id):
            if let mix = player.library.mix(withID: id) {
                player.load(mix)
            }
            player.play()

        case .sleepTimer(let minutes):
            player.setTimer(minutes: minutes)
            if !player.isPlaying { player.play() }
        }
    }
}
