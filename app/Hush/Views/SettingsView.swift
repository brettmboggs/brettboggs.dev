import SwiftUI

struct SettingsView: View {
    @Environment(PlayerController.self) private var player
    @State private var confirmClear = false
    @State private var healthRefused = false

    var body: some View {
        SheetShell(title: "Settings") {
            VStack(alignment: .leading, spacing: 30) {
                proSection
                soundSection
                playbackSection
                interfaceSection
                healthSection
                aboutSection
            }
        }
        .alert("Clear the journal?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { player.journal.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every recorded night is deleted. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var proSection: some View {
        if player.entitlements.isPro {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Hush Pro").padding(.bottom, 4)
                SettingRow(
                    title: "Unlocked",
                    detail: "Thank you. Everything is open, on every device you sign in to."
                ) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ember)
                }
                Hairline()
            }
        } else {
            Button {
                player.requestUpgrade(.direct)
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hush Pro")
                            .font(Typeface.display(21))
                            .foregroundStyle(Palette.ink)
                        Text("Eight layers, every mix, the sunrise alarm. One payment, no subscription.")
                            .font(Typeface.body(12))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Text(player.entitlements.store.displayPrice)
                        .font(Typeface.meta(13, weight: .semibold))
                        .foregroundStyle(Palette.ground)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Palette.ember))
                }
                .padding(15)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.raised)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel("Sound")

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(
                    "Volume",
                    trailing: "\(Int(player.settings.masterVolume * 100))"
                )
                FaderBar(
                    value: player.settings.masterVolume,
                    tint: Palette.ember,
                    height: 6,
                    onChange: { value in
                        player.settings.masterVolume = value
                        player.commitMasterVolume()
                    },
                    onCommit: { player.settings.save() }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Tone", trailing: tiltLabel)
                FaderBar(
                    value: (player.settings.tilt + 1) / 2,
                    tint: Palette.clay,
                    height: 6,
                    onChange: { value in
                        player.settings.tilt = value * 2 - 1
                        player.commitTilt()
                    },
                    onCommit: { player.settings.save() }
                )
                Text("Warm rolls the top off everything. Bright opens it up.")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.inkFaint)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(
                    "Fade in",
                    trailing: "\(Int(player.settings.fadeInSeconds))s"
                )
                FaderBar(
                    value: player.settings.fadeInSeconds / 30,
                    tint: Palette.moss,
                    height: 6,
                    onChange: { player.settings.fadeInSeconds = ($0 * 30).rounded() },
                    onCommit: { player.settings.save() }
                )
            }
        }
    }

    private var tiltLabel: String {
        let tilt = player.settings.tilt
        if tilt < -0.15 { return "Warm" }
        if tilt > 0.15 { return "Bright" }
        return "Flat"
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Playback").padding(.bottom, 4)

            SettingRow(
                title: "Mix with other audio",
                detail: "Let a podcast or another app play alongside."
            ) {
                toggle(
                    isOn: player.settings.mixWithOtherAudio,
                    set: {
                        player.settings.mixWithOtherAudio = $0
                        player.settings.save()
                        player.reconfigureSession()
                    }
                )
            }
            Hairline()

            SettingRow(
                title: "Pause when unplugged",
                detail: "Stop instead of switching to the speaker."
            ) {
                toggle(
                    isOn: player.settings.pauseOnDisconnect,
                    set: {
                        player.settings.pauseOnDisconnect = $0
                        player.settings.save()
                    }
                )
            }
            Hairline()
        }
    }

    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Interface").padding(.bottom, 4)

            SettingRow(
                title: "Dim while playing",
                detail: "Fades the screen down after \(Int(player.settings.autoDimSeconds)) seconds of no touches."
            ) {
                toggle(
                    isOn: player.settings.autoDim,
                    set: {
                        player.settings.autoDim = $0
                        player.settings.save()
                    }
                )
            }
            Hairline()

            SettingRow(title: "Haptics", detail: nil) {
                toggle(
                    isOn: player.settings.hapticsEnabled,
                    set: {
                        player.settings.hapticsEnabled = $0
                        player.settings.save()
                    }
                )
            }
            Hairline()
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Health").padding(.bottom, 4)

            SettingRow(
                title: "Write nights to Health",
                detail: healthDetail
            ) {
                toggle(
                    isOn: player.settings.writeToHealth,
                    set: { newValue in
                        player.settings.writeToHealth = newValue
                        player.settings.save()
                        healthRefused = false
                        guard newValue else { return }
                        Task {
                            let granted = await HealthWriter.requestAuthorization()
                            if !granted {
                                player.settings.writeToHealth = false
                                player.settings.save()
                                healthRefused = true
                            }
                        }
                    }
                )
                .disabled(!HealthWriter.isAvailable)
                .opacity(HealthWriter.isAvailable ? 1 : 0.4)
            }
            Hairline()
        }
    }

    private var healthDetail: String {
        if !HealthWriter.isAvailable {
            return "Not available on this device."
        }
        if healthRefused {
            // The HealthKit capability is off in this build by default. README
            // says how to turn it on; until then, be straight about it.
            return "Health declined the request. Turn on the HealthKit capability for the app target in Xcode, then try again."
        }
        return "Mirrors each session as sleep data. Off by default."
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("About")

            Text("""
            Most sounds in Hush are generated as they play, a sample at a time. \
            Those never loop, because there is nothing to loop. The Recordings \
            shelf is real audio, joined end to end with a crossfade.

            Nothing you do here leaves your phone.
            """)
                .font(Typeface.body(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Version")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                Text(Self.versionString)
                    .font(Typeface.meta(11))
                    .foregroundStyle(Palette.inkFaint)
            }

            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Text("Clear journal")
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.emberDeep)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func toggle(isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { isOn }, set: set))
            .toggleStyle(WarmToggleStyle())
            .labelsHidden()
    }
}
