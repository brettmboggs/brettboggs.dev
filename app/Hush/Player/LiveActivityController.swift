import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Dynamic Island and Lock Screen countdown for a running sleep timer.
final class LiveActivityController {
    #if canImport(ActivityKit)
    private var activity: Activity<SleepTimerAttributes>?
    #endif

    var isEnabled: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    func start(mixName: String, endDate: Date, isWaking: Bool = false) {
        #if canImport(ActivityKit)
        guard isEnabled, activity == nil else {
            update(mixName: mixName, endDate: endDate, isPlaying: true, isWaking: isWaking)
            return
        }
        let attributes = SleepTimerAttributes(startedAt: Date())
        let state = SleepTimerAttributes.ContentState(
            mixName: mixName,
            endDate: endDate,
            isPlaying: true,
            isWaking: isWaking
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: endDate.addingTimeInterval(60)),
                pushType: nil
            )
        } catch {
            NSLog("Hush: could not start Live Activity: \(error.localizedDescription)")
        }
        #endif
    }

    func update(mixName: String, endDate: Date, isPlaying: Bool, isWaking: Bool) {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let state = SleepTimerAttributes.ContentState(
            mixName: mixName,
            endDate: endDate,
            isPlaying: isPlaying,
            isWaking: isWaking
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: endDate.addingTimeInterval(60))
            )
        }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        guard let current = activity else { return }
        activity = nil
        Task {
            await current.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}
