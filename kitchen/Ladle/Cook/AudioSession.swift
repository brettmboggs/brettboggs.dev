import AVFoundation
import Foundation

/// One place that configures the audio session, because the microphone and
/// the spoken steps have to share it.
enum AudioSession {
    static func configureForSpeaking() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            NSLog("Ladle: audio session (speak) failed: \(error.localizedDescription)")
        }
    }

    static func configureForListening() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    static func release() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
