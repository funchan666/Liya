import SwiftUI

@main
struct LiyaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = LocalStore()
    @StateObject private var checkout = CoinCheckout()
    @StateObject private var session = LiyaSession()
    @StateObject private var social = SocialStore()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(checkout).environmentObject(session).environmentObject(social)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task { await checkout.recover(); await session.resumeAccount(); await social.refresh(session); social.watchMessages(session) }
                    }
                }
        }
    }
}
