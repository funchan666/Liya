import Foundation
import Combine

struct LiyaCall: Identifiable {
    let id: UUID
}

@MainActor
final class LiyaCalls: ObservableObject {
    @Published private(set) var call: LiyaCall?
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var permissionDenied = false

    func watch(_ session: LiyaSession) async { }
    func refresh(_ session: LiyaSession) async { }
    func start(_ session: LiyaSession, peer: UUID, kind: String) async {
        error = "Calls are unavailable right now."
    }
    func end(_ session: LiyaSession) async { call = nil }
    func reset() async { call = nil; error = nil; permissionDenied = false }
}
