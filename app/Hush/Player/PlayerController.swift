import Foundation
import Observation
import SwiftUI
import UIKit

/// Why playback ended, which decides what gets written to the journal.
enum StopReason {
    case user
    case timer
    case alarm
    case disconnected
}

/// The single owner of playback state. Views read it, intents drive it, and it
/// is the only thing that talks to the audio engine.
/// Main-thread only. Every caller (SwiftUI, timers, remote commands,
/// App Intents) already runs there, so this stays a plain class rather than
/// an actor-isolated one.
@Observable
final class PlayerController {

    // MARK: Dependencies

    let settings: Settings
    let library: Library
    let journal: Journal
    let entitlements: Entitlements

    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private let nowPlaying = NowPlayingCenter()
    @ObservationIgnored private let liveActivity = LiveActivityController()

    // MARK: Published state

    private(set) var currentMix: Mix
    private(set) var isPlaying = false
    private(set) var meterLevel: Double = 0

    private(set) var timerStart: Date?
    private(set) var timerEnd: Date?

    private(set) var nextAlarm: Date?
    private(set) var isWaking = false
    private(set) var alarmRinging = false

    /// Set when the audio engine refuses to start, so the UI can say so instead
    /// of showing a play button that silently does nothing.
    private(set) var engineFailed = false

    /// Non-nil while the upgrade sheet should be on screen. Set by whatever the
    /// person was trying to do, so the ask always answers that.
    var paywall: PaywallReason?

    // MARK: Internals

    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var sunriseTask: Task<Void, Never>?
    @ObservationIgnored private var didBeginTimerFade = false
    @ObservationIgnored private var snoozeUntil: Date?
    @ObservationIgnored private var lastWindDownFire: Date?
    @ObservationIgnored private var isForeground = true

    /// Layers are summed before the master, so each one is held back to leave
    /// room for a six-deep stack. The soft clipper catches the rest.
    private static let layerHeadroom: Float = 0.6
    private static let pauseFadeSeconds: Double = 1.6

    // MARK: - Life cycle

    init(settings: Settings, library: Library, journal: Journal, entitlements: Entitlements) {
        self.settings = settings
        self.library = library
        self.journal = journal
        self.entitlements = entitlements
        self.currentMix = library.allMixes.first ?? Mix(name: "Empty", layers: [])

        engine.onInterruptionEnded = { [weak self] shouldResume in
            guard let self, shouldResume, self.isPlaying else { return }
            _ = self.engine.start()
        }
        engine.onOutputDisconnected = { [weak self] in
            guard let self, self.settings.pauseOnDisconnect, self.isPlaying else { return }
            self.pause(reason: .disconnected)
        }
        engine.onGraphRebuilt = { [weak self] in
            guard let self else { return }
            self.applyMix()
            self.engine.renderer.tiltTarget = Float(self.settings.tilt)
            self.engine.renderer.setMasterGain(Float(self.settings.masterVolume), over: 0.4)
        }

        nowPlaying.onPlay = { [weak self] in self?.play() }
        nowPlaying.onPause = { [weak self] in self?.pause(reason: .user) }
        nowPlaying.onStop = { [weak self] in self?.pause(reason: .user) }
        nowPlaying.onNextMix = { [weak self] in self?.cycleMix(by: 1) }
        nowPlaying.onPreviousMix = { [weak self] in self?.cycleMix(by: -1) }

        engine.configureSession(mixWithOthers: settings.mixWithOtherAudio)
        nowPlaying.configureCommands()
        recomputeNextAlarm()
        publishSnapshot()
        // The tick runs for the life of the process, not just during playback:
        // the alarm and the wind-down schedule both need it while stopped.
        startTick()
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            isForeground = true
            startTick()
            startMeter()
            recomputeNextAlarm()
        case .inactive, .background:
            isForeground = false
            stopMeter()
            settings.save()
        @unknown default:
            break
        }
    }

    // MARK: - Transport

    func toggle() {
        isPlaying ? pause(reason: .user) : play()
    }

    func play() {
        guard !currentMix.isEmpty else { return }
        stopTask?.cancel()
        stopTask = nil

        engine.configureSession(mixWithOthers: settings.mixWithOtherAudio)

        guard engine.start() else {
            engineFailed = true
            return
        }
        engineFailed = false

        let wasPlaying = isPlaying
        isPlaying = true
        if sessionStart == nil { sessionStart = Date() }

        // After `isPlaying`, so file streams open, and after `start`, so the
        // gains land on the renderer the engine actually built.
        applyMix()
        engine.renderer.tiltTarget = Float(settings.tilt)

        // A resume after a pause should not make the user wait out a fresh
        // six-second fade.
        let fade = wasPlaying ? 0.4 : settings.fadeInSeconds
        engine.renderer.setMasterGain(Float(settings.masterVolume), over: fade)

        if settings.timerMinutes > 0, timerEnd == nil, !isWaking, !alarmRinging {
            armTimer(minutes: settings.timerMinutes)
        }

        startTick()
        startMeter()
        updateNowPlaying()
        publishSnapshot()
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    func pause(reason: StopReason = .user) {
        guard isPlaying else { return }
        isPlaying = false
        isWaking = false
        sunriseTask?.cancel()
        sunriseTask = nil

        engine.renderer.setMasterGain(0, over: PlayerController.pauseFadeSeconds)

        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PlayerController.pauseFadeSeconds + 0.15))
            guard let self, !Task.isCancelled, !self.isPlaying else { return }
            self.engine.stop()
        }

        finishSession(reason: reason)
        stopMeter()
        meterLevel = 0
        liveActivity.end()
        nowPlaying.update(
            mixName: currentMix.name,
            subtitle: currentMix.summary,
            isPlaying: false,
            timerStart: timerStart,
            timerEnd: timerEnd
        )
        publishSnapshot()
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    /// Ends the night: stops, clears the timer, drops the Live Activity.
    func stopEverything() {
        pause(reason: .user)
        cancelTimer()
        nowPlaying.clear()
    }

    private func finishSession(reason: StopReason) {
        guard let start = sessionStart else { return }
        sessionStart = nil
        let session = SleepSession(
            start: start,
            end: Date(),
            mixName: currentMix.name,
            endedAtAlarm: reason == .alarm
        )
        journal.record(session)
        if settings.writeToHealth, session.duration >= 120 {
            Task { await HealthWriter.write(session: session) }
        }
    }

    // MARK: - Mix editing

    func load(_ mix: Mix) {
        currentMix = mix
        applyMix()
        updateNowPlaying()
        publishSnapshot()
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    func isActive(_ soundID: String) -> Bool {
        currentMix.contains(soundID)
    }

    func toggleSound(_ kind: SoundKind) {
        if currentMix.contains(kind.id) {
            remove(soundID: kind.id)
        } else {
            add(kind)
        }
    }

    func add(_ kind: SoundKind) {
        guard !currentMix.contains(kind.id) else { return }
        guard currentMix.layers.count < entitlements.maximumLayers else {
            requestUpgrade(.layers)
            return
        }
        markAsEdited()
        currentMix.layers.append(Layer(kind: kind))
        applyMix()
        publishSnapshot()
        Haptics.tap(enabled: settings.hapticsEnabled)
        if !isPlaying { play() }
    }

    func remove(soundID: String) {
        guard currentMix.contains(soundID) else { return }
        markAsEdited()
        currentMix.layers.removeAll { $0.soundID == soundID }
        applyMix()
        publishSnapshot()
        Haptics.tap(enabled: settings.hapticsEnabled)
        if currentMix.isEmpty && isPlaying { pause(reason: .user) }
    }

    func setLevel(_ level: Double, for soundID: String) {
        update(soundID: soundID) { $0.level = min(max(level, 0), 1) }
    }

    func setTone(_ tone: Double, for soundID: String) {
        update(soundID: soundID) { $0.tone = min(max(tone, 0), 1) }
    }

    func setMotion(_ motion: Double, for soundID: String) {
        update(soundID: soundID) { $0.motion = min(max(motion, 0), 1) }
    }

    func toggleMute(_ soundID: String) {
        update(soundID: soundID) { $0.isMuted.toggle() }
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    private func update(soundID: String, _ change: (inout Layer) -> Void) {
        guard let index = currentMix.layers.firstIndex(where: { $0.soundID == soundID }) else { return }
        markAsEdited()
        change(&currentMix.layers[index])
        applyLayer(currentMix.layers[index])
    }

    /// Editing a preset turns the working mix into an unsaved variant rather
    /// than silently mutating something the user thinks is fixed.
    private func markAsEdited() {
        guard currentMix.isBuiltIn else { return }
        currentMix = Mix(
            id: UUID(),
            name: currentMix.name,
            layers: currentMix.layers,
            isBuiltIn: false
        )
    }

    func clearMix() {
        currentMix = Mix(name: "Mix", layers: [])
        applyMix()
        if isPlaying { pause(reason: .user) }
        publishSnapshot()
    }

    func requestUpgrade(_ reason: PaywallReason) {
        guard !entitlements.isPro else { return }
        paywall = reason
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    /// True once the working mix has drifted from anything on the shelf.
    var currentMixIsUnsaved: Bool {
        guard !currentMix.isEmpty, !currentMix.isBuiltIn else { return false }
        return library.mix(withID: currentMix.id) == nil
    }

    /// Overwriting a mix you already saved is always allowed; only a new one
    /// counts against the free limit.
    var canSaveAnotherMix: Bool {
        if !currentMix.isBuiltIn, library.mix(withID: currentMix.id) != nil { return true }
        return library.userMixes.count < entitlements.maximumSavedMixes
    }

    @discardableResult
    func saveCurrentMix(named name: String) -> Mix {
        var mix = currentMix
        mix.name = library.uniqueName(basedOn: name)
        mix.isBuiltIn = false
        if library.mix(withID: mix.id)?.isBuiltIn ?? false {
            mix.id = UUID()
        }
        mix.createdAt = Date()
        library.save(mix)
        currentMix = mix
        publishSnapshot()
        Haptics.success(enabled: settings.hapticsEnabled)
        return mix
    }

    /// Builds a plausible mix: one anchor, one or two things that sit under it.
    func surpriseMe() {
        let anchors = ["rain.light", "rain.heavy", "rain.roof", "ocean", "stream",
                       "fire", "fan", "airliner", "train", "wind.trees", "storm"]
        let unders = ["noise.brown", "noise.pink", "cabin", "wind.plain", "crickets"]

        guard let anchorID = anchors.randomElement(),
              let anchor = SoundCatalog.kind(for: anchorID) else { return }

        var layers = [Layer(kind: anchor)]
        layers[0].level = 0.62 + Double.random(in: 0...0.22)
        layers[0].tone = Double.random(in: 0.25...0.75)
        layers[0].motion = Double.random(in: 0.25...0.75)

        let extras = Int.random(in: 1...2)
        for id in unders.shuffled().prefix(extras) {
            guard let kind = SoundCatalog.kind(for: id) else { continue }
            var layer = Layer(kind: kind)
            layer.level = 0.18 + Double.random(in: 0...0.24)
            layer.tone = Double.random(in: 0.3...0.7)
            layer.motion = Double.random(in: 0.3...0.7)
            layers.append(layer)
        }

        currentMix = Mix(name: "Something New", layers: layers)
        applyMix()
        publishSnapshot()
        Haptics.success(enabled: settings.hapticsEnabled)
        if !isPlaying { play() }
    }

    func cycleMix(by offset: Int) {
        let all = library.allMixes
        guard !all.isEmpty else { return }
        let index = all.firstIndex { $0.id == currentMix.id } ?? 0
        let next = ((index + offset) % all.count + all.count) % all.count
        load(all[next])
    }

    // MARK: - Engine parameters

    private func applyMix() {
        // Streams must be open before their gains come up, but only while we
        // are actually playing: decoding a paused mix is pure battery drain.
        let active: Set<String> = isPlaying
            ? Set(currentMix.layers.filter { !$0.isMuted }.map(\.soundID))
            : []
        engine.renderer.updateRecordings(active: active)

        for slot in engine.renderer.slots {
            if let layer = currentMix.layer(for: slot.soundID), !layer.isMuted {
                slot.targetGain = perceptualGain(Float(layer.level)) * PlayerController.layerHeadroom
                slot.texture.targetTone = Float(layer.tone)
                slot.texture.targetMotion = Float(layer.motion)
            } else {
                slot.targetGain = 0
            }
        }
    }

    private func applyLayer(_ layer: Layer) {
        guard let slot = engine.renderer.slot(for: layer.soundID) else { return }
        if let recording = slot.texture as? RecordingTexture {
            if layer.isMuted || !isPlaying {
                recording.deactivate()
            } else if !recording.isActive {
                recording.activate()
            }
        }
        slot.targetGain = layer.isMuted
            ? 0
            : perceptualGain(Float(layer.level)) * PlayerController.layerHeadroom
        slot.texture.targetTone = Float(layer.tone)
        slot.texture.targetMotion = Float(layer.motion)
    }

    func commitMasterVolume() {
        // Never fight a fade that is already running.
        guard !isWaking, !didBeginTimerFade else { return }
        engine.renderer.setMasterGain(Float(settings.masterVolume), over: 0.08)
    }

    func commitTilt() {
        engine.renderer.tiltTarget = Float(settings.tilt)
    }

    func reconfigureSession() {
        engine.configureSession(mixWithOthers: settings.mixWithOtherAudio)
    }

    // MARK: - Sleep timer

    var timerRemaining: TimeInterval? {
        guard let end = timerEnd else { return nil }
        return max(end.timeIntervalSinceNow, 0)
    }

    func setTimer(minutes: Int) {
        settings.timerMinutes = minutes
        settings.save()
        if minutes <= 0 {
            cancelTimer()
        } else {
            armTimer(minutes: minutes)
        }
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    private func armTimer(minutes: Int) {
        let now = Date()
        timerStart = now
        timerEnd = now.addingTimeInterval(Double(minutes) * 60)
        didBeginTimerFade = false
        // A fade longer than the timer itself would start in the past.
        if settings.fadeOutMinutes * 60 > Double(minutes) * 60 * 0.9 {
            settings.fadeOutMinutes = max(Double(minutes) * 0.25, 1)
        }
        if isPlaying, let end = timerEnd {
            liveActivity.start(mixName: currentMix.name, endDate: end)
        }
        updateNowPlaying()
        publishSnapshot()
    }

    func extendTimer(byMinutes minutes: Int) {
        guard let end = timerEnd else {
            setTimer(minutes: minutes)
            return
        }
        timerEnd = end.addingTimeInterval(Double(minutes) * 60)
        didBeginTimerFade = false
        // The fade was already under way, so climb back to level.
        engine.renderer.setMasterGain(Float(settings.masterVolume), over: 3)
        if let newEnd = timerEnd {
            liveActivity.update(
                mixName: currentMix.name, endDate: newEnd,
                isPlaying: isPlaying, isWaking: isWaking
            )
        }
        updateNowPlaying()
        publishSnapshot()
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    func cancelTimer() {
        timerEnd = nil
        timerStart = nil
        didBeginTimerFade = false
        settings.timerMinutes = 0
        settings.save()
        liveActivity.end()
        if isPlaying {
            engine.renderer.setMasterGain(Float(settings.masterVolume), over: 1.5)
        }
        updateNowPlaying()
        publishSnapshot()
    }

    // MARK: - Wake

    func recomputeNextAlarm() {
        guard settings.alarmEnabled else {
            nextAlarm = nil
            publishSnapshot()
            return
        }
        if let snooze = snoozeUntil, snooze > Date() {
            nextAlarm = snooze
            publishSnapshot()
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let hour = settings.alarmMinuteOfDay / 60
        let minute = settings.alarmMinuteOfDay % 60
        var found: Date?

        for offset in 0...8 {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: now),
                let candidate = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: day
                ),
                candidate > now.addingTimeInterval(30)
            else { continue }

            if settings.alarmRepeats && !settings.alarmWeekdays.isEmpty {
                let weekday = calendar.component(.weekday, from: candidate)
                guard settings.alarmWeekdays.contains(weekday) else { continue }
            }
            found = candidate
            break
        }
        nextAlarm = found
        publishSnapshot()
    }

    func applyAlarmSettings() {
        settings.save()
        recomputeNextAlarm()
        Task { await AlarmNotifications.reschedule(settings: settings) }
    }

    private func beginSunrise(endingAt alarm: Date) {
        isWaking = true
        didBeginTimerFade = true
        timerEnd = nil
        timerStart = nil

        if let id = settings.alarmMixID, let mix = library.mix(withID: id) {
            currentMix = mix
        } else if let first = Mix.wakePresets.first {
            currentMix = first
        }
        applyMix()

        if !isPlaying { play() }

        // Dip to near silence so swapping the mix is not a jump cut, then climb
        // for the rest of the window.
        engine.renderer.setMasterGain(0.02, over: 2)
        sunriseTask?.cancel()
        sunriseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard let self, !Task.isCancelled, self.isWaking else { return }
            let remaining = max(alarm.timeIntervalSinceNow, 5)
            self.engine.renderer.setMasterGain(1.0, over: remaining)
        }

        liveActivity.start(mixName: currentMix.name, endDate: alarm, isWaking: true)
        updateNowPlaying()
        publishSnapshot()
    }

    private func fireAlarm() {
        alarmRinging = true
        isWaking = false
        sunriseTask?.cancel()
        sunriseTask = nil
        snoozeUntil = nil

        if !isPlaying { play() }
        engine.renderer.setMasterGain(1.0, over: 1)
        Haptics.success(enabled: settings.hapticsEnabled)
        liveActivity.end()
        publishSnapshot()
    }

    func dismissAlarm() {
        alarmRinging = false
        snoozeUntil = nil
        pause(reason: .alarm)
        recomputeNextAlarm()
    }

    func snoozeAlarm(minutes: Int = 9) {
        alarmRinging = false
        snoozeUntil = Date().addingTimeInterval(Double(minutes) * 60)
        nextAlarm = snoozeUntil
        engine.renderer.setMasterGain(Float(settings.masterVolume) * 0.35, over: 3)
        publishSnapshot()
    }

    // MARK: - Ticking

    private func startTick() {
        guard tick == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    /// Ordinary pausing leaves the tick running: the alarm and the wind-down
    /// schedule still need a heartbeat while nothing is playing.
    deinit {
        tick?.invalidate()
        meterTimer?.invalidate()
    }

    private func onTick() {
        let now = Date()

        if let end = timerEnd, isPlaying, !isWaking {
            let fadeSeconds = max(settings.fadeOutMinutes * 60, 1)
            if !didBeginTimerFade, now >= end.addingTimeInterval(-fadeSeconds) {
                didBeginTimerFade = true
                let target: Float = settings.timerEndAction == .stop
                    ? 0
                    : Float(settings.masterVolume) * 0.22
                engine.renderer.setMasterGain(
                    target, over: max(end.timeIntervalSince(now), 1)
                )
            }
            if now >= end {
                timerEnd = nil
                timerStart = nil
                didBeginTimerFade = false
                liveActivity.end()
                if settings.timerEndAction == .stop {
                    pause(reason: .timer)
                    return
                }
            }
        }

        if settings.alarmEnabled, let alarm = nextAlarm {
            let sunriseStart = alarm.addingTimeInterval(-Double(settings.sunriseMinutes) * 60)
            if !isWaking, !alarmRinging, now >= sunriseStart, now < alarm {
                beginSunrise(endingAt: alarm)
            }
            if !alarmRinging, now >= alarm {
                fireAlarm()
            }
        }

        checkWindDown(now: now)

        // Nothing below is worth doing on an idle tick.
        guard isPlaying || alarmRinging || isWaking else { return }
        updateNowPlaying()
        publishSnapshot()
    }

    /// Only fires while the app is alive. iOS will not wake a suspended app to
    /// start audio, and the Wake screen says so rather than pretending.
    private func checkWindDown(now: Date) {
        guard settings.windDownEnabled, !isPlaying else { return }
        let calendar = Calendar.current
        let minuteOfDay = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        guard minuteOfDay == settings.windDownMinuteOfDay else { return }
        if let last = lastWindDownFire, now.timeIntervalSince(last) < 120 { return }
        lastWindDownFire = now

        if let id = settings.windDownMixID, let mix = library.mix(withID: id) {
            currentMix = mix
        }
        play()
    }

    private func startMeter() {
        guard meterTimer == nil, isForeground, isPlaying else { return }
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.meterLevel = Double(self.engine.renderer.meterLevel)
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    // MARK: - Outward state

    private func updateNowPlaying() {
        nowPlaying.update(
            mixName: currentMix.name,
            subtitle: currentMix.summary,
            isPlaying: isPlaying,
            timerStart: timerStart,
            timerEnd: timerEnd
        )
    }

    private func publishSnapshot() {
        SharedStore.writeSnapshot(
            PlaybackSnapshot(
                isPlaying: isPlaying,
                mixName: currentMix.isEmpty ? "Nothing playing" : currentMix.name,
                mixSummary: currentMix.summary,
                layerCount: currentMix.layers.count,
                timerEnd: timerEnd,
                wakeAt: settings.alarmEnabled ? nextAlarm : nil
            )
        )
        WidgetRefresher.reload()
    }
}
