import Foundation

// Machines and rooms. What makes these convincing is not the noise floor but
// the periodicity sitting on top of it: a compressor cycle, a drum rotation,
// a pendulum. Get the rhythm right and the noise underneath can be simple.

/// Window air conditioner. Brighter than a fan, with a compressor under it.
final class AirConditionerTexture: Texture {
    private var rngL = FastRandom(seed: 0xAC01), rngR = FastRandom(seed: 0xAC02)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var airLP_L = Biquad(), airLP_R = Biquad()
    private var humL = Biquad(), humR = Biquad()
    private var harmonicL = Biquad(), harmonicR = Biquad()
    private var cycle = SlowDrift(seed: 0xAC03)
    private var humLevel: Float = 0.4
    private var cycleDepth: Float = 0.05

    override func build() {
        cycle.prepare(rate: 0.035, sampleRate: sampleRate)
    }

    override func configure() {
        airLP_L.setLowpass(1600 + tone * 4200, q: 0.6, sampleRate: sampleRate)
        airLP_R.setLowpass(1640 + tone * 4200, q: 0.6, sampleRate: sampleRate)
        humL.setPeak(118, q: 6, gainDB: 5 + motion * 9, sampleRate: sampleRate)
        humR.setPeak(120, q: 6, gainDB: 5 + motion * 9, sampleRate: sampleRate)
        harmonicL.setPeak(236, q: 7, gainDB: 3 + motion * 5, sampleRate: sampleRate)
        harmonicR.setPeak(240, q: 7, gainDB: 3 + motion * 5, sampleRate: sampleRate)
        humLevel = 0.3 + motion * 0.5
        cycleDepth = 0.03 + motion * 0.09
    }

    override func nextFrame() -> (Float, Float) {
        let breathing = 1 + cycle.next() * cycleDepth
        let nl = rngL.bipolar()
        let nr = rngR.bipolar()

        let airLeft = airLP_L.process(pinkL.process(nl)) * 1.3
        let airRight = airLP_R.process(pinkR.process(nr)) * 1.3
        let bodyLeft = harmonicL.process(humL.process(brownL.process(nl))) * humLevel * 1.6
        let bodyRight = harmonicR.process(humR.process(brownR.process(nr))) * humLevel * 1.6

        return ((airLeft + bodyLeft) * breathing, (airRight + bodyRight) * breathing)
    }
}

/// Washing machine, mid cycle. The drum turning is the whole sound.
final class WasherTexture: Texture {
    private var rngL = FastRandom(seed: 0x5701), rngR = FastRandom(seed: 0x5702)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var rumbleL = Biquad(), rumbleR = Biquad()
    private var sloshL = Biquad(), sloshR = Biquad()
    private var motorL = Biquad(), motorR = Biquad()
    private var drum = Phasor()
    private var motorLevel: Float = 0.4
    private var sloshDepth: Float = 0.4

    override func build() {
        drum.setFrequency(0.55, sampleRate: sampleRate)
    }

    override func configure() {
        rumbleL.setLowpass(320 + tone * 700, q: 0.7, sampleRate: sampleRate)
        rumbleR.setLowpass(330 + tone * 700, q: 0.7, sampleRate: sampleRate)
        sloshL.setBandpass(900, q: 0.8, sampleRate: sampleRate)
        sloshR.setBandpass(940, q: 0.8, sampleRate: sampleRate)
        motorL.setPeak(96, q: 5, gainDB: 4 + tone * 8, sampleRate: sampleRate)
        motorR.setPeak(98, q: 5, gainDB: 4 + tone * 8, sampleRate: sampleRate)
        motorLevel = 0.3 + tone * 0.5
        sloshDepth = 0.2 + motion * 0.6
        // Half a turn per second up to a little over one.
        drum.setFrequency(0.38 + motion * 0.55, sampleRate: sampleRate)
    }

    override func nextFrame() -> (Float, Float) {
        // Asymmetric: water piles up on one side of the drum and drops.
        let raw = 0.5 - 0.5 * cosf(2 * .pi * drum.nextPhase())
        let sloshEnvelope = raw * raw

        let nl = rngL.bipolar()
        let nr = rngR.bipolar()
        let bodyLeft = motorL.process(rumbleL.process(brownL.process(nl))) * 1.7 * motorLevel
        let bodyRight = motorR.process(rumbleR.process(brownR.process(nr))) * 1.7 * motorLevel
        let waterLeft = sloshL.process(pinkL.process(nl)) * sloshEnvelope * sloshDepth * 1.4
        let waterRight = sloshR.process(pinkR.process(nr)) * sloshEnvelope * sloshDepth * 1.4

        let swell = 0.82 + sloshEnvelope * 0.3
        return ((bodyLeft * swell) + waterLeft, (bodyRight * swell) + waterRight)
    }
}

/// Tumble dryer. A rotation, and something in the drum that falls once a turn.
final class DryerTexture: Texture {
    private var rngL = FastRandom(seed: 0x6D01), rngR = FastRandom(seed: 0x6D02)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var rumbleL = Biquad(), rumbleR = Biquad()
    private var heatL = Biquad(), heatR = Biquad()
    private var grains: GrainBank!
    private var thumpRNG = FastRandom(seed: 0x6D03)
    private var rotationSamples: Int = 48_000
    private var counter: Int = 0
    private var heatLevel: Float = 0.3
    private var thumpLevel: Float = 0.3

    override func build() {
        grains = GrainBank(capacity: 6, sampleRate: sampleRate, seed: 0x6D04)
    }

    override func configure() {
        rumbleL.setLowpass(280 + tone * 620, q: 0.7, sampleRate: sampleRate)
        rumbleR.setLowpass(288 + tone * 620, q: 0.7, sampleRate: sampleRate)
        heatL.setBandpass(2400, q: 0.5, sampleRate: sampleRate)
        heatR.setBandpass(2460, q: 0.5, sampleRate: sampleRate)
        heatLevel = 0.12 + tone * 0.34
        let perSecond = 0.6 + motion * 0.7
        rotationSamples = max(Int(sampleRate / perSecond), 8_000)
        thumpLevel = 0.10 + motion * 0.30
    }

    override func nextFrame() -> (Float, Float) {
        counter += 1
        if counter >= rotationSamples {
            counter = 0
            grains.trigger(
                frequency: 90 + thumpRNG.uniform() * 160,
                decaySeconds: 0.05 + thumpRNG.uniform() * 0.07,
                amplitude: thumpLevel * (0.6 + thumpRNG.uniform() * 0.7),
                noiseAmount: 0.72,
                pan: 0.3 + thumpRNG.uniform() * 0.4,
                resonance: 2.2,
                attackSeconds: 0.010
            )
        }

        let nl = rngL.bipolar()
        let nr = rngR.bipolar()
        var left = rumbleL.process(brownL.process(nl)) * 1.9
            + heatL.process(pinkL.process(nl)) * heatLevel
        var right = rumbleR.process(brownR.process(nr)) * 1.9
            + heatR.process(pinkR.process(nr)) * heatLevel

        let (gl, gr) = grains.nextFrame()
        left += gl
        right += gr
        return (left, right)
    }
}

/// Distant traffic, from a room above it. Cars pass; the road never stops.
final class HighwayTexture: Texture {
    private var rngL = FastRandom(seed: 0x4701), rngR = FastRandom(seed: 0x4702)
    private var passRNG = FastRandom(seed: 0x4703)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var roadL = Biquad(), roadR = Biquad()
    private var passL = Biquad(), passR = Biquad()
    private var passEnvelope = OnePole()

    private var passSamples: Int = 0
    private var passElapsed: Int = 0
    private var countdown: Int = 0
    private var passPan: Float = 0.5
    private var passLevel: Float = 0
    private var passCoefCounter: Int = 0
    private var passProgress: Float = 0

    override func build() {
        passEnvelope.setTimeConstant(seconds: 0.25, sampleRate: sampleRate)
        countdown = Int(sampleRate * 3)
    }

    override func configure() {
        roadL.setLowpass(380 + tone * 1400, q: 0.6, sampleRate: sampleRate)
        roadR.setLowpass(390 + tone * 1400, q: 0.6, sampleRate: sampleRate)
    }

    override func nextFrame() -> (Float, Float) {
        countdown -= 1
        if countdown <= 0 && passSamples == 0 {
            // A car every 2 to 20 seconds, depending on how busy the road is.
            let mean = 20 - motion * 17
            let gap = Int(sampleRate * mean * (0.4 + passRNG.uniform() * 1.4))
            countdown = max(gap, Int(sampleRate / 2))
            passSamples = Int(sampleRate * (1.6 + passRNG.uniform() * 2.6))
            passElapsed = 0
            passPan = passRNG.uniform() < 0.5 ? 0.15 : 0.85
            passLevel = 0.12 + passRNG.uniform() * 0.26
        }

        var passLeft: Float = 0
        var passRight: Float = 0
        if passSamples > 0 {
            passProgress = Float(passElapsed) / Float(passSamples)
            passElapsed += 1
            if passElapsed >= passSamples {
                passSamples = 0
                passElapsed = 0
            }

            passCoefCounter -= 1
            if passCoefCounter <= 0 {
                passCoefCounter = 64
                // Falls in pitch as it goes by, the way a real one does.
                let center = lerpf(900, 380, passProgress)
                passL.setBandpass(center, q: 1.1, sampleRate: sampleRate)
                passR.setBandpass(center * 1.05, q: 1.1, sampleRate: sampleRate)
            }

            let shape = sinf(.pi * clampf(passProgress, 0, 1))
            let envelope = passEnvelope.process(shape * passLevel)
            // Pans across as it passes.
            let pan = lerpf(passPan, 1 - passPan, passProgress)
            let nl = pinkL.process(rngL.bipolar())
            let value = passL.process(nl) * envelope * 2.2
            passLeft = value * (1 - pan)
            passRight = passR.process(nl) * envelope * 2.2 * pan
        } else {
            _ = passEnvelope.process(0)
        }

        let left = roadL.process(brownL.process(rngL.bipolar())) * 1.8 + passLeft
        let right = roadR.process(brownR.process(rngR.bipolar())) * 1.8 + passRight
        return (left, right)
    }
}

/// A busy room heard from a corner of it. Speech shaped, never words.
final class CafeTexture: Texture {
    private struct Speaker {
        var phase: Float = 0
        var rate: Float = 4
        var pan: Float = 0.5
        var level: Float = 0
        var target: Float = 0
        var countdown: Int = 0
        var band = Biquad()
        var center: Float = 900
    }

    private var speakers = [Speaker](repeating: Speaker(), count: 4)
    private var rng = FastRandom(seed: 0xCA01)
    private var noiseL = FastRandom(seed: 0xCA02), noiseR = FastRandom(seed: 0xCA03)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var roomL = Biquad(), roomR = Biquad()
    private var clinkRNG = FastRandom(seed: 0xCA04)
    private var grains: GrainBank!
    private var levelSmooth = [OnePole](repeating: OnePole(), count: 4)
    private var clinkProbability: Float = 0.00002
    private var coefCounter: Int = 0

    override func build() {
        grains = GrainBank(capacity: 8, sampleRate: sampleRate, seed: 0xCA05)
        for i in speakers.indices {
            speakers[i].rate = 3.0 + rng.uniform() * 2.6
            speakers[i].pan = rng.uniform()
            speakers[i].center = 500 + rng.uniform() * 1600
            speakers[i].countdown = Int(rng.uniform() * sampleRate * 3)
            levelSmooth[i].setTimeConstant(seconds: 0.25, sampleRate: sampleRate)
        }
        roomL.setLowpass(3200, q: 0.6, sampleRate: sampleRate)
        roomR.setLowpass(3260, q: 0.6, sampleRate: sampleRate)
    }

    override func configure() {
        clinkProbability = (0.05 + motion * 0.5) / sampleRate
        coefCounter = 0
    }

    override func nextFrame() -> (Float, Float) {
        var left: Float = 0
        var right: Float = 0

        let refresh = coefCounter <= 0
        if refresh { coefCounter = 64 }
        coefCounter -= 1

        for i in speakers.indices {
            // Talking comes in phrases with gaps, not a constant stream.
            speakers[i].countdown -= 1
            if speakers[i].countdown <= 0 {
                let talking = rng.uniform() < (0.4 + motion * 0.45)
                speakers[i].target = talking ? (0.25 + rng.uniform() * 0.6) : 0
                speakers[i].countdown = Int(sampleRate * (0.5 + rng.uniform() * 2.4))
                if talking {
                    speakers[i].center = 420 + rng.uniform() * (900 + tone * 1800)
                    speakers[i].rate = 3.0 + rng.uniform() * 2.8
                }
            }
            if refresh {
                speakers[i].band.setBandpass(speakers[i].center, q: 1.6, sampleRate: sampleRate)
            }

            speakers[i].level = levelSmooth[i].process(speakers[i].target)
            guard speakers[i].level > 0.002 else { continue }

            // Syllable rate amplitude modulation is what reads as speech.
            speakers[i].phase += speakers[i].rate / sampleRate
            if speakers[i].phase >= 1 { speakers[i].phase -= 1 }
            let syllable = 0.35 + 0.65 * (0.5 - 0.5 * cosf(2 * .pi * speakers[i].phase))

            let source = pinkL.process(noiseL.bipolar())
            let value = speakers[i].band.process(source) * speakers[i].level * syllable * 1.5
            left += value * (1 - speakers[i].pan)
            right += value * speakers[i].pan
        }

        if clinkRNG.uniform() < clinkProbability {
            grains.trigger(
                frequency: 1800 + clinkRNG.uniform() * 2200,
                decaySeconds: 0.06 + clinkRNG.uniform() * 0.14,
                amplitude: 0.028 + clinkRNG.uniform() * 0.045,
                noiseAmount: 0.25,
                pan: clinkRNG.uniform(),
                resonance: 14 + clinkRNG.uniform() * 18,
                attackSeconds: 0.006
            )
        }
        let (gl, gr) = grains.nextFrame()

        left = roomL.process(left) + gl
        right = roomR.process(right) + gr
        left += pinkL.process(noiseL.bipolar()) * 0.05
        right += pinkR.process(noiseR.bipolar()) * 0.05
        return (left, right)
    }
}

/// A clock in the hall. Tick and tock are not the same sound.
final class ClockTexture: Texture {
    private var grains: GrainBank!
    private var rng = FastRandom(seed: 0xC101)
    private var roomL = FastRandom(seed: 0xC102), roomR = FastRandom(seed: 0xC103)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var roomLP_L = Biquad(), roomLP_R = Biquad()
    private var periodSamples: Int = 48_000
    private var counter: Int = 0
    private var isTick = true
    private var woodFrequency: Float = 1800

    override func build() {
        grains = GrainBank(capacity: 6, sampleRate: sampleRate, seed: 0xC104)
        roomLP_L.setLowpass(320, q: 0.6, sampleRate: sampleRate)
        roomLP_R.setLowpass(330, q: 0.6, sampleRate: sampleRate)
    }

    override func configure() {
        // A pendulum second, give or take.
        let perSecond = 0.7 + motion * 0.7
        periodSamples = max(Int(sampleRate / perSecond), 6_000)
        woodFrequency = 1100 + tone * 2400
    }

    override func nextFrame() -> (Float, Float) {
        counter += 1
        if counter >= periodSamples {
            counter = 0
            // The escapement is asymmetric: tock sits lower than tick.
            let frequency = isTick ? woodFrequency : woodFrequency * 0.76
            grains.trigger(
                frequency: frequency,
                decaySeconds: 0.010 + rng.uniform() * 0.010,
                amplitude: (isTick ? 0.19 : 0.16) * (0.9 + rng.uniform() * 0.2),
                noiseAmount: 0.55,
                pan: 0.5,
                resonance: 9,
                attackSeconds: 0.0016
            )
            // A little body under the click, so it sounds like wood.
            grains.trigger(
                frequency: frequency * 0.31,
                decaySeconds: 0.030,
                amplitude: isTick ? 0.075 : 0.062,
                noiseAmount: 0.3,
                pan: 0.5,
                resonance: 4,
                attackSeconds: 0.003
            )
            isTick.toggle()
        }

        let (gl, gr) = grains.nextFrame()
        let left = roomLP_L.process(brownL.process(roomL.bipolar())) * 0.5
        let right = roomLP_R.process(brownR.process(roomR.bipolar())) * 0.5
        return (left + gl, right + gr)
    }
}

/// Wind chimes. The wind decides when, the tuning decides what.
final class ChimeTexture: Texture {
    /// Major pentatonic. Any two of these sound fine together, which is the
    /// whole point: the wind is not going to pick tastefully.
    private static let ratios: [Float] = [1.0, 9.0 / 8.0, 5.0 / 4.0, 3.0 / 2.0, 5.0 / 3.0, 2.0]

    private var grains: GrainBank!
    private var rng = FastRandom(seed: 0xCE01)
    private var windL = FastRandom(seed: 0xCE02), windR = FastRandom(seed: 0xCE03)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var windLP_L = Biquad(), windLP_R = Biquad()
    private var gust = SlowDrift(seed: 0xCE04)
    private var baseFrequency: Float = 523
    private var strikeProbability: Float = 0.0001
    private var cooldown: Int = 0

    override func build() {
        // Long decays need somewhere to live: eight bars ringing at once.
        grains = GrainBank(capacity: 14, sampleRate: sampleRate, seed: 0xCE05)
        gust.prepare(rate: 0.10, sampleRate: sampleRate)
        windLP_L.setLowpass(1100, q: 0.6, sampleRate: sampleRate)
        windLP_R.setLowpass(1130, q: 0.6, sampleRate: sampleRate)
    }

    override func configure() {
        baseFrequency = 392 + tone * 480
        strikeProbability = (0.25 + motion * 2.6) / sampleRate
    }

    override func nextFrame() -> (Float, Float) {
        let breeze = gust.next()
        // Chimes ring when the wind picks up, not on a timer.
        let excitement = clampf(0.35 + breeze * 0.9, 0, 1.6)

        if cooldown > 0 { cooldown -= 1 }
        if cooldown == 0 && rng.uniform() < strikeProbability * excitement {
            let ratio = ChimeTexture.ratios[Int(rng.uniform() * Float(ChimeTexture.ratios.count)) % ChimeTexture.ratios.count]
            let frequency = baseFrequency * ratio
            let amplitude = 0.06 + rng.uniform() * 0.13
            let pan = 0.2 + rng.uniform() * 0.6
            let decay = 2.2 + rng.uniform() * 3.4

            // A tube has a strong second partial, and two bars never ring at
            // exactly the same pitch, which is where the shimmer comes from.
            grains.trigger(frequency: frequency, decaySeconds: decay,
                           amplitude: amplitude, noiseAmount: 0, pan: pan,
                           attackSeconds: 0.025)
            grains.trigger(frequency: frequency * 2.76, decaySeconds: decay * 0.45,
                           amplitude: amplitude * 0.28, noiseAmount: 0, pan: pan,
                           attackSeconds: 0.030)
            grains.trigger(frequency: frequency * 1.004, decaySeconds: decay * 0.9,
                           amplitude: amplitude * 0.5, noiseAmount: 0, pan: 1 - pan,
                           attackSeconds: 0.028)

            cooldown = Int(sampleRate * (0.10 + rng.uniform() * 0.35))
        }

        let (gl, gr) = grains.nextFrame()
        let windLeft = windLP_L.process(pinkL.process(windL.bipolar())) * 0.22 * (0.6 + excitement * 0.5)
        let windRight = windLP_R.process(pinkR.process(windR.bipolar())) * 0.22 * (0.6 + excitement * 0.5)
        return (gl * 0.85 + windLeft, gr * 0.85 + windRight)
    }
}

/// Singing bowl. Sustained, inharmonic, and always slightly out of tune with
/// itself, which is what produces the beating.
final class BowlTexture: Texture {
    private struct Partial {
        var a = Phasor()
        var b = Phasor()
        var level: Float = 0
    }

    /// Real bowls are not harmonic. These ratios are why it sounds like metal
    /// rather than an organ.
    private static let ratios: [Float] = [1.0, 2.74, 5.42]
    private static let levels: [Float] = [1.0, 0.34, 0.12]

    private var partials = [Partial](repeating: Partial(), count: 3)
    private var rng = FastRandom(seed: 0xB001)
    private var amplitude: Float = 0
    private var peak: Float = 0
    private var attackRemaining: Int = 0
    private var attackStep: Float = 0
    private var decayPerSample: Float = 0.99999
    private var countdown: Int = 0
    private var airL = FastRandom(seed: 0xB002), airR = FastRandom(seed: 0xB003)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var airHP_L = Biquad(), airHP_R = Biquad()
    private var baseFrequency: Float = 210
    private var beatSpread: Float = 0.004

    override func build() {
        airHP_L.setHighpass(3000, q: 0.7, sampleRate: sampleRate)
        airHP_R.setHighpass(3060, q: 0.7, sampleRate: sampleRate)
        countdown = 1
    }

    override func configure() {
        baseFrequency = 150 + tone * 240
        beatSpread = 0.0012 + motion * 0.010
        retune()
    }

    private func retune() {
        for i in partials.indices {
            let frequency = baseFrequency * BowlTexture.ratios[i]
            partials[i].a.setFrequency(frequency, sampleRate: sampleRate)
            // The detuned twin is what beats against the first.
            partials[i].b.setFrequency(frequency * (1 + beatSpread), sampleRate: sampleRate)
            partials[i].level = BowlTexture.levels[i]
        }
    }

    override func nextFrame() -> (Float, Float) {
        countdown -= 1
        if countdown <= 0 {
            // Struck again every 20 to 50 seconds, before it fully dies.
            countdown = Int(sampleRate * (20 + rng.uniform() * 30))
            peak = 0.26 + rng.uniform() * 0.12
            // A quarter second of rise. A struck bowl blooms; it does not bang.
            attackRemaining = Int(sampleRate * 0.25)
            attackStep = peak / Float(max(attackRemaining, 1))
            let decaySeconds: Float = 14 + rng.uniform() * 10
            decayPerSample = expf(-1 / (decaySeconds * sampleRate))
            var generator = rng
            for i in partials.indices {
                partials[i].a.randomizePhase(&generator)
                partials[i].b.randomizePhase(&generator)
            }
            rng = generator
        }

        if attackRemaining > 0 {
            amplitude += attackStep
            attackRemaining -= 1
        } else {
            amplitude *= decayPerSample
        }

        var value: Float = 0
        for i in partials.indices {
            let pair = partials[i].a.nextSine() + partials[i].b.nextSine() * 0.85
            value += pair * partials[i].level
        }
        value *= amplitude * 0.30

        // A breath of air keeps the tail from sounding synthetic.
        let left = value + airHP_L.process(pinkL.process(airL.bipolar())) * 0.035
        let right = value * 0.97 + airHP_R.process(pinkR.process(airR.bipolar())) * 0.035
        return (left, right)
    }
}

/// Oscillating fan.
///
/// The panning is the obvious part and the least convincing on its own. What
/// sells it is that the treble falls away as the head turns: a fan pointed at
/// the far wall is not just quieter, it is duller. Sweeping a lowpass in step
/// with the pan is the whole trick.
final class OscillatingFanTexture: Texture {
    private var rngL = FastRandom(seed: 0x0F01), rngR = FastRandom(seed: 0x0F02)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var toneL = Biquad(), toneR = Biquad()
    private var motorL = Biquad(), motorR = Biquad()
    private var blade = Phasor()
    private var sweep = Phasor()
    private var coefCounter: Int = 0
    private var brightness: Float = 2400
    private var motorLevel: Float = 0.4
    private var bladeDepth: Float = 0.07

    override func build() {
        blade.setFrequency(23, sampleRate: sampleRate)
        sweep.setFrequency(0.14, sampleRate: sampleRate)
        motorL.setPeak(112, q: 5, gainDB: 5, sampleRate: sampleRate)
        motorR.setPeak(114, q: 5, gainDB: 5, sampleRate: sampleRate)
    }

    override func configure() {
        brightness = 1500 + tone * 3600
        motorLevel = 0.28 + tone * 0.45
        bladeDepth = 0.03 + tone * 0.10
        // A full sweep every 5 to 14 seconds.
        sweep.setFrequency(1 / (5 + (1 - motion) * 9), sampleRate: sampleRate)
    }

    override func nextFrame() -> (Float, Float) {
        // -1 facing left, +1 facing right, 0 facing you.
        let facing = sinf(2 * .pi * sweep.nextPhase())
        let towards = 1 - abs(facing)

        coefCounter -= 1
        if coefCounter <= 0 {
            coefCounter = 64
            // Pointed away, the top end goes with it.
            let cutoff = brightness * (0.42 + towards * 0.58)
            toneL.setLowpass(cutoff, q: 0.6, sampleRate: sampleRate)
            toneR.setLowpass(cutoff * 1.04, q: 0.6, sampleRate: sampleRate)
        }

        let nl = rngL.bipolar()
        let nr = rngR.bipolar()
        let coreL = brownL.process(nl) * 0.8 + pinkL.process(nl) * 0.5
        let coreR = brownR.process(nr) * 0.8 + pinkR.process(nr) * 0.5

        var left = motorL.process(toneL.process(coreL)) * 1.6 * motorLevel
        var right = motorR.process(toneR.process(coreR)) * 1.6 * motorLevel

        let chop = 1 + blade.nextSine() * bladeDepth
        left *= chop
        right *= chop

        // Level and balance move together, gently.
        let swell = 0.72 + towards * 0.34
        left *= swell * (1 - facing * 0.28)
        right *= swell * (1 + facing * 0.28)
        return (left, right)
    }
}
