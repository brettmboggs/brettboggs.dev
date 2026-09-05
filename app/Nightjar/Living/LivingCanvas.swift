import SwiftUI

/// The orb, drawn full-bleed behind a screen.
///
/// `breath` is a function of time rather than a stored value so that a
/// breathing session can drive it at frame rate without writing to observable
/// state sixty times a second. Idle screens use `idleBreath`, six slow breaths
/// a minute, which is roughly where a resting person ends up.
struct LivingCanvas: View, Animatable {
    /// Audio meter, 0...1. Swells the body a little.
    var energy: Double = 0
    /// Overall brightness of the body. Falls in bedside mode.
    var intensity: Double = 1
    /// Edge glow. Faint on most screens, strong while breathing.
    var rim: Double = 0.18
    /// Where the body sits, as a fraction of the height.
    var centerY: Double = 0.42
    /// Frames per second. Lower while dimmed to save the battery.
    var frameRate: Double = 30
    var breath: (Date) -> Double = LivingCanvas.idleBreath

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lets `.animation(value:)` glide the orb between screens instead of
    /// cutting.
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(intensity, AnimatablePair(rim, centerY)) }
        set {
            intensity = newValue.first
            rim = newValue.second.first
            centerY = newValue.second.second
        }
    }

    /// Six breaths a minute, eased.
    static func idleBreath(_ date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let raw = 0.5 + 0.5 * sin(t * 2 * .pi / 10)
        return raw * raw * (3 - 2 * raw)
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / max(frameRate, 1))) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let drift = reduceMotion ? 120.0 : seconds.truncatingRemainder(dividingBy: 3600)
                let fullness = breath(timeline.date)
                Rectangle()
                    .fill(Palette.ground)
                    .colorEffect(
                        ShaderLibrary.nightjarOrb(
                            .float2(geo.size),
                            .float(Float(drift)),
                            .float(Float(fullness)),
                            .float(Float(min(max(energy, 0), 1))),
                            .float(Float(intensity)),
                            .float(Float(rim)),
                            .float(Float(centerY))
                        )
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// A small orb for rows and buttons, drawn with plain SwiftUI so it costs
/// nothing. Same colours, same breath.
struct OrbMark: View {
    var size: CGFloat = 22
    var isLit: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            let fullness = LivingCanvas.idleBreath(timeline.date)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Palette.ember.opacity(isLit ? 0.55 : 0.18),
                                Palette.rose.opacity(isLit ? 0.22 : 0.08),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * (0.55 + fullness * 0.12)
                        )
                    )
                    .frame(width: size * 1.6, height: size * 1.6)
                Circle()
                    .fill(isLit ? Palette.ember : Palette.inkFaint)
                    .frame(width: size * (0.42 + fullness * 0.08), height: size * (0.42 + fullness * 0.08))
                    .blur(radius: size * 0.05)
            }
            .frame(width: size, height: size)
        }
    }
}
