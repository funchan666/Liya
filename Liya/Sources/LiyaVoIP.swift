import UIKit
import PushKit
import CallKit
import AVFoundation
import LiveKit
import Supabase

/// PushKit is activated only after a real bundle identifier and server-side APNs configuration exist.
@MainActor
final class LiyaVoIP: NSObject, ObservableObject, @preconcurrency PKPushRegistryDelegate, @preconcurrency CXProviderDelegate {
    static let shared = LiyaVoIP()
    private let provider: CXProvider
    private var registry: PKPushRegistry?
    private weak var session: LiyaSession?
    private weak var calls: LiyaCalls?
    private weak var store: LocalStore?
    private var token: String?
    private var systemCall: UUID?
    private var incomingMonitor: Task<Void, Never>?
    private var systemAudio = false
    private let readyKey = "liya.voip.configured"
    @Published private(set) var permissionReminder: String? = UserDefaults.standard.string(forKey: "liya.voip.permissionReminder")

    override private init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }
    func startIfPreviouslyConfigured() {
        guard UserDefaults.standard.bool(forKey: readyKey) else { return }
        startRegistry()
    }
    func bind(session: LiyaSession, calls: LiyaCalls, store: LocalStore) {
        self.session = session; self.calls = calls; self.store = store
    }
    func updateRegistration() async {
        guard let session, session.userID != nil, !session.isSigningOut, !session.isDeletingAccount,
              let bundle = Bundle.main.bundleIdentifier, !bundle.hasPrefix("example.") else { return }
        do {
            struct Status: Decodable { let configured: Bool; let bundleID: String?; enum CodingKeys: String, CodingKey { case configured; case bundleID = "bundle_id" } }
            let status: Status = try await session.client.functions.invoke("liya-voip-registration", options: FunctionInvokeOptions(body: ["action":"status"]))
            guard status.configured, status.bundleID == bundle else { UserDefaults.standard.set(false, forKey: readyKey); return }
            UserDefaults.standard.set(true, forKey: readyKey)
            startRegistry()
            await uploadToken()
        } catch { /* Registration is retried after the account resumes. */ }
    }
    private func startRegistry() {
        guard registry == nil, let bundle = Bundle.main.bundleIdentifier, !bundle.hasPrefix("example.") else { return }
        let value = PKPushRegistry(queue: .main)
        value.delegate = self
        value.desiredPushTypes = [.voIP]
        registry = value
    }
    private func uploadToken() async {
        guard let session, session.userID != nil, let token, let bundle = Bundle.main.bundleIdentifier else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        struct Result: Decodable { let ok: Bool }
        do {
            let _: Result = try await session.client.functions.invoke("liya-voip-registration", options: FunctionInvokeOptions(body: ["action":"register","token":token,"environment":environment,"bundle_id":bundle]))
        } catch { /* The next account resume retries the current token. */ }
    }
    func unregisterForSignOut() async -> Bool {
        guard let token else { return !UserDefaults.standard.bool(forKey: readyKey) }
        guard let session, session.userID != nil else { return false }
        struct Result: Decodable { let ok: Bool }
        do {
            let result: Result = try await session.client.functions.invoke("liya-voip-registration", options: FunctionInvokeOptions(body: ["action": "unregister", "token": token]))
            return result.ok
        } catch { return false }
    }
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        token = credentials.token.map { String(format: "%02x", $0) }.joined()
        Task { await uploadToken() }
    }
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        let old = token; token = nil
        guard let old, let session, session.userID != nil else { return }
        Task {
            struct Result: Decodable { let ok: Bool }
            let _: Result? = try? await session.client.functions.invoke("liya-voip-registration", options: FunctionInvokeOptions(body: ["action":"unregister","token":old]))
        }
    }
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        let id = (payload.dictionaryPayload["call_id"] as? String).flatMap(UUID.init(uuidString:))
        let reported = id ?? UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "Liya member")
        update.localizedCallerName = "Liya member"
        update.hasVideo = payload.dictionaryPayload["video"] as? Bool ?? false
        update.supportsHolding = false
        provider.reportNewIncomingCall(with: reported, update: update) { [weak self] error in
            completion()
            Task { @MainActor in
                guard let self else { return }
                guard error == nil, let id else {
                    if error == nil { self.provider.reportCall(with: reported, endedAt: Date(), reason: .failed) }
                    return
                }
                self.systemCall = id
                await self.refreshIncoming(id)
            }
        }
    }
    private func refreshIncoming(_ id: UUID) async {
        await waitForBinding()
        guard let session, let calls, await session.restoreForIncomingCall() else {
            provider.reportCall(with: id, endedAt: Date(), reason: .failed); systemCall = nil; return
        }
        await waitForCall(id, session: session, calls: calls)
        guard calls.call?.id == id else {
            provider.reportCall(with: id, endedAt: Date(), reason: .remoteEnded); systemCall = nil; return
        }
        guard calls.call?.status == "ringing" else { return }
        incomingMonitor?.cancel()
        incomingMonitor = Task { [weak self, weak session, weak calls] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard let self, let session, let calls, self.systemCall == id else { return }
                await calls.refresh(session)
                if calls.call?.id != id {
                    self.provider.reportCall(with: id, endedAt: Date(), reason: .remoteEnded)
                    self.systemCall = nil
                    return
                }
                if calls.call?.status != "ringing" { return }
            }
        }
    }
    func providerDidReset(_ provider: CXProvider) {
        let previous = systemCall
        incomingMonitor?.cancel(); incomingMonitor = nil
        systemCall = nil
        restoreAutomaticAudio()
        if let previous, let session, let calls, calls.call?.id == previous { Task { await calls.end(session) } }
    }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            await waitForBinding()
            guard systemCall == action.callUUID, let session, let calls, await session.restoreForIncomingCall() else { action.fail(); return }
            await waitForCall(action.callUUID, session: session, calls: calls)
            guard let call = calls.call, call.id == action.callUUID, call.status == "ringing",
                  AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                  call.kind != "video" || AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                if let call = calls.call, call.id == action.callUUID {
                    permissionReminder = call.kind
                    UserDefaults.standard.set(call.kind, forKey: "liya.voip.permissionReminder")
                }
                if calls.call?.id == action.callUUID { await calls.end(session) }
                action.fail(); provider.reportCall(with: action.callUUID, endedAt: Date(), reason: .failed); systemCall = nil; return
            }
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
            do { try AudioManager.shared.setEngineAvailability(.none); systemAudio = true }
            catch { restoreAutomaticAudio(); action.fail(); return }
            await calls.accept(session)
            guard calls.room != nil, calls.call?.id == action.callUUID else {
                restoreAutomaticAudio(); action.fail(); provider.reportCall(with: action.callUUID, endedAt: Date(), reason: .failed); systemCall = nil; return
            }
            store?.inPreview = true
            incomingMonitor?.cancel(); incomingMonitor = nil
            action.fulfill()
        }
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            if let calls, let session, calls.call?.id == action.callUUID { await calls.end(session) }
            incomingMonitor?.cancel(); incomingMonitor = nil
            systemCall = nil; action.fulfill(); restoreAutomaticAudio()
        }
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            guard systemCall == action.callUUID, let calls, calls.room != nil else { action.fail(); return }
            if calls.microphoneOn == action.isMuted { await calls.toggleMicrophone() }
            if calls.microphoneOn != action.isMuted { action.fulfill() } else { action.fail() }
        }
    }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        guard systemAudio else { return }
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
            try AudioManager.shared.setEngineAvailability(.default)
        } catch {
            if let id = systemCall { provider.reportCall(with: id, endedAt: Date(), reason: .failed); systemCall = nil }
            if let calls, let session { Task { await calls.end(session) } }
            restoreAutomaticAudio()
        }
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        if systemAudio { try? AudioManager.shared.setEngineAvailability(.none) }
    }
    func observeCall(_ id: UUID?) {
        guard let systemCall, id != systemCall else { return }
        provider.reportCall(with: systemCall, endedAt: Date(), reason: .remoteEnded)
        incomingMonitor?.cancel(); incomingMonitor = nil
        self.systemCall = nil; restoreAutomaticAudio()
    }
    private func restoreAutomaticAudio() {
        guard systemAudio else { return }
        try? AudioManager.shared.setEngineAvailability(.default)
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        systemAudio = false
    }
    private func waitForBinding() async {
        for _ in 0..<30 {
            if session != nil, calls != nil { return }
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
        }
    }
    func dismissPermissionReminder() {
        permissionReminder = nil
        UserDefaults.standard.removeObject(forKey: "liya.voip.permissionReminder")
    }
    func resolvePermissionReminder() async {
        let video = permissionReminder == "video"
        dismissPermissionReminder()
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if audioStatus == .denied || audioStatus == .restricted || (video && (cameraStatus == .denied || cameraStatus == .restricted)) {
            if let url = URL(string: UIApplication.openSettingsURLString) { _ = await UIApplication.shared.open(url) }
            return
        }
        if audioStatus == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        if video && cameraStatus == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
    }
    private func waitForCall(_ id: UUID, session: LiyaSession, calls: LiyaCalls) async {
        for _ in 0..<20 {
            if calls.call?.id == id { return }
            await calls.refresh(session)
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
        }
    }
}

@MainActor final class LiyaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        LiyaVoIP.shared.startIfPreviouslyConfigured()
        return true
    }
}
