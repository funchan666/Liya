import SwiftUI
import AVFoundation
import LiveKit
import Supabase

struct LiyaCall: Decodable, Identifiable {
    let id: UUID
    let callerID: UUID
    let calleeID: UUID
    let kind: String
    let status: String
    let expiresAt: String
    enum CodingKeys: String, CodingKey {
        case id, kind, status
        case callerID = "caller_id", calleeID = "callee_id", expiresAt = "expires_at"
    }
    var expired: Bool {
        guard status == "ringing" else { return false }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: expiresAt) ?? plain.date(from: expiresAt) else { return true }
        return date <= Date()
    }
}

@MainActor
final class LiyaCalls: ObservableObject {
    @Published private(set) var call: LiyaCall?
    @Published private(set) var room: Room?
    @Published private(set) var busy = false
    @Published private(set) var microphoneOn = true
    @Published private(set) var cameraOn = true
    @Published var error: String?
    @Published var permissionDenied = false
    private var allowedID: UUID?
    private var connectingID: UUID?
    private var refreshing = false
    private var ownerID: UUID?
    private var lastHeartbeat = Date.distantPast
    private var connectionFailed = false

    func watch(_ session: LiyaSession) async {
        guard let owner = session.userID else { await reset(); return }
        if ownerID != owner { await reset(); ownerID = owner }
        while !Task.isCancelled && session.userID == owner {
            await refresh(session)
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
        }
        if session.userID != owner { await reset() }
    }
    func refresh(_ session: LiyaSession) async {
        guard let owner = session.userID, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let rows: [LiyaCall] = try await session.client.from("liya_calls")
                .select("id,caller_id,callee_id,kind,status,expires_at")
                .order("created_at", ascending: false).limit(30).execute().value
            guard session.userID == owner else { return }
            let next = rows.first { $0.status != "ended" && !$0.expired }
            if let existing = call, next?.id != existing.id {
                if let room { await room.disconnect(); self.room = nil }
                call = nil; allowedID = nil; connectingID = nil; connectionFailed = false
            }
            guard let next else { return }
            call = next
            if next.status == "accepted", allowedID == next.id, room == nil, connectingID == nil, !connectionFailed {
                await connect(session, call: next)
            }
            if room != nil, next.status == "accepted" {
                if Date().timeIntervalSince(lastHeartbeat) > 15 {
                    let _: LiyaCall = try await session.client.rpc("liya_call_transition", params: ["p_id": next.id.uuidString, "p_action": "heartbeat"]).single().execute().value
                    lastHeartbeat = Date()
                }
            }
        } catch {
            if call != nil { self.error = "Call updates are unavailable. Check your connection." }
        }
    }
    func start(_ session: LiyaSession, peer: UUID, kind: String) async {
        guard !busy, call == nil, let owner = session.userID else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            struct Status: Decodable { let configured: Bool }
            let status: Status = try await session.client.functions.invoke("liya-call-token", options: FunctionInvokeOptions(body: ["action": "status"]))
            guard status.configured else { error = "Calling is not configured yet."; return }
            guard await requestPermissions(video: kind == "video") else { return }
            guard session.userID == owner else { return }
            let id = UUID()
            allowedID = id
            let record: LiyaCall = try await session.client.rpc("liya_call_create", params: ["p_id": id.uuidString, "p_callee": peer.uuidString, "p_kind": kind]).single().execute().value
            call = record
        } catch { self.error = "Couldn't confirm the invitation. The member may be busy or the connection may have been interrupted." }
    }
    func accept(_ session: LiyaSession) async {
        guard let current = call, current.calleeID == session.userID, current.status == "ringing", !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        guard await requestPermissions(video: current.kind == "video") else { return }
        guard session.userID == current.calleeID else { return }
        do {
            allowedID = current.id
            let updated: LiyaCall = try await session.client.rpc("liya_call_transition", params: ["p_id": current.id.uuidString, "p_action": "accept"]).single().execute().value
            call = updated
            await connect(session, call: updated)
        } catch { self.error = "Couldn't confirm the answer. The invitation may have expired or the connection may have been interrupted." }
    }
    private func connect(_ session: LiyaSession, call current: LiyaCall) async {
        guard connectingID == nil, room == nil, allowedID == current.id else { return }
        connectingID = current.id
        defer { connectingID = nil }
        let newRoom = Room()
        do {
            struct Ticket: Decodable { let url: String; let token: String }
            let ticket: Ticket = try await session.client.functions.invoke("liya-call-token", options: FunctionInvokeOptions(body: ["action": "join", "call_id": current.id.uuidString]))
            try await newRoom.connect(url: ticket.url, token: ticket.token)
            guard call?.id == current.id, allowedID == current.id else { await newRoom.disconnect(); return }
            try await newRoom.localParticipant.setMicrophone(enabled: true)
            if current.kind == "video" { try await newRoom.localParticipant.setCamera(enabled: true) }
            guard call?.id == current.id, allowedID == current.id else { await newRoom.disconnect(); return }
            microphoneOn = true; cameraOn = current.kind == "video"; room = newRoom; connectionFailed = false
            lastHeartbeat = .distantPast
        } catch {
            await newRoom.disconnect()
            self.error = "Couldn't connect the call. Please try again."
            connectionFailed = true
        }
    }
    func end(_ session: LiyaSession) async {
        let id = call?.id
        allowedID = nil; connectingID = nil
        if let room { await room.disconnect(); self.room = nil }
        call = nil; connectionFailed = false
        if let id {
            do {
                let _: LiyaCall = try await session.client.rpc("liya_call_transition", params: ["p_id": id.uuidString, "p_action": "end"]).single().execute().value
            } catch { self.error = "Couldn't confirm that the call ended. Please check your connection." }
        }
    }
    func toggleMicrophone() async {
        guard let room else { return }
        do { try await room.localParticipant.setMicrophone(enabled: !microphoneOn); microphoneOn.toggle() }
        catch { self.error = "Couldn't change the microphone. Please try again." }
    }
    func toggleCamera() async {
        guard let room else { return }
        do { try await room.localParticipant.setCamera(enabled: !cameraOn); cameraOn.toggle() }
        catch { self.error = "Couldn't change the camera. Please try again." }
    }
    func retryConnection(_ session: LiyaSession) async {
        guard let current = call, current.status == "accepted", allowedID == current.id, !busy else { return }
        busy = true
        defer { busy = false }
        if let room { await room.disconnect(); self.room = nil }
        error = nil; connectionFailed = false
        await connect(session, call: current)
    }
    func reset() async {
        allowedID = nil; connectingID = nil
        if let room { await room.disconnect(); self.room = nil }
        call = nil; ownerID = nil; connectionFailed = false; error = nil; permissionDenied = false
    }
    private func requestPermissions(video: Bool) async -> Bool {
        func access(_ kind: AVMediaType) async -> Bool {
            switch AVCaptureDevice.authorizationStatus(for: kind) {
            case .authorized: return true
            case .notDetermined: return await AVCaptureDevice.requestAccess(for: kind)
            default: return false
            }
        }
        guard await access(.audio) else { permissionDenied = true; error = "Microphone access is needed for a call."; return false }
        if video {
            guard await access(.video) else { permissionDenied = true; error = "Camera access is needed for a video call."; return false }
        }
        permissionDenied = false
        return true
    }
}

struct LiyaCallScreen: View {
    @EnvironmentObject private var calls: LiyaCalls
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.openURL) private var openURL
    let initial: LiyaCall
    private var call: LiyaCall { calls.call ?? initial }
    private var peer: UUID { call.callerID == session.userID ? call.calleeID : call.callerID }
    var body: some View {
        ZStack {
            LiyaBackground(name: "color-background")
            DuoControlRegion { size in
                ScrollView {
                    VStack(spacing: 18) {
                        Text(social.person(peer)?.displayName ?? "Liya member").font(.title2.bold()).foregroundStyle(.white)
                        Text(call.kind == "video" ? "Video call" : "Voice call").foregroundStyle(.white.opacity(0.85))
                        if let room = calls.room, call.kind == "video" {
                            CallVideo(room: room).frame(height: min(max(size.height * 0.42, 200), 420)).clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        if call.status == "ringing" {
                            Text(call.calleeID == session.userID ? "Incoming call" : "Calling…").foregroundStyle(.white)
                        } else if let room = calls.room { CallConnectionStatus(room: room) }
                        else { Text("Connecting…").foregroundStyle(.white) }
                        if let error = calls.error { Text(error).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center) }
                        if call.status == "accepted" && calls.room == nil && calls.error != nil {
                            Button("Reconnect") { Task { await calls.retryConnection(session) } }.foregroundStyle(.white).frame(minHeight: 44).disabled(calls.busy)
                        }
                        if calls.permissionDenied {
                            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                                .foregroundStyle(.white).frame(minHeight: 44)
                        }
                        if call.status == "ringing" && call.calleeID == session.userID {
                            PrimaryButton(title: calls.busy ? "Connecting…" : "Answer", disabled: calls.busy) { Task { await calls.accept(session) } }
                        }
                        if calls.room != nil {
                            HStack(spacing: 12) {
                                Button(calls.microphoneOn ? "Mute" : "Unmute") { Task { await calls.toggleMicrophone() } }
                                if call.kind == "video" { Button(calls.cameraOn ? "Camera off" : "Camera on") { Task { await calls.toggleCamera() } } }
                            }.foregroundStyle(.white).frame(minHeight: 44)
                            if calls.room?.connectionState == .disconnected {
                                Button("Reconnect") { Task { await calls.retryConnection(session) } }.foregroundStyle(.white).frame(minHeight: 44).disabled(calls.busy)
                            }
                        }
                        Button(call.status == "ringing" && call.calleeID == session.userID ? "Decline" : "End call") { Task { await calls.end(session) } }
                            .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 48).background(Color.red.opacity(0.8), in: Capsule())
                    }.padding(24).frame(maxWidth: 540).frame(maxWidth: .infinity).frame(minHeight: size.height).modifier(AdaptiveContainerMargins())
                }
            }
        }.interactiveDismissDisabled()
    }
}

private struct CallConnectionStatus: View {
    @ObservedObject var room: Room
    var body: some View {
        Text(room.connectionState == .reconnecting ? "Reconnecting…" : (room.connectionState == .disconnected ? "Connection lost" : (room.remoteParticipants.isEmpty ? "Waiting for the other member…" : "Connected")))
            .foregroundStyle(.white)
    }
}

private struct CallVideo: View {
    @ObservedObject var room: Room
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let participant = room.remoteParticipants.values.first { RemoteCallVideo(participant: participant) }
            else { Color.black.opacity(0.4).overlay(Text("Waiting for the other person…").foregroundStyle(.white)) }
            LocalCallVideo(participant: room.localParticipant).frame(width: 100, height: 140).clipShape(RoundedRectangle(cornerRadius: 12)).padding(12)
        }
    }
}
private struct RemoteCallVideo: View {
    @ObservedObject var participant: RemoteParticipant
    var body: some View {
        if let track = participant.firstCameraVideoTrack { SwiftUIVideoView(track) }
        else { Color.black.opacity(0.4).overlay(Text("Camera is off").foregroundStyle(.white)) }
    }
}
private struct LocalCallVideo: View {
    @ObservedObject var participant: LocalParticipant
    var body: some View {
        if let track = participant.firstCameraVideoTrack { SwiftUIVideoView(track) }
        else { Color.black.opacity(0.4).overlay(Text("Camera off").font(.caption).foregroundStyle(.white)) }
    }
}
