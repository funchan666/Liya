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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var checkout: CoinCheckout
    @State private var selection: CoinPackage?

    var body: some View {
        PageShell(title: "My wallet") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    Image("wallet-coin").resizable().scaledToFit().frame(width: 66, height: 66).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your balance").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(session.coinBalance.map { $0.formatted() } ?? "—")
                                .font(.system(.largeTitle, design: .rounded).bold()).foregroundStyle(liyaInk).monospacedDigit()
                            Text("coins").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                        if session.coinBalance == nil { Text("Balance unavailable").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 8)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(liyaAccent.opacity(0.08), lineWidth: 1))

                if let error = session.walletError {
                    OfflineNote(text: error)
                } else if !checkout.isConnected {
                    OfflineNote(text: "Purchases are currently unavailable.")
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coin packs").font(.title3.bold()).foregroundStyle(liyaInk)
                        Text("USD reference prices · App Store confirms your final price.")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Refresh") { Task { await session.refreshWallet() } }
                        .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                        .accessibilityLabel("Refresh balance")
                }
                if dynamicTypeSize.isAccessibilitySize {
                    packageGrid(columns: 2)
                } else {
                    ViewThatFits(in: .horizontal) {
                        packageGrid(columns: 3).frame(minWidth: 285)
                        packageGrid(columns: 2)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A little more with coins").font(.headline).foregroundStyle(liyaInk)
                        Text("Coming soon · No coins will be charged yet")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 8) {
                        useRow("Mood Prism", detail: "A new look for your diary", cost: 120, image: "mood-calm")
                        useRow("Profile Glow", detail: "Personalize your profile", cost: 180, image: "nav-soft-profile")
                        useRow("Post Spotlight", detail: "Give your post a little boost", cost: 280, image: "nav-soft-square")
                    }
                    Text("Chat is always free")
                        .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
            }.padding(.top, 12).modifier(AdaptiveContainerMargins())
        }.sheet(item: $selection) { pack in AppleCoinPackSheet(pack: pack) }
            .task { await session.refreshWallet() }
    }

    private func packageGrid(columns count: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: count), spacing: 8) {
            ForEach(CoinPackage.all) { pack in
                Button { selection = pack } label: {
                    VStack(spacing: 7) {
                        Image("wallet-coin").resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                        VStack(spacing: 2) {
                            Text(pack.coins.formatted()).font(.system(.headline, design: .rounded).bold())
                                .foregroundStyle(liyaInk).lineLimit(1).minimumScaleFactor(0.8).monospacedDigit()
                            Text("coins").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("US$\(pack.referenceUSD) ref.").font(.caption.weight(.semibold)).foregroundStyle(liyaAccent)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(liyaAccent.opacity(0.08), in: Capsule())
                    }.frame(maxWidth: .infinity, minHeight: 132).padding(.horizontal, 4).padding(.vertical, 8)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(liyaAccent.opacity(0.10), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("\(pack.coins.formatted()) coins, reference price US dollars \(pack.referenceUSD). Select to check the App Store price.")
            }
        }
    }

    private func useRow(_ title: String, detail: String, cost: Int, image: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image).resizable().scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(cost)").font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent).monospacedDigit()
                Text("coins").font(.caption2).foregroundStyle(.secondary)
            }.fixedSize(horizontal: true, vertical: false)
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
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
