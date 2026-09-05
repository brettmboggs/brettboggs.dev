import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Optional mirror of a finished session into the Health app.
///
/// Entirely opt-in and entirely non-essential: if the HealthKit capability is
/// not enabled on the build, every call here fails quietly and the local
/// journal still has the night.
enum HealthWriter {

    static var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    #if canImport(HealthKit)
    private static let store = HKHealthStore()

    private static var sleepType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }
    #endif

    @discardableResult
    static func requestAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard isAvailable, let type = sleepType else { return false }
        do {
            try await store.requestAuthorization(toShare: [type], read: [])
            return true
        } catch {
            NSLog("Hush: HealthKit authorization unavailable: \(error.localizedDescription)")
            return false
        }
        #else
        return false
        #endif
    }

    static func write(session: SleepSession) async {
        #if canImport(HealthKit)
        guard isAvailable, let type = sleepType else { return }
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return }

        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: session.start,
            end: session.end
        )
        do {
            try await store.save(sample)
        } catch {
            NSLog("Hush: could not write sleep sample: \(error.localizedDescription)")
        }
        #endif
    }
}
