import Foundation

/// The sound of the breath itself, for guided sessions.
///
/// Filtered pink noise whose level follows how much air is moving and whose
/// colour follows the direction: an inhale is bright and rising, an exhale is
/// darker and falling. It sits under whatever mix is playing, or alone.
///
/// `targetFlow` and `targetOpenness` are written from the main thread by the
/// session ticker and smoothed here at control rate, the same contract as
/// every other texture.
final class BreathGuideTexture: Texture {
    /// 0 still ... 1 full flow.
    var targetFlow: Float = 0
    /// 0 dark (exhale) ... 1 bright (inhale).
    var targetOpenness: Float = 0.5

    private var flowSmoother = OnePole()
    private var openSmoother = OnePole()
    private var flow: Float = 0
    private var openness: Float = 0.5

    private var rngL = FastRandom(seed: 0xB4EA_0001)
    private var rngR = FastRandom(seed: 0xB4EA_0002)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var bodyL = Biquad(), bodyR = Biquad()
    private var airL = Biquad(), airR = Biquad()
    private var level: Float = 0
    private var airLevel: Float = 0

    override func build() {
        let controlRate = sampleRate / 64
        flowSmoother.setTimeConstant(seconds: 0.30, sampleRate: controlRate)
        openSmoother.setTimeConstant(seconds: 0.45, sampleRate: controlRate)
        flowSmoother.reset(to: 0)
        openSmoother.reset(to: 0.5)
    }

    override func configure() {
        flow = flowSmoother.process(targetFlow)
        openness = openSmoother.process(targetOpenness)
        let center = 320 + openness * 1500
        bodyL.setBandpass(center, q: 0.55, sampleRate: sampleRate)
        bodyR.setBandpass(center * 1.05, q: 0.55, sampleRate: sampleRate)
        airL.setHighpass(2400 + openness * 2200, q: 0.7, sampleRate: sampleRate)
        airR.setHighpass(2450 + openness * 2200, q: 0.7, sampleRate: sampleRate)
        level = flow * flow * 1.6
        airLevel = flow * (0.08 + openness * 0.28)
    }

    override func nextFrame() -> (Float, Float) {
        guard level > 0.0005 else { return (0, 0) }
        let nl = pinkL.process(rngL.bipolar())
        let nr = pinkR.process(rngR.bipolar())
        let left = bodyL.process(nl) * level + airL.process(nl) * airLevel
        let right = bodyR.process(nr) * level + airR.process(nr) * airLevel
        return (left, right)
    }
}
