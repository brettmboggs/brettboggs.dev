import ActivityKit
import SwiftUI
import WidgetKit

struct SleepTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepTimerAttributes.self) { context in
            lockScreen(context.state)
                .activityBackgroundTint(Palette.ground)
                .activitySystemActionForegroundColor(Palette.ember)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isWaking ? "sunrise" : "moon.zzz")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Palette.ember)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.endDate, style: .timer)
                        .font(Typeface.meta(15))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Palette.ember)
                        .frame(width: 74)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.mixName)
                                .font(Typeface.body(15, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Text(context.state.isWaking ? "Waking you up" : "Sleep timer")
                                .font(Typeface.meta(9))
                                .tracking(1.2)
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        Button(intent: StopPlaybackIntent()) {
                            Text("Stop")
                                .font(Typeface.body(13, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Palette.raisedHigh))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: context.state.isWaking ? "sunrise" : "moon.zzz")
                    .foregroundStyle(Palette.ember)
            } compactTrailing: {
                Text(context.state.endDate, style: .timer)
                    .font(Typeface.meta(12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ember)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(Palette.ember)
            }
            .keylineTint(Palette.ember)
        }
    }

    private func lockScreen(_ state: SleepTimerAttributes.ContentState) -> some View {
        HStack(spacing: 14) {
            Image(systemName: state.isWaking ? "sunrise" : "moon.zzz")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.ember)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.mixName)
                    .font(Typeface.display(19))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(state.isWaking ? "Sunrise under way" : "Fades out at the end")
                    .font(Typeface.meta(9))
                    .tracking(1.2)
                    .foregroundStyle(Palette.inkFaint)
            }

            Spacer(minLength: 4)

            Text(state.endDate, style: .timer)
                .font(Typeface.meta(17))
                .monospacedDigit()
                .foregroundStyle(Palette.ember)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
