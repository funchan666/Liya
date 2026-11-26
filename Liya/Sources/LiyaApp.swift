import SwiftUI

@main
struct LiyaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = LocalStore()
    @StateObject private var checkout = CoinCheckout()
    @StateObject private var session = LiyaSession()
    @StateObject private var social = SocialStore()
    @StateObject private var calls = LiyaCalls()
    @State private var showingLaunch = true
    @AppStorage("liya.language") private var language = "en"

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(checkout).environmentObject(session).environmentObject(social).environmentObject(calls)
                .font(LiyaType.reading)
                .environment(\.locale, Locale(identifier: language))
                .accessibilityHidden(showingLaunch)
                .overlay {
                    if showingLaunch { LiyaLaunchOverlay() }
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
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            DuoControlRegion { _ in
                ZStack {
                    Image("launch-icon").resizable().scaledToFit().frame(width: 140, height: 140)
                        .accessibilityHidden(true)
                    VStack(spacing: 2) {
                        LiyaLoadingIndicator(size: 38).accessibilityHidden(true)
                        Text("Opening Liya…").font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(.white)
                    }
                    .offset(y: 110)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
