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

/// Where a wind-down routine is.
enum RoutineStage: Equatable {
    case breathing
    case playing
}

/// The single owner of playback state. Views read it, the lock screen drives
/// it, and it is the only thing that talks to the audio engine.
/// Main-thread only. Every caller (SwiftUI, timers, remote commands) already
/// runs there, so this stays a plain class rather than an actor-isolated one.
@Observable
final class PlayerController {

    // MARK: Dependencies

    let settings: Settings
    let library: Library
    let journal: Journal
    let plan: Plan
    var store: Store { plan.store }

    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private let nowPlaying = NowPlayingCenter()

    // MARK: Published state

    private(set) var currentMix: Mix
    private(set) var isPlaying = false
    private(set) var meterLevel: Double = 0

    private(set) var timerStart: Date?
    private(set) var timerEnd: Date?

    private(set) var nextAlarm: Date?
    private(set) var isWaking = false
    private(set) var alarmRinging = false

    /// The running breathing session, if any.
    private(set) var breath: BreathSession?
    private(set) var routineStage: RoutineStage?

    /// A locked sound is playing on borrowed time.
    private(set) var previewEndsAt: Date?

    /// Set when the audio engine refuses to start, so the UI can say so instead
    /// of showing a play button that silently does nothing.
    private(set) var engineFailed = false

    /// Non-nil while the upgrade sheet should be on screen. Set by whatever the
    /// person was trying to do, so the ask always answers that.
    var paywall: PaywallReason?

    /// The first full night just ended. The Tonight screen turns this into one
    /// soft offer, once.
    private(set) var pendingFirstNightOffer = false

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
    /// A night is anything longer than this.
    private static let nightSeconds: TimeInterval = 20 * 60

    // MARK: - Life cycle

    init(settings: Settings, library: Library, journal: Journal, plan: Plan) {
        self.settings = settings
        self.library = library
        self.journal = journal
        self.plan = plan

        if let id = settings.routineMixID, let saved = library.mix(withID: id) {
            self.currentMix = saved
        } else {
            self.currentMix = Mix.recommended(for: settings.goal)
        }

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
        // The tick runs for the life of the process, not just during playback:
        // the alarm and the bedtime schedule both need it while stopped.
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
        // six-second fade. Neither should a mix arriving under a breath.
        let fade = (wasPlaying || breath != nil) ? 0.6 : settings.fadeInSeconds
        engine.renderer.setMasterGain(Float(settings.masterVolume), over: fade)

        if settings.timerMinutes > 0, timerEnd == nil, !isWaking, !alarmRinging {
            armTimer(minutes: settings.timerMinutes)
        }

        startTick()
        startMeter()
        updateNowPlaying()
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    func pause(reason: StopReason = .user) {
        guard isPlaying else { return }
        isPlaying = false
        isWaking = false
        sunriseTask?.cancel()
        sunriseTask = nil

        if breath == nil {
            engine.renderer.setMasterGain(0, over: PlayerController.pauseFadeSeconds)
            scheduleEngineStop(after: PlayerController.pauseFadeSeconds + 0.15)
        } else {
            // A breathing session is still using the engine. Silence the mix,
            // keep the master where it is.
            engine.renderer.updateRecordings(active: [])
            for slot in engine.renderer.slots { slot.targetGain = 0 }
        }

        finishSession(reason: reason)
        stopMeter()
        meterLevel = 0
        nowPlaying.update(
            mixName: currentMix.name,
            subtitle: currentMix.summary,
            isPlaying: false,
            timerStart: timerStart,
            timerEnd: timerEnd
        )
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    /// Ends the night: stops, clears the timer, leaves the lock screen.
    func stopEverything() {
        endBreath()
        pause(reason: .user)
        cancelTimer()
        nowPlaying.clear()
    }

    private func scheduleEngineStop(after seconds: Double) {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, !self.isPlaying, self.breath == nil else { return }
            self.engine.stop()
        }
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

        if session.duration >= PlayerController.nightSeconds {
            settings.nightsCompleted += 1
            if settings.nightsCompleted == 1, !settings.didOfferAfterFirstNight, !plan.isPlus {
                pendingFirstNightOffer = true
            }
            settings.save()
        }
    }

    /// The Tonight screen calls this after it has shown the offer.
    func consumeFirstNightOffer() {
        pendingFirstNightOffer = false
        settings.didOfferAfterFirstNight = true
        settings.save()
    }

    // MARK: - Mix editing

    func load(_ mix: Mix) {
        currentMix = mix
        beginPreviewIfNeeded()
        applyMix()
        updateNowPlaying()
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
        guard currentMix.layers.count < plan.maximumLayers else {
            requestUpgrade(.layers)
            return
        }
        if !plan.allows(kind) {
            // One preview at a time. A second locked sound is the ask.
            guard previewEndsAt == nil else {
                requestUpgrade(.sound(kind.id))
                return
            }
            previewEndsAt = Date().addingTimeInterval(Plan.previewSeconds)
        }
        markAsEdited()
        currentMix.layers.append(Layer(kind: kind))
        applyMix()
        Haptics.tap(enabled: settings.hapticsEnabled)
        if !isPlaying { play() }
    }

    func remove(soundID: String) {
        guard currentMix.contains(soundID) else { return }
        markAsEdited()
        currentMix.layers.removeAll { $0.soundID == soundID }
        if !currentMixHasLockedSounds { previewEndsAt = nil }
        applyMix()
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
        previewEndsAt = nil
        applyMix()
        if isPlaying { pause(reason: .user) }
    }

    func isFavourite(_ soundID: String) -> Bool {
        settings.favouriteSoundIDs.contains(soundID)
    }

    func toggleFavourite(_ soundID: String) {
        if settings.favouriteSoundIDs.contains(soundID) {
            settings.favouriteSoundIDs.remove(soundID)
        } else {
            settings.favouriteSoundIDs.insert(soundID)
        }
        settings.save()
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    func requestUpgrade(_ reason: PaywallReason) {
        guard !plan.isPlus else { return }
        paywall = reason
        settings.lastPaywallShown = Date()
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
        return library.userMixes.count < plan.maximumSavedMixes
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
        Haptics.success(enabled: settings.hapticsEnabled)
        return mix
    }

    /// Builds a plausible mix from what the plan allows: one anchor, one thing
    /// that sits under it.
    func surpriseMe() {
        let anchorIDs = ["rain.light", "rain.heavy", "rain.roof", "ocean", "stream",
                         "fire", "fan", "airliner", "train", "wind.trees", "storm", "waterfall"]
        let underIDs = ["noise.brown", "noise.pink", "cabin", "wind.plain", "crickets"]

        let anchors = anchorIDs.compactMap { SoundCatalog.kind(for: $0) }.filter { plan.allows($0) }
        let unders = underIDs.compactMap { SoundCatalog.kind(for: $0) }.filter { plan.allows($0) }
        guard let anchor = anchors.randomElement() else { return }

        var layers = [Layer(kind: anchor)]
        layers[0].level = 0.62 + Double.random(in: 0...0.22)
        layers[0].tone = Double.random(in: 0.25...0.75)
        layers[0].motion = Double.random(in: 0.25...0.75)

        let extras = min(plan.maximumLayers - 1, Int.random(in: 1...2))
        for kind in unders.shuffled().prefix(max(extras, 0)) {
            var layer = Layer(kind: kind)
            layer.level = 0.18 + Double.random(in: 0...0.24)
            layer.tone = Double.random(in: 0.3...0.7)
            layer.motion = Double.random(in: 0.3...0.7)
            layers.append(layer)
        }

        currentMix = Mix(name: "Something New", layers: layers)
        previewEndsAt = nil
        applyMix()
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

    // MARK: - Previews of locked sounds

    var currentMixHasLockedSounds: Bool {
        currentMix.layers.contains { layer in
            guard let kind = layer.kind else { return false }
            return !plan.allows(kind)
        }
    }

    /// A preset that uses Plus sounds plays for a while, then asks.
    private func beginPreviewIfNeeded() {
        guard !plan.isPlus, currentMixHasLockedSounds else {
            previewEndsAt = nil
            return
        }
        if previewEndsAt == nil {
            previewEndsAt = Date().addingTimeInterval(Plan.previewSeconds)
        }
    }

    var previewRemaining: TimeInterval? {
        guard let end = previewEndsAt else { return nil }
        return max(end.timeIntervalSinceNow, 0)
    }

    private func endPreview() {
        previewEndsAt = nil
        let locked = currentMix.layers.filter { layer in
            guard let kind = layer.kind else { return false }
            return !plan.allows(kind)
        }
        guard let first = locked.first else { return }
        markAsEdited()
        currentMix.layers.removeAll { layer in locked.contains { $0.soundID == layer.soundID } }
        applyMix()
        if currentMix.isEmpty && isPlaying { pause(reason: .user) }
        requestUpgrade(.sound(first.soundID))
    }

    // MARK: - Breathing

    var isBreathing: Bool { breath != nil }

    func startBreath(_ pattern: BreathPattern, minutes: Int) {
        guard plan.allows(pattern) else {
            requestUpgrade(.breath)
            return
        }
        endBreath()

        let session = BreathSession(pattern: pattern, minutes: minutes)
        session.onPhaseChange = { [weak self] kind in self?.breathPhaseChanged(kind) }
        session.onFinish = { [weak self] in self?.breathFinished() }
        breath = session

        ensureEngineRunning()
        engine.renderer.guideTargetGain = settings.breathGuideSound ? 0.55 : 0
        session.start()
        settings.breathMinutes = minutes
        settings.save()
    }

    func pauseBreath() {
        breath?.pause()
        engine.renderer.guide.targetFlow = 0
    }

    func resumeBreath() {
        breath?.resume()
    }

    /// Stops the session. If it was the first half of a routine, the routine
    /// carries on into the mix, since that is what the person asked for.
    func endBreath() {
        guard let session = breath else { return }
        session.stop()
    }

    /// Bails out of a session and any routine it was part of.
    func cancelBreath() {
        routineStage = nil
        endBreath()
    }

    func setBreathGuide(enabled: Bool) {
        settings.breathGuideSound = enabled
        settings.save()
        engine.renderer.guideTargetGain = (enabled && breath != nil) ? 0.55 : 0
    }

    private func breathPhaseChanged(_ kind: BreathPhase.Kind) {
        Haptics.breath(kind, enabled: settings.hapticsEnabled && settings.breathHaptics)
        let guide = engine.renderer.guide
        switch kind {
        case .inhale:
            guide.targetFlow = 1
            guide.targetOpenness = 0.85
        case .topUp:
            guide.targetFlow = 0.7
            guide.targetOpenness = 1
        case .holdFull:
            guide.targetFlow = 0
            guide.targetOpenness = 0.8
        case .exhale:
            guide.targetFlow = 0.85
            guide.targetOpenness = 0.18
        case .holdEmpty:
            guide.targetFlow = 0
            guide.targetOpenness = 0.3
        }
    }

    private func breathFinished() {
        engine.renderer.guide.targetFlow = 0
        engine.renderer.guideTargetGain = 0
        breath = nil

        if routineStage == .breathing {
            continueRoutineIntoSound()
        } else if !isPlaying {
            engine.renderer.setMasterGain(0, over: 1.5)
            scheduleEngineStop(after: 1.8)
        }
    }

    /// Starts the hardware for a breath with no mix underneath it.
    private func ensureEngineRunning() {
        stopTask?.cancel()
        stopTask = nil
        engine.configureSession(mixWithOthers: settings.mixWithOtherAudio)
        guard engine.start() else {
            engineFailed = true
            return
        }
        engineFailed = false
        if !isPlaying {
            engine.renderer.setMasterGain(Float(settings.masterVolume), over: 1.2)
        }
    }

    // MARK: - Wind-down routine

    var routinePattern: BreathPattern {
        let chosen = BreathPattern.named(settings.routineBreathPatternID, custom: settings.customBreath)
        return plan.allows(chosen) ? chosen : BreathPattern.fourSevenEight
    }

    var routineMix: Mix {
        if let id = settings.routineMixID, let saved = library.mix(withID: id) { return saved }
        return currentMix.isEmpty ? Mix.recommended(for: settings.goal) : currentMix
    }

    /// Breathe, then sound, then the timer. One tap.
    func startRoutine() {
        routineStage = .breathing
        startBreath(routinePattern, minutes: settings.routineBreathMinutes)
        if breath == nil {
            // The pattern was refused. Go straight to sound.
            continueRoutineIntoSound()
        }
    }

    private func continueRoutineIntoSound() {
        routineStage = .playing
        let mix = routineMix
        currentMix = mix
        beginPreviewIfNeeded()
        applyMix()
        settings.timerMinutes = settings.routineTimerMinutes
        settings.save()
        if isPlaying {
            if timerEnd == nil, settings.timerMinutes > 0 { armTimer(minutes: settings.timerMinutes) }
        } else {
            play()
        }
        updateNowPlaying()
    }

    func finishRoutine() {
        routineStage = nil
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
                slot.targetGain = perceptualGain(Float(layer.level))
                    * PlayerController.layerHeadroom
                    * Float(layer.kind?.trim ?? 1)
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
            : perceptualGain(Float(layer.level))
                * PlayerController.layerHeadroom
                * Float(layer.kind?.trim ?? 1)
        slot.texture.targetTone = Float(layer.tone)
        slot.texture.targetMotion = Float(layer.motion)
    }

    func commitMasterVolume() {
        // Never fight a fade that is already running.
        guard !isWaking, !didBeginTimerFade else { return }
        guard isPlaying || breath != nil else { return }
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
        } else if isPlaying {
            armTimer(minutes: minutes)
        } else {
            // Armed on play.
            timerEnd = nil
            timerStart = nil
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
            // Snap to one of the offered choices so the picker still shows it.
            let wanted = max(Double(minutes) * 0.25, 1)
            let choices: [Double] = [1, 5, 10, 20]
            settings.fadeOutMinutes = choices.filter { $0 <= wanted }.max() ?? 1
            settings.save()
        }
        updateNowPlaying()
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
        updateNowPlaying()
        Haptics.tap(enabled: settings.hapticsEnabled)
    }

    func cancelTimer() {
        timerEnd = nil
        timerStart = nil
        didBeginTimerFade = false
        settings.timerMinutes = 0
        settings.save()
        if isPlaying {
            engine.renderer.setMasterGain(Float(settings.masterVolume), over: 1.5)
        }
        updateNowPlaying()
    }

    // MARK: - Wake

    func recomputeNextAlarm() {
        guard settings.alarmEnabled else {
            nextAlarm = nil
            return
        }
        if let snooze = snoozeUntil, snooze > Date() {
            nextAlarm = snooze
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
    }

    func applyAlarmSettings() {
        settings.save()
        recomputeNextAlarm()
        Task { await Reminders.rescheduleAlarm(settings: settings) }
    }

    func applyBedtimeSettings() {
        settings.save()
        Task { await Reminders.rescheduleBedtime(settings: settings) }
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
        previewEndsAt = nil
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
        updateNowPlaying()
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
                routineStage = nil
                if settings.timerEndAction == .stop {
                    pause(reason: .timer)
                    return
                }
            }
        }

        if let end = previewEndsAt {
            if plan.isPlus {
                previewEndsAt = nil
            } else if now >= end {
                endPreview()
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

        checkBedtime(now: now)

        // Nothing below is worth doing on an idle tick.
        guard isPlaying || alarmRinging || isWaking else { return }
        updateNowPlaying()
    }

    /// Only fires while the app is alive. iOS will not wake a suspended app to
    /// start audio, and the Rest screen says so rather than pretending.
    private func checkBedtime(now: Date) {
        guard settings.windDownEnabled, !isPlaying, breath == nil else { return }
        let calendar = Calendar.current
        let minuteOfDay = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        guard minuteOfDay == settings.bedtimeMinuteOfDay else { return }
        if let last = lastWindDownFire, now.timeIntervalSince(last) < 120 { return }
        lastWindDownFire = now
        startRoutine()
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

    // MARK: - Lock screen

    private func updateNowPlaying() {
        nowPlaying.update(
            mixName: currentMix.name,
            subtitle: currentMix.summary,
            isPlaying: isPlaying,
            timerStart: timerStart,
            timerEnd: timerEnd
        )
    }
}
