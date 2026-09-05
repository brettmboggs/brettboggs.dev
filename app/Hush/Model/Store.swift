import Foundation
import Observation
import StoreKit

/// StoreKit 2, one non-consumable, no subscription.
///
/// The entire commercial model is a single lifetime unlock. That is a deliberate
/// position in a category where the going rate is sixty dollars a year for white
/// noise: price it once, price it low, keep the free tier good enough to
/// recommend, and make it up on volume.
@Observable
final class Store {
    static let proProductID = "dev.brettboggs.hush.pro"

    private(set) var product: Product?
    private(set) var isPro = false
    private(set) var isPurchasing = false
    private(set) var loadFailed = false

    /// Localized price, or a sensible placeholder until the store answers.
    var displayPrice: String { product?.displayPrice ?? "$4.99" }

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
        Task { await loadProduct() }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Catalogue

    func loadProduct() async {
        do {
            let found = try await Product.products(for: [Store.proProductID])
            await MainActor.run {
                self.product = found.first
                self.loadFailed = found.isEmpty
            }
        } catch {
            NSLog("Hush: could not load products: \(error.localizedDescription)")
            await MainActor.run { self.loadFailed = true }
        }
    }

    // MARK: - Entitlement

    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Store.verify(result) else { continue }
            if transaction.productID == Store.proProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        await MainActor.run { self.isPro = owned }
    }

    // MARK: - Purchase

    enum PurchaseOutcome {
        case unlocked
        case cancelled
        case pending
        case failed(String)
    }

    func purchase() async -> PurchaseOutcome {
        guard let product else {
            return .failed("The store is not reachable right now.")
        }
        await MainActor.run { self.isPurchasing = true }
        defer { Task { @MainActor in self.isPurchasing = false } }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Store.verify(verification)
                await transaction.finish()
                await refresh()
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
            return isPro ? .unlocked : .failed("No previous purchase found on this Apple Account.")
        } catch {
            return .failed(error.localizedDescription)
        }
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
