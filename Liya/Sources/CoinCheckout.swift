import Foundation
import Combine
import StoreKit
import Supabase

/// Implementations must verify Apple's signed transaction on the server and
/// return only after an idempotent credit for this account has committed.
@MainActor
protocol CoinSettlement: AnyObject {
    var accountID: UUID { get }
    var environment: AppStore.Environment { get }
    func deliver(signedTransaction: String, productID: String) async throws
}

@MainActor
final class CoinCheckout: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private var checkingConnection = false
    @Published private var settlement: (any CoinSettlement)? = nil
    private var processing = Set<UInt64>()
    private var updatesTask: Task<Void, Never>?
    private var configurationGeneration = UUID()

    var canPurchase: Bool { settlement != nil && !busy && !checkingConnection }
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

    func clearConnection() {
        configurationGeneration = UUID()
        checkingConnection = false
        setSettlement(nil)
    }

    func refreshConnection(_ session: LiyaSession) async {
        let generation = UUID(); configurationGeneration = generation
        checkingConnection = true
        defer { if configurationGeneration == generation { checkingConnection = false } }
        guard let owner = session.userID else { setSettlement(nil); return }
        do {
            struct Status: Decodable { let code: String }
            let status: Status = try await session.client.functions.invoke(
                "liya-apple-coins", options: FunctionInvokeOptions(body: ["action": "status"])
            )
            guard status.code == "ready", case let .verified(appTransaction) = try await AppTransaction.shared,
                  appTransaction.bundleID == Bundle.main.bundleIdentifier,
                  appTransaction.environment == .production || appTransaction.environment == .sandbox,
                  session.userID == owner, configurationGeneration == generation else {
                if configurationGeneration == generation { setSettlement(nil) }
                return
            }
            let sandbox = appTransaction.environment == .sandbox
            guard await session.configurePurchaseWallet(sandbox: sandbox, owner: owner),
                  session.userID == owner, configurationGeneration == generation else {
                if configurationGeneration == generation { setSettlement(nil) }
                return
            }
            setSettlement(CloudCoinSettlement(session: session, owner: owner, environment: appTransaction.environment))
        } catch {
            if session.userID == owner && configurationGeneration == generation { setSettlement(nil) }
        }
    }

    func purchase(_ product: Product, pack: CoinPackage) async {
        guard let account = settlement?.accountID, !busy, !checkingConnection,
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
        guard let settlement, transaction.appAccountToken == settlement.accountID,
              transaction.environment == settlement.environment else {
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

@MainActor
private final class CloudCoinSettlement: CoinSettlement {
    private let session: LiyaSession
    let accountID: UUID
    let environment: AppStore.Environment

    init(session: LiyaSession, owner: UUID, environment: AppStore.Environment) {
        self.session = session; self.accountID = owner; self.environment = environment
    }

    func deliver(signedTransaction: String, productID: String) async throws {
        struct Response: Decodable { let code: String }
        guard session.userID == accountID else { throw SettlementError.accountChanged }
        let result: Response = try await session.client.functions.invoke("liya-apple-coins", options: FunctionInvokeOptions(body: [
            "signed_transaction": signedTransaction, "product_id": productID
        ]))
        guard result.code == "delivered", session.userID == accountID else { throw SettlementError.deliveryPending }
        await session.refreshWallet()
    }
    private enum SettlementError: Error { case accountChanged, deliveryPending }
}
