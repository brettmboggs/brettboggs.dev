import StoreKit
import SwiftUI

struct PaywallView: View {
    let reason: PaywallReason

    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var message: String?
    @State private var didUnlock = false

    private var store: Store { player.entitlements.store }

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            BreathingBackdrop(level: 0.2, isPlaying: true, intensity: 0.55)
                .allowsHitTesting(false)

            if didUnlock {
                unlocked
            } else {
                offer
            }
        }
        .presentationBackground(Palette.ground)
        .animation(.settleSlow, value: didUnlock)
    }

    // MARK: - Offer

    private var offer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Palette.raised))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

            Spacer(minLength: 12)

            Text(reason.headline)
                .font(Typeface.display(38))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(reason.line)
                .font(Typeface.body(15))
                .foregroundStyle(Palette.inkSoft)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 22)

            VStack(spacing: 0) {
                ForEach(ProFeature.allCases) { feature in
                    row(feature)
                    if feature != ProFeature.allCases.last { Hairline(inset: 32) }
                }
            }

            Spacer(minLength: 22)

            if let message {
                Text(message)
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.emberDeep)
                    .padding(.bottom, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buyButton

            Text("One payment. Yours forever, on every device you sign in to, and shareable with your family. There is no subscription and there never will be.")
                .font(Typeface.body(12))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            Button {
                Task { await handle(store.restore()) }
            } label: {
                Text("Restore a previous purchase")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing)
            .padding(.bottom, 8)
        }
        .pageGutter()
    }

    private func row(_ feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.symbol)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Palette.ember)
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(Typeface.body(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(feature.detail)
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    private var buyButton: some View {
        Button {
            Task { await handle(store.purchase()) }
        } label: {
            ZStack {
                Capsule().fill(Palette.ember)
                if store.isPurchasing {
                    ProgressView()
                        .tint(Palette.ground)
                } else {
                    HStack(spacing: 8) {
                        Text("Unlock everything")
                        Text(store.displayPrice)
                            .foregroundStyle(Palette.ground.opacity(0.7))
                    }
                    .font(Typeface.body(16, weight: .semibold))
                    .foregroundStyle(Palette.ground)
                }
            }
            .frame(height: 54)
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing || store.loadFailed)
        .opacity(store.loadFailed ? 0.45 : 1)
    }

    // MARK: - Unlocked

    private var unlocked: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.ground)
                .frame(width: 74, height: 74)
                .background(Circle().fill(Palette.ember))

            Text("Thank you")
                .font(Typeface.display(34))
                .foregroundStyle(Palette.ink)

            Text("Everything is open. Sleep well.")
                .font(Typeface.body(15))
                .foregroundStyle(Palette.inkSoft)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(Typeface.body(16, weight: .semibold))
                    .foregroundStyle(Palette.ground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Palette.ember))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .pageGutter()
        .transition(.opacity)
    }

    // MARK: - Outcome

    private func handle(_ outcome: Store.PurchaseOutcome) async {
        switch outcome {
        case .unlocked:
            Haptics.success(enabled: player.settings.hapticsEnabled)
            message = nil
            didUnlock = true
        case .cancelled:
            message = nil
        case .pending:
            message = "That needs approval before it can finish. Hush will unlock on its own once it clears."
        case .failed(let reason):
            message = reason
        }
    }
}
