import AVFoundation
import Foundation

/// A bundled recording, played as just another voice in the mix.
///
/// Routing recordings through the same renderer as the synthesized textures is
/// the whole point: the sleep-timer fade, the sunrise ramp, the master tilt and
/// the limiter all behave identically whether a layer is a file or generated.
///
/// The audio thread only ever touches `ring`, which is created once in `build()`
/// before this object can be rendered and is never replaced. The stream that
/// fills it is created and destroyed on the main thread, so activating or
/// dropping a recording can never race a render call: it can only mean the ring
/// stops being refilled, and an empty ring is silence.
final class RecordingTexture: Texture {
    private let resource: String

    private var ring: AudioRingBuffer!
    private var stream: RecordingStream?

    private var tiltHighL = Biquad(), tiltHighR = Biquad()
    private var tiltLowL = Biquad(), tiltLowR = Biquad()
    private var drift = SlowDrift(seed: 0x2E17)
    private var driftDepth: Float = 0

    init(resource: String) {
        self.resource = resource
        super.init()
    }

    override func build() {
        // Two seconds of slack. The reader wakes every 400 ms, so this is five
        // times the headroom it needs, and it keeps the always-allocated cost
        // near 1 MB per recording as the library grows.
        ring = AudioRingBuffer(frames: Int(sampleRate * 2))
        drift.prepare(rate: 0.045, sampleRate: sampleRate)
    }

    override func configure() {
        // Tone tilts the recording warm or bright without touching the master.
        let db = (tone - 0.5) * 14
        tiltHighL.setHighShelf(2000, gainDB: db, sampleRate: sampleRate)
        tiltHighR.setHighShelf(2040, gainDB: db, sampleRate: sampleRate)
        tiltLowL.setLowShelf(240, gainDB: -db * 0.6, sampleRate: sampleRate)
        tiltLowR.setLowShelf(245, gainDB: -db * 0.6, sampleRate: sampleRate)

        // A ten-minute loop is still a loop. A slow level wander keeps it from
        // settling into something the ear can memorise.
        driftDepth = motion * 0.26
    }

    override func nextFrame() -> (Float, Float) {
        let (rawLeft, rawRight) = ring.readFrame()
        let wander = 1 + drift.next() * driftDepth
        let left = tiltLowL.process(tiltHighL.process(rawLeft)) * wander
        let right = tiltLowR.process(tiltHighR.process(rawRight)) * wander
        return (left, right)
    }

    // MARK: - Lifecycle, main thread only

    var isActive: Bool { stream != nil }

    /// Must be called before this voice's gain is raised.
    func activate() {
        guard stream == nil, ring != nil else { return }
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: 2
        ) else { return }

        // Safe here and only here: the gain is still zero, so the audio thread
        // is not reading this voice.
        ring.reset()

        guard let created = RecordingStream(
            resource: resource,
            outputFormat: format,
            ring: ring
        ) else { return }

        stream = created
        RecordingStreamPool.shared.add(created)
    }

    /// Stops decoding. The ring simply stops being refilled, which the audio
    /// thread reads as silence.
    func deactivate() {
        guard let current = stream else { return }
        stream = nil
        RecordingStreamPool.shared.remove(current)
    }

    deinit {
        if let current = stream {
            RecordingStreamPool.shared.remove(current)
        }
    }
}
