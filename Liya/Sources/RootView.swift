import SwiftUI
import AuthenticationServices
import CryptoKit

private struct ProfileDetailVisibilityKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

private struct LiyaTabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct LiyaTabActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var profileDetailVisible: Binding<Bool> {
        get { self[ProfileDetailVisibilityKey.self] }
        set { self[ProfileDetailVisibilityKey.self] = newValue }
    }
    var liyaTabBarClearance: CGFloat {
        get { self[LiyaTabBarClearanceKey.self] }
        set { self[LiyaTabBarClearanceKey.self] = newValue }
    }
    var liyaTabActive: Bool {
        get { self[LiyaTabActiveKey.self] }
        set { self[LiyaTabActiveKey.self] = newValue }
    }
}

enum LiyaTabBarLayout {
    static let height: CGFloat = 68
    static let bottomPadding: CGFloat = 4
    static let contentClearance: CGFloat = height + bottomPadding + 12
}

private enum LiyaTab: Int, CaseIterable {
    case discover, square, compose, messages, profile
    var title: String {
        switch self { case .discover: return "Video"; case .square: return "Square"; case .compose: return "Create"; case .messages: return "Messages"; case .profile: return "Profile" }
    }
    var image: String {
        switch self {
        case .discover: return "navigation-media-feed"
        case .square: return "navigation-community"
        case .compose: return "navigation-compose"
        case .messages: return "navigation-inbox"
        case .profile: return "navigation-profile"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var checkout: CoinCheckout
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var calls: LiyaCalls
    @State private var selection: LiyaTab = .discover
    @State private var profileDetailVisible = false

    var body: some View {
        if !store.inPreview {
            WelcomeView()
            .onAppear { selection = .discover; profileDetailVisible = false }
        } else {
            ZStack {
                Group {
                    tab(.discover) { VideoHome(active: selection == .discover && checkout.welcomeGift == nil && calls.call == nil) }
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
            .task(id: session.catalogGeneration) {
                guard session.userID != nil else { return }
                await session.refreshCuratedFollows(store: store)
            }
            .onLiyaChange(of: store.videoRequest) { request in
                if request != nil { selection = .discover }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !profileDetailVisible {
                    LiyaGlassTabBar(selection: $selection)
                        .frame(height: LiyaTabBarLayout.height)
                        .padding(.horizontal, 10)
                        .padding(.bottom, LiyaTabBarLayout.bottomPadding)
                }
            }
            .disabled(checkout.welcomeGift != nil)
            .accessibilityHidden(checkout.welcomeGift != nil)
            .overlay {
                if checkout.welcomeGift != nil {
                    WelcomeCoinGift(creditedCoins: CoinCheckout.WelcomeGift.coins)
                }
            }
            .environment(\.profileDetailVisible, $profileDetailVisible)
            .environment(\.liyaTabBarClearance, profileDetailVisible ? 0 : LiyaTabBarLayout.contentClearance)
        }
    }

    private func tab<Content: View>(_ item: LiyaTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content() }
            .environment(\.liyaTabActive, selection == item)
            .opacity(selection == item ? 1 : 0)
            .allowsHitTesting(selection == item)
            .accessibilityHidden(selection != item)
    }
}

private struct LiyaGlassTabBar: View {
    @Binding var selection: LiyaTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let diameter: CGFloat = 48
    private let gap: CGFloat = 8

    var body: some View {
        DuoControlRegion { size in
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if #available(iOS 26.0, *) {
                        GlassEffectContainer(spacing: 0) { buttons(in: size.width) }
                    } else {
                        buttons(in: size.width)
                    }
                }
                .frame(minWidth: size.width, minHeight: size.height)
            }
        }
    }

    private func buttons(in width: CGFloat) -> some View {
        let otherButtonsWidth = CGFloat(LiyaTab.allCases.count - 1) * (diameter + gap)
        let maximumSelectedWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 66 : 140
        let selectedWidth = min(maximumSelectedWidth, max(diameter, width - otherButtonsWidth - 10))

        return HStack(spacing: gap) {
            ForEach(LiyaTab.allCases, id: \.rawValue) { item in
                let selected = selection == item
                let icon = Image(item.image).renderingMode(.original).resizable().scaledToFit()
                    .frame(width: selected ? 36 : 32, height: selected ? 36 : 32)
                Button {
                    selection = item
                } label: {
                    Group {
                        if selected && !dynamicTypeSize.isAccessibilitySize {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 3) {
                                    icon
                                    Text(LocalizedStringKey(item.title))
                                        .font(LiyaType.text(.subheadline, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                                .fixedSize()
                                icon
                            }
                        } else {
                            icon
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(width: selected ? selectedWidth : diameter, height: diameter)
                    .modifier(TabGlassSurface(selected: selected))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(item.title)))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 5)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: selection)
    }
}

private struct TabGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let selected: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(selected ? liyaAccent : .secondary, lineWidth: selected ? 2 : 1)
                        .allowsHitTesting(false)
                }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(selected ? liyaAccent.opacity(0.20) : nil).interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(selected ? liyaAccent.opacity(0.7) : .white.opacity(0.55))
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    @Environment(\.locale) private var locale
    @State private var policy: PolicyPage?
    @State private var agreed = false
    @State private var showAgreementReminder = false
    @State private var showEmail = false
    @State private var appleNonce: String?
    @State private var accountChoice: WelcomeAccountChoice?
    var body: some View {
        ZStack {
            LiyaBackground(name: "welcome-clear")
            DuoControlRegion { size in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: max(180, size.height * 0.38))
                        VStack(spacing: 6) {
                            Text("Share how you feel")
                                .font(LiyaType.journalTitle)
                                .foregroundStyle(.white)
                            Text("Every mood belongs here.")
                                .font(LiyaType.detail)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: 22)
                        signInActions.frame(maxWidth: 350)
                        if let name = session.savedAccountLabel {
                            Button {
                                accountChoice = WelcomeAccountChoice(name: name, action: .resume)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(decorative: "navigation-profile").resizable().scaledToFit().frame(width: 26, height: 26)
                                    Text("Saved account").font(LiyaType.text(.footnote, weight: .semibold))
                                    if name != String(localized: "Saved account", locale: locale) {
                                        Text(verbatim: name).font(LiyaType.text(.footnote)).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                .foregroundStyle(liyaInk)
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(session.isSigningIn || session.passwordRecovery)
                            .padding(.top, 8)
                        }
                        if let errorMessage = session.errorMessage {
                            Text(LocalizedStringKey(errorMessage)).font(LiyaType.text(.footnote)).foregroundStyle(.white)
                                .multilineTextAlignment(.center).padding(.top, 8)
                        }
                        if let notice = session.welcomeNotice {
                            Text(LocalizedStringKey(notice)).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(.white)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                        }
                        if session.showAppleRevocationHelp {
                            Text("If you used Sign in with Apple, you can also stop using Apple with Liya in your Apple Account settings.")
                                .font(LiyaType.text(.footnote)).foregroundStyle(.white)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                            Link("How to manage Sign in with Apple", destination: URL(string: "https://support.apple.com/en-us/102571")!)
                                .font(LiyaType.text(.footnote, weight: .semibold)).underline().foregroundStyle(.white).frame(minHeight: 44)
                        }
                        agreementRow.padding(.top, 10)
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
        }
        .onLiyaChange(of: session.emailConfirmationID) { confirmation in
            if showEmail, confirmation != nil, !session.passwordRecovery {
                showEmail = false
                finishSignIn()
            }
        }
        .onLiyaChange(of: session.passwordRecovery) { recovering in
            if recovering { showEmail = false }
        }.sheet(isPresented: Binding(
            get: { showEmail || session.passwordRecovery },
            set: { if !$0 { showEmail = false } }
        )) {
            EmailAccountView(recovery: session.passwordRecovery) {
                showEmail = false
                finishSignIn()
            }
            .id(session.passwordRecovery)
            .environmentObject(session)
        }.sheet(item: $policy) { page in
            NavigationStack {
                LegalDocumentView(page: page)
            }
        }.sheet(item: $accountChoice) { choice in
            WelcomeAccountSheet(choice: choice, onResume: finishSignIn)
        }
    }

    private var signInActions: some View {
        VStack(spacing: 12) {
            WelcomeAction(title: "Continue with email", image: "consent-button", foreground: .white) {
                if agreed { session.clearAuthFeedback(); showEmail = true }
                else { showAgreementReminder = true }
            }
            .disabled(session.isSigningIn)
            .clipShape(Capsule())
            SignInWithAppleButton(.continue) { request in
                let nonce = UUID().uuidString + UUID().uuidString
                appleNonce = nonce
                request.requestedScopes = [.email, .fullName]
                request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
            } onCompletion: { result in
                let nonce = appleNonce
                appleNonce = nil
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let data = credential.identityToken,
                          let token = String(data: data, encoding: .utf8), let nonce else {
                        session.appleAuthorizationFailed(); return
                    }
                    let subject = credential.user
                    let signIn: @MainActor () async -> Void = {
                        if await session.appleSignIn(token: token, nonce: nonce, subject: subject) { finishSignIn() }
                    }
                    if let name = session.savedAccountLabel, !session.matchesSavedApple(subject) {
                        accountChoice = WelcomeAccountChoice(name: name, action: .replace(signIn))
                    } else {
                        Task { await signIn() }
                    }
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled { session.appleAuthorizationFailed() }
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .overlay {
                Color.white
                    .overlay {
                        Image("apple-continue-english")
                            .resizable().scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 54)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(Text(verbatim: "Continue with Apple"))
            .clipShape(Capsule())
            .disabled(!agreed || session.isSigningIn)
            .accessibilityHidden(!agreed)
            .allowsHitTesting(agreed && !session.isSigningIn)
            .overlay {
                if !agreed {
                    Button { showAgreementReminder = true } label: { Color.clear.contentShape(Rectangle()) }
                        .accessibilityLabel(Text(verbatim: "Continue with Apple"))
                }
            }
        }
    }

    private func finishSignIn() {
        guard !store.inPreview, !session.passwordRecovery, session.hasSavedMemberSession, let owner = session.userID else { return }
        store.prepareCloudSpace(owner)
        store.inPreview = true
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
                    .font(LiyaType.text(.footnote)).foregroundStyle(liyaInk)
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
                .font(LiyaType.text(.footnote, weight: .semibold))
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
                .font(LiyaType.text(.title3, weight: .bold)).foregroundStyle(liyaInk)
                .multilineTextAlignment(.center)
            Text("Please read and agree to our Terms of Service and Privacy Policy before continuing.")
                .font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.8))
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
            .font(LiyaType.text(.footnote, weight: .semibold))
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
            Text(LocalizedStringKey(page.title)).underline()
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

struct EmailAccountView: View {
    enum Mode { case signIn, signUp, reset, newPassword }
    let onSuccess: () -> Void
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var validation: String?
    @State private var accountChoice: WelcomeAccountChoice?
    @FocusState private var focused: Field?
    private enum Field { case email, password, confirmation }

    init(recovery: Bool = false, onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
        _mode = State(initialValue: recovery ? .newPassword : .signIn)
    }

    private var title: String {
        switch mode {
        case .signIn: return "Welcome back"
        case .signUp: return "Make Liya yours"
        case .reset: return "Reset your password"
        case .newPassword: return "Choose a new password"
        }
    }

    var body: some View {
        ZStack {
            LiyaBackground()
            DuoControlRegion { size in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Spacer()
                            Button("Close") {
                                if mode == .newPassword { Task { if await session.cancelPasswordRecovery() { dismiss() } } }
                                else { dismiss() }
                            }
                            .font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaAccent)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(session.isSigningIn)
                        }
                        Text(LocalizedStringKey(title)).font(LiyaType.text(.largeTitle, weight: .bold)).foregroundStyle(liyaInk)
                        Text(mode == .signIn ? "Sign in to pick up where you left off." : mode == .signUp ? "Create an account for your moments and connections." : mode == .reset ? "We'll send a link to your email address." : "Use a password you haven't used before.")
                            .font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 16) {
                            if mode != .newPassword {
                                fieldLabel("Email")
                                TextField("you@example.com", text: $email)
                                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($focused, equals: .email).submitLabel(.next)
                                    .onSubmit { focused = mode == .reset ? nil : .password }
                                    .padding(16).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                            }
                            if mode != .reset {
                                fieldLabel(mode == .newPassword ? "New password" : "Password")
                                SecureField("At least 6 characters", text: $password)
                                    .textContentType(mode == .signIn ? .password : .newPassword)
                                    .focused($focused, equals: .password).submitLabel(mode == .signIn ? .go : .next)
                                    .onSubmit { if mode == .signIn { submit() } else { focused = .confirmation } }
                                    .padding(16).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                            }
                            if mode == .signUp || mode == .newPassword {
                                fieldLabel("Confirm password")
                                SecureField("Enter your password again", text: $confirmation)
                                    .textContentType(.newPassword).focused($focused, equals: .confirmation)
                                    .submitLabel(.go).onSubmit { submit() }
                                    .padding(16).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        if let message = validation ?? session.errorMessage {
                            Text(message).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let notice = session.authNotice {
                            Text(notice).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(liyaInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        WelcomeAction(title: session.isSigningIn ? "Please wait…" : actionTitle, image: "consent-button", foreground: .white, isLoading: session.isSigningIn) { submit() }
                            .disabled(session.isSigningIn)
                        if mode != .newPassword {
                            HStack {
                                Button(mode == .signUp ? "Already have an account? Sign in" : "Create account") {
                                    changeMode(mode == .signUp ? .signIn : .signUp)
                                }.frame(minHeight: 44)
                                Spacer()
                                if mode == .signIn {
                                    Button("Forgot password?") { changeMode(.reset) }.frame(minHeight: 44)
                                } else if mode == .reset {
                                    Button("Sign in") { changeMode(.signIn) }.frame(minHeight: 44)
                                }
                            }.font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent)
                                .disabled(session.isSigningIn)
                        }
                    }
                    .frame(maxWidth: 430, alignment: .leading)
                    .frame(maxWidth: .infinity, minHeight: size.height, alignment: .top)
                    .padding(.horizontal, 24).padding(.bottom, 28)
                }
            }
        }
        .interactiveDismissDisabled(session.isSigningIn || mode == .newPassword)
        .sheet(item: $accountChoice) { choice in
            WelcomeAccountSheet(choice: choice, onResume: onSuccess)
        }
    }

    private var actionTitle: String {
        switch mode { case .signIn: return "Sign in"; case .signUp: return "Create account"; case .reset: return "Send reset link"; case .newPassword: return "Save password" }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title)).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
    }

    private func changeMode(_ next: Mode) {
        mode = next; password = ""; confirmation = ""; validation = nil; session.clearAuthFeedback()
    }

    private func submit() {
        validation = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode != .newPassword && (!cleanEmail.contains("@") || cleanEmail.contains(" ")) {
            validation = "Enter a valid email address."; return
        }
        if mode != .reset && password.isEmpty { validation = "Enter your password."; return }
        if (mode == .signUp || mode == .newPassword) && password.count < 6 {
            validation = "Choose a password with at least 6 characters."; return
        }
        if (mode == .signUp || mode == .newPassword) && password != confirmation {
            validation = "Your passwords don't match."; return
        }
        focused = nil
        let selectedMode = mode
        let submittedPassword = password
        let submitCredentials: @MainActor () async -> Void = {
            let succeeded: Bool
            switch selectedMode {
            case .signIn: succeeded = await session.emailSignIn(email: cleanEmail, password: submittedPassword)
            case .signUp: succeeded = await session.emailSignUp(email: cleanEmail, password: submittedPassword)
            case .reset: await session.sendPasswordReset(email: cleanEmail); succeeded = false
            case .newPassword: succeeded = await session.updatePassword(submittedPassword)
            }
            if succeeded { password = ""; confirmation = ""; onSuccess() }
        }
        let reauthenticating = selectedMode == .signIn && session.matchesSavedEmail(cleanEmail)
        if selectedMode != .newPassword, !reauthenticating, let name = session.savedAccountLabel {
            accountChoice = WelcomeAccountChoice(name: name, action: .replace(submitCredentials))
        } else {
            Task { await submitCredentials() }
        }
    }
}

private struct WelcomeAccountChoice: Identifiable {
    enum Action {
        case resume
        case replace(@MainActor () async -> Void)
    }

    let id = UUID()
    let name: String
    let action: Action
}

private struct WelcomeAccountSheet: View {
    let choice: WelcomeAccountChoice
    let onResume: () -> Void
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var calls: LiyaCalls
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        PageShell(title: title) {
            VStack(spacing: 16) {
                Image(decorative: "navigation-profile").resizable().scaledToFit().frame(width: 48, height: 48)
                switch choice.action {
                case .resume: Text("Keep using \(choice.name)?")
                case .replace: Text("Sign out of \(choice.name) to continue?")
                }
                if let errorMessage {
                    Text(LocalizedStringKey(errorMessage)).font(LiyaType.text(.footnote)).foregroundStyle(.secondary)
                }
                WelcomeAction(title: working ? "Please wait…" : actionTitle, image: "consent-button",
                              foreground: .white, isLoading: working) {
                    guard !working else { return }
                    working = true
                    Task { await confirm() }
                }.clipShape(Capsule())
            }
            .multilineTextAlignment(.center).foregroundStyle(liyaInk)
            .padding(20).frame(maxWidth: 380).frame(maxWidth: .infinity)
        }
        .disabled(working)
        .interactiveDismissDisabled(working)
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch choice.action { case .resume: return "Saved account"; case .replace: return "Switch accounts?" }
    }

    private var actionTitle: String {
        switch choice.action { case .resume: return "Continue"; case .replace: return "Sign out and continue" }
    }

    private func confirm() async {
        defer { working = false }
        switch choice.action {
        case .resume:
            if await session.restoreSavedAccount() {
                onResume()
            } else if session.hasSavedMemberSession {
                errorMessage = session.errorMessage
            } else {
                dismiss()
            }
        case .replace(let signIn):
            if session.hasSavedMemberSession {
                guard await session.signOutForAccountChange(store: store, social: social, calls: calls) else {
                    errorMessage = session.signOutError
                    return
                }
            }
            await signIn()
            dismiss()
        }
    }
}

struct WelcomeAction: View {
    let title: String
    let image: String
    let foreground: Color
    var isLoading = false
    var fullArtwork = false
    @ScaledMetric(relativeTo: .headline) var artworkLabelInset: CGFloat = 18
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            if fullArtwork {
                ZStack {
                    Color.clear.aspectRatio(2172.0 / 724.0, contentMode: .fit)
                    label.padding(.vertical, artworkLabelInset)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background { Image(decorative: image).resizable() }
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
            Text(LocalizedStringKey(title))
                .font(LiyaType.action)
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 16)
    }
}
