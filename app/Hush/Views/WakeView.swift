import SwiftUI

struct WakeView: View {
    @Environment(PlayerController.self) private var player
    @State private var showTimePicker = false
    @State private var showWindDownPicker = false

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    heading
                    alarmSection
                    windDownSection
                    journalSection
                }
                .pageGutter()
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showTimePicker) {
            TimePickerSheet(
                title: "Alarm",
                minuteOfDay: player.settings.alarmMinuteOfDay
            ) { minute in
                player.settings.alarmMinuteOfDay = minute
                player.applyAlarmSettings()
            }
        }
        .sheet(isPresented: $showWindDownPicker) {
            TimePickerSheet(
                title: "Wind down",
                minuteOfDay: player.settings.windDownMinuteOfDay
            ) { minute in
                player.settings.windDownMinuteOfDay = minute
                player.settings.save()
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wake")
                .font(Typeface.display(32))
                .foregroundStyle(Palette.ink)
            if let next = player.nextAlarm, player.settings.alarmEnabled {
                Text("Next: \(Format.dayAndTime(next))")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.ember.opacity(0.9))
            } else {
                Text("No alarm set.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.top, 14)
    }

    // MARK: Alarm

    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Alarm")

            HStack(alignment: .center) {
                Button {
                    showTimePicker = true
                } label: {
                    Text(Format.timeOfDay(minuteOfDay: player.settings.alarmMinuteOfDay))
                        .font(Typeface.display(46))
                        .foregroundStyle(
                            player.settings.alarmEnabled ? Palette.ink : Palette.inkFaint
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { player.settings.alarmEnabled },
                    set: { newValue in
                        if newValue, !player.entitlements.isUnlocked(.sunriseAlarm) {
                            player.requestUpgrade(.alarm)
                            return
                        }
                        player.settings.alarmEnabled = newValue
                        player.applyAlarmSettings()
                        if newValue {
                            Task { _ = await AlarmNotifications.requestAuthorization() }
                        }
                    }
                ))
                .toggleStyle(WarmToggleStyle())
                .labelsHidden()
            }

            weekdayPicker

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(
                    "Sunrise",
                    trailing: "\(player.settings.sunriseMinutes) min before"
                )
                FaderBar(
                    value: Double(player.settings.sunriseMinutes) / 45,
                    tint: Palette.ember,
                    onChange: { value in
                        player.settings.sunriseMinutes = max(1, Int((value * 45).rounded()))
                    },
                    onCommit: { player.applyAlarmSettings() }
                )
                Text("Sound fades in from silence over this window, then the alarm lands.")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.inkFaint)
            }

            wakeSoundPicker

            if player.settings.alarmEnabled && player.settings.timerEndAction == .stop
                && player.settings.timerMinutes > 0 {
                calloutBox(
                    "Your sleep timer stops playback, so the sunrise cannot run. Set the timer to fade to quiet instead, and the alarm will still reach you."
                )
            } else if player.settings.alarmEnabled {
                calloutBox(
                    "The sunrise runs while sound is playing. If playback has stopped, a normal notification still fires at the alarm time."
                )
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let isOn = player.settings.alarmWeekdays.contains(weekday)
                Button {
                    if isOn {
                        player.settings.alarmWeekdays.remove(weekday)
                    } else {
                        player.settings.alarmWeekdays.insert(weekday)
                    }
                    player.settings.alarmRepeats = !player.settings.alarmWeekdays.isEmpty
                    player.applyAlarmSettings()
                } label: {
                    Text(Format.weekdayInitial(weekday))
                        .font(Typeface.meta(12, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Palette.ground : Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isOn ? Palette.ember : Palette.raised)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var wakeSoundPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Wake sound")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Mix.wakePresets) { mix in
                        let isSelected = player.settings.alarmMixID == mix.id
                        Button {
                            player.settings.alarmMixID = mix.id
                            player.applyAlarmSettings()
                        } label: {
                            Text(mix.name)
                                .font(Typeface.body(13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Palette.ground : Palette.inkSoft)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule().fill(isSelected ? Palette.ember : Palette.raised)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Wind down

    private var windDownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Wind down")

            SettingRow(
                title: Format.timeOfDay(minuteOfDay: player.settings.windDownMinuteOfDay),
                detail: "Starts your last mix at this time, while Hush is open."
            ) {
                Toggle("", isOn: Binding(
                    get: { player.settings.windDownEnabled },
                    set: { newValue in
                        if newValue, !player.entitlements.isUnlocked(.sunriseAlarm) {
                            player.requestUpgrade(.alarm)
                            return
                        }
                        player.settings.windDownEnabled = newValue
                        player.settings.save()
                    }
                ))
                .toggleStyle(WarmToggleStyle())
                .labelsHidden()
            }
            .contentShape(Rectangle())
            .onTapGesture { showWindDownPicker = true }

            Hairline()
        }
    }

    // MARK: Journal

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Nights", trailing: "\(player.journal.sessions.count) recorded")

            if player.journal.sessions.isEmpty {
                Text("Sessions over two minutes get logged here. Nothing leaves your phone.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.inkFaint)
            } else {
                HStack(spacing: 0) {
                    stat("Streak", "\(player.journal.streak)", "nights")
                    stat("Average", Format.duration(player.journal.averageDuration), "a night")
                    stat("Usual", player.journal.favouriteMix ?? "-", "mix")
                }

                VStack(spacing: 0) {
                    ForEach(visibleNights) { session in
                        HStack {
                            Text(Format.dayAndTime(session.start))
                                .font(Typeface.body(13))
                                .foregroundStyle(Palette.inkSoft)
                            Spacer()
                            Text(session.mixName)
                                .font(Typeface.meta(10))
                                .foregroundStyle(Palette.inkFaint)
                                .lineLimit(1)
                            Text(Format.duration(session.duration))
                                .font(Typeface.meta(11))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                        Hairline()
                    }

                    if hiddenNightCount > 0 {
                        Button {
                            player.requestUpgrade(.journal)
                        } label: {
                            HStack {
                                Text("\(hiddenNightCount) more \(hiddenNightCount == 1 ? "night" : "nights")")
                                    .font(Typeface.body(13))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Palette.ember)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Free shows the last week; Pro shows everything.
    private var visibleNights: [SleepSession] {
        let all = player.journal.recent
        guard let limit = player.entitlements.journalNightLimit else {
            return Array(all.prefix(12))
        }
        return Array(all.prefix(limit))
    }

    private var hiddenNightCount: Int {
        guard player.entitlements.journalNightLimit != nil else { return 0 }
        return max(player.journal.sessions.count - visibleNights.count, 0)
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Typeface.display(24))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(label) · \(unit)".uppercased())
                .font(Typeface.meta(9))
                .tracking(1.1)
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calloutBox(_ text: String) -> some View {
        Text(text)
            .font(Typeface.body(12))
            .foregroundStyle(Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.raised)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.ember.opacity(0.6))
                    .frame(width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
    }
}

// MARK: - Time picker

struct TimePickerSheet: View {
    let title: String
    let minuteOfDay: Int
    let onSave: (Int) -> Void

    @State private var date: Date = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetShell(title: title) {
            VStack(spacing: 20) {
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.colorScheme, .dark)

                SoftButton(title: "Set", isProminent: true) {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                    onSave((components.hour ?? 7) * 60 + (components.minute ?? 0))
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            var components = DateComponents()
            components.hour = minuteOfDay / 60
            components.minute = minuteOfDay % 60
            date = Calendar.current.date(from: components) ?? Date()
        }
    }
}
