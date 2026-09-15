import SwiftUI

/// Every timer, and a way to start another.
struct TimersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var timers = TimerCenter.shared
    @State private var customMinutes = 12
    @State private var label = ""

    var body: some View {
        NavigationStack {
            List {
                if timers.timers.isEmpty {
                    EmptyNote(title: "No timers", message: "Start one below, or tap a time in a recipe step.")
                        .indexInsets()
                }
                ForEach(timers.timers) { timer in
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        TimerRow(timer: timer, now: context.date, isRinging: timers.ringing.contains(timer.id))
                    }
                    .indexInsets()
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            timers.stop(timer.id)
                        } label: {
                            Label("Stop", systemImage: "xmark")
                        }
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([1, 3, 5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                                Chip(title: minutes == 60 ? "1 hr" : "\(minutes) min") {
                                    start(minutes * 60)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                    HStack {
                        Stepper(value: $customMinutes, in: 1...600) {
                            Text("\(customMinutes) min")
                                .font(Typeface.meta(14, weight: .semibold))
                        }
                        Button("Start") { start(customMinutes * 60) }
                            .font(Typeface.body(15, weight: .semibold))
                    }
                    .indexInsets()
                    TextField("Name (optional)", text: $label)
                        .indexInsets()
                } header: {
                    SectionLabel("New timer")
                        .padding(.horizontal, 20)
                        .textCase(nil)
                }
                .listRowSeparator(.hidden)
            }
            .plainList()
            .navigationTitle("Timers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if timers.timers.count > 1 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Stop all") { timers.stopAll() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func start(_ seconds: Int) {
        let name = label.isBlank ? (CookSession.shared.recipe?.title ?? "Timer") : label.collapsed
        timers.start(seconds: seconds, label: name, recipeID: CookSession.shared.recipe?.id, stepIndex: nil)
        label = ""
        Haptics.success()
    }
}

struct TimerRow: View {
    let timer: KitchenTimer
    let now: Date
    let isRinging: Bool
    @State private var center = TimerCenter.shared

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isRinging ? "Time's up" : Format.clock(timer.remaining(at: now)))
                    .font(Typeface.meta(28, weight: .semibold))
                    .monospacedDigit()
                Text(timer.label)
                    .font(Typeface.body(13))
                    .foregroundStyle(Ink.inkSoft)
                    .lineLimit(1)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Ink.hairline)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Ink.accent).frame(width: geo.size.width * min(1, max(0, progress)))
                        }
                }
                .frame(height: 2)
            }
            Spacer()
            if isRinging {
                Button("+1 min") { center.addMinute(timer.id) }
                    .font(Typeface.body(14, weight: .medium))
                Button("Done") { center.dismissRinging(timer.id) }
                    .font(Typeface.body(14, weight: .semibold))
            } else {
                Button {
                    if timer.isPaused { center.resume(timer.id) } else { center.pause(timer.id) }
                } label: {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Ink.paperRaised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(timer.isPaused ? "Resume" : "Pause")
                Button {
                    center.addMinute(timer.id)
                } label: {
                    Text("+1")
                        .font(Typeface.meta(13, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Ink.paperRaised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a minute")
            }
        }
        .padding(.vertical, 8)
    }

    private var progress: Double {
        guard timer.totalSeconds > 0 else { return 1 }
        return 1 - Double(timer.remaining(at: now)) / Double(timer.totalSeconds)
    }
}
