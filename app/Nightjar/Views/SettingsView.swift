import SwiftUI

struct SettingsView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var restoreMessage: String?
    @State private var isRedeeming = false
    @State private var redeemField = ""
    @State private var redeemFailed = false

    private let privacyURL = URL(string: "https://brettboggs.dev/slumbio/privacy/")!
    private let termsURL = URL(string: "https://brettboggs.dev/slumbio/terms/")!
    private let supportURL = URL(string: "https://brettboggs.dev/slumbio/")!

    var body: some View {
        @Bindable var settings = player.settings

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(title: "Settings", onClose: { dismiss() })

                plusRow
                    .padding(.top, 22)

                SectionLabel("Sound")
                    .padding(.top, 28)
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Volume", trailing: "\(Int(settings.masterVolume * 100))")
                        .padding(.top, 10)
                    FaderBar(value: settings.masterVolume) { value in
                        settings.masterVolume = value
                        player.commitMasterVolume()
                    } onCommit: {
                        settings.save()
                    }
                    SectionLabel("Warm · Bright", trailing: tiltLabel)
                        .padding(.top, 6)
                    FaderBar(value: (settings.tilt + 1) / 2, tint: Palette.rose) { value in
                        settings.tilt = value * 2 - 1
                        player.commitTilt()
                    } onCommit: {
                        settings.save()
                    }
                }
                Hairline()
                    .padding(.top, 6)
                SettingRow(title: "Fade in", detail: "Seconds to full volume on play.") {
                    ChoiceRow(
                        options: [(2.0, "2"), (6.0, "6"), (15.0, "15"), (30.0, "30")],
                        selection: settings.fadeInSeconds
                    ) { choice in
                        settings.fadeInSeconds = choice
                        settings.save()
                    }
                    .frame(width: 190)
                }
                Hairline()
                SettingRow(title: "Mix with other audio", detail: "Let a podcast or another app play alongside.") {
                    Toggle("", isOn: Binding(
                        get: { settings.mixWithOtherAudio },
                        set: { settings.mixWithOtherAudio = $0; settings.save(); player.reconfigureSession() }
                    ))
                    .toggleStyle(WarmToggleStyle())
                    .labelsHidden()
                }
                Hairline()
                SettingRow(title: "Pause when headphones unplug") {
                    Toggle("", isOn: Binding(
                        get: { settings.pauseOnDisconnect },
                        set: { settings.pauseOnDisconnect = $0; settings.save() }
                    ))
                    .toggleStyle(WarmToggleStyle())
                    .labelsHidden()
                }
                Hairline()

                SectionLabel("Screen")
                    .padding(.top, 28)
                SettingRow(title: "Dim after a while", detail: "The screen settles down once you stop touching it.") {
                    Toggle("", isOn: Binding(
                        get: { settings.autoDim },
                        set: { settings.autoDim = $0; settings.save() }
                    ))
                    .toggleStyle(WarmToggleStyle())
                    .labelsHidden()
                }
                Hairline()
                SettingRow(title: "Softer glow", detail: "Turns the light down on every screen.") {
                    Toggle("", isOn: Binding(
                        get: { settings.reduceGlow },
                        set: { settings.reduceGlow = $0; settings.save() }
                    ))
                    .toggleStyle(WarmToggleStyle())
                    .labelsHidden()
                }
                Hairline()
                SettingRow(title: "Haptics") {
                    Toggle("", isOn: Binding(
                        get: { settings.hapticsEnabled },
                        set: { settings.hapticsEnabled = $0; settings.save() }
                    ))
                    .toggleStyle(WarmToggleStyle())
                    .labelsHidden()
                }
                Hairline()

                SectionLabel("About")
                    .padding(.top, 28)
                Link(destination: privacyURL) {
                    IndexRow(title: "Privacy", detail: "No account, no analytics, no network. Everything stays on the phone.") {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                .buttonStyle(.plain)
                Hairline()
                Link(destination: termsURL) {
                    IndexRow(title: "Terms") {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                .buttonStyle(.plain)
                Hairline()
                Link(destination: supportURL) {
                    IndexRow(title: "Help", detail: "Write to Brett. He reads all of it.") {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                .buttonStyle(.plain)
                Hairline()

                // Long-press is the whole entry point. Deliberately invisible:
                // it is the owner's key, not a feature, and nothing on screen
                // should read as a way around paying.
                Text(versionLine)
                    .font(Typeface.meta(11))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.top, 24)
                    .onLongPressGesture(minimumDuration: 1.5) {
                        guard !player.store.isUnlocked else { return }
                        redeemField = ""
                        redeemFailed = false
                        isRedeeming = true
                        Haptics.tap(enabled: player.settings.hapticsEnabled)
                    }

                Color.clear.frame(height: 30)
            }
            .pageGutter()
        }
        .sheetDressing()
        .paywallHost()
        .alert("Unlock", isPresented: $isRedeeming) {
            TextField("Code", text: $redeemField)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { redeemField = "" }
            Button("Unlock") {
                if player.store.redeem(redeemField) {
                    Haptics.success(enabled: player.settings.hapticsEnabled)
                } else {
                    redeemFailed = true
                }
                redeemField = ""
            }
        } message: {
            Text(redeemFailed ? "That code did not work." : "")
        }
    }

    private var plusDetail: String {
        let store = player.store
        if store.isUnlocked && !store.isEntitled { return "Unlocked on this phone." }
        if store.isLifetime { return "Yours for good. Thank you." }
        return "Manage or cancel in Settings › Apple Account › Subscriptions."
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "Slumbio \(version) (\(build))"
    }

    private var tiltLabel: String {
        let value = Int((player.settings.tilt * 10).rounded())
        if value == 0 { return "Flat" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private var plusRow: some View {
        let store = player.store
        return VStack(alignment: .leading, spacing: 0) {
            if player.plan.isPlus {
                HStack(spacing: 12) {
                    OrbMark(size: 26, isLit: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Slumbio Plus")
                            .font(Typeface.body(16, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(plusDetail)
                            .font(Typeface.body(12))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.raised.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 1)
                )
            } else {
                Button {
                    player.requestUpgrade(.direct)
                } label: {
                    HStack(spacing: 12) {
                        OrbMark(size: 26, isLit: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Slumbio Plus")
                                .font(Typeface.body(16, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Text("Every sound, every pattern, and the mornings.")
                                .font(Typeface.body(12))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Palette.raised.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        let outcome = await store.restore()
                        await MainActor.run {
                            switch outcome {
                            case .unlocked: restoreMessage = "Plus is back."
                            case .failed(let text): restoreMessage = text
                            case .cancelled, .pending: restoreMessage = nil
                            }
                        }
                    }
                } label: {
                    Text(restoreMessage ?? "Restore a previous purchase")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.top, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
