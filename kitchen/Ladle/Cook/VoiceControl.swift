import AVFoundation
import Foundation
import Observation
import Speech

enum VoiceCommand: Equatable {
    case next
    case back
    case repeatStep
    case readStep
    case startTimer(minutes: Int?)
    case stopTimer
    case ingredients
    case howMuch(String)
    case finish
    case stopListening
}

/// Words that move the recipe along when hands are covered in dough.
///
/// The microphone stays open while cook mode is showing and the toggle is
/// on. Recognition runs on the phone when the device supports it. Nothing
/// is recorded and nothing is kept: the transcript is scanned for a handful
/// of commands and thrown away.
@Observable
final class VoiceControl {
    static let shared = VoiceControl()

    enum Status: Equatable {
        case off
        case starting
        case listening
        case denied
        case unavailable(String)
    }

    private(set) var status: Status = .off
    /// The last words heard, shown small so she can see it is working.
    private(set) var lastHeard: String = ""
    var onCommand: ((VoiceCommand) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var consumedSegments = 0
    private var lastCommandAt: Date = .distantPast
    private var lastCommand: VoiceCommand?
    private var restartTimer: Timer?

    var isListening: Bool { status == .listening || status == .starting }

    // MARK: - Lifecycle

    func start() {
        guard status == .off || status == .denied, !isListening else { return }
        status = .starting
        Task { @MainActor in
            let speechOK = await Self.requestSpeechPermission()
            guard speechOK else { self.status = .denied; return }
            let micOK = await AVAudioApplication.requestRecordPermission()
            guard micOK else { self.status = .denied; return }
            self.beginListening()
        }
    }

    func stop() {
        generation += 1
        restartTimer?.invalidate()
        restartTimer = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        status = .off
        lastHeard = ""
        AudioSession.release()
    }

    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { auth in
                continuation.resume(returning: auth == .authorized)
            }
        }
    }

    private func beginListening() {
        let locale = Locale(identifier: "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            status = .unavailable("Speech recognition is not available on this phone right now.")
            return
        }
        self.recognizer = recognizer
        do {
            try AudioSession.configureForListening()
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                status = .unavailable("No microphone was found.")
                return
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            status = .unavailable("The microphone could not be started.")
            return
        }
        status = .listening
        startRecognitionTask()
    }

    /// Apple ends a recognition task after about a minute, so a fresh one
    /// is started well before that and whenever the last one finishes.
    private func startRecognitionTask() {
        guard let recognizer, status == .listening else { return }
        generation += 1
        let myGeneration = generation
        task?.cancel()
        task = nil
        request?.endAudio()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = [
            "next step", "next", "go back", "back", "repeat", "read it", "start timer",
            "set a timer", "ingredients", "how much", "finish", "stop listening",
        ]
        self.request = request
        consumedSegments = 0

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.generation == myGeneration else { return }
                if let result {
                    self.handle(result)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.scheduleRestart(after: 0.2)
                }
            }
        }

        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.startRecognitionTask() }
        }
    }

    private func scheduleRestart(after delay: TimeInterval) {
        guard status == .listening else { return }
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.startRecognitionTask() }
        }
    }

    // MARK: - Hearing

    private func handle(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        // The phone's own voice, read back through the microphone, is not a
        // command.
        if Speaker.shared.isSpeaking || Date().timeIntervalSince(Speaker.shared.finishedAt) < 0.8 {
            consumedSegments = segments.count
            return
        }
        if segments.count < consumedSegments { consumedSegments = 0 }
        let fresh = segments[consumedSegments...].map(\.substring).joined(separator: " ").lowercased()
        let tail = segments.suffix(6).map(\.substring).joined(separator: " ")
        if !tail.isEmpty { lastHeard = tail }
        guard !fresh.isEmpty, let command = VoiceGrammar.command(in: fresh) else { return }
        consumedSegments = segments.count
        let now = Date()
        if command == lastCommand, now.timeIntervalSince(lastCommandAt) < 1.5 { return }
        lastCommand = command
        lastCommandAt = now
        onCommand?(command)
    }
}

/// The words that count, most specific first.
enum VoiceGrammar {
    private static let howMuch = try! NSRegularExpression(pattern: #"how (?:much|many) (?:of )?(?:the )?([a-z' ]+?)(?: do i need| is it| do we need| goes in| in this| for this)?$"#)
    private static let timerFor = try! NSRegularExpression(pattern: #"(?:set|start)(?: a| the)? timer(?: for)? (\d+|one|two|three|four|five|six|seven|eight|nine|ten|twelve|fifteen|twenty|twenty five|thirty|forty|forty five|fifty|sixty|ninety|an hour|half an hour) ?(minutes?|mins?|hours?|hour)?"#)

    private static let numbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "twelve": 12, "fifteen": 15, "twenty": 20, "twenty five": 25, "thirty": 30, "forty": 40,
        "forty five": 45, "fifty": 50, "sixty": 60, "ninety": 90, "an hour": 60, "half an hour": 30,
    ]

    static func command(in text: String) -> VoiceCommand? {
        let t = " " + text.replacingOccurrences(of: "  ", with: " ") + " "
        func has(_ phrases: [String]) -> Bool {
            phrases.contains { t.contains(" " + $0 + " ") }
        }
        if has(["stop listening", "pause listening", "stop the microphone", "turn off voice"]) { return .stopListening }
        if has(["finish cooking", "i'm done", "im done", "all done", "we're done", "were done", "end cooking", "stop cooking", "finished cooking"]) { return .finish }
        let ns = text as NSString
        if let match = timerFor.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let amount = ns.substring(with: match.range(at: 1))
            var minutes = numbers[amount] ?? Int(amount)
            if match.range(at: 2).location != NSNotFound {
                let unit = ns.substring(with: match.range(at: 2))
                if unit.hasPrefix("hour"), let m = minutes, !amount.contains("hour") { minutes = m * 60 }
            }
            return .startTimer(minutes: minutes)
        }
        if has(["start timer", "start the timer", "start a timer", "set timer", "set the timer", "set a timer", "timer please"]) { return .startTimer(minutes: nil) }
        if has(["stop timer", "stop the timer", "cancel timer", "cancel the timer"]) { return .stopTimer }
        if has(["show ingredients", "ingredients please", "what do i need", "ingredient list", "ingredients"]) { return .ingredients }
        if let match = howMuch.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let thing = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !thing.isEmpty { return .howMuch(thing) }
        }
        if has(["read it again", "say that again", "read that again", "repeat that", "repeat", "again please", "what was that", "one more time"]) { return .repeatStep }
        if has(["read it", "read the step", "read this step", "read step", "read"]) { return .readStep }
        if has(["go back", "previous step", "previous", "last step", "back one", "back"]) { return .back }
        if has(["next step", "next", "continue", "go on", "keep going", "forward", "okay next", "ok next", "done", "what's next", "whats next"]) { return .next }
        return nil
    }
}
