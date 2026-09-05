import Foundation

/// Base class for every synthesized texture.
///
/// `targetTone` / `targetMotion` are written from the main thread when a slider
/// moves. The audio thread smooths them and only rebuilds filter coefficients at
/// control rate, so a moving slider never tears a coefficient set mid-block.
class Texture {
    private(set) var sampleRate: Float = 48_000

    /// 0...1, written from the main thread.
    var targetTone: Float = 0.5
    /// 0...1, written from the main thread.
    var targetMotion: Float = 0.5

    /// Smoothed values. Audio thread only.
    private(set) var tone: Float = 0.5
    private(set) var motion: Float = 0.5

    private var toneSmoother = OnePole()
    private var motionSmoother = OnePole()
    private var controlCounter: Int = 0
    private let controlPeriod: Int = 64

    final func prepare(sampleRate: Float, tone: Float, motion: Float) {
        self.sampleRate = sampleRate
        targetTone = tone
        targetMotion = motion
        self.tone = tone
        self.motion = motion

        let controlRate = sampleRate / Float(controlPeriod)
        toneSmoother.setTimeConstant(seconds: 0.12, sampleRate: controlRate)
        motionSmoother.setTimeConstant(seconds: 0.12, sampleRate: controlRate)
        toneSmoother.reset(to: tone)
        motionSmoother.reset(to: motion)
        controlCounter = 0

        build()
        configure()
    }

    /// One-time construction that needs the sample rate.
    func build() {}

    /// Control-rate refresh. Reads `tone` and `motion`.
    func configure() {}

    /// One stereo frame, roughly -1...1.
    func nextFrame() -> (Float, Float) { (0, 0) }

    /// Advances parameter smoothing and refreshes coefficients. Called at
    /// control rate by `render`, and by any texture that hosts another one.
    final func controlTick() {
        tone = toneSmoother.process(targetTone)
        motion = motionSmoother.process(targetMotion)
        configure()
    }

    /// Accumulates this texture into the output buffers with a linear gain ramp.
    final func render(
        frames: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        gainStart: Float,
        gainEnd: Float
    ) {
        guard frames > 0 else { return }
        var gain = gainStart
        let step = (gainEnd - gainStart) / Float(frames)

        for i in 0..<frames {
            if controlCounter <= 0 {
                controlCounter = controlPeriod
                controlTick()
            }
            controlCounter -= 1

            let (l, r) = nextFrame()
            left[i] += l * gain
            right[i] += r * gain
            gain += step
        }
    }
}

// MARK: - Rain

/// Filtered bed plus stochastic droplets. Density and brightness are the two
/// things that separate a drizzle from a downpour, so both are exposed.
final class RainTexture: Texture {
    enum Character { case light, heavy, roof }

    private let character: Character
    private var rngL: FastRandom
    private var rngR: FastRandom
    private var dropRNG: FastRandom
    private var bedHPL = Biquad(), bedHPR = Biquad()
    private var bedLPL = Biquad(), bedLPR = Biquad()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var surge = SlowDrift(seed: 0x51A1)
    private var grains: GrainBank!

    private var dropProbability: Float = 0.002
    private var dropLow: Float = 1500
    private var dropSpan: Float = 3000
    private var dropDecay: Float = 0.006
    private var dropResonance: Float = 4
    private var dropNoise: Float = 0.85
    private var dropLevel: Float = 0.5
    private var bedLevel: Float = 0.5
    private var surgeDepth: Float = 0.1

    init(character: Character) {
        self.character = character
        rngL = FastRandom(seed: 0x1234_5678)
        rngR = FastRandom(seed: 0x8765_4321)
        dropRNG = FastRandom(seed: 0xBEEF_0001)
        super.init()
    }

    override func build() {
        grains = GrainBank(capacity: 40, sampleRate: sampleRate, seed: 0x0FAB)
        surge.prepare(rate: 0.09, sampleRate: sampleRate)
    }

    override func configure() {
        switch character {
        case .light:
            bedHPL.setHighpass(700 + tone * 700, q: 0.7, sampleRate: sampleRate)
            bedHPR.setHighpass(720 + tone * 700, q: 0.7, sampleRate: sampleRate)
            bedLPL.setLowpass(2600 + tone * 6000, q: 0.6, sampleRate: sampleRate)
            bedLPR.setLowpass(2650 + tone * 6000, q: 0.6, sampleRate: sampleRate)
            dropProbability = (18 + motion * 150) / sampleRate
            dropLow = 1200 + tone * 1800
            dropSpan = 1800 + tone * 2600
            dropDecay = 0.004 + (1 - tone) * 0.006
            dropResonance = 3.5
            dropNoise = 0.82
            dropLevel = 0.22
            bedLevel = 0.5
            surgeDepth = 0.06 + motion * 0.08

        case .heavy:
            bedHPL.setHighpass(180 + tone * 400, q: 0.7, sampleRate: sampleRate)
            bedHPR.setHighpass(190 + tone * 400, q: 0.7, sampleRate: sampleRate)
            bedLPL.setLowpass(3200 + tone * 5200, q: 0.6, sampleRate: sampleRate)
            bedLPR.setLowpass(3250 + tone * 5200, q: 0.6, sampleRate: sampleRate)
            dropProbability = (90 + motion * 320) / sampleRate
            dropLow = 700 + tone * 1200
            dropSpan = 1600 + tone * 2200
            dropDecay = 0.003 + (1 - tone) * 0.005
            dropResonance = 3
            dropNoise = 0.9
            dropLevel = 0.16
            bedLevel = 0.78
            surgeDepth = 0.10 + motion * 0.16

        case .roof:
            bedHPL.setHighpass(400 + tone * 500, q: 0.7, sampleRate: sampleRate)
            bedHPR.setHighpass(420 + tone * 500, q: 0.7, sampleRate: sampleRate)
            bedLPL.setLowpass(2200 + tone * 3800, q: 0.6, sampleRate: sampleRate)
            bedLPR.setLowpass(2250 + tone * 3800, q: 0.6, sampleRate: sampleRate)
            dropProbability = (30 + motion * 190) / sampleRate
            dropLow = 900 + tone * 2200
            dropSpan = 2400 + tone * 3400
            // Metal rings: longer decay and a much tighter resonance.
            dropDecay = 0.012 + tone * 0.055
            dropResonance = 6 + tone * 16
            dropNoise = 0.55 - tone * 0.35
            dropLevel = 0.30
            bedLevel = 0.34
            surgeDepth = 0.05 + motion * 0.09
        }
    }

    override func nextFrame() -> (Float, Float) {
        let swell = 1 + surge.next() * surgeDepth

        var l = pinkL.process(rngL.bipolar())
        var r = pinkR.process(rngR.bipolar())
        l = bedLPL.process(bedHPL.process(l)) * bedLevel * swell
        r = bedLPR.process(bedHPR.process(r)) * bedLevel * swell

        if dropRNG.uniform() < dropProbability * swell {
            let f = dropLow + dropRNG.uniform() * dropSpan
            grains.trigger(
                frequency: f,
                decaySeconds: dropDecay * (0.6 + dropRNG.uniform() * 0.9),
                amplitude: dropLevel * (0.35 + dropRNG.uniform() * 0.9),
                noiseAmount: dropNoise,
                pan: dropRNG.uniform(),
                resonance: dropResonance
            )
        }

        let (gl, gr) = grains.nextFrame()
        return (l + gl, r + gr)
    }
}

// MARK: - Thunderstorm

final class StormTexture: Texture {
    private var rain = RainTexture(character: .heavy)
    private var rng = FastRandom(seed: 0x7B0D_0001)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var noiseL = FastRandom(seed: 0xAA11), noiseR = FastRandom(seed: 0xBB22)
    private var rumbleLP_L = Biquad(), rumbleLP_R = Biquad()
    private var attack = OnePole()
    private var body = OnePole()
    private var roll = SlowDrift(seed: 0x33CC)
    private var gateSamples: Int = 0
    private var countdown: Int = 0
    private var strikeLevel: Float = 0
    private var strikePan: Float = 0.5
    private var rumbleCutoff: Float = 300

    override func build() {
        rain.prepare(sampleRate: sampleRate, tone: 0.4, motion: 0.45)
        attack.setTimeConstant(seconds: 0.28, sampleRate: sampleRate)
        body.setTimeConstant(seconds: 0.55, sampleRate: sampleRate)
        roll.prepare(rate: 1.6, sampleRate: sampleRate)
        countdown = Int(sampleRate * 6)
    }

    override func configure() {
        rain.targetTone = 0.35 + tone * 0.25
        rain.targetMotion = 0.4
        rain.controlTick()
        // Distance: near strikes are bright and frequent, far ones are a dull roll.
        rumbleCutoff = 90 + (1 - tone) * 900
        rumbleLP_L.setLowpass(rumbleCutoff, q: 0.7, sampleRate: sampleRate)
        rumbleLP_R.setLowpass(rumbleCutoff * 1.05, q: 0.7, sampleRate: sampleRate)
    }

    override func nextFrame() -> (Float, Float) {
        countdown -= 1
        if countdown <= 0 {
            // 12s to 90s apart, tightening as motion rises.
            let mean = 90 - motion * 78
            let jitter = 0.45 + rng.uniform() * 1.4
            countdown = max(Int(sampleRate * mean * jitter), Int(sampleRate * 4))
            gateSamples = Int(sampleRate * (0.25 + rng.uniform() * 1.3))
            strikeLevel = 0.35 + rng.uniform() * 0.65
            strikePan = 0.25 + rng.uniform() * 0.5
        }

        var gate: Float = 0
        if gateSamples > 0 {
            gateSamples -= 1
            gate = strikeLevel
        }
        let envelope = body.process(attack.process(gate))
        let rolling = envelope * (1 + roll.next() * 0.45)

        var thunderL: Float = 0
        var thunderR: Float = 0
        if rolling > 0.0008 {
            let bl = brownL.process(noiseL.bipolar())
            let br = brownR.process(noiseR.bipolar())
            thunderL = rumbleLP_L.process(bl) * rolling * (1 - strikePan) * 2.4
            thunderR = rumbleLP_R.process(br) * rolling * strikePan * 2.4
        }

        let (rl, rr) = rain.nextFrame()
        return (rl * 0.85 + thunderL, rr * 0.85 + thunderR)
    }
}

// MARK: - Ocean

/// Asymmetric wave envelope: waves rise faster than they fall, and no two
/// cycles are the same length.
final class OceanTexture: Texture {
    private var rngL = FastRandom(seed: 0x0CEA), rngR = FastRandom(seed: 0x0CEB)
    private var cycleRNG = FastRandom(seed: 0x0CEC)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var bodyLP_L = Biquad(), bodyLP_R = Biquad()
    private var foamHP_L = Biquad(), foamHP_R = Biquad()
    private var envSmooth = OnePole()

    private var phase: Float = 0
    private var cycleSamples: Float = 48_000 * 11
    private var risePortion: Float = 0.34
    private var cycleAmp: Float = 1
    private var foamAmount: Float = 0.4

    override func build() {
        envSmooth.setTimeConstant(seconds: 0.05, sampleRate: sampleRate)
        newCycle()
    }

    override func configure() {
        bodyLP_L.setLowpass(320 + tone * 900, q: 0.6, sampleRate: sampleRate)
        bodyLP_R.setLowpass(330 + tone * 900, q: 0.6, sampleRate: sampleRate)
        foamHP_L.setHighpass(1400 + tone * 3200, q: 0.6, sampleRate: sampleRate)
        foamHP_R.setHighpass(1430 + tone * 3200, q: 0.6, sampleRate: sampleRate)
        foamAmount = 0.18 + tone * 0.55
    }

    private func newCycle() {
        // 7s to 17s sets, longer and more varied as motion rises.
        let base = 7 + motion * 6
        let spread = 1 + motion * 4
        cycleSamples = sampleRate * (base + cycleRNG.uniform() * spread)
        risePortion = 0.26 + cycleRNG.uniform() * 0.16
        cycleAmp = 0.55 + cycleRNG.uniform() * 0.45
    }

    override func nextFrame() -> (Float, Float) {
        phase += 1 / cycleSamples
        if phase >= 1 {
            phase -= 1
            newCycle()
        }

        // Fast rise, long fall, then shaped for a rounder crest.
        let raw: Float
        if phase < risePortion {
            raw = phase / risePortion
        } else {
            raw = 1 - (phase - risePortion) / (1 - risePortion)
        }
        let shaped = raw * raw * (3 - 2 * raw)
        let envelope = envSmooth.process(shaped * cycleAmp)

        let bl = brownL.process(rngL.bipolar())
        let br = brownR.process(rngR.bipolar())
        let bodyL = bodyLP_L.process(bl) * (0.30 + envelope * 0.85)
        let bodyR = bodyLP_R.process(br) * (0.30 + envelope * 0.85)

        // Foam only appears near the crest.
        let crest = envelope * envelope * envelope
        let fl = foamHP_L.process(pinkL.process(rngL.bipolar())) * crest * foamAmount * 1.6
        let fr = foamHP_R.process(pinkR.process(rngR.bipolar())) * crest * foamAmount * 1.6

        return (bodyL + fl, bodyR + fr)
    }
}

// MARK: - Creek

final class StreamTexture: Texture {
    private var rngL = FastRandom(seed: 0x5711), rngR = FastRandom(seed: 0x5722)
    private var burbleRNG = FastRandom(seed: 0x5733)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var bpL = Biquad(), bpR = Biquad()
    private var hissL = Biquad(), hissR = Biquad()
    private var grains: GrainBank!
    private var burbleProbability: Float = 0.004
    private var burbleLow: Float = 400
    private var burbleSpan: Float = 1200

    override func build() {
        grains = GrainBank(capacity: 28, sampleRate: sampleRate, seed: 0x57AA)
    }

    override func configure() {
        let center = 900 + tone * 2200
        bpL.setBandpass(center, q: 0.8, sampleRate: sampleRate)
        bpR.setBandpass(center * 1.04, q: 0.8, sampleRate: sampleRate)
        hissL.setHighpass(3000 + tone * 3000, q: 0.7, sampleRate: sampleRate)
        hissR.setHighpass(3050 + tone * 3000, q: 0.7, sampleRate: sampleRate)
        burbleProbability = (25 + motion * 190) / sampleRate
        burbleLow = 260 + tone * 500
        burbleSpan = 600 + tone * 1400
    }

    override func nextFrame() -> (Float, Float) {
        let nl = pinkL.process(rngL.bipolar())
        let nr = pinkR.process(rngR.bipolar())
        var l = bpL.process(nl) * 1.5 + hissL.process(nl) * 0.30
        var r = bpR.process(nr) * 1.5 + hissR.process(nr) * 0.30

        if burbleRNG.uniform() < burbleProbability {
            grains.trigger(
                frequency: burbleLow + burbleRNG.uniform() * burbleSpan,
                decaySeconds: 0.012 + burbleRNG.uniform() * 0.045,
                amplitude: 0.10 + burbleRNG.uniform() * 0.20,
                noiseAmount: 0.35,
                pan: burbleRNG.uniform(),
                resonance: 9 + burbleRNG.uniform() * 12
            )
        }

        let (gl, gr) = grains.nextFrame()
        l += gl
        r += gr
        return (l * 0.55, r * 0.55)
    }
}

// MARK: - Wind

final class WindTexture: Texture {
    enum Character { case open, pines }

    private let character: Character
    private var rngL: FastRandom
    private var rngR: FastRandom
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var bpL = Biquad(), bpR = Biquad()
    private var bp2L = Biquad(), bp2R = Biquad()
    private var hissL = Biquad(), hissR = Biquad()
    private var centerDrift = SlowDrift(seed: 0x1D01)
    private var gustDrift = SlowDrift(seed: 0x1D02)
    private var center2Drift = SlowDrift(seed: 0x1D03)
    private var coefCounter: Int = 0

    private var centerBase: Float = 500
    private var centerRange: Float = 400
    private var resonance: Float = 1.6
    private var gustDepth: Float = 0.4
    private var hissLevel: Float = 0.1
    private var secondLevel: Float = 0

    init(character: Character) {
        self.character = character
        rngL = FastRandom(seed: character == .open ? 0x2001 : 0x3001)
        rngR = FastRandom(seed: character == .open ? 0x2002 : 0x3002)
        super.init()
    }

    override func build() {
        centerDrift.prepare(rate: 0.16, sampleRate: sampleRate)
        center2Drift.prepare(rate: 0.11, sampleRate: sampleRate)
        gustDrift.prepare(rate: 0.07, sampleRate: sampleRate)
    }

    override func configure() {
        switch character {
        case .open:
            centerBase = 240 + tone * 700
            centerRange = 140 + tone * 420
            resonance = 1.1 + tone * 1.4
            hissLevel = 0.05 + tone * 0.14
            secondLevel = 0
        case .pines:
            centerBase = 1100 + tone * 2600
            centerRange = 500 + tone * 1500
            resonance = 1.6 + tone * 2.6
            hissLevel = 0.10 + tone * 0.26
            secondLevel = 0.55
        }
        gustDepth = 0.20 + motion * 0.70
        hissL.setHighpass(4000, q: 0.7, sampleRate: sampleRate)
        hissR.setHighpass(4100, q: 0.7, sampleRate: sampleRate)
    }

    override func nextFrame() -> (Float, Float) {
        let wander = centerDrift.next()
        let wander2 = center2Drift.next()

        // Sweeping a bandpass means new coefficients, which cost trig. Doing it
        // every 32 samples is still far faster than the drift itself moves.
        coefCounter -= 1
        if coefCounter <= 0 {
            coefCounter = 32
            let center = clampf(centerBase + wander * centerRange, 60, sampleRate * 0.4)
            bpL.setBandpass(center, q: resonance, sampleRate: sampleRate)
            bpR.setBandpass(center * 1.06, q: resonance, sampleRate: sampleRate)
            if secondLevel > 0 {
                let c2 = clampf(centerBase * 2.1 + wander2 * centerRange, 200, sampleRate * 0.42)
                bp2L.setBandpass(c2, q: resonance * 1.5, sampleRate: sampleRate)
                bp2R.setBandpass(c2 * 1.07, q: resonance * 1.5, sampleRate: sampleRate)
            }
        }

        let nl = pinkL.process(rngL.bipolar())
        let nr = pinkR.process(rngR.bipolar())
        var l = bpL.process(nl) * 2.2
        var r = bpR.process(nr) * 2.2

        if secondLevel > 0 {
            l += bp2L.process(nl) * 1.6 * secondLevel
            r += bp2R.process(nr) * 1.6 * secondLevel
        }

        l += hissL.process(nl) * hissLevel
        r += hissR.process(nr) * hissLevel

        // Gusts swell the whole band together.
        let gust = 1 + gustDrift.next() * gustDepth
        let level = clampf(gust, 0.15, 2.2) * 0.55
        return (l * level, r * level)
    }
}

// MARK: - Fire

final class FireTexture: Texture {
    private var rngL = FastRandom(seed: 0xF11E), rngR = FastRandom(seed: 0xF12E)
    private var crackRNG = FastRandom(seed: 0xF13E)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var roarLP_L = Biquad(), roarLP_R = Biquad()
    private var burstDrift = SlowDrift(seed: 0xF1AA)
    private var grains: GrainBank!
    private var crackleProbability: Float = 0.003
    private var roarLevel: Float = 0.5

    override func build() {
        grains = GrainBank(capacity: 24, sampleRate: sampleRate, seed: 0xF1BB)
        burstDrift.prepare(rate: 0.22, sampleRate: sampleRate)
    }

    override func configure() {
        let cutoff = 180 + tone * 520
        roarLP_L.setLowpass(cutoff, q: 0.7, sampleRate: sampleRate)
        roarLP_R.setLowpass(cutoff * 1.06, q: 0.7, sampleRate: sampleRate)
        roarLevel = 0.35 + tone * 0.75
        crackleProbability = (6 + motion * 70) / sampleRate
    }

    override func nextFrame() -> (Float, Float) {
        let bl = brownL.process(rngL.bipolar())
        let br = brownR.process(rngR.bipolar())
        var l = roarLP_L.process(bl) * roarLevel * 1.5
        var r = roarLP_R.process(br) * roarLevel * 1.5

        // Fires crackle in bursts, not evenly.
        let burst = 1 + burstDrift.next() * 0.85
        if crackRNG.uniform() < crackleProbability * max(burst, 0.1) {
            let big = crackRNG.uniform() < 0.08
            grains.trigger(
                frequency: big
                    ? 260 + crackRNG.uniform() * 700
                    : 900 + crackRNG.uniform() * 5200,
                decaySeconds: big
                    ? 0.03 + crackRNG.uniform() * 0.07
                    : 0.002 + crackRNG.uniform() * 0.014,
                amplitude: big
                    ? 0.30 + crackRNG.uniform() * 0.40
                    : 0.06 + crackRNG.uniform() * 0.26,
                noiseAmount: 0.78,
                pan: 0.15 + crackRNG.uniform() * 0.7,
                resonance: 2.5 + crackRNG.uniform() * 6
            )
        }

        let (gl, gr) = grains.nextFrame()
        l += gl
        r += gr
        return (l, r)
    }
}

// MARK: - Crickets

/// Several independent insects, each with its own tempo, pitch and position.
/// Interleaving them is what keeps it from sounding like a loop.
final class CricketTexture: Texture {
    private struct Insect {
        var countdown: Int = 0
        var pulsesLeft: Int = 0
        var pulseSamples: Int = 0
        var gapSamples: Int = 0
        var inPulse: Bool = false
        var phase: Float = 0
        var frequency: Float = 4500
        var pan: Float = 0.5
        var amp: Float = 0.5
        var envelope: Float = 0
    }

    private var insects = [Insect](repeating: Insect(), count: 7)
    private var rng = FastRandom(seed: 0xC21C)
    private var airRNG_L = FastRandom(seed: 0xC22C), airRNG_R = FastRandom(seed: 0xC23C)
    private var airPinkL = PinkFilter(), airPinkR = PinkFilter()
    private var airLP_L = Biquad(), airLP_R = Biquad()
    private var envSmooth = [OnePole](repeating: OnePole(), count: 7)
    private var activeCount: Int = 4
    private var baseFrequency: Float = 4500

    override func build() {
        for i in insects.indices {
            insects[i].countdown = Int(rng.uniform() * sampleRate * 3)
            envSmooth[i].setTimeConstant(seconds: 0.004, sampleRate: sampleRate)
        }
        airLP_L.setLowpass(900, q: 0.6, sampleRate: sampleRate)
        airLP_R.setLowpass(920, q: 0.6, sampleRate: sampleRate)
    }

    override func configure() {
        baseFrequency = 3400 + tone * 2800
        activeCount = 2 + Int(motion * 5)
    }

    override func nextFrame() -> (Float, Float) {
        var left: Float = 0
        var right: Float = 0

        for i in 0..<min(activeCount, insects.count) {
            if insects[i].pulsesLeft <= 0 {
                insects[i].countdown -= 1
                if insects[i].countdown <= 0 {
                    // A chirp is a short run of pulses, then a long rest.
                    insects[i].pulsesLeft = 3 + Int(rng.uniform() * 3)
                    insects[i].pulseSamples = Int(sampleRate * (0.012 + rng.uniform() * 0.014))
                    insects[i].gapSamples = Int(sampleRate * (0.020 + rng.uniform() * 0.030))
                    insects[i].frequency = baseFrequency * (0.86 + rng.uniform() * 0.30)
                    insects[i].pan = rng.uniform()
                    insects[i].amp = 0.10 + rng.uniform() * 0.22
                    insects[i].inPulse = true
                    insects[i].countdown = insects[i].pulseSamples
                }
            }

            var target: Float = 0
            if insects[i].pulsesLeft > 0 {
                insects[i].countdown -= 1
                if insects[i].inPulse {
                    target = 1
                    if insects[i].countdown <= 0 {
                        insects[i].inPulse = false
                        insects[i].countdown = insects[i].gapSamples
                        insects[i].pulsesLeft -= 1
                        if insects[i].pulsesLeft <= 0 {
                            // Rest 0.8s to 4s before the next chirp.
                            insects[i].countdown = Int(sampleRate * (0.8 + rng.uniform() * 3.2))
                        }
                    }
                } else if insects[i].countdown <= 0 {
                    insects[i].inPulse = true
                    insects[i].countdown = insects[i].pulseSamples
                }
            }

            let env = envSmooth[i].process(target)
            if env > 0.0008 {
                insects[i].phase += insects[i].frequency / sampleRate
                if insects[i].phase >= 1 { insects[i].phase -= 1 }
                // Two partials: the second gives the chirp its edge.
                let p = insects[i].phase
                let value = (sinf(2 * .pi * p) + 0.35 * sinf(4 * .pi * p))
                    * env * insects[i].amp
                left += value * (1 - insects[i].pan)
                right += value * insects[i].pan
            }
        }

        // A thin bed of night air underneath.
        let al = airLP_L.process(airPinkL.process(airRNG_L.bipolar())) * 0.16
        let ar = airLP_R.process(airPinkR.process(airRNG_R.bipolar())) * 0.16
        return (left + al, right + ar)
    }
}

// MARK: - Room tone

final class RoomToneTexture: Texture {
    private var rngL = FastRandom(seed: 0x900D), rngR = FastRandom(seed: 0x900E)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var lpL = Biquad(), lpR = Biquad()
    private var peakL = Biquad(), peakR = Biquad()
    private var airL = Biquad(), airR = Biquad()
    private var drift = SlowDrift(seed: 0x900F)
    private var airLevel: Float = 0.1
    private var driftDepth: Float = 0.1

    override func build() {
        drift.prepare(rate: 0.05, sampleRate: sampleRate)
    }

    override func configure() {
        lpL.setLowpass(180 + tone * 260, q: 0.7, sampleRate: sampleRate)
        lpR.setLowpass(186 + tone * 260, q: 0.7, sampleRate: sampleRate)
        peakL.setPeak(62, q: 3, gainDB: 7, sampleRate: sampleRate)
        peakR.setPeak(64, q: 3, gainDB: 7, sampleRate: sampleRate)
        airL.setHighpass(5200, q: 0.7, sampleRate: sampleRate)
        airR.setHighpass(5300, q: 0.7, sampleRate: sampleRate)
        airLevel = 0.03 + tone * 0.13
        driftDepth = 0.05 + motion * 0.25
    }

    override func nextFrame() -> (Float, Float) {
        let wobble = 1 + drift.next() * driftDepth
        let bl = brownL.process(rngL.bipolar())
        let br = brownR.process(rngR.bipolar())
        let l = peakL.process(lpL.process(bl)) * 1.7 * wobble
            + airL.process(pinkL.process(rngL.bipolar())) * airLevel
        let r = peakR.process(lpR.process(br)) * 1.7 * wobble
            + airR.process(pinkR.process(rngR.bipolar())) * airLevel
        return (l, r)
    }
}

// MARK: - Box fan

final class FanTexture: Texture {
    private var rngL = FastRandom(seed: 0xFA01), rngR = FastRandom(seed: 0xFA02)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var lpL = Biquad(), lpR = Biquad()
    private var hpL = Biquad(), hpR = Biquad()
    private var motorL = Biquad(), motorR = Biquad()
    private var blade = Phasor()
    private var sweep = Phasor()
    private var bladeDepth: Float = 0.08
    private var sweepDepth: Float = 0
    private var motorLevel: Float = 0.4

    override func build() {
        blade.setFrequency(21, sampleRate: sampleRate)
        // One head turn every ~9 seconds.
        sweep.setFrequency(0.11, sampleRate: sampleRate)
    }

    override func configure() {
        lpL.setLowpass(900 + tone * 2600, q: 0.6, sampleRate: sampleRate)
        lpR.setLowpass(920 + tone * 2600, q: 0.6, sampleRate: sampleRate)
        hpL.setHighpass(60, q: 0.7, sampleRate: sampleRate)
        hpR.setHighpass(62, q: 0.7, sampleRate: sampleRate)
        motorL.setPeak(118, q: 5, gainDB: 4 + tone * 8, sampleRate: sampleRate)
        motorR.setPeak(120, q: 5, gainDB: 4 + tone * 8, sampleRate: sampleRate)
        motorLevel = 0.25 + tone * 0.5
        bladeDepth = 0.02 + motion * 0.16
        sweepDepth = motion > 0.55 ? (motion - 0.55) * 1.1 : 0
    }

    override func nextFrame() -> (Float, Float) {
        let bl = brownL.process(rngL.bipolar()) * 0.75 + pinkL.process(rngL.bipolar()) * 0.45
        let br = brownR.process(rngR.bipolar()) * 0.75 + pinkR.process(rngR.bipolar()) * 0.45
        var l = motorL.process(hpL.process(lpL.process(bl))) * 1.5 * motorLevel
        var r = motorR.process(hpR.process(lpR.process(br))) * 1.5 * motorLevel

        // Blade chop.
        let chop = 1 + blade.nextSine() * bladeDepth
        l *= chop
        r *= chop

        // The head turning: level and balance drift together.
        if sweepDepth > 0 {
            let s = sweep.nextSine()
            let amount = sweepDepth * 0.5
            l *= 1 + s * amount
            r *= 1 - s * amount
        } else {
            _ = sweep.nextPhase()
        }

        return (l, r)
    }
}

// MARK: - Airliner cabin

final class AirlinerTexture: Texture {
    private var rngL = FastRandom(seed: 0xA1F1), rngR = FastRandom(seed: 0xA1F2)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var lpL = Biquad(), lpR = Biquad()
    private var hullL = Biquad(), hullR = Biquad()
    private var hissL = Biquad(), hissR = Biquad()
    private var turbulence = SlowDrift(seed: 0xA1F3)
    private var spectral = SlowDrift(seed: 0xA1F4)
    private var hissLevel: Float = 0.1
    private var turbDepth: Float = 0.08

    override func build() {
        turbulence.prepare(rate: 0.06, sampleRate: sampleRate)
        spectral.prepare(rate: 0.03, sampleRate: sampleRate)
    }

    override func configure() {
        lpL.setLowpass(210 + tone * 620, q: 0.6, sampleRate: sampleRate)
        lpR.setLowpass(216 + tone * 620, q: 0.6, sampleRate: sampleRate)
        hullL.setPeak(88, q: 2.5, gainDB: 6, sampleRate: sampleRate)
        hullR.setPeak(91, q: 2.5, gainDB: 6, sampleRate: sampleRate)
        hissL.setHighpass(2200, q: 0.7, sampleRate: sampleRate)
        hissR.setHighpass(2250, q: 0.7, sampleRate: sampleRate)
        hissLevel = 0.04 + tone * 0.20
        turbDepth = 0.04 + motion * 0.22
    }

    override func nextFrame() -> (Float, Float) {
        let breathe = 1 + turbulence.next() * turbDepth
        let colour = spectral.next() * 0.2

        let bl = brownL.process(rngL.bipolar())
        let br = brownR.process(rngR.bipolar())
        let l = hullL.process(lpL.process(bl)) * 2.0 * breathe
            + hissL.process(pinkL.process(rngL.bipolar())) * (hissLevel + colour * 0.05)
        let r = hullR.process(lpR.process(br)) * 2.0 * breathe
            + hissR.process(pinkR.process(rngR.bipolar())) * (hissLevel + colour * 0.05)
        return (l, r)
    }
}

// MARK: - Night train

final class TrainTexture: Texture {
    private var rngL = FastRandom(seed: 0x7A11), rngR = FastRandom(seed: 0x7A12)
    private var clackRNG = FastRandom(seed: 0x7A13)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var lpL = Biquad(), lpR = Biquad()
    private var hpL = Biquad(), hpR = Biquad()
    private var grains: GrainBank!
    private var sway = SlowDrift(seed: 0x7A14)

    private var intervalSamples: Int = 24_000
    private var countdown: Int = 0
    private var inPair: Bool = false
    private var clackLevel: Float = 0.3

    override func build() {
        grains = GrainBank(capacity: 16, sampleRate: sampleRate, seed: 0x7A15)
        sway.prepare(rate: 0.08, sampleRate: sampleRate)
        countdown = 1_000
    }

    override func configure() {
        lpL.setLowpass(240 + tone * 900, q: 0.7, sampleRate: sampleRate)
        lpR.setLowpass(248 + tone * 900, q: 0.7, sampleRate: sampleRate)
        hpL.setHighpass(35, q: 0.7, sampleRate: sampleRate)
        hpR.setHighpass(36, q: 0.7, sampleRate: sampleRate)
        // Faster train, closer-spaced joints.
        let perSecond = 0.9 + motion * 1.6
        intervalSamples = max(Int(sampleRate / perSecond), 2_000)
        clackLevel = 0.10 + motion * 0.34
    }

    override func nextFrame() -> (Float, Float) {
        let swayValue = 1 + sway.next() * 0.16
        let bl = brownL.process(rngL.bipolar())
        let br = brownR.process(rngR.bipolar())
        var l = hpL.process(lpL.process(bl)) * 1.9 * swayValue
        var r = hpR.process(lpR.process(br)) * 1.9 * swayValue

        countdown -= 1
        if countdown <= 0 {
            let pan = 0.2 + clackRNG.uniform() * 0.6
            grains.trigger(
                frequency: 150 + clackRNG.uniform() * 420,
                decaySeconds: 0.020 + clackRNG.uniform() * 0.035,
                amplitude: clackLevel * (0.6 + clackRNG.uniform() * 0.6),
                noiseAmount: 0.62,
                pan: pan,
                resonance: 4 + clackRNG.uniform() * 6
            )
            if inPair {
                inPair = false
                countdown = intervalSamples
            } else {
                // "da-dum": the second axle follows close behind.
                inPair = true
                countdown = Int(Float(intervalSamples) * (0.13 + clackRNG.uniform() * 0.06))
            }
        }

        let (gl, gr) = grains.nextFrame()
        l += gl
        r += gr
        return (l, r)
    }
}

// MARK: - Plain noise

final class PlainNoiseTexture: Texture {
    enum Colour { case white, pink, brown }

    private let colour: Colour
    private var common = FastRandom(seed: 0x0C0F_0001)
    private var indepL = FastRandom(seed: 0x0A11)
    private var indepR = FastRandom(seed: 0x0A22)
    private var pinkC = PinkFilter(), pinkL = PinkFilter(), pinkR = PinkFilter()
    private var brownC = BrownFilter(), brownL = BrownFilter(), brownR = BrownFilter()
    private var tiltL = Biquad(), tiltR = Biquad()
    private var tilt2L = Biquad(), tilt2R = Biquad()
    private var width: Float = 0.5

    init(colour: Colour) {
        self.colour = colour
        super.init()
    }

    override func configure() {
        // One slider tilts the whole spectrum: warm at 0, bright at 1.
        let db = (tone - 0.5) * 16
        tiltL.setHighShelf(1800, gainDB: db, sampleRate: sampleRate)
        tiltR.setHighShelf(1830, gainDB: db, sampleRate: sampleRate)
        tilt2L.setLowShelf(320, gainDB: -db * 0.7, sampleRate: sampleRate)
        tilt2R.setLowShelf(325, gainDB: -db * 0.7, sampleRate: sampleRate)
        width = motion
    }

    override func nextFrame() -> (Float, Float) {
        let wc = common.bipolar()
        let wl = indepL.bipolar()
        let wr = indepR.bipolar()

        let c: Float
        let il: Float
        let ir: Float
        switch colour {
        case .white:
            c = wc * 0.4
            il = wl * 0.4
            ir = wr * 0.4
        case .pink:
            c = pinkC.process(wc) * 1.5
            il = pinkL.process(wl) * 1.5
            ir = pinkR.process(wr) * 1.5
        case .brown:
            c = brownC.process(wc) * 0.9
            il = brownL.process(wl) * 0.9
            ir = brownR.process(wr) * 0.9
        }

        // width 0 is mono, width 1 is fully decorrelated.
        let l = lerpf(c, il, width)
        let r = lerpf(c, ir, width)
        return (tilt2L.process(tiltL.process(l)), tilt2R.process(tiltR.process(r)))
    }
}

// MARK: - Factory

enum TextureFactory {
    static func make(_ kind: SoundKind) -> Texture {
        if case .recording(let resource) = kind.source {
            return RecordingTexture(resource: resource)
        }
        switch kind.id {
        case "rain.light": return RainTexture(character: .light)
        case "rain.heavy": return RainTexture(character: .heavy)
        case "rain.roof": return RainTexture(character: .roof)
        case "storm": return StormTexture()
        case "ocean": return OceanTexture()
        case "stream": return StreamTexture()
        case "wind.plain": return WindTexture(character: .open)
        case "wind.trees": return WindTexture(character: .pines)
        case "fire": return FireTexture()
        case "crickets": return CricketTexture()
        case "cabin": return RoomToneTexture()
        case "fan": return FanTexture()
        case "airliner": return AirlinerTexture()
        case "train": return TrainTexture()
        case "noise.white": return PlainNoiseTexture(colour: .white)
        case "noise.pink": return PlainNoiseTexture(colour: .pink)
        case "noise.brown": return PlainNoiseTexture(colour: .brown)
        default: return PlainNoiseTexture(colour: .brown)
        }
    }
}
