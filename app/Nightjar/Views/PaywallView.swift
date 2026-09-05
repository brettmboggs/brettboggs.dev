import StoreKit
import SwiftUI

/// Three ways in. Yearly is preselected and carries the free week; monthly
/// makes it look cheap; lifetime is there for people who will not subscribe.
/// No countdowns, no fake scarcity, and the free tier is named on the page.
struct PaywallView: View {
    enum Choice: Hashable {
        case monthly, yearly, lifetime
    }

    let reason: PaywallReason

    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var choice: Choice = .yearly
    @State private var message: String?
    @State private var didUnlock = false

    private var store: Store { player.store }

    private let privacyURL = URL(string: "https://brettboggs.dev/slumbio/privacy/")!
    private let termsURL = URL(string: "https://brettboggs.dev/slumbio/terms/")!

    var body: some View {
        ZStack {
            LivingCanvas(energy: 0.15, intensity: 0.7, rim: 0.12, centerY: 0.12, frameRate: 24)

            if didUnlock {
                unlocked
            } else {
                offer
            }
        }
        .sheetDressing()
        .animation(.settleSlow, value: didUnlock)
    }

    // MARK: - Offer

    private var offer: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    IconButton(systemImage: "xmark", size: 32) { dismiss() }
                }
                .padding(.top, 18)

                Spacer().frame(height: 60)

                Text(reason.headline)
                    .font(Typeface.display(36))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(reason.line)
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(PlusFeature.allCases) { feature in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: feature.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Palette.ember)
                                .frame(width: 22)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
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
                        .padding(.vertical, 9)
                    }
                }
                .padding(.top, 24)

                plans
                    .padding(.top, 24)

                SoftButton(title: buttonTitle, isProminent: true, isWide: true) {
                    buy()
                }
                .padding(.top, 18)
                .disabled(store.isPurchasing || selectedProduct == nil)
                .opacity(store.isPurchasing || selectedProduct == nil ? 0.6 : 1)

                Text(finePrint)
                    .font(Typeface.body(11))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                if let message {
                    Text(message)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.ember)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }

                HStack(spacing: 18) {
                    Button("Restore") { restore() }
                    Link("Privacy", destination: privacyURL)
                    Link("Terms", destination: termsURL)
                    Spacer()
                    Button("Not now") { dismiss() }
                }
                .font(Typeface.body(13))
                .foregroundStyle(Palette.inkFaint)
                .buttonStyle(.plain)
                .padding(.top, 18)

                Text("Twelve sounds, two layers, the timer, two breathing patterns and every tip stay free, forever.")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
            }
            .pageGutter()
        }
    }

    private var plans: some View {
        VStack(spacing: 8) {
            if let yearly = store.yearly {
                planRow(
                    .yearly,
                    title: "Yearly",
                    price: yearly.displayPrice + " / year",
                    detail: yearlyDetail,
                    badge: "Best value"
                )
            }
            if let lifetime = store.lifetime {
                planRow(
                    .lifetime,
                    title: "Lifetime",
                    price: lifetime.displayPrice + " once",
                    detail: "Pay once, keep it. Shares with your family.",
                    badge: nil
                )
            }
            if let monthly = store.monthly {
                planRow(
                    .monthly,
                    title: "Monthly",
                    price: monthly.displayPrice + " / month",
                    detail: "Cancel any time.",
                    badge: nil
                )
            }
            if store.didLoad && store.yearly == nil && store.lifetime == nil && store.monthly == nil {
                Text("The App Store is not answering right now. Try again in a moment.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.vertical, 20)
            }
            if !store.didLoad {
                ProgressView()
                    .tint(Palette.inkSoft)
                    .padding(.vertical, 20)
            }
        }
    }

    private var yearlyDetail: String {
        var parts: [String] = []
        if let perMonth = store.yearlyPerMonth { parts.append("\(perMonth) a month") }
        if let saving = store.yearlySavingPercent { parts.append("save \(saving)%") }
        if store.yearlyTrialAvailable { parts.insert("First week free", at: 0) }
        return parts.joined(separator: " · ")
    }

    private func planRow(_ value: Choice, title: String, price: String, detail: String, badge: String?) -> some View {
        let isSelected = choice == value
        return Button {
            withAnimation(.settle) { choice = value }
            Haptics.tap(enabled: player.settings.hapticsEnabled)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Circle()
                    .strokeBorder(isSelected ? Palette.ember : Palette.hairline, lineWidth: isSelected ? 6 : 1.5)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(Typeface.body(16, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        if let badge {
                            Text(badge.uppercased())
                                .font(Typeface.meta(9, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(Palette.ground)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Palette.ember))
                        }
                    }
                    Text(detail)
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(price)
                    .font(Typeface.meta(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Palette.raisedHigh : Palette.raised.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Palette.ember.opacity(0.7) : Palette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var selectedProduct: Product? {
        switch choice {
        case .monthly: return store.monthly
        case .yearly: return store.yearly
        case .lifetime: return store.lifetime
        }
    }

    private var buttonTitle: String {
        if store.isPurchasing { return "One moment" }
        switch choice {
        case .yearly: return store.yearlyTrialAvailable ? "Start the free week" : "Continue with yearly"
        case .monthly: return "Continue with monthly"
        case .lifetime: return "Buy once"
        }
    }

    private var finePrint: String {
        switch choice {
        case .yearly:
            let price = store.yearly?.displayPrice ?? ""
            if store.yearlyTrialAvailable {
                return "Free for 7 days, then \(price) a year. Renews automatically until cancelled, at least a day before the period ends. Cancel any time in Settings › Apple Account › Subscriptions. We will remind you two days before the week is up."
            }
            return "\(price) a year. Renews automatically until cancelled, at least a day before the period ends. Cancel any time in Settings › Apple Account › Subscriptions."
        case .monthly:
            let price = store.monthly?.displayPrice ?? ""
            return "\(price) a month. Renews automatically until cancelled, at least a day before the period ends. Cancel any time in Settings › Apple Account › Subscriptions."
        case .lifetime:
            return "One payment. No renewal. Family Sharing included."
        }
    }

    // MARK: - Actions

    private func buy() {
        guard let product = selectedProduct else { return }
        message = nil
        Task {
            let outcome = await store.purchase(product)
            await MainActor.run {
                switch outcome {
                case .unlocked:
                    didUnlock = true
                    Haptics.success(enabled: player.settings.hapticsEnabled)
                case .cancelled:
                    break
                case .pending:
                    message = "Waiting on approval. Plus unlocks as soon as it clears."
                case .failed(let text):
                    message = text
                }
            }
        }
    }

    private func restore() {
        message = nil
        Task {
            let outcome = await store.restore()
            await MainActor.run {
                switch outcome {
                case .unlocked: didUnlock = true
                case .failed(let text): message = text
                case .cancelled, .pending: break
                }
            }
        }
    }

    // MARK: - Unlocked

    private var unlocked: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Plus")
                .font(Typeface.display(44))
                .foregroundStyle(Palette.ink)
            Text("Everything is open. Sleep well.")
                .font(Typeface.body(15))
                .foregroundStyle(Palette.inkSoft)
            Spacer()
            SoftButton(title: "Back to it", isProminent: true, isWide: true) { dismiss() }
                .pageGutter()
                .padding(.bottom, 30)
        }
    }
}
