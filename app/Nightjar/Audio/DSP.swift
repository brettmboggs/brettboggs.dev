import Foundation

// Real-time primitives. Everything here is allocation-free once constructed and
// is only ever touched from the audio render thread after `prepare`.

@inline(__always)
func clampf(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
    x < lo ? lo : (x > hi ? hi : x)
}

@inline(__always)
func lerpf(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

/// Maps a 0...1 slider to a perceptual gain. Silence at 0, unity at 1.
@inline(__always)
func perceptualGain(_ x: Float) -> Float {
    let c = clampf(x, 0, 1)
    return c * c * c * 0.7 + c * 0.3 * c
}

// MARK: - Noise

/// xorshift32. Fast, no allocation, plenty of quality for a noise bed.
struct FastRandom {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed == 0 ? 0x9E37_79B9 : seed
    }

    @inline(__always)
    mutating func nextUInt() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// 0 ..< 1
    @inline(__always)
    mutating func uniform() -> Float {
        Float(nextUInt() >> 8) * (1.0 / 16_777_216.0)
    }

    /// -1 ..< 1
    @inline(__always)
    mutating func bipolar() -> Float {
        uniform() * 2 - 1
    }

    /// Roughly gaussian, cheap. Sum of three uniforms.
    @inline(__always)
    mutating func gauss() -> Float {
        (uniform() + uniform() + uniform() - 1.5) * 1.1547
    }
}

/// Paul Kellet's refined pink-noise filter. -3 dB/octave, no allocation.
struct PinkFilter {
    init() {}

    private var b0: Float = 0, b1: Float = 0, b2: Float = 0
    private var b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0

    @inline(__always)
    mutating func process(_ white: Float) -> Float {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return out * 0.18
    }
}

/// Leaky integrator. -6 dB/octave.
struct BrownFilter {
    init() {}

    private var z: Float = 0

    @inline(__always)
    mutating func process(_ white: Float) -> Float {
        z = (z + 0.02 * white) / 1.02
        return clampf(z * 3.5, -1, 1)
    }
}

// MARK: - Filters

/// One-pole lowpass. Used for smoothing control signals and dulling noise.
struct OnePole {
    init() {}

    private var a: Float = 0.01
    private var z: Float = 0

    /// `hz` is the -3 dB point.
    mutating func setCutoff(_ hz: Float, sampleRate: Float) {
        let f = clampf(hz, 0.0001, sampleRate * 0.49)
        a = clampf(1 - expf(-2 * .pi * f / sampleRate), 0, 1)
    }

    /// Direct time-constant form, for parameter smoothing.
    mutating func setTimeConstant(seconds: Float, sampleRate: Float) {
        let t = max(seconds, 0.0001)
        a = clampf(1 - expf(-1 / (t * sampleRate)), 0, 1)
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        z += a * (x - z)
        return z
    }

    @inline(__always)
    mutating func reset(to value: Float) { z = value }

    var value: Float { z }
}

/// RBJ cookbook biquad, transposed direct form II.
struct Biquad {
    init() {}

    private var b0: Float = 1, b1: Float = 0, b2: Float = 0
    private var a1: Float = 0, a2: Float = 0
    private var z1: Float = 0, z2: Float = 0

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        // Cheap denormal guard: these filters run for hours at a stretch.
        if y > -1e-25 && y < 1e-25 { z1 = 0; z2 = 0 }
        return y
    }

    mutating func reset() { z1 = 0; z2 = 0 }

    private mutating func normalize(_ nb0: Float, _ nb1: Float, _ nb2: Float,
                                    _ na0: Float, _ na1: Float, _ na2: Float) {
        let inv = 1 / na0
        b0 = nb0 * inv; b1 = nb1 * inv; b2 = nb2 * inv
        a1 = na1 * inv; a2 = na2 * inv
    }

    private static func omega(_ hz: Float, _ sampleRate: Float) -> Float {
        2 * .pi * clampf(hz, 10, sampleRate * 0.47) / sampleRate
    }

    mutating func setLowpass(_ hz: Float, q: Float, sampleRate: Float) {
        let w = Biquad.omega(hz, sampleRate)
        let cw = cosf(w), alpha = sinf(w) / (2 * max(q, 0.05))
        normalize((1 - cw) / 2, 1 - cw, (1 - cw) / 2, 1 + alpha, -2 * cw, 1 - alpha)
    }

    mutating func setHighpass(_ hz: Float, q: Float, sampleRate: Float) {
        let w = Biquad.omega(hz, sampleRate)
        let cw = cosf(w), alpha = sinf(w) / (2 * max(q, 0.05))
        normalize((1 + cw) / 2, -(1 + cw), (1 + cw) / 2, 1 + alpha, -2 * cw, 1 - alpha)
    }

    /// Constant 0 dB peak gain.
    mutating func setBandpass(_ hz: Float, q: Float, sampleRate: Float) {
        let w = Biquad.omega(hz, sampleRate)
        let cw = cosf(w), alpha = sinf(w) / (2 * max(q, 0.05))
        normalize(alpha, 0, -alpha, 1 + alpha, -2 * cw, 1 - alpha)
    }

    mutating func setPeak(_ hz: Float, q: Float, gainDB: Float, sampleRate: Float) {
        let a = powf(10, gainDB / 40)
        let w = Biquad.omega(hz, sampleRate)
        let cw = cosf(w), alpha = sinf(w) / (2 * max(q, 0.05))
        normalize(1 + alpha * a, -2 * cw, 1 - alpha * a,
                  1 + alpha / a, -2 * cw, 1 - alpha / a)
    }

    mutating func setLowShelf(_ hz: Float, gainDB: Float, sampleRate: Float) {
        let a = powf(10, gainDB / 40)
        let w = Biquad.omega(hz, sampleRate)
        let cw = cosf(w), sw = sinf(w)
        let alpha = sw / 2 * sqrtf((a + 1 / a) * (1 / 0.9 - 1) + 2)
        let twoSqrtAAlpha = 2 * sqrtf(a) * alpha
        normalize(
            a * ((a + 1) - (a - 1) * cw + twoSqrtAAlpha),
            2 * a * ((a - 1) - (a + 1) * cw),
            a * ((a + 1) - (a - 1) * cw - twoSqrtAAlpha),
            (a + 1) + (a - 1) * cw + twoSqrtAAlpha,
            -2 * ((a - 1) + (a + 1) * cw),
            (a + 1) + (a - 1) * cw - twoSqrtAAlpha
        )
    }

    mutating func setHighShelf(_ hz: Float, gainDB: Float, sampleRate: Float) {
        let a = powf(10, gainDB / 40)
        let w = Biquad.omega(hz, sampleRate)
        let cw = cosf(w), sw = sinf(w)
        let alpha = sw / 2 * sqrtf((a + 1 / a) * (1 / 0.9 - 1) + 2)
        let twoSqrtAAlpha = 2 * sqrtf(a) * alpha
        normalize(
            a * ((a + 1) + (a - 1) * cw + twoSqrtAAlpha),
            -2 * a * ((a - 1) + (a + 1) * cw),
            a * ((a + 1) + (a - 1) * cw - twoSqrtAAlpha),
            (a + 1) - (a - 1) * cw + twoSqrtAAlpha,
            2 * ((a - 1) - (a + 1) * cw),
            (a + 1) - (a - 1) * cw - twoSqrtAAlpha
        )
    }
}

// MARK: - Modulation

/// Band-limited wander used for gusts, swell and drift. A random walk through
/// a pair of one-poles, so it never steps and never repeats.
struct SlowDrift {
    private var target: Float = 0
    private var stage1 = OnePole()
    private var stage2 = OnePole()
    private var counter: Int = 0
    private var period: Int = 4800
    private var rng: FastRandom

    init(seed: UInt32) {
        rng = FastRandom(seed: seed)
    }

    /// `hz` is roughly how often a new target is chosen.
    mutating func prepare(rate hz: Float, sampleRate: Float) {
        period = max(Int(sampleRate / max(hz, 0.01)), 32)
        stage1.setTimeConstant(seconds: 1 / max(hz, 0.01), sampleRate: sampleRate)
        stage2.setTimeConstant(seconds: 1 / max(hz, 0.01), sampleRate: sampleRate)
    }

    /// -1 ... 1, smooth.
    @inline(__always)
    mutating func next() -> Float {
        counter += 1
        if counter >= period {
            counter = 0
            target = rng.bipolar()
        }
        return stage2.process(stage1.process(target))
    }
}

/// Plain sine oscillator, phase accumulator.
struct Phasor {
    init() {}

    private var phase: Float = 0
    private var inc: Float = 0

    mutating func setFrequency(_ hz: Float, sampleRate: Float) {
        inc = hz / sampleRate
    }

    mutating func randomizePhase(_ rng: inout FastRandom) {
        phase = rng.uniform()
    }

    @inline(__always)
    mutating func nextPhase() -> Float {
        phase += inc
        if phase >= 1 { phase -= 1 }
        return phase
    }

    @inline(__always)
    mutating func nextSine() -> Float {
        sinf(2 * .pi * nextPhase())
    }
}

// MARK: - Grains

/// One transient: a resonant tone mixed with a noise burst, rising over an
/// attack and then decaying. Used for raindrops, fire crackle, cricket chirps,
/// rail clatter, clock ticks and chimes.
///
/// The attack is the important part. A grain that starts at full amplitude on
/// a single sample is a step in the waveform, which is a click, and a click is
/// the one thing guaranteed to pull someone out of light sleep. Dense fast
/// events want it near zero; anything sparse and exposed wants tens of
/// milliseconds so it swells instead of snapping.
struct Grain {
    init() {}

    var active: Bool = false
    var amp: Float = 0
    var peak: Float = 0
    var attackRemaining: Int = 0
    var attackStep: Float = 0
    var decay: Float = 0.999
    var phase: Float = 0
    var phaseInc: Float = 0
    var noiseAmount: Float = 0
    var pan: Float = 0.5
    var filter = Biquad()
}

/// Fixed-capacity pool of grains. Allocated once, never grows.
final class GrainBank {
    private var grains: [Grain]
    private var rng: FastRandom
    private let sampleRateRef: Float

    init(capacity: Int, sampleRate: Float, seed: UInt32) {
        grains = Array(repeating: Grain(), count: max(capacity, 1))
        rng = FastRandom(seed: seed)
        sampleRateRef = sampleRate
    }

    /// Steals the quietest slot if all are busy, so density never clips.
    ///
    /// `attackSeconds` of zero keeps the old behaviour for dense textures where
    /// a crisp edge is the character. Anything sparse should pass a real value.
    func trigger(
        frequency: Float,
        decaySeconds: Float,
        amplitude: Float,
        noiseAmount: Float,
        pan: Float,
        resonance: Float = 6,
        attackSeconds: Float = 0
    ) {
        var index = -1
        var quietest: Float = .greatestFiniteMagnitude
        for i in grains.indices {
            if !grains[i].active { index = i; break }
            if grains[i].amp < quietest { quietest = grains[i].amp; index = i }
        }
        guard index >= 0 else { return }

        var grain = Grain()
        grain.active = true
        grain.peak = amplitude
        grain.decay = expf(-1 / (max(decaySeconds, 0.001) * sampleRateRef))
        grain.phase = 0
        grain.phaseInc = frequency / sampleRateRef
        grain.noiseAmount = noiseAmount
        grain.pan = clampf(pan, 0, 1)
        grain.filter.setBandpass(frequency, q: resonance, sampleRate: sampleRateRef)

        let attack = Int(max(attackSeconds, 0) * sampleRateRef)
        if attack > 1 {
            grain.amp = 0
            grain.attackRemaining = attack
            grain.attackStep = amplitude / Float(attack)
        } else {
            grain.amp = amplitude
            grain.attackRemaining = 0
        }
        grains[index] = grain
    }

    /// Renders one stereo frame from every live grain.
    @inline(__always)
    func nextFrame() -> (Float, Float) {
        var left: Float = 0
        var right: Float = 0
        for i in grains.indices where grains[i].active {
            grains[i].phase += grains[i].phaseInc
            if grains[i].phase >= 1 { grains[i].phase -= 1 }

            let tone = sinf(2 * .pi * grains[i].phase)
            let noise = rng.bipolar()
            let raw = lerpf(tone, grains[i].filter.process(noise), grains[i].noiseAmount)
            let value = raw * grains[i].amp

            if grains[i].attackRemaining > 0 {
                grains[i].amp += grains[i].attackStep
                grains[i].attackRemaining -= 1
                if grains[i].attackRemaining == 0 { grains[i].amp = grains[i].peak }
            } else {
                grains[i].amp *= grains[i].decay
                if grains[i].amp < 0.0002 {
                    grains[i].active = false
                    grains[i].filter.reset()
                }
            }

            left += value * (1 - grains[i].pan)
            right += value * grains[i].pan
        }
        // Grains are summed at half power because both channels get a share.
        return (left * 1.4, right * 1.4)
    }

    func reset() {
        for i in grains.indices { grains[i].active = false }
    }
}
