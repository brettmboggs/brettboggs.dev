import Foundation

/// One leg of a breathing cycle.
struct BreathPhase: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case inhale
        /// A second, shorter sip on top of a full inhale. The physiological sigh.
        case topUp
        case holdFull
        case exhale
        case holdEmpty

        var label: String {
            switch self {
            case .inhale: return "Breathe in"
            case .topUp: return "A little more"
            case .holdFull: return "Hold"
            case .exhale: return "Breathe out"
            case .holdEmpty: return "Rest"
            }
        }
    }

    let kind: Kind
    let seconds: Double
}

/// A named cycle. `phases` always sums to one full breath.
struct BreathPattern: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let blurb: String
    let phases: [BreathPhase]
    let isFree: Bool
    /// Where in the library it sits.
    let rank: Int

    var cycleSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }

    /// "4 · 7 · 8" for the row subtitle.
    var signature: String {
        phases.map { Format.seconds($0.seconds) }.joined(separator: " · ")
    }

    var breathsPerMinute: Double { 60 / max(cycleSeconds, 1) }

    /// Fullness of the lungs, 0...1, at `t` seconds into a cycle. This is the
    /// value the orb and the guide sound follow, so it is continuous and
    /// eased, never a step.
    func fullness(at t: Double) -> Double {
        var elapsed = t.truncatingRemainder(dividingBy: max(cycleSeconds, 0.001))
        if elapsed < 0 { elapsed += cycleSeconds }
        var level = 0.0
        for phase in phases {
            let progress = min(max(elapsed / max(phase.seconds, 0.001), 0), 1)
            let eased = BreathPattern.ease(progress)
            switch phase.kind {
            case .inhale:
                let start = level
                let end = 0.85
                if elapsed <= phase.seconds { return start + (end - start) * eased }
                level = end
            case .topUp:
                let start = level
                let end = 1.0
                if elapsed <= phase.seconds { return start + (end - start) * eased }
                level = end
            case .holdFull:
                if elapsed <= phase.seconds { return level }
            case .exhale:
                let start = level
                if elapsed <= phase.seconds { return start * (1 - eased) }
                level = 0
            case .holdEmpty:
                if elapsed <= phase.seconds { return 0 }
            }
            elapsed -= phase.seconds
        }
        return level
    }

    /// Which phase is active at `t` seconds into a cycle, and how far through.
    func phase(at t: Double) -> (index: Int, progress: Double) {
        var elapsed = t.truncatingRemainder(dividingBy: max(cycleSeconds, 0.001))
        if elapsed < 0 { elapsed += cycleSeconds }
        for (index, phase) in phases.enumerated() {
            if elapsed < phase.seconds {
                return (index, elapsed / max(phase.seconds, 0.001))
            }
            elapsed -= phase.seconds
        }
        return (max(phases.count - 1, 0), 1)
    }

    /// Smoothstep. Lungs do not move linearly.
    private static func ease(_ x: Double) -> Double {
        x * x * (3 - 2 * x)
    }

    // MARK: - Library

    static let fourSevenEight = BreathPattern(
        id: "478",
        name: "4 · 7 · 8",
        blurb: "The one for falling asleep. A long hold, a longer exhale.",
        phases: [
            BreathPhase(kind: .inhale, seconds: 4),
            BreathPhase(kind: .holdFull, seconds: 7),
            BreathPhase(kind: .exhale, seconds: 8),
        ],
        isFree: true,
        rank: 0
    )

    static let box = BreathPattern(
        id: "box",
        name: "Box",
        blurb: "Four sides, four seconds each. Steadies a racing evening.",
        phases: [
            BreathPhase(kind: .inhale, seconds: 4),
            BreathPhase(kind: .holdFull, seconds: 4),
            BreathPhase(kind: .exhale, seconds: 4),
            BreathPhase(kind: .holdEmpty, seconds: 4),
        ],
        isFree: true,
        rank: 1
    )

    static let coherent = BreathPattern(
        id: "coherent",
        name: "Coherent",
        blurb: "Five and a half seconds each way. About five breaths a minute.",
        phases: [
            BreathPhase(kind: .inhale, seconds: 5.5),
            BreathPhase(kind: .exhale, seconds: 5.5),
        ],
        isFree: false,
        rank: 2
    )

    static let longExhale = BreathPattern(
        id: "long-exhale",
        name: "Long Exhale",
        blurb: "In for four, out for eight. The exhale is where the calm is.",
        phases: [
            BreathPhase(kind: .inhale, seconds: 4),
            BreathPhase(kind: .exhale, seconds: 8),
        ],
        isFree: false,
        rank: 3
    )

    static let sigh = BreathPattern(
        id: "sigh",
        name: "Physiological Sigh",
        blurb: "Two breaths in through the nose, one slow one out. Resets fast.",
        phases: [
            BreathPhase(kind: .inhale, seconds: 2.5),
            BreathPhase(kind: .topUp, seconds: 1),
            BreathPhase(kind: .exhale, seconds: 7),
        ],
        isFree: false,
        rank: 4
    )

    static func custom(_ seconds: [Double]) -> BreathPattern {
        let s = seconds.count == 4 ? seconds : [4, 4, 6, 2]
        var phases: [BreathPhase] = [BreathPhase(kind: .inhale, seconds: max(s[0], 1))]
        if s[1] > 0.4 { phases.append(BreathPhase(kind: .holdFull, seconds: s[1])) }
        phases.append(BreathPhase(kind: .exhale, seconds: max(s[2], 1)))
        if s[3] > 0.4 { phases.append(BreathPhase(kind: .holdEmpty, seconds: s[3])) }
        return BreathPattern(
            id: "custom",
            name: "Your Own",
            blurb: "Set the four numbers yourself.",
            phases: phases,
            isFree: false,
            rank: 5
        )
    }

    static let library: [BreathPattern] = [fourSevenEight, box, coherent, longExhale, sigh]

    static func named(_ id: String, custom: [Double]) -> BreathPattern {
        if id == "custom" { return BreathPattern.custom(custom) }
        return library.first { $0.id == id } ?? fourSevenEight
    }
}
