import SwiftUI
import StoreKit

struct CoinPackage: Identifiable {
    let id: String
    let coins: Int
    let usPriceInCents: Int

    func referencePrice(in locale: Locale) -> String {
        let dollars = Decimal(usPriceInCents) / 100
        return dollars.formatted(.currency(code: "USD").presentation(.isoCode).locale(locale))
    }

    static let all: [CoinPackage] = [
        .init(id: "ceyarlaxiuojqsbi", coins: 450, usPriceInCents: 99),
        .init(id: "gxaojqvpvmykrgif", coins: 950, usPriceInCents: 199),
        .init(id: "hzlqemvjatucwprd", coins: 1500, usPriceInCents: 299),
        .init(id: "hqahzvljpcaltfnm", coins: 2700, usPriceInCents: 499),
        .init(id: "npdkdztghlqpfxnr", coins: 5800, usPriceInCents: 999),
        .init(id: "qwnbrlxesdvyampt", coins: 9000, usPriceInCents: 1499),
        .init(id: "czyghtwgjcswnuvl", coins: 12500, usPriceInCents: 1999),
        .init(id: "jemidcjpjteygrfy", coins: 34000, usPriceInCents: 4999),
        .init(id: "qmubwwcjusfbmlpw", coins: 72000, usPriceInCents: 9999)
    ]
}

struct WalletView: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var packWidth: CGFloat = 138
    @EnvironmentObject private var checkout: CoinCheckout
    @State private var selection: CoinPackage?
    @State private var appearanceToUnlock: CoinCheckout.Appearance?

    var body: some View {
        PageShell(title: "My wallet") {
            VStack(alignment: .leading, spacing: 20) {
                balanceHeader
                if let message = checkout.message, checkout.walletError == nil {
                    Text(verbatim: words(message))
                        .font(LiyaType.detail).foregroundStyle(liyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: words("Coin packs")).font(LiyaType.text(.title3, weight: .bold)).foregroundStyle(liyaInk)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: words("USD prices are estimates. Select a pack for your App Store price."))
                        .font(LiyaType.text(.footnote)).foregroundStyle(liyaInk.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                packageGrid
                Button(words("Check purchases")) { checkout.recover(showIssues: true) }
                    .font(LiyaType.text(.footnote, weight: .semibold))
                    .foregroundStyle(liyaAccent).frame(minHeight: 44)
                    .disabled(checkout.busy)
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: words("Personalize Liya")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                    VStack(spacing: 8) {
                        appearanceRow(.moodPrism, detail: "A violet palette for your mood diary", image: "mood-calm")
                        appearanceRow(.profileGlow, detail: "A colorful accent for your profile", image: "nav-soft-profile")
                        appearanceRow(.tideglassPaper, detail: "Sea-glass stationery for your journal postcards", image: "journal-paper-tideglass")
                    }
                    Text(verbatim: words("Each style unlocks once. Comparing days and sharing postcards are free."))
                        .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
            }.padding(.top, 12).modifier(AdaptiveContainerMargins())
        }
        .sheet(item: $selection) { pack in
            AppleCoinPackSheet(pack: pack)
        }
        .sheet(item: $appearanceToUnlock) { appearance in
            ZStack {
                LiyaBackground()
                DuoControlRegion { size in
                    ScrollView {
                        VStack(spacing: 14) {
                            HostedArtwork("wallet-coin").scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
                            Text(verbatim: words(appearance.title)).font(LiyaType.sectionHeading)
                            Text(verbatim: words.inserting(appearance.cost.formatted(.number.locale(locale)), into: "Spend %lld coins to unlock this style once.")).font(LiyaType.reading)
                            PrimaryButton(title: "Unlock") {
                                if !checkout.owns(appearance) { checkout.select(appearance) }
                                appearanceToUnlock = nil
                            }
                            Button(words("Cancel")) { appearanceToUnlock = nil }.frame(minHeight: 44)
                        }.multilineTextAlignment(.center).foregroundStyle(liyaInk)
                            .frame(maxWidth: 420).padding(20).frame(maxWidth: .infinity, minHeight: size.height)
                    }
                }
            }.presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(270), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var balanceHeader: some View {
        HStack(spacing: 15) {
            HostedArtwork("wallet-coin").scaledToFit().frame(width: 62, height: 62)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: words("Your balance"))
                    .font(LiyaType.text(.subheadline, weight: .semibold))
                    .foregroundStyle(liyaInk.opacity(0.72))
                if let balance = checkout.balance {
                    Text(verbatim: words.inserting(balance.formatted(.number.locale(locale)), into: "%@ coins"))
                        .font(LiyaType.text(.title, weight: .bold)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                } else if checkout.walletError == nil {
                    LiyaLoadingIndicator(size: 24)
                }
                if let issue = checkout.walletError {
                    Text(verbatim: words(issue)).font(LiyaType.text(.footnote))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(words("Refresh balance")) { checkout.recover(showIssues: true) }
                        .font(LiyaType.action).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .foregroundStyle(liyaInk)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
    }

    private var packageGrid: some View {
        let column = dynamicTypeSize.isAccessibilitySize ? GridItem(.flexible()) : GridItem(.adaptive(minimum: packWidth), spacing: 10)
        return LazyVGrid(columns: [column], spacing: 10) {
            ForEach(CoinPackage.all) { pack in
                let amount = pack.coins.formatted(.number.locale(locale))
                let price = checkout.displayPrice(for: pack) ?? pack.referencePrice(in: locale)
                Button {
                    checkout.clearMessage()
                    checkout.loadProduct(pack)
                    selection = pack
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            HostedArtwork("wallet-coin").scaledToFit().frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                            Text(amount).font(LiyaType.text(.headline, weight: .bold)).monospacedDigit()
                        }
                        Text(verbatim: price)
                            .font(LiyaType.text(.subheadline, weight: .bold)).monospacedDigit()
                            .foregroundStyle(liyaAccent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                    .foregroundStyle(liyaInk)
                    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(liyaAccent.opacity(0.13)))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(words.inserting(amount, into: "%@ coins"))
                .accessibilityValue(Text(verbatim: price))
            }
        }
    }

    private func appearanceRow(_ appearance: CoinCheckout.Appearance, detail: String, image: String) -> some View {
        let owned = checkout.owns(appearance)
        let badge: String = owned ? (checkout.isActive(appearance) ? "Turn off" : "Apply") : words.inserting(appearance.cost.formatted(.number.locale(locale)), into: "%lld coins")
        return Button {
            if owned { checkout.select(appearance) }
            else { appearanceToUnlock = appearance }
        } label: {
            useRow(appearance.title, detail: detail, badge: badge, image: image)
        }.buttonStyle(.plain).disabled(checkout.balance == nil || checkout.walletError != nil || checkout.busy)
    }

    private func useRow(_ title: String, detail: String, badge: String, image: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HostedArtwork(image).scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                Text(verbatim: words(detail)).font(LiyaType.text(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 5)
            Text(verbatim: words(badge)).font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent)
                .multilineTextAlignment(.trailing)
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct AppleCoinPackSheet: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var checkout: CoinCheckout
    let pack: CoinPackage
    @State private var submitted = false

    var body: some View {
        SafetyPanel(title: "Your coin pack", subject: nil, back: nil, close: { dismiss() }) {
            HostedArtwork("wallet-coin").scaledToFit()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: words.inserting(pack.coins.formatted(.number.locale(locale)), into: "%@ coins"))
                    .font(LiyaType.text(.title, weight: .bold)).monospacedDigit()
                    .foregroundStyle(liyaInk)
                purchaseControls
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onLiyaChange(of: checkout.busy) { busy in
            guard submitted, !busy else { return }
            submitted = false
            if checkout.walletError == nil && !checkout.isAwaitingDelivery(pack) && !checkout.isAwaitingApproval(pack) {
                dismiss()
            }
        }
        .onLiyaChange(of: checkout.isAwaitingDelivery(pack)) { pending in
            if !pending && checkout.walletError == nil { dismiss() }
        }
        .onDisappear { checkout.cancelProductRequest(for: pack) }
    }

    @ViewBuilder private var purchaseControls: some View {
        if let issue = checkout.walletError {
            note(issue)
            actionButton("Refresh balance") { checkout.recover(showIssues: true) }
        } else if checkout.isAwaitingDelivery(pack) {
            note("Your purchase is pending delivery.")
            actionButton("Check purchases") { checkout.recover(showIssues: true) }
        } else if checkout.isAwaitingApproval(pack) {
            note("Purchase pending")
        } else if !SKPaymentQueue.canMakePayments() {
            note("Purchases are turned off on this device.")
        } else if checkout.loadingProductID == pack.id {
            HStack(spacing: 9) {
                LiyaLoadingIndicator(size: 22).accessibilityHidden(true)
                note("Checking the App Store…")
            }
        } else if !checkout.productLoadFailed, let price = checkout.displayPrice(for: pack) {
            LabeledContent {
                Text(verbatim: price).font(LiyaType.text(.headline, weight: .bold)).monospacedDigit()
            } label: {
                Text(verbatim: words("App Store price")).font(LiyaType.detail)
            }
            .foregroundStyle(liyaInk)
            if let message = checkout.message { note(message) }
            actionButton(checkout.busy ? "Processing…" : "Buy with Apple",
                         disabled: !checkout.canPurchase(pack)) {
                submitted = true
                checkout.purchase(pack)
            }
        } else {
            note("Could not load the App Store price. Please try again.")
            actionButton("Try again") { checkout.loadProduct(pack) }
        }
    }

    private func actionButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: words(title)).font(LiyaType.action).foregroundStyle(liyaInk)
                .frame(maxWidth: .infinity, minHeight: 48)
                .modifier(ContactBarSurface())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: words(text)).font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.77))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct WelcomeCoinGift: View {
    @Environment(\.locale) private var locale
    @Environment(\.liyaWords) private var words
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
                .background { HostedArtwork(decorative: "color-background") }
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
            HostedArtwork(decorative: "welcome-gift").scaledToFit()
                .frame(width: artworkSize, height: artworkSize)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            Text(verbatim: words("Welcome to Liya"))
                .font(LiyaType.text(.title2, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: words.inserting(creditedCoins.formatted(.number.locale(locale)), into: "%@ coins added to your wallet."))
                .font(LiyaType.text(.subheadline, weight: .medium))
            if checkout.walletError != nil {
                Text(verbatim: words("Couldn’t save your wallet. Tap again to continue."))
                    .font(LiyaType.text(.footnote, weight: .medium))
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
