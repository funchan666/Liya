import UIKit
import Combine

@MainActor
final class LiyaVoIP: ObservableObject {
 static let shared = LiyaVoIP()
 func startIfPreviouslyConfigured() { }
 func bind(session: LiyaSession, calls: LiyaCalls, store: LocalStore) { }
 func updateRegistration() async { }
 func unregisterForSignOut() async -> Bool { true }
 func observeCall(_ id: UUID?) { }
}

@MainActor final class LiyaAppDelegate: NSObject, UIApplicationDelegate {
 func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
