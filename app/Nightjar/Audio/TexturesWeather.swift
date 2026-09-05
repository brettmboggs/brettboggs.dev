import Foundation

/// Heavy falling water. Broad, low-weighted, with a spray band on top.
final class WaterfallTexture: Texture {
    private var rngL = FastRandom(seed: 0xA401)
    private var rngR = FastRandom(seed: 0xA402)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var bodyL = Biquad(), bodyR = Biquad()
    private var sprayL = Biquad(), sprayR = Biquad()
    private var surge = SlowDrift(seed: 0xA403)
    private var sprayLevel: Float = 0.3
    private var surgeDepth: Float = 0.1

    override func build() {
        surge.prepare(rate: 0.07, sampleRate: sampleRate)
    }

    override func configure() {
        bodyL.setLowpass(900 + tone * 2600, q: 0.6, sampleRate: sampleRate)
        bodyR.setLowpass(920 + tone * 2600, q: 0.6, sampleRate: sampleRate)
        sprayL.setHighpass(2600 + tone * 3200, q: 0.7, sampleRate: sampleRate)
        sprayR.setHighpass(2650 + tone * 3200, q: 0.7, sampleRate: sampleRate)
        sprayLevel = 0.12 + tone * 0.42
        surgeDepth = 0.04 + motion * 0.16
    }

    override func nextFrame() -> (Float, Float) {
        let swell = 1 + surge.next() * surgeDepth
        let nl = rngL.bipolar()
        let nr = rngR.bipolar()

        // Brown for weight, pink for the sheet of water over it.
        let coreL = brownL.process(nl) * 0.85 + pinkL.process(nl) * 0.9
        let coreR = brownR.process(nr) * 0.85 + pinkR.process(nr) * 0.9

        let left = bodyL.process(coreL) * 1.5 * swell
            + sprayL.process(pinkL.process(nl)) * sprayLevel
        let right = bodyR.process(coreR) * 1.5 * swell
            + sprayR.process(pinkR.process(nr)) * sprayLevel
        return (left, right)
    }
}

/// Snowstorm. Wind with the whistle taken out and a dense hiss put in: snow
/// absorbs the high end, which is why a blizzard sounds muffled rather than sharp.
final class BlizzardTexture: Texture {
    private var rngL = FastRandom(seed: 0xB201), rngR = FastRandom(seed: 0xB202)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var bandL = Biquad(), bandR = Biquad()
    private var hissL = Biquad(), hissR = Biquad()
    private var centerDrift = SlowDrift(seed: 0xB203)
    private var gustDrift = SlowDrift(seed: 0xB204)
    private var coefCounter: Int = 0
    private var centerBase: Float = 320
    private var centerRange: Float = 200
    private var hissLevel: Float = 0.4
    private var gustDepth: Float = 0.5

    override func build() {
        centerDrift.prepare(rate: 0.12, sampleRate: sampleRate)
        gustDrift.prepare(rate: 0.06, sampleRate: sampleRate)
    }

    override func configure() {
        centerBase = 220 + tone * 520
        centerRange = 120 + tone * 300
        hissLevel = 0.26 + tone * 0.34
        gustDepth = 0.22 + motion * 0.62
        hissL.setBandpass(1600, q: 0.5, sampleRate: sampleRate)
        hissR.setBandpass(1660, q: 0.5, sampleRate: sampleRate)
    }

    override func nextFrame() -> (Float, Float) {
        let wander = centerDrift.next()
        coefCounter -= 1
        if coefCounter <= 0 {
            coefCounter = 32
            let center = clampf(centerBase + wander * centerRange, 60, sampleRate * 0.4)
            bandL.setBandpass(center, q: 0.9, sampleRate: sampleRate)
            bandR.setBandpass(center * 1.05, q: 0.9, sampleRate: sampleRate)
        }

        let nl = pinkL.process(rngL.bipolar())
        let nr = pinkR.process(rngR.bipolar())
        var left = bandL.process(nl) * 2.0 + hissL.process(nl) * hissLevel * 1.8
        var right = bandR.process(nr) * 2.0 + hissR.process(nr) * hissLevel * 1.8

        let gust = clampf(1 + gustDrift.next() * gustDepth, 0.2, 2.0) * 0.6
        left *= gust
        right *= gust
        return (left, right)
    }
}

/// Weather a long way off. No rain, just the roll.
final class DistantThunderTexture: Texture {
    private var rng = FastRandom(seed: 0xD701)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var noiseL = FastRandom(seed: 0xD702), noiseR = FastRandom(seed: 0xD703)
    private var airL = FastRandom(seed: 0xD704), airR = FastRandom(seed: 0xD705)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var airLP_L = Biquad(), airLP_R = Biquad()
    private var rumbleL = Biquad(), rumbleR = Biquad()
    private var attack = OnePole()
    private var body = OnePole()
    private var roll = SlowDrift(seed: 0xD706)

    private var gateSamples: Int = 0
    private var countdown: Int = 0
    private var strikeLevel: Float = 0
    private var strikePan: Float = 0.5

    override func build() {
        // Slower than a close strike: distance smears the attack.
        attack.setTimeConstant(seconds: 0.55, sampleRate: sampleRate)
        body.setTimeConstant(seconds: 1.1, sampleRate: sampleRate)
        roll.prepare(rate: 1.1, sampleRate: sampleRate)
        airLP_L.setLowpass(600, q: 0.6, sampleRate: sampleRate)
        airLP_R.setLowpass(620, q: 0.6, sampleRate: sampleRate)
        countdown = Int(sampleRate * 5)
    }

    override func configure() {
        // Further away is duller and quieter.
        let cutoff = 55 + (1 - tone) * 340
        rumbleL.setLowpass(cutoff, q: 0.7, sampleRate: sampleRate)
        rumbleR.setLowpass(cutoff * 1.06, q: 0.7, sampleRate: sampleRate)
    }

    override func nextFrame() -> (Float, Float) {
        countdown -= 1
        if countdown <= 0 {
            let mean = 75 - motion * 60
            let jitter = 0.4 + rng.uniform() * 1.5
            countdown = max(Int(sampleRate * mean * jitter), Int(sampleRate * 6))
            gateSamples = Int(sampleRate * (0.6 + rng.uniform() * 2.2))
            // Capped: a roll that swells to a predictable ceiling reads as
            // weather. One that occasionally lands twice as loud reads as a
            // noise in the house.
            strikeLevel = 0.28 + rng.uniform() * 0.30
            strikePan = 0.3 + rng.uniform() * 0.4
        }

        var gate: Float = 0
        if gateSamples > 0 {
            gateSamples -= 1
            gate = strikeLevel
        }
        let envelope = body.process(attack.process(gate))
        let rolling = envelope * (1 + roll.next() * 0.5)

        var left: Float = 0
        var right: Float = 0
        if rolling > 0.0008 {
            left = rumbleL.process(brownL.process(noiseL.bipolar())) * rolling * (1 - strikePan) * 2.6
            right = rumbleR.process(brownR.process(noiseR.bipolar())) * rolling * strikePan * 2.6
        }

        left += airLP_L.process(pinkL.process(airL.bipolar())) * 0.09
        right += airLP_R.process(pinkR.process(airR.bipolar())) * 0.09
        return (left, right)
    }
}
