import Foundation
import Combine
import StoreKit

@MainActor
final class CoinCheckout: NSObject, ObservableObject {
    struct WelcomeGift: Identifiable {
        let id = UUID()
        static let coins = 600
    }

    enum Appearance: String, Identifiable {
        case moodPrism, profileGlow, tideglassPaper

        var id: String { rawValue }
        var title: String {
            switch self {
            case .moodPrism: return "Mood Prism"
            case .profileGlow: return "Profile Glow"
            case .tideglassPaper: return "Tideglass paper"
            }
        }
        var cost: Int64 {
            switch self {
            case .moodPrism: return 120
            case .profileGlow: return 180
            case .tideglassPaper: return 90
            }
        }
    }

    @Published private(set) var loadingProductID: String?
    @Published private(set) var productLoadFailed = false
    @Published private(set) var message: String?
    @Published private(set) var walletError: String?
    @Published private(set) var welcomeGift: WelcomeGift?
    @Published private var wallet: CoinWalletLedger?
    @Published private var store = CoinWalletLedger.currentStore
    @Published private var products: [String: SKProduct] = [:]
    @Published private var submittedPack: String?
    @Published private var purchasing: Set<String> = []
    @Published private var deferred: Set<String> = []
    @Published private var undelivered: Set<String> = []

    private let queue = SKPaymentQueue.default()
    private var productRequest: SKProductsRequest?
    private var receiptRequest: SKReceiptRefreshRequest?
    private var walletNeedsReceipt = false
    private var selectedPack: CoinPackage?
    private var finishing: Set<ObjectIdentifier> = []

    var balance: Int64? { wallet?.balance(in: store) }
    var busy: Bool { submittedPack != nil || !purchasing.isEmpty }

    override init() {
        super.init()
        loadWallet()
        queue.delegate = self
        queue.add(self)
    }

    deinit {
        queue.remove(self)
        productRequest?.cancel()
        receiptRequest?.cancel()
    }

    func loadProduct(_ pack: CoinPackage) {
        selectedPack = pack
        productRequest?.cancel()
        products[pack.id] = nil
        productLoadFailed = false
        loadingProductID = pack.id
        let request = SKProductsRequest(productIdentifiers: [pack.id])
        request.delegate = self
        productRequest = request
        request.start()
    }

    func cancelProductRequest(for pack: CoinPackage) {
        guard selectedPack?.id == pack.id else { return }
        selectedPack = nil
        productRequest?.cancel()
        productRequest = nil
        loadingProductID = nil
        productLoadFailed = false
    }

    func displayPrice(for pack: CoinPackage) -> String? {
        guard let product = products[pack.id] else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price)
    }

    func isAwaitingApproval(_ pack: CoinPackage) -> Bool { deferred.contains(pack.id) }

    func isAwaitingDelivery(_ pack: CoinPackage) -> Bool { undelivered.contains(pack.id) }

    func canPurchase(_ pack: CoinPackage) -> Bool {
        wallet != nil && walletError == nil && !busy && SKPaymentQueue.canMakePayments()
            && selectedPack?.id == pack.id && loadingProductID == nil && !productLoadFailed
            && products[pack.id] != nil && !deferred.contains(pack.id) && !undelivered.contains(pack.id)
    }

    func purchase(_ pack: CoinPackage) {
        guard canPurchase(pack), let wallet, let product = products[pack.id] else { return }
        let payment = SKMutablePayment(product: product)
        payment.applicationUsername = wallet.token.uuidString
        submittedPack = pack.id
        message = nil
        queue.add(payment)
    }

    func recover(showIssues: Bool = false) {
        if showIssues { clearMessage() }
        store = CoinWalletLedger.currentStore
        if wallet == nil || walletError != nil { loadWallet() }
        let outstanding = queue.transactions
        handle(outstanding)
        if showIssues && receiptRequest == nil && (walletNeedsReceipt || (CoinWalletLedger.transactionStore == nil && !undelivered.isEmpty)) {
            let request = SKReceiptRefreshRequest(receiptProperties: nil)
            receiptRequest = request
            request.delegate = self
            request.start()
        }
        if showIssues, walletError == nil, message == nil, !busy {
            if !undelivered.isEmpty {
                message = "Your purchase is pending delivery."
            } else if !deferred.isEmpty {
                message = "Awaiting approval."
            } else {
                message = "Your balance is up to date."
            }
        }
    }

    func clearMessage() {
        if !busy { message = nil }
    }

    func owns(_ appearance: Appearance) -> Bool { wallet?.owns(appearance, in: store) == true }

    func isActive(_ appearance: Appearance) -> Bool { wallet?.isActive(appearance, in: store) == true }

    func select(_ appearance: Appearance) {
        guard var updated = wallet, walletError == nil, !busy else { return }
        let wasActive = updated.isActive(appearance, in: store)
        do {
            try updated.select(appearance, in: store)
            if save(updated) { message = wasActive ? "Appearance turned off." : "Appearance applied." }
        } catch CoinWalletLedger.Failure.insufficientFunds {
            message = "You don't have enough coins for this appearance."
        } catch {
            walletError = "Your balance couldn’t be saved."
        }
    }

    func acknowledgeWelcome() -> Bool {
        guard var updated = wallet else { return false }
        updated.welcomePending = false
        guard save(updated) else { return false }
        welcomeGift = nil
        return true
    }

    private func loadWallet() {
        walletNeedsReceipt = false
        do {
            let saved = try CoinWalletLedger.load()
            wallet = saved
            walletError = nil
            if saved.welcomePending && welcomeGift == nil { welcomeGift = WelcomeGift() }
        } catch CoinWalletLedger.Failure.storeNotIdentified {
            walletNeedsReceipt = true
            wallet = nil
            walletError = "Please try opening your wallet again."
        } catch {
            wallet = nil
            walletError = "Please try opening your wallet again."
        }
    }

    private func save(_ updated: CoinWalletLedger) -> Bool {
        do {
            try updated.save()
            wallet = updated
            walletError = nil
            return true
        } catch {
            walletError = "Your balance couldn’t be saved."
            return false
        }
    }

    private func handle(_ transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            guard let pack = CoinPackage.all.first(where: { $0.id == transaction.payment.productIdentifier }) else { continue }
            switch transaction.transactionState {
            case .purchasing:
                break
            case .deferred:
                if !deferred.contains(pack.id) { message = "Awaiting approval." }
                if submittedPack == pack.id { submittedPack = nil }
            case .purchased:
                if submittedPack == pack.id { submittedPack = nil }
                guard !finishing.contains(ObjectIdentifier(transaction)) else { continue }
                if deliver(transaction, pack: pack) { finish(transaction) }
            case .failed:
                if submittedPack == pack.id { submittedPack = nil }
                let error = transaction.error as NSError?
                if error?.domain != SKErrorDomain || error?.code != SKError.Code.paymentCancelled.rawValue {
                    message = "Please try your purchase again."
                }
                finish(transaction)
            case .restored:
                finish(transaction)
            @unknown default:
                break
            }
        }
        updateQueueState()
    }

    private func deliver(_ transaction: SKPaymentTransaction, pack: CoinPackage) -> Bool {
        guard var updated = wallet else { return false }
        guard let purchaseStore = CoinWalletLedger.transactionStore,
              let id = transaction.transactionIdentifier, !id.isEmpty else {
            message = "Your purchase is pending delivery."
            return false
        }
        store = purchaseStore
        if updated.credited(id, in: purchaseStore) { return true }
        if let username = transaction.payment.applicationUsername, !username.isEmpty,
           UUID(uuidString: username) != updated.token {
            message = "This purchase belongs to a different wallet."
            return false
        }
        let (coins, overflow) = Int64(pack.coins).multipliedReportingOverflow(by: Int64(transaction.payment.quantity))
        guard coins > 0, !overflow else {
            message = "Your purchase is pending delivery."
            return false
        }
        do {
            try updated.credit(coins, transactionID: id, in: purchaseStore)
        } catch {
            message = "Your purchase is pending delivery."
            return false
        }
        guard save(updated) else { return false }
        message = "Coins added to your wallet."
        return true
    }

    private func finish(_ transaction: SKPaymentTransaction) {
        if finishing.insert(ObjectIdentifier(transaction)).inserted { queue.finishTransaction(transaction) }
    }

    private func updateQueueState() {
        let transactions = queue.transactions
        purchasing = Set(transactions.filter { $0.transactionState == .purchasing }.map { $0.payment.productIdentifier })
        deferred = Set(transactions.filter { $0.transactionState == .deferred }.map { $0.payment.productIdentifier })
        undelivered = Set(transactions.filter { $0.transactionState == .purchased && !finishing.contains(ObjectIdentifier($0)) }
            .map { $0.payment.productIdentifier })
    }
}

extension CoinCheckout: SKProductsRequestDelegate {
    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.productRequest === request, let pack = self.selectedPack else { return }
            self.productRequest = nil
            self.loadingProductID = nil
            let product = response.products.first { $0.productIdentifier == pack.id }
            self.products[pack.id] = product
            self.productLoadFailed = product == nil
        }
    }

    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.productRequest === request {
                self.productRequest = nil
                self.loadingProductID = nil
                self.productLoadFailed = true
            } else if self.receiptRequest === request {
                self.receiptRequest = nil
                if !self.undelivered.isEmpty { self.message = "Your purchase is pending delivery." }
            }
        }
    }

    nonisolated func requestDidFinish(_ request: SKRequest) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.receiptRequest === request else { return }
            self.receiptRequest = nil
            self.loadWallet()
            self.recover()
        }
    }
}

extension CoinCheckout: SKPaymentTransactionObserver, SKPaymentQueueDelegate {
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        DispatchQueue.main.async { [weak self] in self?.handle(transactions) }
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for transaction in transactions { self.finishing.remove(ObjectIdentifier(transaction)) }
            self.updateQueueState()
        }
    }

    nonisolated func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.products.removeAll()
            if let pack = self.selectedPack { self.loadProduct(pack) }
        }
    }

    nonisolated func paymentQueue(_ paymentQueue: SKPaymentQueue, shouldContinue transaction: SKPaymentTransaction,
                                 in newStorefront: SKStorefront) -> Bool { false }
}
