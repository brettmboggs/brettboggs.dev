import AVFoundation
import Foundation

/// Owns the AVAudioEngine graph and the audio session.
///
/// The graph is intentionally tiny: one source node that renders the entire mix,
/// straight into the main mixer. All the work happens inside `Renderer`.
final class AudioEngine {

    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private(set) var renderer: Renderer
    private(set) var isRunning = false

    /// Fired when an interruption ends. `true` means the system says we may resume.
    var onInterruptionEnded: ((Bool) -> Void)?
    /// Fired when headphones are pulled, which should pause like any other player.
    var onOutputDisconnected: (() -> Void)?
    /// Fired after the graph was rebuilt, so the current mix can be reapplied.
    var onGraphRebuilt: (() -> Void)?

    private var mixWithOthers = false
    private var observers: [NSObjectProtocol] = []

    init() {
        renderer = Renderer(sampleRate: 48_000)
        registerObservers()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Session

    func configureSession(mixWithOthers: Bool) {
        self.mixWithOthers = mixWithOthers
        let session = AVAudioSession.sharedInstance()
        do {
            var options: AVAudioSession.CategoryOptions = []
            if mixWithOthers { options.insert(.mixWithOthers) }
            try session.setCategory(.playback, mode: .default, options: options)
            // A long IO buffer is the single biggest power win for something
            // that runs for eight hours straight.
            try session.setPreferredIOBufferDuration(0.023)
            // The two streamed files are 44.1 kHz. If the route honours this,
            // sample-rate conversion drops out entirely; if it does not, the
            // converter handles it and nothing else changes.
            try session.setPreferredSampleRate(44_100)
        } catch {
            NSLog("Slumbio: audio session configuration failed: \(error.localizedDescription)")
        }
    }

    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("Slumbio: audio session activation failed: \(error.localizedDescription)")
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            // Deactivation routinely fails if something else grabbed the route.
            // It is not worth surfacing.
        }
    }

    // MARK: - Graph

    private func buildGraph() {
        if let existing = sourceNode {
            engine.detach(existing)
            sourceNode = nil
        }

        var rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if rate < 8_000 || rate > 192_000 { rate = 48_000 }

        if abs(Double(renderer.sampleRate) - rate) > 1 {
            renderer = Renderer(sampleRate: Float(rate))
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            NSLog("Slumbio: could not create a render format at \(rate) Hz")
            return
        }

        // Captured strongly on purpose. A weak load on the audio thread is not
        // real-time safe, and there is no cycle: the renderer holds nothing.
        let target = renderer
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            guard
                abl.count > 0,
                let leftRaw = abl[0].mData
            else { return noErr }

            let left = leftRaw.assumingMemoryBound(to: Float.self)
            var right = left
            var stereo = false
            if abl.count > 1, let rightRaw = abl[1].mData {
                right = rightRaw.assumingMemoryBound(to: Float.self)
                stereo = true
            }

            target.render(
                frames: Int(frameCount),
                left: left,
                right: right,
                stereo: stereo
            )
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    // MARK: - Transport

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        activateSession()

        if sourceNode == nil {
            buildGraph()
        }
        guard sourceNode != nil else { return false }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            return true
        } catch {
            NSLog("Slumbio: engine start failed: \(error.localizedDescription)")
            // One retry after a full rebuild covers most transient route errors.
            rebuildGraph()
            do {
                try engine.start()
                isRunning = true
                return true
            } catch {
                NSLog("Slumbio: engine restart failed: \(error.localizedDescription)")
                isRunning = false
                return false
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
        renderer.resetMaster()
        renderer.releaseRecordings()
        deactivateSession()
    }

    /// Stops the hardware without tearing down the session, for interruptions.
    func pauseHardware() {
        guard isRunning else { return }
        engine.pause()
        isRunning = false
    }

    private func rebuildGraph() {
        engine.stop()
        isRunning = false
        engine = AVAudioEngine()
        sourceNode = nil
        buildGraph()
        onGraphRebuilt?()
    }

    // MARK: - System events

    private func registerObservers() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Everything is invalid after a media services reset.
            self.configureSession(mixWithOthers: self.mixWithOthers)
            self.rebuildGraph()
        })

        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.rebuildGraph()
            _ = self.start()
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            pauseHardware()
        case .ended:
            var shouldResume = false
            if let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    .contains(.shouldResume)
            }
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones came out. Never blast a sleeping room through the speaker.
            onOutputDisconnected?()
        case .override, .categoryChange, .newDeviceAvailable:
            break
        default:
            break
        }
    }
}

/// The renderer is handed to the audio thread deliberately; its cross-thread
/// contract is documented on the type itself.
extension Renderer: @unchecked Sendable {}
