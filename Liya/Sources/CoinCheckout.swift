import Foundation
import Combine
import StoreKit

/// Implementations must verify Apple's signed transaction on the server and
/// return only after an idempotent credit for this account has committed.
@MainActor
protocol CoinSettlement: AnyObject {
    var accountID: UUID { get }
    func deliver(signedTransaction: String, productID: String) async throws
}

@MainActor
final class CoinCheckout: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private var settlement: (any CoinSettlement)? = nil
    private var processing = Set<UInt64>()
    private var updatesTask: Task<Void, Never>?

    var canPurchase: Bool { settlement != nil && !busy }
    var isConnected: Bool { settlement != nil }

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.deliver(result)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func setSettlement(_ settlement: (any CoinSettlement)?) {
        self.settlement = settlement
        if settlement != nil { Task { await recover() } }
    }

    func purchase(_ product: Product, pack: CoinPackage) async {
        guard let account = settlement?.accountID, !busy,
              product.id == pack.id, product.type == .consumable else {
            message = "Purchase is unavailable. Please try again when your account is connected."
            return
        }
        busy = true; message = nil
        defer { busy = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(account)]) {
            case .success(let result):
                await deliver(result)
            case .pending:
                message = "Your purchase is awaiting Apple approval. Coins will be delivered after confirmation."
            case .userCancelled:
                message = "Purchase cancelled."
            @unknown default:
                message = "The purchase status is unavailable. Check your wallet later."
            }
        } catch {
            message = "The purchase could not be started. Please try again."
        }
    }

    func recover() async {
        guard settlement != nil else { return }
        for await result in Transaction.unfinished { await deliver(result) }
    }

    func hasUnfinishedPurchase(for account: UUID) async -> Bool {
        if busy { return true }
        for await result in Transaction.unfinished {
            switch result {
            case .verified(let transaction):
                if CoinPackage.all.contains(where: { $0.id == transaction.productID }) &&
                    (transaction.appAccountToken == nil || transaction.appAccountToken == account) { return true }
            case .unverified:
                return true
            }
        }
        return false
    }

    private func deliver(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            message = "Apple could not verify this transaction. It has not been delivered."
            return
        }
        guard transaction.productType == .consumable, transaction.revocationDate == nil,
              CoinPackage.all.contains(where: { $0.id == transaction.productID }) else { return }
        guard let settlement, transaction.appAccountToken == settlement.accountID else {
            message = "A purchase is waiting for its original account to reconnect."
            return
        }
        guard processing.insert(transaction.id).inserted else { return }
        defer { processing.remove(transaction.id) }
        do {
            try await settlement.deliver(signedTransaction: result.jwsRepresentation, productID: transaction.productID)
            await transaction.finish()
            message = "Coins delivered."
        } catch {
            // Keep the transaction unfinished for the original account to retry.
            message = "Payment is awaiting confirmation. Please return to the same account to retry."
        }
    }
}
