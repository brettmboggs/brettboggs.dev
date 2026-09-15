import AVFoundation
import Foundation
import Observation

/// Reads a step out loud.
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    private(set) var isSpeaking = false
    /// When the last utterance finished, so the listener can ignore the
    /// tail of its own voice coming back through the microphone.
    private(set) var finishedAt: Date = .distantPast

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, listening: Bool = false) {
        stop()
        guard !text.isBlank else { return }
        if !listening { AudioSession.configureForSpeaking() }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.1
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        finishedAt = Date()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        finishedAt = Date()
    }
}
