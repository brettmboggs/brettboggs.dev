import Foundation
import HealthKit

/// Writes finished nights into Apple Health, and nothing else.
///
/// Write only, on purpose. Reading sleep back would mean asking for a share
/// permission the app has no use for, and the whole argument of this app is
/// that it asks for as little as possible. Health is the one place a night
/// can usefully leave Slumbio, because it does not leave the phone to get
/// there.
///
/// Off until it is switched on in Settings. Nothing is written retroactively:
/// turning it on today does not backfill a journal that was recorded while
/// the person had not agreed to this.
@Observable
final class HealthMirror {
    enum State: Equatable {
        case unavailable
        case off
        case on
        case denied
    }

    private(set) var state: State

    @ObservationIgnored private let store = HKHealthStore()

    /// The only type this app ever touches.
    @ObservationIgnored
    private let sleepType = HKCategoryType(.sleepAnalysis)

    init(enabled: Bool) {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        state = enabled ? .on : .off
        if enabled { refreshAuthorisation() }
    }

    var isAvailable: Bool { state != .unavailable }

    /// Asks for permission the first time, then remembers the answer.
    ///
    /// HealthKit never tells an app that a write was refused, by design, so
    /// `.denied` here only ever comes from the status it does report. A night
    /// that silently goes nowhere is the documented behaviour and there is
    /// nothing to do about it but say so in Settings.
    func setEnabled(_ enabled: Bool) async {
        guard isAvailable else { return }
        guard enabled else {
            state = .off
            return
        }
        do {
            try await store.requestAuthorization(toShare: [sleepType], read: [])
            state = store.authorizationStatus(for: sleepType) == .sharingDenied ? .denied : .on
        } catch {
            state = .denied
        }
    }

    private func refreshAuthorisation() {
        if store.authorizationStatus(for: sleepType) == .sharingDenied {
            state = .denied
        }
    }

    /// One night, as one asleep sample.
    ///
    /// `.asleepUnspecified` rather than a stage: the app has no idea which
    /// stage anyone was in, and claiming otherwise would put a fiction into
    /// the same graph that a watch writes the truth into.
    func record(_ session: SleepSession) {
        guard state == .on, session.duration >= 120 else { return }
        let sample = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: session.start,
            end: session.end,
            metadata: [HKMetadataKeyExternalUUID: session.id.uuidString]
        )
        store.save(sample) { _, error in
            if let error {
                NSLog("Slumbio: could not write to Health: \(error.localizedDescription)")
            }
        }
    }
}
