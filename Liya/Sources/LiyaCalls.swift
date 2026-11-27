import AVFoundation
import SwiftUI

enum LiyaCallKind {
    case voice, video
}

struct LiyaCall: Identifiable {
    let id = UUID()
    let ownerID: UUID
    let peerID: UUID
    let displayName: String
    let kind: LiyaCallKind
}

enum LiyaCallStartResult {
    case started(UUID)
    case notMutual, cancelled
    case failure(String)
    case permissionDenied(String)
}

private enum WaitingRoomInput {
    case frontCamera, microphone

    var media: AVMediaType { self == .frontCamera ? .video : .audio }

    var unavailableReason: String {
        self == .frontCamera ? "The front camera is unavailable." : "The microphone is unavailable."
    }

    var previousDenialReason: String {
        self == .frontCamera ? "Camera access is off. Your video preview is unavailable." : "Microphone access is off. Your sound level is unavailable."
    }

    var hasDevice: Bool {
        switch self {
        case .frontCamera: return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
        case .microphone: return AVCaptureDevice.default(for: .audio) != nil
        }
    }
}

@MainActor
final class LiyaCalls: ObservableObject {
    @Published private(set) var call: LiyaCall?
    private var pendingCall: LiyaCall?

    func start(_ session: LiyaSession, social: SocialStore, peer: UUID, kind: LiyaCallKind,
               displayName: String) async -> LiyaCallStartResult {
        guard let owner = session.userID, !session.isGuest, owner != peer else { return .notMutual }
        guard call == nil, pendingCall == nil, !session.isSigningOut, !session.isDeletingAccount, !Task.isCancelled else { return .cancelled }
        let request = LiyaCall(ownerID: owner, peerID: peer, displayName: displayName, kind: kind)
        pendingCall = request
        defer { if pendingCall?.id == request.id { pendingCall = nil } }

        func isCurrent() -> Bool {
            pendingCall?.id == request.id && session.userID == owner &&
                !session.isSigningOut && !session.isDeletingAccount && !Task.isCancelled
        }

        do {
            let allowed = try await social.isMutualFollow(session, target: peer)
            guard isCurrent() else { return .cancelled }
            guard allowed else { return .notMutual }

            let inputs: [WaitingRoomInput] = kind == .video ? [.frontCamera, .microphone] : [.microphone]
            var needsPermission: [WaitingRoomInput] = []
            for input in inputs {
                switch AVCaptureDevice.authorizationStatus(for: input.media) {
                case .authorized: break
                case .notDetermined: needsPermission.append(input)
                case .denied: return .permissionDenied(input.previousDenialReason)
                case .restricted: return .failure(input.unavailableReason)
                @unknown default: return .failure(input.unavailableReason)
                }
                guard input.hasDevice else { return .failure(input.unavailableReason) }
            }
            for input in needsPermission {
                let granted = await AVCaptureDevice.requestAccess(for: input.media)
                guard isCurrent(), granted else { return .cancelled }
            }
            if !needsPermission.isEmpty {
                let stillMutual = try await social.isMutualFollow(session, target: peer)
                guard isCurrent() else { return .cancelled }
                guard stillMutual else { return .notMutual }
            }
            call = request
            return .started(request.id)
        } catch {
            guard isCurrent() else { return .cancelled }
            return .failure("Couldn’t check your connection. Try again in a moment.")
        }
    }

    func retainSession(_ owner: UUID?) {
        if let pendingCall, pendingCall.ownerID != owner { self.pendingCall = nil }
        if let call, call.ownerID != owner { self.call = nil }
    }

    func reset() {
        pendingCall = nil
        call = nil
    }

    func cancel(_ id: UUID) {
        if call?.id == id { call = nil }
    }
}

struct LiyaCallScreen: View {
    @Environment(\.liyaWords) private var words
    let call: LiyaCall
    @EnvironmentObject private var calls: LiyaCalls
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var capture = WaitingMediaCapture()

    var body: some View {
        ZStack {
            LiyaBackground(name: call.kind == .video ? "journal-paper-daybreak" : "journal-paper-tideglass")
            Color(red: 0.09, green: 0.06, blue: 0.18).opacity(0.72).ignoresSafeArea()
            DuoControlRegion { size in
                VStack(spacing: 10) {
                    GeometryReader { viewport in
                        ScrollView {
                            VStack(spacing: 18) {
                                callHeader
                                if call.kind == .video {
                                    cameraPreview(height: min(370, max(140, size.height * 0.46)))
                                }
                                microphoneMeter
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 18)
                            .frame(maxWidth: 450)
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                        }
                        .modifier(AdaptiveContainerMargins())
                    }
                    Button(action: endWaiting) {
                        Text(verbatim: words("Cancel call"))
                            .font(LiyaType.action)
                            .padding(.horizontal, 32).padding(.vertical, 10)
                            .frame(minHeight: 48)
                            .modifier(CallCancelGlass())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape) { endWaiting() }
        .onAppear { updateCapture() }
        .onLiyaChange(of: scenePhase) { _ in updateCapture() }
        .onLiyaChange(of: calls.call?.id) { _ in updateCapture() }
        .onLiyaChange(of: session.userID) { _ in updateCapture() }
        .onDisappear { endWaiting() }
    }

    private var callHeader: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                HostedArtwork(call.kind == .video ? "profile-action-video" : "profile-action-voice").scaledToFit().frame(width: 23, height: 23)
                    .accessibilityHidden(true)
                Text(verbatim: words(call.kind == .video ? "Video call" : "Voice call"))
                    .font(LiyaType.text(.subheadline, weight: .semibold))
            }
            if call.kind == .voice {
                SocialAvatar(personID: call.peerID)
                    .frame(width: 92, height: 92)
                    .background(.white.opacity(0.92), in: Circle()).clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.42), lineWidth: 1))
                    .padding(.vertical, 8).accessibilityHidden(true)
            }
            Text(verbatim: call.displayName)
                .font(LiyaType.journalTitle).accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                if !reduceMotion { LiyaLoadingIndicator(size: 19).accessibilityHidden(true) }
                Text(verbatim: words("Waiting…")).font(LiyaType.reading)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func cameraPreview(height: CGFloat) -> some View {
        ZStack {
            Color.black
            if scenePhase == .active {
                WaitingSelfPreview(capture: capture).accessibilityHidden(true)
            }
            if capture.state != .running || scenePhase != .active {
                Color.black
                if scenePhase == .active && (capture.state == .starting || capture.state == .idle) {
                    ProgressView().tint(.white).accessibilityLabel(Text(verbatim: words("Starting camera")))
                } else if capture.state == .unavailable {
                    Text(verbatim: words("Preview unavailable")).font(LiyaType.reading)
                } else {
                    Text(verbatim: words("Preview paused")).font(LiyaType.reading)
                }
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .overlay(alignment: .bottomLeading) {
            Text(verbatim: words("Your camera"))
                .font(LiyaType.text(.caption, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.68), in: Capsule())
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).strokeBorder(.white.opacity(0.27)))
    }

    @ViewBuilder private var microphoneMeter: some View {
        if capture.state == .running && scenePhase == .active {
            ProgressView(value: capture.microphoneLevel, total: 1) {
                Text(verbatim: words("Microphone level")).font(LiyaType.text(.subheadline, weight: .semibold))
            }
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(maxWidth: 240)
            .padding(.vertical, 8)
        } else if call.kind == .voice && capture.state == .unavailable {
            Text(verbatim: words("Microphone unavailable")).font(LiyaType.reading)
        } else if call.kind == .voice && capture.state == .interrupted {
            Text(verbatim: words("Microphone paused")).font(LiyaType.reading)
        }
    }

    private func updateCapture() {
        guard scenePhase == .active, calls.call?.id == call.id, session.userID == call.ownerID else {
            capture.stop()
            return
        }
        capture.start(video: call.kind == .video)
    }

    private func endWaiting() {
        capture.stop()
        calls.cancel(call.id)
    }
}

private struct CallCancelGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let tint = Color(red: 0.65, green: 0.16, blue: 0.30)

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(tint, in: Capsule())
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26, *) {
                content.glassEffect(.regular.tint(tint).interactive(), in: Capsule())
            } else {
                content.background(tint, in: Capsule()).background(.thinMaterial, in: Capsule())
            }
            #else
            content.background(tint, in: Capsule()).background(.thinMaterial, in: Capsule())
            #endif
        }
    }
}
