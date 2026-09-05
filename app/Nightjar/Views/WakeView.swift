import SwiftUI

/// Alarm, sunrise, bedtime. Honest about what iOS lets a suspended app do.
struct WakeView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var alarmDate = Date()
    @State private var bedtimeDate = Date()
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var settings = player.settings
        let isPlus = player.plan.isPlus

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(title: "Mornings", subtitle: nextAlarmLine, onClose: { dismiss() })

                // MARK: Alarm

                SectionLabel("Sunrise alarm")
                    .padding(.top, 26)

                SettingRow(title: "Alarm", detail: isPlus ? nil : "Part of Plus.") {
                    if isPlus {
                        Toggle("", isOn: Binding(
                            get: { settings.alarmEnabled },
                            set: { on in
                                settings.alarmEnabled = on
                                player.applyAlarmSettings()
                                if on { requestNotifications() }
                            }
                        ))
                        .toggleStyle(WarmToggleStyle())
                        .labelsHidden()
                    } else {
                        PlusMark()
                            .onTapGesture { player.requestUpgrade(.wake) }
                    }
                }
                Hairline()

                if isPlus {
                    SettingRow(title: "Time") {
                        DatePicker("", selection: $alarmDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(Palette.ember)
                            .onChange(of: alarmDate) { _, date in
                                let minute = minuteOfDay(date)
                                guard minute != settings.alarmMinuteOfDay else { return }
                                settings.alarmMinuteOfDay = minute
                                player.applyAlarmSettings()
                            }
                    }
                    Hairline()

                    SettingRow(title: "Sunrise", detail: "Minutes of climb before the alarm.") {
                        ChoiceRow(
                            options: [(5, "5"), (15, "15"), (30, "30"), (45, "45")],
                            selection: settings.sunriseMinutes
                        ) { choice in
                            settings.sunriseMinutes = choice
                            player.applyAlarmSettings()
                        }
                        .frame(width: 190)
                    }
                    Hairline()

                    SettingRow(title: "Repeat") {
                        Toggle("", isOn: Binding(
                            get: { settings.alarmRepeats },
                            set: { settings.alarmRepeats = $0; player.applyAlarmSettings() }
                        ))
                        .toggleStyle(WarmToggleStyle())
                        .labelsHidden()
                    }
                    if settings.alarmRepeats {
                        weekdayRow
                            .padding(.bottom, 12)
                    }
                    Hairline()

                    SectionLabel("Wake to")
                        .padding(.top, 22)
                    VStack(spacing: 0) {
                        ForEach(Mix.wakePresets) { mix in
                            Button {
                                settings.alarmMixID = mix.id
                                player.applyAlarmSettings()
                            } label: {
                                IndexRow(title: mix.name, detail: mix.summary, isActive: selectedWakeID == mix.id) {
                                    if selectedWakeID == mix.id { OrbMark(size: 18, isLit: true) }
                                }
                            }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }

                    Text("The sunrise needs the app alive and playing. Keep the sleep timer on Fade to quiet, or off, so the bed runs all night. If playback has stopped, a plain notification still fires at the alarm time.")
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    if settings.alarmEnabled && settings.timerEndAction == .stop && settings.timerMinutes > 0 {
                        Text("Your sleep timer is set to Stop, which will end playback before the sunrise.")
                            .font(Typeface.body(12))
                            .foregroundStyle(Palette.ember)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                }

                // MARK: Bedtime

                SectionLabel("Bedtime")
                    .padding(.top, 30)

                SettingRow(title: "Time") {
                    DatePicker("", selection: $bedtimeDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Palette.ember)
                        .onChange(of: bedtimeDate) { _, date in
                            let minute = minuteOfDay(date)
                            guard minute != settings.bedtimeMinuteOfDay else { return }
                            settings.bedtimeMinuteOfDay = minute
                            player.applyBedtimeSettings()
                        }
                }
                Hairline()
                SettingRow(title: "Reminder", detail: "A quiet notification fifteen minutes before.") {
                    Toggle("", isOn: Binding(
                        get: { settings.bedtimeReminderEnabled },
                        set: { on in
                            settings.bedtimeReminderEnabled = on
                            player.applyBedtimeSettings()
                            if on { requestNotifications() }
                        }
                    ))
                    .toggleStyle(WarmToggleStyle())
                    .labelsHidden()
                }
                Hairline()
                SettingRow(title: "Start the routine", detail: "Only while the app is open on screen. iOS does not wake a closed app to play sound.") {
                    Toggle("", isOn: Binding(
                        get: { settings.windDownEnabled },
                        set: { settings.windDownEnabled = $0; settings.save() }
                    ))
                    .toggleStyle(WarmToggleStyle())
                    .labelsHidden()
                }
                Hairline()

                if notificationsDenied {
                    Text("Notifications are off for Nightjar. Turn them on in Settings so the alarm and reminder can fire.")
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.ember)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }

                Color.clear.frame(height: 30)
            }
            .pageGutter()
        }
        .sheetDressing()
        .paywallHost()
        .onAppear {
            alarmDate = date(minuteOfDay: settings.alarmMinuteOfDay)
            bedtimeDate = date(minuteOfDay: settings.bedtimeMinuteOfDay)
        }
    }

    private var selectedWakeID: UUID {
        player.settings.alarmMixID ?? Mix.wakePresets[0].id
    }

    private var nextAlarmLine: String {
        guard player.settings.alarmEnabled, let next = player.nextAlarm else {
            return "No alarm set."
        }
        return "Next: \(Format.dayAndTime(next))"
    }

    private var weekdayRow: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let isOn = player.settings.alarmWeekdays.contains(weekday)
                Button {
                    var days = player.settings.alarmWeekdays
                    if isOn { days.remove(weekday) } else { days.insert(weekday) }
                    player.settings.alarmWeekdays = days
                    player.applyAlarmSettings()
                } label: {
                    Text(Format.weekdayInitial(weekday))
                        .font(Typeface.meta(12, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Palette.ground : Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isOn ? Palette.ember : Palette.raised)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func requestNotifications() {
        Task {
            let granted = await Reminders.requestAuthorization()
            await MainActor.run { notificationsDenied = !granted }
            await Reminders.rescheduleAlarm(settings: player.settings)
            await Reminders.rescheduleBedtime(settings: player.settings)
        }
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func date(minuteOfDay: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Ringing

struct AlarmOverlay: View {
    @Environment(PlayerController.self) private var player
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LivingCanvas(energy: 0.6, intensity: 1.3, rim: 0.5, centerY: 0.4, frameRate: 30)
            VStack(spacing: 18) {
                Spacer()
                Text(Format.timeOfDay(now))
                    .font(Typeface.display(64))
                    .foregroundStyle(Palette.ink)
                Text("Morning")
                    .font(Typeface.body(16))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                HStack(spacing: 14) {
                    SoftButton(title: "Snooze 9 min", systemImage: "zzz", isWide: true) {
                        player.snoozeAlarm()
                    }
                    SoftButton(title: "I'm up", systemImage: "sun.max", isProminent: true, isWide: true) {
                        player.dismissAlarm()
                    }
                }
                .pageGutter()
                .padding(.bottom, 40)
            }
        }
        .onReceive(clock) { date in now = date }
    }
}
