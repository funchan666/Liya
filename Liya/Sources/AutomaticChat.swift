import SwiftUI
import Combine

struct AutoChatMessage: Decodable, Identifiable {
    let id: UUID
    let requestID: UUID
    let role: String
    let body: String
    let createdAt: String
    enum CodingKeys: String, CodingKey { case id, role, body; case requestID = "request_id", createdAt = "created_at" }
}

@MainActor
final class AutomaticChat: ObservableObject {
    @Published private(set) var messages: [AutoChatMessage] = []
    @Published private(set) var loading = false
    @Published private(set) var sending = false
    @Published private(set) var waiting = false
    @Published var error: String?
    private var pendingPoll: Task<Void, Never>?
    private var generation = UUID()

    func load(_ session: LiyaSession) async {
        guard let owner = session.userID, !loading else { return }
        let current = UUID(); generation = current
        loading = true; error = nil; messages = []
        defer { loading = false }
        do {
            var all: [AutoChatMessage] = []; var offset = 0
            while true {
                let page: [AutoChatMessage] = try await session.client.from("liya_auto_messages")
                    .select("id,request_id,role,body,created_at").eq("owner_id", value: owner.uuidString)
                    .order("created_at").order("id").range(from: offset, to: offset + 499).execute().value
                all.append(contentsOf: page)
                if page.count < 500 { break }; offset += 500
            }
            guard session.userID == owner, generation == current else { return }
            messages = all
        } catch { if session.userID == owner && generation == current { self.error = "Couldn't load this conversation. Please try again." } }
    }

    func send(_ session: LiyaSession, id: UUID, text: String) async -> Bool {
        guard let owner = session.userID, !sending, !waiting else { return false }
        sending = true; error = nil
        defer { sending = false }
        do {
            struct ReplyDue: Decodable { let replyVisibleAt: String; enum CodingKeys: String, CodingKey { case replyVisibleAt = "reply_visible_at" } }
            let response: [ReplyDue] = try await session.client.rpc("liya_auto_send", params: ["p_request": id.uuidString, "p_body": text]).execute().value
            guard !response.isEmpty, session.userID == owner else { throw ChatError.unconfirmed }
            await load(session)
            guard error == nil, messages.contains(where: { $0.requestID == id && $0.role == "user" && $0.body == text }) else { throw ChatError.unconfirmed }
            schedulePending(session)
            return true
        } catch {
            error = "Couldn't confirm the message. Your draft is still here; try again."
            return false
        }
    }

    func schedulePending(_ session: LiyaSession) {
        pendingPoll?.cancel()
        guard messages.last?.role == "user" else { waiting = false; return }
        waiting = true
        pendingPoll = Task { [weak self, weak session] in
            for attempt in 0..<6 {
                do { try await Task.sleep(nanoseconds: attempt == 0 ? 3_300_000_000 : 1_000_000_000) } catch { return }
                guard let self, let session, !Task.isCancelled else { return }
                await self.load(session)
                if self.error != nil { self.waiting = false; return }
                if self.messages.last?.role != "user" { self.waiting = false; return }
            }
            if let self { self.waiting = false; self.error = "The reply is taking longer than expected. Refresh to check." }
        }
    }

    func stop() { pendingPoll?.cancel(); pendingPoll = nil; waiting = false }
    private enum ChatError: Error { case unconfirmed }
}

struct AutomaticChatView: View {
    @EnvironmentObject private var session: LiyaSession
    @AppStorage("liya.aiDraft") private var draft = ""
    @AppStorage("liya.autoAttempt") private var attempt = ""
    @AppStorage("liya.autoFingerprint") private var fingerprint = ""
    @StateObject private var chat = AutomaticChat()
    var body: some View {
        ZStack {
            LiyaBackground(name: "color-background")
            VStack(spacing: 12) {
                PageHeader(title: "AI chat", light: true)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Image("ai-heading").resizable().scaledToFit().frame(width: 190, height: 72).accessibilityLabel("AI chat")
                            Text("Automated, prewritten replies · not a person or professional support.").font(.footnote).foregroundStyle(.white.opacity(0.9))
                            if chat.loading { Text("Loading conversation…").foregroundStyle(.white) }
                            if let error = chat.error {
                                Text(error).font(.footnote).foregroundStyle(.white)
                                Button("Refresh") { Task { await chat.load(session); chat.schedulePending(session) } }.foregroundStyle(.white).frame(minHeight: 44)
                            }
                            ForEach(chat.messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == "user" ? "You" : "Liya · automatic reply").font(.caption.bold()).foregroundStyle(liyaAccent)
                                    Text(message.body).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(14).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16)).id(message.id)
                            }
                            if chat.waiting { Text("Liya is preparing a reply…").font(.footnote).foregroundStyle(.white) }
                            if chat.messages.isEmpty && !chat.loading {
                                ForEach(["Give me some positive energy", "How can I feel calmer?", "Tell me a heartwarming story"], id: \.self) { prompt in
                                    Button { draft = draft.isEmpty ? prompt : draft + "\n" + prompt } label: {
                                        Text(prompt).font(.subheadline).foregroundStyle(liyaInk).padding(10).background(.white.opacity(0.85), in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.bottom, 12)
                    }.onChange(of: chat.messages.count) { _ in
                        if let last = chat.messages.last { withAnimation { reader.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                VStack(spacing: 10) {
                    TextField("Write a message", text: $draft, axis: .vertical).lineLimit(1...4).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16)).disabled(chat.sending)
                    PrimaryButton(title: chat.sending ? "Sending…" : "Send · free", disabled: chat.sending || chat.waiting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000) {
                        guard let owner = session.userID else { return }
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        let stamp = SocialAttempt.fingerprint(owner: owner, text: text, files: [])
                        if stamp != fingerprint || UUID(uuidString: attempt) == nil { fingerprint = stamp; attempt = UUID().uuidString }
                        guard let id = UUID(uuidString: attempt) else { return }
                        Task { if await chat.send(session, id: id, text: text) { draft = ""; attempt = ""; fingerprint = "" } }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 12).frame(maxWidth: 660)
            }
        }.navigationBarHidden(true)
            .task { await chat.load(session); chat.schedulePending(session) }
            .onDisappear { chat.stop() }
    }
}
