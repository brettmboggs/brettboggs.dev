import SwiftUI

/// The one hero element.
///
/// Slow warm blooms that drift, breathe, and swell with the actual output of
/// the mix. When nothing is playing it settles almost to a stop rather than
/// freezing, which reads as resting instead of broken.
struct BreathingBackdrop: View {
    let level: Double
    let isPlaying: Bool
    /// Falls to near zero in bedside mode.
    var intensity: Double = 1

    private struct Bloom {
        let hue: Color
        let orbitRadius: Double
        let speed: Double
        let phase: Double
        let size: Double
        let origin: CGPoint
    }

    private static let blooms: [Bloom] = [
        Bloom(hue: Color(hex: 0xC2703A), orbitRadius: 0.10, speed: 0.031,
              phase: 0.0, size: 0.95, origin: CGPoint(x: 0.50, y: 0.72)),
        Bloom(hue: Color(hex: 0x8C5A3C), orbitRadius: 0.14, speed: 0.019,
              phase: 1.7, size: 0.78, origin: CGPoint(x: 0.24, y: 0.44)),
        Bloom(hue: Color(hex: 0x6E7A52), orbitRadius: 0.12, speed: 0.023,
              phase: 3.4, size: 0.66, origin: CGPoint(x: 0.78, y: 0.36)),
        Bloom(hue: Color(hex: 0x5A6076), orbitRadius: 0.16, speed: 0.014,
              phase: 5.1, size: 0.72, origin: CGPoint(x: 0.62, y: 0.86)),
        Bloom(hue: Color(hex: 0xE39A4A), orbitRadius: 0.07, speed: 0.041,
              phase: 2.3, size: 0.44, origin: CGPoint(x: 0.40, y: 0.60)),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: intensity < 0.02)) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                context.addFilter(.blur(radius: min(size.width, size.height) * 0.11))

                for bloom in Self.blooms {
                    // Two incommensurate rates, so the drift never visibly loops.
                    let angle = t * bloom.speed + bloom.phase
                    let dx = cos(angle) * bloom.orbitRadius
                    let dy = sin(angle * 0.73 + bloom.phase) * bloom.orbitRadius * 0.7

                    let breath = 1 + sin(t * 0.11 + bloom.phase) * 0.10
                    let swell = 1 + level * 0.42
                    let radius = size.width * bloom.size * 0.55 * breath * swell

                    let center = CGPoint(
                        x: size.width * (bloom.origin.x + dx),
                        y: size.height * (bloom.origin.y + dy * 0.6)
                    )

                    let alpha = (isPlaying ? 0.40 : 0.24) * intensity
                    let gradient = Gradient(stops: [
                        .init(color: bloom.hue.opacity(alpha), location: 0),
                        .init(color: bloom.hue.opacity(alpha * 0.35), location: 0.45),
                        .init(color: .clear, location: 1),
                    ])

                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            gradient,
                            center: center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
        }
        .background(Palette.ground)
        .overlay {
            // Pulls the edges down so text always has something to sit on.
            RadialGradient(
                colors: [.clear, Palette.ground.opacity(0.75)],
                center: .center,
                startRadius: 60,
                endRadius: 460
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .animation(.settleSlow, value: isPlaying)
    }
}
