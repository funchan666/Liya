import SwiftUI

@main
struct LiyaApp: App {
    @StateObject private var store = LocalStore()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
        }
    }
}
