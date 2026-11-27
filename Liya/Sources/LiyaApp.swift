import SwiftUI

@main
struct LiyaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = LocalStore()
    @StateObject private var checkout = CoinCheckout()
    @StateObject private var session = LiyaSession()
    @StateObject private var social = SocialStore()
    @StateObject private var interface = InterfaceLibrary()
    @StateObject private var calls = LiyaCalls()
    @State private var showingLaunch = true
    @AppStorage("liya.language") private var language = "en"

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(checkout).environmentObject(session).environmentObject(social).environmentObject(calls)
                .font(interface.fontsReady ? LiyaType.reading : .body)
                .environment(\.locale, Locale(identifier: language))
                .accessibilityHidden(showingLaunch)
                .overlay {
                    if showingLaunch { LiyaLaunchOverlay() }
                }
                .environment(\.liyaWords, interface.wording(in: language))
                .environmentObject(interface)
                .task(id: "\(interface.connectionRevision)/\(scenePhase == .background)") {
                    guard scenePhase != .background else { return }
                    async let fonts: Void = interface.prepareFonts()
                    async let wording: Void = interface.prepareWording()
                    _ = await (fonts, wording)
                }
                .task {
                    guard showingLaunch else { return }
                    session.prepareWelcome(store: store)
                    try? await Task.sleep(nanoseconds: 850_000_000)
                    showingLaunch = false
                }
                .onOpenURL { url in
                    Task {
                        while session.isSigningIn {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            if Task.isCancelled { return }
                        }
                        _ = await session.handleAuthURL(url)
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    checkout.recover()
                }
                .onLiyaChange(of: store.inPreview ? session.userID : nil) { owner in
                    calls.retainSession(owner)
                }
                .onLiyaChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task {
                            await session.resumeAccount()
                            await social.refresh(session)
                            social.watchMessages(session)
                        }
                    }
                }
        }
    }
}

private struct LiyaLaunchOverlay: View {
    @Environment(\.liyaWords) private var words
    var body: some View {
        ZStack {
            Color(red: 0.243, green: 0.235, blue: 0.882).ignoresSafeArea()
            DuoControlRegion { _ in
                ZStack {
                    HostedArtwork("launch-icon").scaledToFit().frame(width: 140, height: 140)
                        .accessibilityHidden(true)
                    VStack(spacing: 2) {
                        LiyaLoadingIndicator(size: 38).accessibilityHidden(true)
                        Text(verbatim: words("Opening Liya…")).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(.white)
                    }
                    .offset(y: 110)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
