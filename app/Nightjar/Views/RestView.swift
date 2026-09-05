import SwiftUI

/// Everything around the sound: what to do, how it went, how to wake.
struct RestView: View {
    @Environment(PlayerController.self) private var player

    @State private var openTip: Tip?
    @State private var showWake = false
    @State private var showJournal = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Rest", subtitle: "Small things that add up.") {
                    EmptyView()
                }
                .padding(.top, 8)

                mornings
                    .padding(.top, 26)

                nights
                    .padding(.top, 26)

                ForEach(Tips.grouped(), id: \.group) { section in
                    SectionLabel(section.group.title)
                        .padding(.top, 30)
                        .padding(.bottom, 4)
                    ForEach(section.tips) { tip in
                        Button {
                            openTip = tip
                        } label: {
                            IndexRow(title: tip.title, detail: tip.body) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }
                }

                Text("General guidance, not medical advice. If sleep has been hard for weeks, talk to a doctor. It is very treatable.")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)

                Color.clear.frame(height: 100)
            }
            .pageGutter()
        }
        .sheet(item: $openTip) { tip in TipSheet(tip: tip) }
        .sheet(isPresented: $showWake) { WakeView() }
        .sheet(isPresented: $showJournal) { JournalSheet() }
    }

    // MARK: - Wake and bedtime

    private var mornings: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Mornings")
                .padding(.bottom, 4)
            Button {
                if player.plan.isPlus {
                    showWake = true
                } else {
                    player.requestUpgrade(.wake)
                }
            } label: {
                IndexRow(
                    title: "Sunrise alarm",
                    detail: alarmLine,
                    isActive: player.settings.alarmEnabled
                ) {
                    HStack(spacing: 10) {
                        if !player.plan.isPlus { PlusMark() }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
            }
            .buttonStyle(.plain)
            Hairline()
            Button {
                showWake = true
            } label: {
                IndexRow(
                    title: "Bedtime",
                    detail: bedtimeLine,
                    isActive: player.settings.bedtimeReminderEnabled || player.settings.windDownEnabled
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .buttonStyle(.plain)
            Hairline()
        }
    }

    private var alarmLine: String {
        guard player.settings.alarmEnabled else { return "Off. Sound that climbs from silence before the alarm." }
        let time = Format.timeOfDay(minuteOfDay: player.settings.alarmMinuteOfDay)
        let days = player.settings.alarmRepeats
            ? Format.weekdaySummary(player.settings.alarmWeekdays)
            : "Once"
        return "\(time) · \(days) · \(player.settings.sunriseMinutes) min sunrise"
    }

    private var bedtimeLine: String {
        let time = Format.timeOfDay(minuteOfDay: player.settings.bedtimeMinuteOfDay)
        var parts: [String] = [time]
        if player.settings.bedtimeReminderEnabled { parts.append("reminder") }
        if player.settings.windDownEnabled { parts.append("starts the routine") }
        return parts.count == 1 ? "\(time) · nothing scheduled" : parts.joined(separator: " · ")
    }

    // MARK: - Journal

    private var nights: some View {
        let journal = player.journal
        let limit = player.plan.journalNightLimit
        let visible = limit.map { Array(journal.recent.prefix($0)) } ?? journal.recent

        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Nights", trailing: journal.streak >= 2 ? "\(journal.streak) running" : nil)
                .padding(.bottom, 4)
            if visible.isEmpty {
                Text("Nothing logged yet. A night is anything over twenty minutes.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.vertical, 14)
            } else {
                Button {
                    showJournal = true
                } label: {
                    IndexRow(
                        title: "\(visible.count) night\(visible.count == 1 ? "" : "s")",
                        detail: "Average \(Format.duration(journal.averageDuration))" + (journal.favouriteMix.map { " · usually \($0)" } ?? "")
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                .buttonStyle(.plain)
            }
            Hairline()
        }
    }
}

// MARK: - Tip

struct TipSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tip: Tip

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: tip.title, subtitle: tip.group.title, onClose: { dismiss() })
            Text(tip.body)
                .font(Typeface.body(17))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
            SectionLabel("Why")
                .padding(.top, 26)
            Text(tip.why)
                .font(Typeface.body(15))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Spacer(minLength: 20)
        }
        .pageGutter()
        .sheetDressing()
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Journal

struct JournalSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let journal = player.journal
        let limit = player.plan.journalNightLimit
        let visible = limit.map { Array(journal.recent.prefix($0)) } ?? journal.recent

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(
                    title: "Nights",
                    subtitle: "Logged on the phone. Nothing leaves it.",
                    onClose: { dismiss() }
                )

                HStack(spacing: 22) {
                    stat("Streak", "\(journal.streak)")
                    stat("Average", Format.duration(journal.averageDuration))
                    stat("Total", Format.duration(journal.totalDuration))
                }
                .padding(.top, 24)

                VStack(spacing: 0) {
                    ForEach(visible) { session in
                        IndexRow(
                            title: Format.dayAndTime(session.start),
                            detail: "\(session.mixName) · \(Format.duration(session.duration))" + (session.endedAtAlarm ? " · woke to sunrise" : "")
                        ) {
                            EmptyView()
                        }
                        Hairline()
                    }
                }
                .padding(.top, 18)

                if let limit, journal.recent.count > limit {
                    Button {
                        player.requestUpgrade(.journal)
                    } label: {
                        HStack(spacing: 10) {
                            PlusMark()
                            Text("\(journal.recent.count - limit) more with Plus")
                                .font(Typeface.body(13))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive) {
                    journal.clear()
                } label: {
                    Text("Clear the log")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.vertical, 20)
                }
                .buttonStyle(.plain)

                Color.clear.frame(height: 20)
            }
            .pageGutter()
        }
        .sheetDressing()
        .paywallHost()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Typeface.display(26))
                .foregroundStyle(Palette.ink)
            Text(label.uppercased())
                .font(Typeface.meta(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Palette.inkFaint)
        }
    }
}
