import Foundation
import Combine
import StoreKit

@MainActor
final class CoinCheckout: ObservableObject {
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

    private struct Wallet: Codable {
        var token = UUID()
        var transactions: [String: [String: Int64]] = [:]
        var welcomePending = true
        var appearances: [String: [String: Bool]] = [:]

        func credits(in environment: String) -> Int64 {
            guard let transactions = transactions[environment] else { return Int64(WelcomeGift.coins) }
            return transactions.values.reduce(Int64(WelcomeGift.coins), +)
        }

        func balance(in environment: String) -> Int64 {
            let purchased = appearances[environment]?.keys.compactMap(Appearance.init(rawValue:)) ?? []
            let spent = purchased.reduce(Int64(0)) { $0 + $1.cost }
            return max(0, credits(in: environment) - spent)
        }
    }

    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var walletError: String?
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var loadingProducts = false
    @Published private(set) var productLoadFailed = false
    @Published var welcomeGift: WelcomeGift?
    @Published private var wallet: Wallet?
    @Published private var environment = AppStore.Environment.production.rawValue

    private var updatesTask: Task<Void, Never>?
    private var recovering = false
    private var resolvingEnvironment = false
    private var finishing = Set<String>()

    var balance: Int64? { wallet?.balance(in: environment) }
    var canPurchase: Bool { wallet != nil && walletError == nil && !busy && AppStore.canMakePayments }

    init() {
        loadWallet()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.deliver(result)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        guard !loadingProducts else { return }
        loadingProducts = true
        productLoadFailed = false
        defer { loadingProducts = false }
        do {
            let available = try await Product.products(for: CoinPackage.all.map(\.id))
            guard !Task.isCancelled else { return }
            products = Dictionary(uniqueKeysWithValues: available.filter { $0.type == .consumable }.map { ($0.id, $0) })
        } catch {
            guard !Task.isCancelled else { return }
            products = [:]
            productLoadFailed = true
        }
    }

    func clearMessage() {
        guard !busy else { return }
        message = nil
    }

    func purchase(_ pack: CoinPackage) async {
        guard canPurchase, let wallet, let product = products[pack.id] else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(wallet.token)]) {
            case .success(let result):
                await deliver(result, showUnmatched: true)
            case .pending:
                message = "Your purchase is awaiting Apple approval."
            case .userCancelled:
                break
            @unknown default:
                message = "The purchase status is unavailable. Check your wallet later."
            }
        } catch {
            message = "The purchase could not be started. Please try again."
        }
    }

    func recover(showIssues: Bool = false) async {
        guard !recovering else { return }
        recovering = true
        defer { recovering = false }
        if showIssues { clearMessage() }
        if wallet == nil || walletError != nil { loadWallet() }
        guard wallet != nil else { return }
        for await result in Transaction.unfinished {
            await deliver(result, showUnmatched: showIssues)
        }
    }

    func identifyStore() async {
        guard !resolvingEnvironment else { return }
        resolvingEnvironment = true
        defer { resolvingEnvironment = false }
        if let result = try? await AppTransaction.shared, case .verified(let app) = result,
           app.bundleID == Bundle.main.bundleIdentifier {
            environment = app.environment.rawValue
        }
    }

    func owns(_ appearance: Appearance) -> Bool {
        wallet?.appearances[environment]?[appearance.rawValue] != nil
    }

    func isActive(_ appearance: Appearance) -> Bool {
        wallet?.appearances[environment]?[appearance.rawValue] == true
    }

    func select(_ appearance: Appearance) {
        guard var wallet, walletError == nil, !busy else { return }
        let current = wallet.appearances[environment]?[appearance.rawValue]
        if current == nil && wallet.balance(in: environment) < appearance.cost {
            message = "You don't have enough coins for this appearance."
            return
        }
        wallet.appearances[environment, default: [:]][appearance.rawValue] = current != true
        if save(wallet) {
            message = current == true ? "Appearance turned off." : "Appearance applied."
        }
    }

    func acknowledgeWelcome() -> Bool {
        guard var wallet else { return false }
        wallet.welcomePending = false
        guard save(wallet) else { return false }
        welcomeGift = nil
        return true
    }

    private func deliver(_ result: VerificationResult<Transaction>, showUnmatched: Bool = false) async {
        guard case .verified(let transaction) = result else {
            if showUnmatched { message = "Apple could not verify this purchase." }
            return
        }
        guard transaction.appBundleID == Bundle.main.bundleIdentifier,
              transaction.productType == .consumable,
              let pack = CoinPackage.all.first(where: { $0.id == transaction.productID }) else { return }
        guard var wallet, transaction.appAccountToken == wallet.token else {
            if showUnmatched { message = "This purchase could not be matched to your wallet. Contact Liya support for help." }
            return
        }
        let store = transaction.environment.rawValue
        let id = String(transaction.id)
        let previous = wallet.transactions[store]?[id]

        if transaction.revocationDate != nil {
            // Record the revocation even if it arrives before the original delivery.
            if previous != 0 {
                wallet.transactions[store, default: [:]][id] = 0
                guard save(wallet) else { return }
                if previous != nil { message = "Apple reversed a coin purchase. Your balance has been updated." }
            }
        } else if previous == nil {
            let (coins, overflow) = Int64(pack.coins).multipliedReportingOverflow(by: Int64(transaction.purchasedQuantity))
            guard !overflow, coins > 0, coins <= Int64.max - wallet.credits(in: store) else {
                message = "This purchase could not be added to your wallet."
                return
            }
            wallet.transactions[store, default: [:]][id] = coins
            guard save(wallet) else { return }
            message = "Coins added to your wallet."
        }
        // The same write saves the credit and its transaction ID for safe recovery.
        environment = store
        let pendingKey = "\(store):\(id)"
        guard finishing.insert(pendingKey).inserted else { return }
        defer { finishing.remove(pendingKey) }
        await transaction.finish()
    }

    private func walletURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        return directory.appendingPathComponent("LiyaCoinWallet.json")
    }

    private func loadWallet() {
        do {
            let data = try Data(contentsOf: walletURL())
            let saved = try JSONDecoder().decode(Wallet.self, from: data)
            wallet = saved
            walletError = nil
            if saved.welcomePending && welcomeGift == nil { welcomeGift = WelcomeGift() }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // If a previously opened wallet disappears, preserve its token and credits in memory.
            if save(wallet ?? Wallet()), wallet?.welcomePending == true, welcomeGift == nil {
                welcomeGift = WelcomeGift()
            }
        } catch {
            walletError = "Your wallet could not be opened. Try again or contact Liya support."
        }
    }

    private func save(_ value: Wallet) -> Bool {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: walletURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            wallet = value
            walletError = nil
            return true
        } catch {
            walletError = "Your wallet could not be saved. Use Check purchases to try again."
            return false
        }
    }
}
