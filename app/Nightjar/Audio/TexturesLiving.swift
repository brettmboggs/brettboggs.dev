import Foundation

// Things with a pulse. The shared trick is that living sound is never
// metronomic: every interval, pitch and amplitude here carries jitter, because
// perfect regularity is the single fastest way to sound synthetic.

/// Womb. A slow double thump under a wash of blood flow.
///
/// The most requested sleep sound that is not noise, and the one people put
/// infants to sleep with, so it is worth getting exactly right: the second
/// beat lands at 30% of the cycle, not 50%, and it is quieter than the first.
final class HeartbeatTexture: Texture {
    private var rng = FastRandom(seed: 0x4B_EA_70)
    private var noiseL = FastRandom(seed: 0x4B01), noiseR = FastRandom(seed: 0x4B02)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var flowL = Biquad(), flowR = Biquad()
    private var flowDrift = SlowDrift(seed: 0x4B03)
    private var grains: GrainBank!

    private var periodSamples: Int = 48_000
    private var counter: Int = 0
    private var didSecondBeat = false
    private var secondBeatAt: Int = 0
    private var thumpFrequency: Float = 54

    override func build() {
        grains = GrainBank(capacity: 8, sampleRate: sampleRate, seed: 0x4B04)
        flowDrift.prepare(rate: 0.13, sampleRate: sampleRate)
        counter = 0
    }

    override func configure() {
        // 48 to 78 bpm. Slower reads as deeper rest.
        let bpm = 48 + motion * 30
        periodSamples = max(Int(sampleRate * 60 / bpm), 1_000)
        secondBeatAt = Int(Float(periodSamples) * 0.30)

        let cutoff = 130 + tone * 320
        flowL.setLowpass(cutoff, q: 0.7, sampleRate: sampleRate)
        flowR.setLowpass(cutoff * 1.05, q: 0.7, sampleRate: sampleRate)
        thumpFrequency = 44 + tone * 26
    }

    private func thump(strong: Bool) {
        grains.trigger(
            frequency: thumpFrequency * (strong ? 1 : 1.18),
            decaySeconds: strong ? 0.075 : 0.055,
            amplitude: (strong ? 0.62 : 0.34) * (0.9 + rng.uniform() * 0.2),
            noiseAmount: 0.42,
            pan: 0.5,
            resonance: 1.6,
            attackSeconds: strong ? 0.014 : 0.011
        )
    }

    override func nextFrame() -> (Float, Float) {
        counter += 1
        if counter >= periodSamples {
            counter = 0
            didSecondBeat = false
            thump(strong: true)
        } else if !didSecondBeat && counter >= secondBeatAt {
            didSecondBeat = true
            thump(strong: false)
        }

        let surge = 1 + flowDrift.next() * 0.22
        let left = flowL.process(brownL.process(noiseL.bipolar())) * 1.5 * surge
        let right = flowR.process(brownR.process(noiseR.bipolar())) * 1.5 * surge

        let (gl, gr) = grains.nextFrame()
        return (left + gl, right + gr)
    }
}

/// A cat, asleep on your chest.
///
/// Purring is roughly 25 Hz amplitude modulation of a low rumble, and it is
/// not a sine: the rise is faster than the fall. It also stops for breath.
final class PurrTexture: Texture {
    private var rngL = FastRandom(seed: 0x9011)
    private var rngR = FastRandom(seed: 0x9012)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var bandL = Biquad(), bandR = Biquad()
    private var breath = SlowDrift(seed: 0x9013)
    private var phase: Float = 0
    private var rate: Float = 25
    private var depth: Float = 0.7

    override func build() {
        breath.prepare(rate: 0.22, sampleRate: sampleRate)
    }

    override func configure() {
        // A bigger cat purrs lower and slower.
        let center = 70 + tone * 190
        bandL.setBandpass(center, q: 0.9, sampleRate: sampleRate)
        bandR.setBandpass(center * 1.06, q: 0.9, sampleRate: sampleRate)
        rate = 21 + tone * 9
        depth = 0.35 + motion * 0.55
    }

    override func nextFrame() -> (Float, Float) {
        phase += rate / sampleRate
        if phase >= 1 { phase -= 1 }

        // Sharper attack than a sine: squaring the falling half steepens it.
        let raw = 0.5 - 0.5 * cosf(2 * .pi * phase)
        let shaped = raw * raw * (3 - 2 * raw)
        let modulation = 1 - depth + depth * shaped

        // Purring pauses to breathe.
        let breathing = 0.72 + 0.38 * (0.5 + 0.5 * breath.next())

        let left = bandL.process(brownL.process(rngL.bipolar())) * 2.4
        let right = bandR.process(brownR.process(rngR.bipolar())) * 2.4
        let gain = modulation * breathing
        return (left * gain, right * gain)
    }
}

/// A pond after dark. Several frogs, none of them in time with each other.
final class FrogTexture: Texture {
    private struct Frog {
        var countdown: Int = 0
        var pulsesLeft: Int = 0
        var pulseSamples: Int = 0
        var gapSamples: Int = 0
        var inPulse: Bool = false
        var phase: Float = 0
        var frequency: Float = 320
        var pan: Float = 0.5
        var amp: Float = 0.3
    }

    private var frogs = [Frog](repeating: Frog(), count: 6)
    private var envelopes = [OnePole](repeating: OnePole(), count: 6)
    private var rng = FastRandom(seed: 0xF206)
    private var bedL = FastRandom(seed: 0xF207), bedR = FastRandom(seed: 0xF208)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var bedLP_L = Biquad(), bedLP_R = Biquad()
    private var formantL = Biquad(), formantR = Biquad()
    private var activeCount: Int = 4
    private var baseFrequency: Float = 320

    override func build() {
        for i in frogs.indices {
            frogs[i].countdown = Int(rng.uniform() * sampleRate * 4)
            envelopes[i].setTimeConstant(seconds: 0.008, sampleRate: sampleRate)
        }
        bedLP_L.setLowpass(700, q: 0.6, sampleRate: sampleRate)
        bedLP_R.setLowpass(720, q: 0.6, sampleRate: sampleRate)
    }

    override func configure() {
        baseFrequency = 190 + tone * 420
        activeCount = 2 + Int(motion * 4)
        // A throaty resonance is what separates a croak from a beep.
        formantL.setBandpass(baseFrequency * 2.6, q: 2.2, sampleRate: sampleRate)
        formantR.setBandpass(baseFrequency * 2.66, q: 2.2, sampleRate: sampleRate)
    }

    override func nextFrame() -> (Float, Float) {
        var left: Float = 0
        var right: Float = 0

        for i in 0..<min(activeCount, frogs.count) {
            if frogs[i].pulsesLeft <= 0 {
                frogs[i].countdown -= 1
                if frogs[i].countdown <= 0 {
                    frogs[i].pulsesLeft = 1 + Int(rng.uniform() * 5)
                    frogs[i].pulseSamples = Int(sampleRate * (0.045 + rng.uniform() * 0.075))
                    frogs[i].gapSamples = Int(sampleRate * (0.050 + rng.uniform() * 0.090))
                    frogs[i].frequency = baseFrequency * (0.78 + rng.uniform() * 0.5)
                    frogs[i].pan = rng.uniform()
                    frogs[i].amp = 0.10 + rng.uniform() * 0.20
                    frogs[i].inPulse = true
                    frogs[i].countdown = frogs[i].pulseSamples
                }
            }

            var target: Float = 0
            if frogs[i].pulsesLeft > 0 {
                frogs[i].countdown -= 1
                if frogs[i].inPulse {
                    target = 1
                    if frogs[i].countdown <= 0 {
                        frogs[i].inPulse = false
                        frogs[i].countdown = frogs[i].gapSamples
                        frogs[i].pulsesLeft -= 1
                        if frogs[i].pulsesLeft <= 0 {
                            frogs[i].countdown = Int(sampleRate * (1.2 + rng.uniform() * 5.5))
                        }
                    }
                } else if frogs[i].countdown <= 0 {
                    frogs[i].inPulse = true
                    frogs[i].countdown = frogs[i].pulseSamples
                }
            }

            let env = envelopes[i].process(target)
            if env > 0.001 {
                frogs[i].phase += frogs[i].frequency / sampleRate
                if frogs[i].phase >= 1 { frogs[i].phase -= 1 }
                let p = frogs[i].phase
                // A rasping waveform, not a clean tone.
                let value = (sinf(2 * .pi * p) + 0.5 * sinf(4 * .pi * p) + 0.22 * sinf(6 * .pi * p))
                    * env * frogs[i].amp
                left += value * (1 - frogs[i].pan)
                right += value * frogs[i].pan
            }
        }

        left = left * 0.6 + formantL.process(left) * 0.7
        right = right * 0.6 + formantR.process(right) * 0.7

        let bl = bedLP_L.process(pinkL.process(bedL.bipolar())) * 0.13
        let br = bedLP_R.process(pinkR.process(bedR.bipolar())) * 0.13
        return (left + bl, right + br)
    }
}

/// Dawn chorus. Short pitch sweeps, sparse and irregular.
///
/// Built to be the default wake sound: it is the one texture here designed to
/// bring you up rather than take you down.
final class BirdTexture: Texture {
    private struct Bird {
        var countdown: Int = 0
        var notesLeft: Int = 0
        var noteSamples: Int = 0
        var elapsed: Int = 0
        var startFrequency: Float = 3000
        var endFrequency: Float = 3600
        var phase: Float = 0
        var pan: Float = 0.5
        var amp: Float = 0.2
        var singing: Bool = false
    }

    private var birds = [Bird](repeating: Bird(), count: 6)
    private var rng = FastRandom(seed: 0xB1D5)
    private var airL = FastRandom(seed: 0xB1D6), airR = FastRandom(seed: 0xB1D7)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var airLP_L = Biquad(), airLP_R = Biquad()
    private var activeCount: Int = 4
    private var baseFrequency: Float = 3200

    override func build() {
        for i in birds.indices {
            birds[i].countdown = Int(rng.uniform() * sampleRate * 5)
        }
        airLP_L.setLowpass(1400, q: 0.6, sampleRate: sampleRate)
        airLP_R.setLowpass(1430, q: 0.6, sampleRate: sampleRate)
    }

    override func configure() {
        baseFrequency = 2200 + tone * 2600
        activeCount = 2 + Int(motion * 4)
    }

    override func nextFrame() -> (Float, Float) {
        var left: Float = 0
        var right: Float = 0

        for i in 0..<min(activeCount, birds.count) {
            if !birds[i].singing {
                birds[i].countdown -= 1
                if birds[i].countdown <= 0 {
                    birds[i].singing = true
                    birds[i].notesLeft = 1 + Int(rng.uniform() * 4)
                    birds[i].pan = rng.uniform()
                    birds[i].amp = 0.06 + rng.uniform() * 0.13
                    var bird = birds[i]
                    startNote(&bird)
                    birds[i] = bird
                }
                continue
            }

            let progress = Float(birds[i].elapsed) / Float(max(birds[i].noteSamples, 1))
            birds[i].elapsed += 1

            if progress >= 1 {
                birds[i].notesLeft -= 1
                if birds[i].notesLeft > 0 {
                    var bird = birds[i]
                    startNote(&bird)
                    birds[i] = bird
                } else {
                    birds[i].singing = false
                    birds[i].countdown = Int(sampleRate * (0.9 + rng.uniform() * 5.0))
                }
                continue
            }

            // Raised-cosine envelope, so a note never clicks at either end.
            let envelope = 0.5 - 0.5 * cosf(2 * .pi * progress)
            let frequency = lerpf(birds[i].startFrequency, birds[i].endFrequency, progress)
            birds[i].phase += frequency / sampleRate
            if birds[i].phase >= 1 { birds[i].phase -= 1 }

            let p = birds[i].phase
            let value = (sinf(2 * .pi * p) + 0.28 * sinf(4 * .pi * p))
                * envelope * birds[i].amp
            left += value * (1 - birds[i].pan)
            right += value * birds[i].pan
        }

        let al = airLP_L.process(pinkL.process(airL.bipolar())) * 0.10
        let ar = airLP_R.process(pinkR.process(airR.bipolar())) * 0.10
        return (left + al, right + ar)
    }

    private func startNote(_ bird: inout Bird) {
        bird.elapsed = 0
        bird.noteSamples = Int(sampleRate * (0.045 + rng.uniform() * 0.11))
        let start = baseFrequency * (0.8 + rng.uniform() * 0.55)
        // Most calls sweep up; some fall.
        let rising = rng.uniform() < 0.68
        let span = 1 + rng.uniform() * 0.55
        bird.startFrequency = start
        bird.endFrequency = rising ? start * span : start / span
    }
}
