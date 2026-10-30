import SwiftUI
import StoreKit

struct CoinPackage: Identifiable {
    let id: String
    let coins: Int
    let referenceUSD: String

    static let all: [CoinPackage] = [
        .init(id: "ceyarlaxiuojqsbi", coins: 450, referenceUSD: "0.99"),
        .init(id: "gxaojqvpvmykrgif", coins: 950, referenceUSD: "1.99"),
        .init(id: "hzlqemvjatucwprd", coins: 1500, referenceUSD: "2.99"),
        .init(id: "hqahzvljpcaltfnm", coins: 2700, referenceUSD: "4.99"),
        .init(id: "npdkdztghlqpfxnr", coins: 5800, referenceUSD: "9.99"),
        .init(id: "qwnbrlxesdvyampt", coins: 9000, referenceUSD: "14.99"),
        .init(id: "czyghtwgjcswnuvl", coins: 12500, referenceUSD: "19.99"),
        .init(id: "jemidcjpjteygrfy", coins: 34000, referenceUSD: "49.99"),
        .init(id: "qmubwwcjusfbmlpw", coins: 72000, referenceUSD: "99.99")
    ]
}

struct WalletView: View {
    @EnvironmentObject private var session: LiyaSession
    @State private var selection: CoinPackage?
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        PageShell(title: "My wallet") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR LIYA BALANCE").font(.caption.bold()).tracking(1.2).foregroundStyle(liyaAccent)
                        Text(session.coinBalance.map { $0.formatted() } ?? "—").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(liyaInk)
                        Text(session.coinBalance == nil ? "Balance unavailable" : "Coins")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image("wallet-coin").resizable().scaledToFit().frame(width: 88, height: 88).accessibilityHidden(true)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.87), in: RoundedRectangle(cornerRadius: 20))

                OfflineNote(text: session.walletError ?? "Secure purchase delivery is not connected yet. Purchases are unavailable.")
                Button("Refresh balance") { Task { await session.refreshWallet() } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Add a little sparkle").font(.title3.bold()).foregroundStyle(liyaInk)
                    Text("Choose a pack to see its current App Store price.").font(.footnote).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(CoinPackage.all) { pack in
                        Button { selection = pack } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image("wallet-coin").resizable().scaledToFit().frame(width: 35, height: 35).accessibilityHidden(true)
                                Text(pack.coins.formatted()).font(.system(.title3, design: .rounded).bold()).foregroundStyle(liyaInk)
                                Text("coins").font(.caption).foregroundStyle(.secondary)
                                Text("See Apple price").font(.caption.bold()).foregroundStyle(liyaAccent)
                            }.frame(maxWidth: .infinity, minHeight: 132, alignment: .leading).padding(.horizontal, 15)
                                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityLabel("\(pack.coins.formatted()) coins, see Apple price")
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Where coins will go").font(.headline).foregroundStyle(liyaInk)
                    useRow("Mood Prism", detail: "Unlock a diary appearance", cost: 120)
                    useRow("Profile Glow", detail: "Activate a profile appearance", cost: 180)
                    useRow("Post Spotlight", detail: "Highlight an eligible post", cost: 280)
                    Text("These features are planned and not yet available. No coins are charged in this preview.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Chat and messages are always free.").font(.footnote.bold()).foregroundStyle(liyaAccent)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
            }.padding(.top, 12)
        }.sheet(item: $selection) { pack in AppleCoinPackSheet(pack: pack) }
            .task { await session.refreshWallet() }
    }

    private func useRow(_ title: String, detail: String, cost: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).foregroundStyle(liyaInk)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Text("\(cost) coins").font(.caption.bold()).foregroundStyle(liyaAccent)
        }
    }
}

private struct AppleCoinPackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var checkout: CoinCheckout
    let pack: CoinPackage
    @State private var product: Product?
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        ZStack {
            LiyaBackground()
            DuoControlRegion { size in
                ScrollView {
                    VStack(spacing: 18) {
                        Image("wallet-coin").resizable().scaledToFit().frame(width: 94, height: 94).accessibilityHidden(true)
                        Text("\(pack.coins.formatted()) coins").font(.title2.bold()).foregroundStyle(liyaInk)
                        if loading {
                            Text("Checking the App Store…").font(.subheadline).foregroundStyle(.secondary)
                        } else if let product {
                            Text(product.displayPrice).font(.title3.bold()).foregroundStyle(liyaAccent)
                            Text("The price shown is supplied by the App Store.").font(.footnote).foregroundStyle(.secondary)
                            if product.type != .consumable {
                                Text("This product is not configured as a coin pack.")
                                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                        } else {
                            Text(message ?? "This pack is not available from the App Store right now.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Try again") { Task { await loadProduct() } }.font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                        }
                        if !checkout.isConnected {
                            Text("Purchasing is unavailable until account and secure coin delivery are connected.")
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        if let message = checkout.message {
                            Text(message).font(.footnote).foregroundStyle(liyaInk).multilineTextAlignment(.center)
                        }
                        PrimaryButton(title: checkout.busy ? "Processing…" : "Continue with Apple",
                                      disabled: product?.type != .consumable || !checkout.canPurchase) {
                            if let product { Task { await checkout.purchase(product, pack: pack) } }
                        }
                        Button("Close") { dismiss() }.font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }.padding(24).frame(maxWidth: 420).frame(maxWidth: .infinity).frame(minHeight: size.height)
                }
            }
        }.task { await loadProduct() }
    }

    @MainActor private func loadProduct() async {
        guard !loading || product == nil else { return }
        loading = true; product = nil; message = nil
        do {
            let products = try await Product.products(for: [pack.id])
            guard !Task.isCancelled else { return }
            product = products.first { $0.id == pack.id }
            if product == nil { message = "This pack is not available from the App Store right now." }
        } catch {
            guard !Task.isCancelled else { return }
            message = "Could not load the App Store price. Please try again."
        }
        loading = false
    }
}

/// Present only after the server confirms the one-time grant for this account.
struct WelcomeCoinGift: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: LiyaSession
    let creditedCoins: Int
    @State private var appeared = false
    @State private var saving = false

    var body: some View {
        ZStack {
            LiyaBackground(name: "color-background")
            DuoControlRegion { size in
                ScrollView {
                    VStack(spacing: 16) {
                        Text("A LITTLE SPARK FOR YOU").font(.caption.bold()).tracking(1.6).foregroundStyle(.white.opacity(0.85))
                        Image("welcome-gift").resizable().scaledToFit().frame(maxWidth: 300, maxHeight: 280)
                            .scaleEffect(appeared || reduceMotion ? 1 : 0.86).opacity(appeared || reduceMotion ? 1 : 0)
                            .accessibilityHidden(true)
                        Text("Welcome to Liya").font(.largeTitle.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                        Text("\(creditedCoins.formatted()) coins added").font(.title3.bold()).foregroundStyle(.white)
                        Text("A bright beginning for your little corner of the world.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
                        if let error = session.walletError { Text(error).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center) }
                        Button(saving ? "Saving…" : "Let's explore") {
                            guard !saving else { return }
                            saving = true
                            Task { if await session.acknowledgeWelcome() { dismiss() }; saving = false }
                        }.disabled(saving).font(.headline).foregroundStyle(liyaInk)
                            .frame(maxWidth: .infinity, minHeight: 52).background(.white, in: Capsule())
                    }.padding(28).frame(maxWidth: 460).frame(maxWidth: .infinity).frame(minHeight: size.height)
                }
            }
        }.onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { appeared = true } }
        }
    }
}
