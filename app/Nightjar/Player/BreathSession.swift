import Foundation
import Observation

/// One guided breathing session: a pattern, a length, and a clock.
///
/// The orb and the guide sound read `fullness(at:)` every frame, which is a
/// pure function of time. The ticker only exists to notice phase boundaries
/// (for the label, the haptic and the guide colour) and the end.
@Observable
final class BreathSession {
    let pattern: BreathPattern
    let totalSeconds: Double

    private(set) var phaseIndex: Int = 0
    private(set) var cyclesDone: Int = 0
    private(set) var isPaused = false
    private(set) var isFinished = false
    /// Set once the timer is up; the session then finishes at the end of the
    /// current cycle so nobody is cut off mid-inhale.
    private(set) var isWindingDown = false

    var onPhaseChange: ((BreathPhase.Kind) -> Void)?
    var onFinish: (() -> Void)?

    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var pausedTotal: TimeInterval = 0
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var lastPhaseIndex = -1
    @ObservationIgnored private var lastCycle = 0

    init(pattern: BreathPattern, minutes: Int) {
        self.pattern = pattern
        self.totalSeconds = Double(max(minutes, 1)) * 60
    }

    var currentPhase: BreathPhase? {
        guard pattern.phases.indices.contains(phaseIndex) else { return nil }
        return pattern.phases[phaseIndex]
    }

    // MARK: - Clock

    func elapsed(at date: Date = Date()) -> TimeInterval {
        let reference = pausedAt ?? date
        return max(reference.timeIntervalSince(startedAt) - pausedTotal, 0)
    }

    var remaining: TimeInterval {
        max(totalSeconds - elapsed(), 0)
    }

    var progress: Double {
        min(elapsed() / max(totalSeconds, 1), 1)
    }

    /// Lung fullness 0...1 right now. Pure, frame-rate safe.
    func fullness(at date: Date) -> Double {
        if isFinished { return 0 }
        return pattern.fullness(at: elapsed(at: date))
    }

    /// Seconds left in the current phase, for the countdown under the label.
    func phaseRemaining(at date: Date = Date()) -> Double {
        let (index, progress) = pattern.phase(at: elapsed(at: date))
        guard pattern.phases.indices.contains(index) else { return 0 }
        return pattern.phases[index].seconds * (1 - progress)
    }

    // MARK: - Transport

    func start() {
        startedAt = Date()
        pausedAt = nil
        pausedTotal = 0
        isFinished = false
        isPaused = false
        isWindingDown = false
        lastPhaseIndex = -1
        lastCycle = 0
        startTicker()
        tick()
    }

    func pause() {
        guard !isPaused, !isFinished else { return }
        isPaused = true
        pausedAt = Date()
        ticker?.invalidate()
        ticker = nil
    }

    func resume() {
        guard isPaused, let since = pausedAt else { return }
        pausedTotal += Date().timeIntervalSince(since)
        pausedAt = nil
        isPaused = false
        startTicker()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        guard !isFinished else { return }
        isFinished = true
        onFinish?()
    }

    deinit {
        ticker?.invalidate()
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard !isFinished, !isPaused else { return }
        let now = Date()
        let seconds = elapsed(at: now)
        let cycle = Int(seconds / max(pattern.cycleSeconds, 0.001))
        let (index, _) = pattern.phase(at: seconds)

        if seconds >= totalSeconds && !isWindingDown {
            isWindingDown = true
        }

        if cycle != lastCycle {
            lastCycle = cycle
            cyclesDone = cycle
            // The timer ran out during the last cycle: this boundary is the
            // natural place to stop.
            if isWindingDown {
                stop()
                return
            }
        }

        if index != lastPhaseIndex {
            lastPhaseIndex = index
            phaseIndex = index
            if let phase = currentPhase {
                onPhaseChange?(phase.kind)
            }
        }
    }
}
