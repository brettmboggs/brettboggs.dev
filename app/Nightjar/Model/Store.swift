import Foundation
import Observation
import StoreKit

/// StoreKit 2. Three ways to pay for the same thing.
///
/// Yearly is the one most people should pick, and it carries the free week.
/// Monthly exists so that yearly has something to be cheaper than. Lifetime is
/// for people who will not subscribe to anything, and it is family-shareable.
/// All three unlock the identical `isPlus`.
@Observable
final class Store {
    enum ProductID {
        static let monthly = "dev.brettboggs.nightjar.plus.monthly"
        static let yearly = "dev.brettboggs.nightjar.plus.yearly"
        static let lifetime = "dev.brettboggs.nightjar.plus.lifetime"
        static let all: [String] = [monthly, yearly, lifetime]
    }

    private(set) var monthly: Product?
    private(set) var yearly: Product?
    private(set) var lifetime: Product?

    private(set) var isPlus = false
    /// True when Plus came from a lifetime purchase rather than a subscription.
    private(set) var isLifetime = false
    /// True when the yearly plan has never been tried on this Apple Account.
    private(set) var yearlyTrialAvailable = false
    private(set) var isPurchasing = false
    private(set) var loadFailed = false
    private(set) var didLoad = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        // Must start before any purchase so an interrupted or Ask-to-Buy
        // transaction is still picked up when it completes.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let transaction = try? Store.verify(update) {
                    await transaction.finish()
                    await self.refresh()
                }
            }
        }
        Task { await refresh() }
        Task { await loadProducts() }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Catalogue

    func loadProducts() async {
        do {
            let found = try await Product.products(for: ProductID.all)
            let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
            let yearlyProduct = byID[ProductID.yearly]
            var trial = false
            if let subscription = yearlyProduct?.subscription,
               subscription.introductoryOffer != nil {
                trial = await subscription.isEligibleForIntroOffer
            }
            let trialAvailable = trial
            let monthlyProduct = byID[ProductID.monthly]
            let lifetimeProduct = byID[ProductID.lifetime]
            let nothingFound = found.isEmpty
            await MainActor.run {
                self.monthly = monthlyProduct
                self.yearly = yearlyProduct
                self.lifetime = lifetimeProduct
                self.yearlyTrialAvailable = trialAvailable
                self.loadFailed = nothingFound
                self.didLoad = true
            }
        } catch {
            NSLog("Slumbio: could not load products: \(error.localizedDescription)")
            await MainActor.run {
                self.loadFailed = true
                self.didLoad = true
            }
        }
    }

    // MARK: - Entitlement

    func refresh() async {
        var owned = false
        var lifetimeOwned = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Store.verify(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if transaction.productID == ProductID.lifetime {
                owned = true
                lifetimeOwned = true
            } else if ProductID.all.contains(transaction.productID) {
                owned = true
            }
        }
        let plus = owned
        let lifetime = lifetimeOwned
        await MainActor.run {
            self.isPlus = plus
            self.isLifetime = lifetime
        }
    }

    // MARK: - Purchase

    enum PurchaseOutcome {
        case unlocked
        case cancelled
        case pending
        case failed(String)
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        await MainActor.run { self.isPurchasing = true }
        defer { Task { @MainActor in self.isPurchasing = false } }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Store.verify(verification)
                await transaction.finish()
                await refresh()
                await scheduleTrialReminderIfNeeded(for: product)
                return .unlocked
            case .userCancelled:
                return .cancelled
            case .pending:
                // Ask to Buy, or an interrupted payment. Transaction.updates
                // will unlock it when it clears.
                return .pending
            @unknown default:
                return .failed("The purchase did not complete.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async -> PurchaseOutcome {
        await MainActor.run { self.isPurchasing = true }
        defer { Task { @MainActor in self.isPurchasing = false } }
        do {
            try await AppStore.sync()
            await refresh()
            return isPlus ? .unlocked : .failed("No previous purchase found on this Apple Account.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// A reminder two days before a free week turns into a charge. Apple
    /// nudges people at day five as well; saying it ourselves is cheaper than
    /// a refund and reads as honest.
    private func scheduleTrialReminderIfNeeded(for product: Product) async {
        guard product.id == ProductID.yearly, yearlyTrialAvailable else { return }
        let fireAt = Date().addingTimeInterval(5 * 24 * 60 * 60)
        await Reminders.scheduleTrialEnding(at: fireAt)
    }

    // MARK: - Display

    /// "$1.67" per month, worked out from the yearly price.
    var yearlyPerMonth: String? {
        guard let yearly else { return nil }
        let perMonth = yearly.price / 12
        return perMonth.formatted(yearly.priceFormatStyle)
    }

    /// Whole-number percent saved by paying yearly instead of monthly.
    var yearlySavingPercent: Int? {
        guard let yearly, let monthly, monthly.price > 0 else { return nil }
        let monthlyForYear = monthly.price * 12
        guard monthlyForYear > yearly.price else { return nil }
        let saved = (monthlyForYear - yearly.price) / monthlyForYear * 100
        return Int((saved as NSDecimalNumber).doubleValue.rounded())
    }

    // MARK: - Verification

    private static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.notEntitled
        case .verified(let safe):
            return safe
        }
    }
}
