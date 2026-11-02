import SwiftUI

private enum LiyaTab: Int, CaseIterable {
    case discover, square, compose, messages, profile
    var title: String {
        switch self { case .discover: return "Video"; case .square: return "Square"; case .compose: return "Create"; case .messages: return "Messages"; case .profile: return "Profile" }
    }
    func image(selected: Bool) -> String {
        switch self {
        case .discover: return selected ? "tab-square" : "tab-video-inactive"
        case .square: return selected ? "tab-discover" : "tab-square-inactive"
        case .compose: return "tab-create"
        case .messages: return selected ? "tab-message" : "tab-message-inactive"
        case .profile: return selected ? "tab-profile" : "tab-profile-inactive"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var calls: LiyaCalls
    @State private var selection: LiyaTab = .discover

    var body: some View {
        if !store.inPreview {
            WelcomeView {
                Task { if await session.signIn() { store.inPreview = true } }
            }
        } else {
            ZStack {
                Group {
                    tab(.discover) { VideoHome(active: selection == .discover) }
                    tab(.square) { SquareHome() }
                    tab(.compose) { ComposeHome() }
                    tab(.messages) { MessagesHome() }
                    tab(.profile) { ProfileHome() }
                }
            }
            .disabled(session.isDeletingAccount)
            .task(id: session.userID) {
                if session.userID != nil { await social.refresh(session); social.watchMessages(session) }
            }
            .task(id: session.userID) { await calls.watch(session) }
            .fullScreenCover(item: Binding(get: { calls.call }, set: { _ in })) { call in
                LiyaCallScreen(initial: call).environmentObject(calls).environmentObject(session).environmentObject(social)
            }
            .onLiyaChange(of: store.videoRequest) { request in
                if request != nil { selection = .discover }
            }
            .sheet(item: $session.welcomeGift) { gift in
                WelcomeCoinGift(creditedCoins: gift.coins).interactiveDismissDisabled()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DuoControlRegion { size in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(LiyaTab.allCases, id: \.rawValue) { item in
                                Button { selection = item } label: {
                                    VStack(spacing: 3) {
                                        Image(item.image(selected: selection == item)).resizable().scaledToFit().frame(width: item == .compose ? 34 : 24, height: 34)
                                        Text(item.title).font(.system(size: 10, weight: selection == item ? .bold : .regular))
                                            .foregroundStyle(selection == item ? liyaAccent : .secondary)
                                    }.frame(width: max(52, (size.width - 16) / CGFloat(LiyaTab.allCases.count)), height: 52).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityAddTraits(selection == item ? .isSelected : [])
                            }
                        }.padding(.horizontal, 8).modifier(AdaptiveContainerMargins())
                    }
                }.frame(height: 52).background(.white)
            }
        }
    }

    private func tab<Content: View>(_ item: LiyaTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content() }
            .opacity(selection == item ? 1 : 0)
            .allowsHitTesting(selection == item)
            .accessibilityHidden(selection != item)
    }
}

private struct WelcomeView: View {
    let enter: () -> Void
    @EnvironmentObject private var session: LiyaSession
    @State private var policy: PolicyPage?
    @State private var agreed = false
    @State private var showAgreementReminder = false
    var body: some View {
        ZStack {
            LiyaBackground(name: "welcome-art")
            DuoControlRegion { size in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: max(200, size.height * 0.42))
                        VStack(spacing: 6) {
                            Text("Share how you feel")
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Every mood belongs here.")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: 45)
                        WelcomeAction(title: session.isSigningIn ? "Connecting…" : "Continue to Liya", image: "welcome-button-v2", foreground: liyaInk, isLoading: session.isSigningIn, fullArtwork: true) {
                            if agreed { enter() } else { showAgreementReminder = true }
                        }
                        .disabled(session.isSigningIn)
                        if let errorMessage = session.errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.white)
                                .multilineTextAlignment(.center).padding(.top, 8)
                        }
                        agreementRow
                            .padding(.top, 10)
                    }
                    .frame(maxWidth: 390)
                    .frame(maxWidth: .infinity, minHeight: size.height, alignment: .top)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .accessibilityHidden(showAgreementReminder)
            .allowsHitTesting(!showAgreementReminder)

            if showAgreementReminder {
                Color.black.opacity(0.55).ignoresSafeArea()
                DuoControlRegion { size in
                    ScrollView {
                        agreementReminder
                            .frame(maxWidth: 360)
                            .frame(maxWidth: .infinity, minHeight: size.height)
                            .padding(.horizontal, 20)
                    }
                }
                .transition(.opacity)
            }
        }.sheet(item: $policy) { page in
            NavigationStack {
                LegalDocumentView(page: page)
            }
        }
    }

    private var agreementRow: some View {
        HStack(alignment: .top, spacing: 4) {
            Button { agreed.toggle() } label: {
                Image(agreed ? "consent-on" : "consent-off")
                    .resizable().scaledToFit().frame(width: 34, height: 34)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Agree to the Terms of Service and Privacy Policy")
            .accessibilityValue(agreed ? "Agreed" : "Not agreed")
            .accessibilityAddTraits(agreed ? .isSelected : [])

            VStack(alignment: .leading, spacing: 0) {
                Text("I agree to the following (tap to read):")
                    .font(.footnote).foregroundStyle(liyaInk)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        policyLink(.terms)
                        Text("and").foregroundStyle(liyaInk)
                        policyLink(.privacy)
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 0) {
                        policyLink(.terms)
                        policyLink(.privacy)
                    }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .frame(minHeight: 44, alignment: .leading)
            }
            .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var agreementReminder: some View {
        VStack(spacing: 14) {
            Text("Before we begin")
                .font(.title3.bold()).foregroundStyle(liyaInk)
                .multilineTextAlignment(.center)
            Text("Please read and agree to our Terms of Service and Privacy Policy before continuing.")
                .font(.subheadline).foregroundStyle(liyaInk.opacity(0.8))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    policyLink(.terms, fromReminder: true)
                    policyLink(.privacy, fromReminder: true)
                }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 0) {
                    policyLink(.terms, fromReminder: true)
                    policyLink(.privacy, fromReminder: true)
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.plain).frame(minHeight: 44)
            WelcomeAction(title: "Back to agreement", image: "consent-button", foreground: .white) {
                showAgreementReminder = false
            }
        }
        .padding(.horizontal, 28).padding(.top, 96).padding(.bottom, 26)
        .background(WelcomePanelBackground())
        .accessibilityElement(children: .contain)
    }

    private func policyLink(_ page: PolicyPage, fromReminder: Bool = false) -> some View {
        Button {
            if fromReminder { showAgreementReminder = false }
            policy = page
        } label: {
            Text(page.title).underline()
                .foregroundStyle(Color(red: 0.18, green: 0.12, blue: 0.48))
                .frame(minHeight: 44)
        }
        .accessibilityHint("Opens \(page.title) for reading")
    }
}

private struct WelcomePanelBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let artworkHeight = geometry.size.width * 958 / 778
            VStack(spacing: 0) {
                Image("panel-background")
                    .resizable().scaledToFit()
                    .frame(width: geometry.size.width, height: artworkHeight)
                Color.white
            }
            .frame(width: geometry.size.width, height: max(geometry.size.height, artworkHeight), alignment: .top)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

private struct WelcomeAction: View {
    let title: String
    let image: String
    let foreground: Color
    var isLoading = false
    var fullArtwork = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            if fullArtwork {
                ZStack {
                    Image(image).resizable().scaledToFit().accessibilityHidden(true)
                    label
                }
                .aspectRatio(2172.0 / 724.0, contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            } else {
                label
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        GeometryReader { geometry in
                            Image(image).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    }
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        HStack(spacing: 8) {
            if isLoading { LiyaLoadingIndicator(size: 30).accessibilityHidden(true) }
            Text(title)
                .font(fullArtwork ? .system(size: 17, weight: .semibold, design: .rounded) : .system(size: 16, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 16)
    }
}
