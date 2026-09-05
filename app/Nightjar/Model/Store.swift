import CryptoKit
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

    /// Plus from an actual App Store transaction.
    private(set) var isEntitled = false
    /// Plus from the owner's unlock code. Kept apart from `isEntitled` so the
    /// paywall, the receipts and the restore flow never confuse the two.
    private(set) var isUnlocked = Store.loadUnlock()

    var isPlus: Bool { isEntitled || isUnlocked }

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
            self.isEntitled = plus
            self.isLifetime = lifetime
        }
    }

    // MARK: - Owner's unlock

    /// Brett's own copy. The app is his; he should not have to buy it back on
    /// every device, and comping himself through the store would mean paying
    /// Apple's cut on his own work.
    ///
    /// Only the hash lives here because this repository is public. The code
    /// itself is not written down in it.
    private static let unlockSalt = "slumbio.unlock.v1"
    private static let unlockDigest =
        "4a7e67de40357b026e92c5d1d4c18901325967934f7c3ee467da3fb8a59118d1"
    private static let unlockDefaultsKey = "plus.unlocked"

    private static func loadUnlock() -> Bool {
        UserDefaults.standard.bool(forKey: unlockDefaultsKey)
    }

    private static func digest(of code: String) -> String {
        let normalised = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let data = Data((unlockSalt + normalised).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns true when the code was right. Wrong codes change nothing.
    @discardableResult
    func redeem(_ code: String) -> Bool {
        guard Store.digest(of: code) == Store.unlockDigest else { return false }
        UserDefaults.standard.set(true, forKey: Store.unlockDefaultsKey)
        isUnlocked = true
        return true
    }

    func revokeUnlock() {
        UserDefaults.standard.set(false, forKey: Store.unlockDefaultsKey)
        isUnlocked = false
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
            // Deliberately isEntitled, not isPlus: an unlock code is not a
            // purchase, and "restored" would be a lie.
            return isEntitled ? .unlocked : .failed("No previous purchase found on this Apple Account.")
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
