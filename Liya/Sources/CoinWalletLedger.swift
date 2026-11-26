import Foundation

struct CoinWalletLedger: Codable {
    enum Failure: Error {
        case insufficientFunds
        case invalidCredits
        case storeNotIdentified
    }

    private struct StoreBinding: Codable, Equatable {
        let store: String
        let installation: String
    }

    private static let unassigned = "Unassigned"
    private(set) var token = UUID()
    var welcomePending = true
    private var transactions: [String: [String: Int64]] = [:]
    private var appearances: [String: [String: Bool]] = [:]
    private var binding: StoreBinding?

    static var transactionStore: String? {
        switch Bundle.main.appStoreReceiptURL?.lastPathComponent.lowercased() {
        case "sandboxreceipt":
            return "Sandbox"
        case "storekittestreceipt", "simulatedstorekitreceipt":
            return "Xcode"
        case "receipt":
            #if DEBUG || targetEnvironment(simulator)
            return "Xcode"
            #else
            return "Production"
            #endif
        default:
            return nil
        }
    }

    static var currentStore: String { transactionStore ?? unassigned }

    private static var installation: String {
        Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent
    }

    private var storesWithHistory: Set<String> {
        let paidStores = transactions.compactMap { $0.value.isEmpty ? nil : $0.key }
        let usedStores = appearances.compactMap { $0.value.isEmpty ? nil : $0.key }
        return Set(paidStores + usedStores).subtracting([Self.unassigned])
    }

    private func storeForLoading() throws -> String {
        if let store = Self.transactionStore { return store }
        if let binding, binding.installation == Self.installation { return binding.store }
        let history = storesWithHistory
        guard !history.isEmpty else { return Self.unassigned }
        #if DEBUG || targetEnvironment(simulator)
        let testing = history.intersection(["Xcode", "Sandbox"])
        if testing.count == 1, let store = testing.first { return store }
        #endif
        throw Failure.storeNotIdentified
    }

    private func partition(for store: String) -> String {
        if store == Self.unassigned, let binding, binding.installation == Self.installation {
            return binding.store
        }
        return store
    }

    private func appearanceStates(in store: String) -> [String: Bool] {
        let partition = partition(for: store)
        let saved = appearances[partition] ?? [:]
        guard partition != Self.unassigned else { return saved }
        return saved.merging(appearances[Self.unassigned] ?? [:]) { _, recent in recent }
    }

    private mutating func bind(to store: String) {
        guard store != Self.unassigned else { return }
        binding = StoreBinding(store: store, installation: Self.installation)
        if let initialStyles = appearances.removeValue(forKey: Self.unassigned) {
            appearances[store, default: [:]].merge(initialStyles) { _, recent in recent }
        }
    }

    private func credits(in store: String) -> Int64 {
        (transactions[partition(for: store)] ?? [:]).values.reduce(Int64(CoinCheckout.WelcomeGift.coins), +)
    }

    func balance(in store: String) -> Int64 {
        let spent = appearanceStates(in: store).keys.compactMap(CoinCheckout.Appearance.init(rawValue:)).reduce(Int64(0)) { $0 + $1.cost }
        return max(0, credits(in: store) - spent)
    }

    func credited(_ id: String, in store: String) -> Bool {
        transactions[partition(for: store)]?[id] != nil
    }

    mutating func credit(_ coins: Int64, transactionID: String, in store: String) throws {
        guard store != Self.unassigned, !transactionID.isEmpty, coins > 0 else { throw Failure.invalidCredits }
        bind(to: store)
        guard !credited(transactionID, in: store) else { return }
        guard !credits(in: store).addingReportingOverflow(coins).overflow else { throw Failure.invalidCredits }
        transactions[store, default: [:]][transactionID] = coins
    }

    func owns(_ appearance: CoinCheckout.Appearance, in store: String) -> Bool {
        appearanceStates(in: store)[appearance.rawValue] != nil
    }

    func isActive(_ appearance: CoinCheckout.Appearance, in store: String) -> Bool {
        appearanceStates(in: store)[appearance.rawValue] == true
    }

    mutating func select(_ appearance: CoinCheckout.Appearance, in store: String) throws {
        bind(to: store)
        let partition = partition(for: store)
        let current = appearances[partition]?[appearance.rawValue]
        guard current != nil || balance(in: store) >= appearance.cost else { throw Failure.insufficientFunds }
        appearances[partition, default: [:]][appearance.rawValue] = current != true
    }

    private static func walletURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        return directory.appendingPathComponent("LiyaCoinWallet.json")
    }

    static func load() throws -> Self {
        let url = try walletURL()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            var newWallet = Self()
            newWallet.bind(to: currentStore)
            try newWallet.save()
            return newWallet
        }
        var wallet = try JSONDecoder().decode(Self.self, from: data)
        for purchases in wallet.transactions.values {
            var total = Int64(CoinCheckout.WelcomeGift.coins)
            for coins in purchases.values {
                let (newTotal, overflow) = total.addingReportingOverflow(coins)
                guard coins >= 0, !overflow else { throw Failure.invalidCredits }
                total = newTotal
            }
        }
        let store = try wallet.storeForLoading()
        if store != unassigned, wallet.binding != StoreBinding(store: store, installation: installation) {
            wallet.bind(to: store)
            try wallet.save()
        }
        return wallet
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.walletURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
