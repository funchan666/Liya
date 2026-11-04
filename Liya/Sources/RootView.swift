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
        case .discover: return "nav-soft-video"
        case .square: return "nav-soft-square"
        case .compose: return "nav-soft-create"
        case .messages: return "nav-soft-messages"
        case .profile: return "nav-soft-profile"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var calls: LiyaCalls
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: LiyaTab = .discover
    @State private var profileDetailVisible = false

    var body: some View {
        if !store.inPreview {
            WelcomeView {
                Task {
                    if await session.signIn() {
                        if let owner = session.userID { store.restoreAccountMaterial(owner) }
                        store.inPreview = true
                    }
                }
            }
            .onAppear { selection = .discover; profileDetailVisible = false }
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
              if !profileDetailVisible {
                DuoControlRegion { size in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(LiyaTab.allCases, id: \.rawValue) { item in
                                Button { selection = item } label: {
                                    Image(item.image)
                                        .renderingMode(.original)
                                        .resizable().scaledToFit()
                                        .frame(width: 46, height: 46)
                                        .saturation(selection == item ? 0.90 : 0.55)
                                        .opacity(selection == item ? 1 : 0.68)
                                        .scaleEffect(selection == item ? 1.08 : 1)
                                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection == item)
                                        .frame(width: max(54, (size.width - 24) / CGFloat(LiyaTab.allCases.count)), height: 64)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(item.title))).accessibilityAddTraits(selection == item ? .isSelected : [])
                            }
                        }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                    }
                    .background {
                        if #available(iOS 26.0, *) {
                            Color.clear.glassEffect(.regular, in: Capsule())
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                }
                .frame(height: LiyaTabBarLayout.height)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, LiyaTabBarLayout.bottomPadding)
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

private struct WelcomeView: View {
    let enter: () -> Void
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    @State private var policy: PolicyPage?
    @State private var agreed = false
    @State private var showAgreementReminder = false
    @State private var showEmail = false
    @State private var appleNonce: String?
    var body: some View {
        ZStack {
            LiyaBackground(name: "welcome-clear")
            DuoControlRegion { size in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: max(180, size.height * 0.38))
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
                        Spacer(minLength: 22)
                        WelcomeAction(title: session.isSigningIn ? "Connecting…" : "Continue to Liya", image: "welcome-button-v2", foreground: liyaInk, isLoading: session.isSigningIn, fullArtwork: true) {
                            if agreed { enter() } else { showAgreementReminder = true }
                        }
                        .disabled(session.isSigningIn)
                        WelcomeAction(title: "Continue with email", image: "consent-button", foreground: .white) {
                            if agreed { session.clearAuthFeedback(); showEmail = true }
                            else { showAgreementReminder = true }
                        }
                        .disabled(session.isSigningIn)
                        .padding(.top, 8)
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
                                Task { if await session.appleSignIn(token: token, nonce: nonce) { finishSignIn() } }
                            case .failure(let error):
                                if (error as? ASAuthorizationError)?.code != .canceled { session.appleAuthorizationFailed() }
                            }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .allowsHitTesting(agreed && !session.isSigningIn)
                        .overlay {
                            if !agreed {
                                Button { showAgreementReminder = true } label: { Color.clear.contentShape(Rectangle()) }
                                    .accessibilityLabel("Continue with Apple")
                            }
                        }
                        .padding(.top, 8)
                        if let errorMessage = session.errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.white)
                                .multilineTextAlignment(.center).padding(.top, 8)
                        }
                        if let notice = session.welcomeNotice {
                            Text(LocalizedStringKey(notice)).font(.footnote.weight(.medium)).foregroundStyle(.white)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
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
        }.onLiyaChange(of: session.passwordRecovery) { recovering in
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
        }
    }

    private func finishSignIn() {
        if let owner = session.userID { store.restoreAccountMaterial(owner) }
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
                            .font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(session.isSigningIn)
                        }
                        Text(LocalizedStringKey(title)).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(liyaInk)
                        Text(mode == .signIn ? "Sign in to pick up where you left off." : mode == .signUp ? "Create an account for your moments and connections." : mode == .reset ? "We'll send a link to your email address." : "Use a password you haven't used before.")
                            .font(.subheadline).foregroundStyle(liyaInk.opacity(0.7))
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
                            Text(message).font(.footnote.weight(.medium)).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let notice = session.authNotice {
                            Text(notice).font(.footnote.weight(.medium)).foregroundStyle(liyaInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        WelcomeAction(title: session.isSigningIn ? "Please wait…" : actionTitle, image: "consent-button", foreground: .white, isLoading: session.isSigningIn) { submit() }
                            .disabled(session.isSigningIn)
                        if mode != .newPassword {
                            HStack {
                                Button(mode == .signUp ? "Already have an account? Sign in" : "Create account") {
                                    changeMode(mode == .signUp ? .signIn : .signUp)
                                }
                                .frame(minHeight: 44)
                                Spacer()
                                if mode == .signIn {
                                    Button("Forgot password?") { changeMode(.reset) }.frame(minHeight: 44)
                                } else if mode == .reset {
                                    Button("Sign in") { changeMode(.signIn) }.frame(minHeight: 44)
                                }
                            }
                            .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent)
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
    }

    private var actionTitle: String {
        switch mode { case .signIn: return "Sign in"; case .signUp: return "Create account"; case .reset: return "Send reset link"; case .newPassword: return "Save password" }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
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
        Task {
            let succeeded: Bool
            switch selectedMode {
            case .signIn: succeeded = await session.emailSignIn(email: cleanEmail, password: submittedPassword)
            case .signUp: succeeded = await session.emailSignUp(email: cleanEmail, password: submittedPassword)
            case .reset: await session.sendPasswordReset(email: cleanEmail); succeeded = false
            case .newPassword: succeeded = await session.updatePassword(submittedPassword)
            }
            if succeeded { password = ""; confirmation = ""; onSuccess() }
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
            Text(LocalizedStringKey(title))
                .font(fullArtwork ? .system(size: 17, weight: .semibold, design: .rounded) : .system(size: 16, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 16)
    }
}
