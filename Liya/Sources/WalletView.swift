import SwiftUI
import StoreKit

struct CoinPackage: Identifiable {
    let id: String
    let coins: Int

    static let all: [CoinPackage] = [
        .init(id: "ceyarlaxiuojqsbi", coins: 450),
        .init(id: "gxaojqvpvmykrgif", coins: 950),
        .init(id: "hzlqemvjatucwprd", coins: 1500),
        .init(id: "hqahzvljpcaltfnm", coins: 2700),
        .init(id: "npdkdztghlqpfxnr", coins: 5800),
        .init(id: "qwnbrlxesdvyampt", coins: 9000),
        .init(id: "czyghtwgjcswnuvl", coins: 12500),
        .init(id: "jemidcjpjteygrfy", coins: 34000),
        .init(id: "qmubwwcjusfbmlpw", coins: 72000)
    ]
}

struct WalletView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var checkout: CoinCheckout
    @State private var selection: CoinPackage?
    @State private var appearanceToUnlock: CoinCheckout.Appearance?

    var body: some View {
        PageShell(title: "My wallet") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    Image("wallet-coin").resizable().scaledToFit().frame(width: 66, height: 66).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your balance").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(checkout.balance.map { $0.formatted() } ?? "—")
                                .font(.system(.largeTitle, design: .rounded).bold()).foregroundStyle(liyaInk).monospacedDigit()
                            Text("coins").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                        if checkout.balance == nil { Text("Balance unavailable").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 8)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(liyaAccent.opacity(0.08), lineWidth: 1))

                Text("Your coin balance is stored on this device.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = checkout.walletError ?? checkout.message {
                    OfflineNote(text: error)
                }
                HStack(alignment: .center) {
                    Text("Coin packs").font(.title3.bold()).foregroundStyle(liyaInk)
                    Spacer(minLength: 8)
                    Button("Check purchases") { Task { await checkout.recover(showIssues: true) } }
                        .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                if checkout.productLoadFailed {
                    Button("Try loading prices again") { Task { await checkout.loadProducts() } }
                        .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
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
                    Text("Personalize Liya").font(.headline).foregroundStyle(liyaInk)
                    VStack(spacing: 8) {
                        appearanceRow(.moodPrism, detail: "A violet palette for your mood diary", image: "mood-calm")
                        appearanceRow(.profileGlow, detail: "A colorful accent for your profile", image: "nav-soft-profile")
                        appearanceRow(.tideglassPaper, detail: "Sea-glass stationery for your journal postcards", image: "journal-paper-tideglass")
                    }
                    Text("Each style unlocks once. Comparing days and sharing postcards are free.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
            }.padding(.top, 12).modifier(AdaptiveContainerMargins())
        }.task { await checkout.loadProducts() }
        .sheet(item: $selection) { pack in
            AppleCoinPackSheet(pack: pack)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $appearanceToUnlock) { appearance in
            ZStack {
                LiyaBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        Image("wallet-coin").resizable().scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
                        Text(LocalizedStringKey(appearance.title)).font(LiyaType.sectionHeading)
                        Text("Spend \(appearance.cost) coins to unlock this style once.").font(LiyaType.reading)
                        PrimaryButton(title: "Unlock") {
                            if !checkout.owns(appearance) { checkout.select(appearance) }
                            appearanceToUnlock = nil
                        }
                        Button("Cancel") { appearanceToUnlock = nil }.frame(minHeight: 44)
                    }.multilineTextAlignment(.center).foregroundStyle(liyaInk)
                        .frame(maxWidth: 420).padding(24).frame(maxWidth: .infinity)
                }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    private func packageGrid(columns count: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: count), spacing: 8) {
            ForEach(CoinPackage.all) { pack in
                let price = checkout.products[pack.id]?.displayPrice
                Button {
                    checkout.clearMessage()
                    selection = pack
                } label: {
                    VStack(spacing: 7) {
                        Image("wallet-coin").resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                        VStack(spacing: 2) {
                            Text(pack.coins.formatted()).font(.system(.headline, design: .rounded).bold())
                                .foregroundStyle(liyaInk).lineLimit(1).minimumScaleFactor(0.8).monospacedDigit()
                            Text("coins").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(price ?? (checkout.loadingProducts ? "Loading price…" : "Price unavailable")).font(.caption.weight(.semibold)).foregroundStyle(liyaAccent)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(liyaAccent.opacity(0.08), in: Capsule())
                    }.frame(maxWidth: .infinity, minHeight: 132).padding(.horizontal, 4).padding(.vertical, 8)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(liyaAccent.opacity(0.10), lineWidth: 1))
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(pack.coins.formatted()) coins")
                    .accessibilityValue(Text(price ?? (checkout.loadingProducts ? "Loading price…" : "Price unavailable")))
            }
        }
    }

    private func appearanceRow(_ appearance: CoinCheckout.Appearance, detail: String, image: String) -> some View {
        let owned = checkout.owns(appearance)
        let badge: LocalizedStringKey = owned ? (checkout.isActive(appearance) ? "Turn off" : "Apply") : "\(appearance.cost) coins"
        return Button {
            if owned { checkout.select(appearance) }
            else { appearanceToUnlock = appearance }
        } label: {
            useRow(appearance.title, detail: detail, badge: badge, image: image)
        }.buttonStyle(.plain).disabled(checkout.balance == nil || checkout.walletError != nil || checkout.busy)
    }

    private func useRow(_ title: String, detail: String, badge: LocalizedStringKey, image: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image).resizable().scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 5)
            Text(badge).font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent)
                .multilineTextAlignment(.trailing)
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct AppleCoinPackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var checkout: CoinCheckout
    let pack: CoinPackage
    private var product: Product? { checkout.products[pack.id] }

    var body: some View {
        ZStack {
            LiyaBackground()
            DuoControlRegion { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your coin pack").font(.title3.weight(.bold)).foregroundStyle(liyaInk)
                                Text("Coins are added to this device.").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Close") { dismiss() }
                                .font(.footnote.weight(.semibold)).foregroundStyle(liyaInk.opacity(0.75))
                                .padding(.horizontal, 15).frame(minHeight: 44)
                                .background(.white.opacity(0.75), in: Capsule())
                                .buttonStyle(.plain)
                        }
                        packSummary
                        if checkout.loadingProducts {
                            HStack(spacing: 10) {
                                LiyaLoadingIndicator(size: 24)
                                Text("Checking the App Store…").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        } else if product == nil {
                            statusCard(title: "Price unavailable", detail: "This pack is currently unavailable from the App Store.")
                        } else if !AppStore.canMakePayments {
                            statusCard(title: "Purchases are restricted", detail: "Check your device settings for in-app purchases.")
                        }
                        if let message = checkout.walletError ?? checkout.message {
                            Text(message).font(.footnote).foregroundStyle(liyaInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if product == nil {
                            PrimaryButton(title: checkout.loadingProducts ? "Checking price…" : "Try again",
                                          disabled: checkout.loadingProducts) {
                                Task { await checkout.loadProducts() }
                            }
                        } else {
                            PrimaryButton(title: checkout.busy ? "Processing…" : "Buy with Apple",
                                          disabled: checkout.loadingProducts || !checkout.canPurchase) {
                                Task { await checkout.purchase(pack) }
                            }
                        }
                    }.padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 24)
                        .frame(maxWidth: 440).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var packSummary: some View {
        HStack(spacing: 14) {
            Image("wallet-coin").resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(pack.coins.formatted()) coins")
                    .font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(liyaInk)
                    .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                if let product {
                    Text(product.displayPrice).font(.headline.weight(.bold)).foregroundStyle(liyaAccent)
                    Text("App Store price").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("App Store price").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(liyaAccent.opacity(0.12), lineWidth: 1))
    }

    private func statusCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
            Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }

}

struct WelcomeCoinGift: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var checkout: CoinCheckout
    let creditedCoins: Int
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            DuoControlRegion { size in
                let artworkSize = min(104, size.height * 0.25)
                ViewThatFits(in: .vertical) {
                    giftContent(artworkSize: artworkSize)
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollView { giftContent(artworkSize: artworkSize) }
                }
                .frame(maxWidth: 292)
                .background { Image(decorative: "color-background").resizable() }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 7)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .padding(16)
            }
        }.onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { appeared = true } }
        }
    }

    private func giftContent(artworkSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(decorative: "welcome-gift")
                .resizable().scaledToFit()
                .frame(width: artworkSize, height: artworkSize)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            Text("Welcome to Liya")
                .font(.system(.title2, design: .rounded).bold())
                .accessibilityAddTraits(.isHeader)
            Text("\(creditedCoins.formatted()) coins added to your wallet.")
                .font(.subheadline.weight(.medium))
            if checkout.walletError != nil {
                Text("Couldn’t save your wallet. Tap again to continue.")
                    .font(.footnote.weight(.medium))
            }
            WelcomeAction(title: "Continue to Liya", image: "welcome-gift-dismiss",
                          foreground: liyaInk, fullArtwork: true) {
                _ = checkout.acknowledgeWelcome()
            }
            .frame(maxWidth: 220)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }
}
