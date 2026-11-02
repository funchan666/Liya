import SwiftUI

@main
struct LiyaApp: App {
    @UIApplicationDelegateAdaptor(LiyaAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = LocalStore()
    @StateObject private var checkout = CoinCheckout()
    @StateObject private var session = LiyaSession()
    @StateObject private var social = SocialStore()
    @StateObject private var calls = LiyaCalls()
    @StateObject private var voip = LiyaVoIP.shared
    @State private var showingLaunch = true

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(checkout).environmentObject(session).environmentObject(social).environmentObject(calls)
                .accessibilityHidden(showingLaunch)
                .overlay {
                    if showingLaunch { LiyaLaunchOverlay() }
                }
                .task {
                    try? await Task.sleep(nanoseconds: 850_000_000)
                    showingLaunch = false
                }
                .sheet(isPresented: Binding(get: { voip.permissionReminder != nil && scenePhase == .active }, set: { if !$0 { voip.dismissPermissionReminder() } })) {
                    LocalConfirmation(title: "Enable call access", message: voip.permissionReminder == "video" ? "The incoming video call couldn't be answered without microphone and camera access. Allow access, then ask the member to call again." : "The incoming call couldn't be answered without microphone access. Allow access, then ask the member to call again.", action: "Allow access") {
                        Task { await voip.resolvePermissionReminder() }
                    } cancel: { voip.dismissPermissionReminder() }
                }
                .task {
                    LiyaVoIP.shared.bind(session: session, calls: calls, store: store)
                    await LiyaVoIP.shared.updateRegistration()
                }
                .onLiyaChange(of: session.userID) { _ in Task { await LiyaVoIP.shared.updateRegistration() } }
                .onLiyaChange(of: calls.call?.id) { id in
                    if id != nil { showingLaunch = false }
                    LiyaVoIP.shared.observeCall(id)
                }
                .onLiyaChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task { await checkout.recover(); await session.resumeAccount(); await social.refresh(session); social.watchMessages(session); await LiyaVoIP.shared.updateRegistration() }
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
                        Text("Opening Liya…").font(.footnote.weight(.medium)).foregroundStyle(.white)
                    }
                    .offset(y: 110)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
