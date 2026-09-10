import SwiftUI

/// Everything around the sound: what to do, how it went, how to wake.
struct RestView: View {
    @Environment(PlayerController.self) private var player

    @State private var openTip: Tip?
    @State private var showWake = false
    @State private var showJournal = false
    @State private var showNotes = false

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

                notes
                    .padding(.top, 30)

                Text("General guidance, not medical advice. If sleep has been hard for weeks, talk to a doctor. It is very treatable.")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)

                Color.clear.frame(height: 100)
            }
            .pageGutter()
        }
        .onAppear {
            #if DEBUG
            switch Demo.sheet {
            case "wake": showWake = true
            case "journal": showJournal = true
            default: break
            }
            #endif
        }
        .sheet(item: $openTip) { tip in TipSheet(tip: tip) }
        .sheet(isPresented: $showWake) { WakeView() }
        .sheet(isPresented: $showJournal) { JournalSheet() }
        .sheet(isPresented: $showNotes) { NotesSheet(onOpen: { openTip = $0 }) }
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

    // MARK: - Notes

    /// One note, and a door to the other twenty-nine.
    ///
    /// All thirty used to be printed here, title and body each, which made
    /// this the longest screen in the app by a distance and buried the two
    /// things above it. They are worth reading one at a time anyway, which is
    /// what the nightly one on the Tonight screen has always done.
    private var notes: some View {
        let tip = Tips.tonight()
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Tonight", trailing: tip.group.title)
                .padding(.bottom, 10)
            Button { openTip = tip } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tip.title)
                        .font(Typeface.display(21))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tip.body)
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Hairline()
                .padding(.top, 18)
            Button { showNotes = true } label: {
                IndexRow(title: "All \(Tips.all.count) notes", detail: "Short, practical, one at a time.") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .buttonStyle(.plain)
            Hairline()
        }
    }

    // MARK: - Journal

    private var nights: some View {
        let journal = player.journal
        let limit = player.plan.journalNightLimit
        let visible = limit.map { Array(journal.recent.prefix($0)) } ?? journal.recent

        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Nights", trailing: journal.streak >= 2 ? "\(journal.streak) running" : nil)
                .padding(.bottom, 10)

            Button {
                if visible.isEmpty { return }
                showJournal = true
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    // Free keeps the last seven nights, so the chart is
                    // seven wide rather than fourteen with half of it greyed
                    // out, which would read as nights the person missed.
                    NightsChart(sessions: visible, nights: limit ?? 14)
                    if visible.isEmpty {
                        Text("Nothing logged yet. A night is anything over twenty minutes.")
                            .font(Typeface.body(13))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            StatCell(value: Format.duration(journal.averageDuration), label: "Average")
                            StatCell(value: "\(visible.count)", label: visible.count == 1 ? "Night" : "Nights")
                            StatCell(
                                value: journal.favouriteMix ?? "None",
                                label: "Usually",
                                isText: true
                            )
                        }
                    }
                }
                .padding(.bottom, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(visible.isEmpty)

            Hairline()
        }
    }
}

// MARK: - Nights

/// Two weeks of nights as bars.
///
/// The journal is the only number this app keeps, and it was a sentence. A
/// column of bars says the same thing without being read, and an empty one
/// still shows the shape of what is coming rather than a blank.
struct NightsChart: View {
    /// Most recent first, the way `Journal.recent` hands them over.
    let sessions: [SleepSession]
    var nights: Int = 14
    var height: CGFloat = 78

    var body: some View {
        let buckets = self.buckets
        let peak = max(buckets.map(\.seconds).max() ?? 0, 6 * 3600)
        let logged = buckets.filter { $0.seconds > 0 }
        let average = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.seconds } / Double(logged.count)

        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                if average > 0 {
                    // Where a usual night lands, so a short one is obvious.
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                        .offset(y: -height * CGFloat(average / peak))
                }
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(buckets, id: \.date) { bucket in
                        let filled = bucket.seconds > 0
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(filled ? Palette.ember.opacity(0.85) : Palette.raisedHigh)
                            .frame(
                                height: filled
                                    ? max(height * CGFloat(bucket.seconds / peak), 4)
                                    : 4
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: height, alignment: .bottom)

            HStack {
                Text(Format.shortDay(buckets.first?.date ?? Date()))
                Spacer()
                Text("Last night")
            }
            .font(Typeface.meta(10))
            .foregroundStyle(Palette.inkFaint)
        }
        .accessibilityElement()
        .accessibilityLabel(
            logged.isEmpty
                ? "No nights logged yet"
                : "\(logged.count) nights in the last two weeks, averaging \(Format.duration(average))"
        )
    }

    /// One entry per calendar day, oldest first, zero where nothing was played.
    private var buckets: [(date: Date, seconds: TimeInterval)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<nights).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let total = sessions
                .filter { calendar.isDate($0.start, inSameDayAs: day) }
                .reduce(0) { $0 + $1.duration }
            return (day, total)
        }
    }
}

/// One number under one word. Three of them make a row.
struct StatCell: View {
    let value: String
    let label: String
    var isText: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(isText ? Typeface.body(15, weight: .medium) : Typeface.display(20))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(Typeface.meta(9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

                // The notes are sleep hygiene, and the patterns are breathing
                // exercises. Neither is medical advice, and one of them has a
                // real contraindication, so say so where they are used rather
                // than only in the terms.
                Text("None of this is medical advice. If sleep has been a problem for weeks, or you have a heart or breathing condition, talk to a doctor.")
                    .font(Typeface.body(11))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

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

// MARK: - All the notes

/// The full shelf, behind one tap instead of in front of everything.
struct NotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onOpen: (Tip) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(
                    title: "Notes",
                    subtitle: "Thirty short ones. Nothing you have to do tonight.",
                    onClose: { dismiss() }
                )
                ForEach(Tips.grouped(), id: \.group) { section in
                    SectionLabel(section.group.title)
                        .padding(.top, 26)
                        .padding(.bottom, 4)
                    ForEach(section.tips) { tip in
                        Button {
                            dismiss()
                            onOpen(tip)
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
                Spacer(minLength: 24)
            }
            .pageGutter()
        }
        .sheetDressing()
        .presentationDetents([.large])
    }
}
