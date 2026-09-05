import Foundation

/// One texture's slot in the mix. Every catalog sound gets a slot at startup,
/// so turning a sound on is only a gain change: nothing is allocated, attached
/// or detached while audio is running, and nothing can click.
final class VoiceSlot {
    let soundID: String
    let texture: Texture

    /// Written from the main thread, read on the audio thread.
    var targetGain: Float = 0
    /// Audio thread only.
    var currentGain: Float = 0

    init(kind: SoundKind, sampleRate: Float) {
        soundID = kind.id
        texture = TextureFactory.make(kind)
        texture.prepare(
            sampleRate: sampleRate,
            tone: Float(kind.defaultTone),
            motion: Float(kind.defaultMotion)
        )
    }

    @inline(__always)
    var isAudible: Bool { targetGain > 0.00005 || currentGain > 0.00005 }
}

/// Everything that runs on the audio thread.
///
/// Cross-thread parameter passing is deliberately primitive: the main thread
/// writes `Float`/`Int32` fields and the audio thread reads them. Word-sized
/// loads and stores do not tear on the hardware this ships to, every value is
/// smoothed or ramped before it reaches the signal, and the audio thread never
/// takes a lock, allocates, or touches runtime machinery that could block.
/// A missed update costs one block, about 10 ms.
final class Renderer {
    let sampleRate: Float
    private(set) var slots: [VoiceSlot]
    private let slotIndex: [String: Int]

    // MARK: Breath guide (not part of the mix, rides alongside it)

    let guide: BreathGuideTexture
    /// Written from the main thread, read on the audio thread.
    var guideTargetGain: Float = 0
    private var guideGain: Float = 0

    // MARK: Master ramp (fade in, sleep-timer fade out, sunrise)

    private var rampToken: Int32 = 0
    private var rampTargetValue: Float = 0
    private var rampSeconds: Double = 0
    private var seenToken: Int32 = -1

    private var masterGain: Float = 0
    private var rampStep: Float = 0
    private var rampRemaining: Int = 0
    private var rampEnd: Float = 0

    // MARK: Master tone

    /// -1 warm ... 0 flat ... +1 bright.
    var tiltTarget: Float = 0
    private var tiltCurrent: Float = 2 // out of range, forces a first update
    private var tiltLowL = Biquad(), tiltLowR = Biquad()
    private var tiltHighL = Biquad(), tiltHighR = Biquad()

    // MARK: Metering (written here, read by the UI)

    private(set) var meterLevel: Float = 0
    private var meterEnvelope: Float = 0

    // MARK: Scratch

    private let maxChunk = 1024
    private var scratchL: UnsafeMutablePointer<Float>
    private var scratchR: UnsafeMutablePointer<Float>

    /// Per-block voice gain smoothing coefficient, about 45 ms.
    private var voiceSmoothing: Float = 0.15

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        var built: [VoiceSlot] = []
        var index: [String: Int] = [:]
        for (i, kind) in SoundCatalog.all.enumerated() {
            built.append(VoiceSlot(kind: kind, sampleRate: sampleRate))
            index[kind.id] = i
        }
        slots = built
        slotIndex = index

        guide = BreathGuideTexture()
        guide.prepare(sampleRate: sampleRate, tone: 0.5, motion: 0.5)

        scratchL = UnsafeMutablePointer<Float>.allocate(capacity: maxChunk)
        scratchR = UnsafeMutablePointer<Float>.allocate(capacity: maxChunk)
        scratchL.initialize(repeating: 0, count: maxChunk)
        scratchR.initialize(repeating: 0, count: maxChunk)

        voiceSmoothing = 1 - expf(-512 / (0.045 * sampleRate))
    }

    deinit {
        releaseRecordings()
        scratchL.deallocate()
        scratchR.deallocate()
    }

    // MARK: - Main-thread API

    func slot(for soundID: String) -> VoiceSlot? {
        guard let i = slotIndex[soundID] else { return nil }
        return slots[i]
    }

    /// Opens and closes file streams to match the mix.
    ///
    /// Must be called before the matching gains are raised: activation resets a
    /// ring buffer, which is only safe while the voice is still silent.
    func updateRecordings(active: Set<String>) {
        for slot in slots {
            guard let recording = slot.texture as? RecordingTexture else { continue }
            let shouldPlay = active.contains(slot.soundID)
            if shouldPlay && !recording.isActive {
                recording.activate()
            } else if !shouldPlay && recording.isActive {
                recording.deactivate()
            }
        }
    }

    /// Stops every reader. Called when the graph is torn down.
    func releaseRecordings() {
        for slot in slots {
            (slot.texture as? RecordingTexture)?.deactivate()
        }
    }

    /// Ramps the master output to `value` over `seconds`. Used for the start
    /// fade-in, the sleep timer's fade-out and the sunrise ramp, all of which
    /// need to hold their shape over durations from one second to an hour.
    func setMasterGain(_ value: Float, over seconds: Double) {
        rampTargetValue = clampf(value, 0, 1)
        rampSeconds = max(seconds, 0)
        rampToken &+= 1
    }

    /// Where the master ramp is headed. Safe to read from the main thread.
    var pendingMasterGain: Float { rampTargetValue }

    /// Clears all state so the next start begins from silence.
    func resetMaster() {
        masterGain = 0
        rampRemaining = 0
        rampEnd = 0
        rampTargetValue = 0
        meterEnvelope = 0
        meterLevel = 0
        for slot in slots {
            slot.currentGain = 0
            slot.targetGain = 0
        }
        guideGain = 0
        guideTargetGain = 0
    }

    // MARK: - Audio thread

    func render(
        frames: Int,
        left outL: UnsafeMutablePointer<Float>,
        right outR: UnsafeMutablePointer<Float>,
        stereo: Bool
    ) {
        updateRampIfNeeded()
        updateTiltIfNeeded()

        var offset = 0
        while offset < frames {
            let n = min(maxChunk, frames - offset)
            renderChunk(frames: n)

            if stereo {
                for i in 0..<n {
                    outL[offset + i] = scratchL[i]
                    outR[offset + i] = scratchR[i]
                }
            } else {
                for i in 0..<n {
                    outL[offset + i] = (scratchL[i] + scratchR[i]) * 0.5
                }
            }
            offset += n
        }
    }

    private func updateRampIfNeeded() {
        let token = rampToken
        guard token != seenToken else { return }
        seenToken = token

        let target = clampf(rampTargetValue, 0, 1)
        let samples = max(Int(rampSeconds * Double(sampleRate)), 1)
        rampEnd = target
        rampRemaining = samples
        rampStep = (target - masterGain) / Float(samples)
    }

    private func updateTiltIfNeeded() {
        let target = clampf(tiltTarget, -1, 1)
        guard abs(target - tiltCurrent) > 0.001 else { return }
        tiltCurrent = target
        let db = target * 7
        tiltHighL.setHighShelf(2400, gainDB: db, sampleRate: sampleRate)
        tiltHighR.setHighShelf(2450, gainDB: db, sampleRate: sampleRate)
        tiltLowL.setLowShelf(260, gainDB: -db * 0.6, sampleRate: sampleRate)
        tiltLowR.setLowShelf(265, gainDB: -db * 0.6, sampleRate: sampleRate)
    }

    private func renderChunk(frames n: Int) {
        // Textures accumulate into the buffer, so the chunk starts silent.
        scratchL.update(repeating: 0, count: n)
        scratchR.update(repeating: 0, count: n)

        for slot in slots where slot.isAudible {
            let start = slot.currentGain
            var end = start + (slot.targetGain - start) * voiceSmoothing
            if abs(slot.targetGain - end) < 0.00005 { end = slot.targetGain }
            slot.texture.render(
                frames: n,
                left: scratchL,
                right: scratchR,
                gainStart: start,
                gainEnd: end
            )
            slot.currentGain = end
        }

        if guideTargetGain > 0.00005 || guideGain > 0.00005 {
            let start = guideGain
            var end = start + (guideTargetGain - start) * voiceSmoothing
            if abs(guideTargetGain - end) < 0.00005 { end = guideTargetGain }
            guide.render(frames: n, left: scratchL, right: scratchR, gainStart: start, gainEnd: end)
            guideGain = end
        }

        applyMaster(frames: n)
    }

    private func applyMaster(frames n: Int) {
        var peak: Float = 0

        for i in 0..<n {
            if rampRemaining > 0 {
                masterGain += rampStep
                rampRemaining -= 1
                if rampRemaining == 0 { masterGain = rampEnd }
            }

            var l = tiltLowL.process(tiltHighL.process(scratchL[i])) * masterGain
            var r = tiltLowR.process(tiltHighR.process(scratchR[i])) * masterGain

            l = Renderer.softClip(l)
            r = Renderer.softClip(r)

            scratchL[i] = l
            scratchR[i] = r

            let magnitude = max(abs(l), abs(r))
            if magnitude > peak { peak = magnitude }
        }

        // Fast attack, slow release, so the UI breathes rather than flickers.
        if peak > meterEnvelope {
            meterEnvelope = peak
        } else {
            meterEnvelope += (peak - meterEnvelope) * 0.05
        }
        meterLevel = meterEnvelope
    }

    /// Soft knee reaching exactly +/-1 at +/-1.5 with a continuous derivative,
    /// so a six-layer mix compresses instead of clipping.
    @inline(__always)
    static func softClip(_ x: Float) -> Float {
        if x >= 1.5 { return 1 }
        if x <= -1.5 { return -1 }
        return x - (x * x * x) / 6.75
    }
}
