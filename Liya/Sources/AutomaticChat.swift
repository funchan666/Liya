import SwiftUI
import Combine
import Supabase

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
    private var generation = UUID()
    private var sendGeneration = UUID()
    private var loadedOwner: UUID?

    func load(_ session: LiyaSession) async {
        guard let owner = session.userID, !loading else { return }
        let current = UUID(); generation = current
        if loadedOwner != owner { messages = []; loadedOwner = owner }
        loading = true; error = nil
        defer { if generation == current { loading = false } }
        do {
            var all: [AutoChatMessage] = []; var offset = 0
            while true {
                let page: [AutoChatMessage] = try await session.client.from("liya_ai_messages")
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
        let current = UUID(); sendGeneration = current
        sending = true; waiting = true; error = nil
        defer { if sendGeneration == current { sending = false; waiting = false } }
        do {
            struct Reply: Decodable { let code: String }
            let response: Reply = try await session.client.functions.invoke("liya-ai-chat", options: FunctionInvokeOptions(body: ["request_id": id.uuidString, "text": text]))
            guard !Task.isCancelled, sendGeneration == current, session.userID == owner else { return false }
            guard response.code == "completed" else { throw ChatError.unconfirmed }
            await load(session)
            guard !Task.isCancelled, sendGeneration == current, session.userID == owner else { return false }
            guard error == nil, messages.contains(where: { $0.requestID == id && $0.role == "user" && $0.body == text }),
                  messages.contains(where: { $0.requestID == id && $0.role == "assistant" }) else { throw ChatError.unconfirmed }
            return true
        } catch {
            guard !Task.isCancelled, sendGeneration == current, session.userID == owner else { return false }
            if let functionError = error as? FunctionsError, case let .httpError(code, _) = functionError {
                switch code {
                case 401: self.error = "Your session has expired. Please sign in again."
                case 409: self.error = "Your reply is still being prepared. Please try again shortly."
                case 429: self.error = "A little busy right now. Please wait and try again."
                default: self.error = "Couldn't get a reply right now. Please try again."
                }
            } else { self.error = "Couldn't get a reply right now. Please try again." }
            return false
        }
    }

    func stop() { generation = UUID(); sendGeneration = UUID(); loading = false; sending = false; waiting = false }
    private enum ChatError: Error { case unconfirmed }
}

struct AutomaticChatView: View {
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: LiyaSession
    @State private var draft = ""
    @State private var attempt = ""
    @State private var fingerprint = ""
    @State private var draftOwner: UUID?
    @State private var sendTask: Task<Void, Never>?
    @State private var pendingRequest: UUID?
    @StateObject private var chat = AutomaticChat()
    private var canSend: Bool {
        session.userID != nil && pendingRequest == nil && !chat.loading && !chat.sending && !chat.waiting &&
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.count <= 2000
    }
    var body: some View {
        ZStack {
            LiyaBackground(name: "ai-chat-background")
            VStack(spacing: 0) {
                PageHeader(title: "AI chat", light: true)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if chat.messages.isEmpty {
                                Image("ai-heading").resizable().scaledToFit().frame(width: 176, height: 60).accessibilityLabel("AI chat")
                                Text("A little space to talk, at your own pace.")
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.94))
                            }
                            if chat.loading && chat.messages.isEmpty { LiyaLoadingIndicator(size: 28) }
                            if let error = chat.error {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.white)
                                    Button("Try again") { if canSend { submit() } else { Task { await chat.load(session) } } }
                                        .font(.footnote.bold()).foregroundStyle(.white).frame(minHeight: 44)
                                        .disabled(chat.sending)
                                }
                            }
                            ForEach(chat.messages) { message in
                                HStack(alignment: .top, spacing: 0) {
                                    if message.role == "user" { Spacer(minLength: 56) }
                                    VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 5) {
                                        Text(message.role == "user" ? "You" : "Liya AI")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.86))
                                            .padding(.horizontal, 4)
                                        Text(message.body)
                                            .font(.body).foregroundStyle(message.role == "user" ? .white : liyaInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .padding(.horizontal, 16).padding(.vertical, 13)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(message.role == "user" ? Color.white.opacity(0.22) : Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
                                    }
                                    .frame(maxWidth: 400, alignment: message.role == "user" ? .trailing : .leading)
                                    if message.role != "user" { Spacer(minLength: 56) }
                                }.id(message.id)
                            }
                            if chat.waiting {
                                Text("Liya AI is preparing a reply…").font(.footnote).foregroundStyle(.white.opacity(0.9)).id("waiting")
                            }
                            if chat.messages.isEmpty && !chat.loading && chat.error == nil {
                                ForEach(["Give me some positive energy", "How can I feel calmer?", "Tell me a heartwarming story"], id: \.self) { prompt in
                                    Button { draft = draft.isEmpty ? prompt : draft + "\n" + prompt } label: {
                                        Text(prompt).font(.subheadline.weight(.medium)).foregroundStyle(liyaInk)
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            .background(.white.opacity(0.94), in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 16)
                            .modifier(AdaptiveContainerMargins())
                    }.scrollDismissesKeyboard(.interactively)
                    .onLiyaChange(of: chat.waiting) { waiting in
                        if waiting { reader.scrollTo("waiting", anchor: .bottom) }
                    }.onLiyaChange(of: chat.messages.count) { _ in
                        if let last = chat.messages.last {
                            if reduceMotion { reader.scrollTo(last.id, anchor: .bottom) }
                            else { withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(last.id, anchor: .bottom) } }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if draft.count > 2000 { Text("Please keep your message under 2,000 characters.").font(.footnote).foregroundStyle(.white) }
                    HStack(alignment: .bottom, spacing: 10) {
                        TextField("Write a message…", text: $draft, axis: .vertical)
                            .lineLimit(1...4).padding(.horizontal, 16).padding(.vertical, 13)
                            .foregroundStyle(liyaInk).tint(liyaAccent)
                            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
                            .disabled(chat.sending || pendingRequest != nil)
                        Button {
                            submit()
                        } label: {
                            Text(chat.sending ? "Sending…" : "Send").font(.subheadline.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 18).frame(minHeight: 48)
                                .background(liyaGradient.opacity(canSend ? 1 : 0.45), in: Capsule())
                        }.buttonStyle(.plain)
                            .disabled(!canSend)
                    }
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12 + tabBarClearance).frame(maxWidth: 660)
                    .modifier(AdaptiveContainerMargins())
            }
        }.navigationBarHidden(true)
            .task(id: session.userID) {
                sendTask?.cancel(); pendingRequest = nil; chat.stop(); restoreDraft()
                await chat.load(session)
            }
            .onLiyaChange(of: draft) { _ in persistDraft() }
            .onDisappear { persistDraft(); sendTask?.cancel(); pendingRequest = nil; chat.stop() }
    }

    private func submit() {
        guard canSend, let owner = session.userID, draftOwner == owner else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = SocialAttempt.fingerprint(owner: owner, text: text, files: [])
        if stamp != fingerprint || UUID(uuidString: attempt) == nil { fingerprint = stamp; attempt = UUID().uuidString }
        guard let id = UUID(uuidString: attempt) else { return }
        persistDraft()
        let operation = UUID(); pendingRequest = operation
        sendTask = Task {
            defer { if pendingRequest == operation { pendingRequest = nil; sendTask = nil } }
            if await chat.send(session, id: id, text: text), !Task.isCancelled, session.userID == owner, draftOwner == owner {
                draft = ""; attempt = ""; fingerprint = ""; persistDraft()
            }
        }
    }

    private func restoreDraft() {
        guard let owner = session.userID else { draftOwner = nil; draft = ""; attempt = ""; fingerprint = ""; return }
        draftOwner = owner
        let prefix = "liya.ai.\(owner.uuidString)."
        draft = UserDefaults.standard.string(forKey: prefix + "draft") ?? ""
        attempt = UserDefaults.standard.string(forKey: prefix + "attempt") ?? ""
        fingerprint = UserDefaults.standard.string(forKey: prefix + "fingerprint") ?? ""
    }

    private func persistDraft() {
        guard let owner = draftOwner, owner == session.userID else { return }
        let prefix = "liya.ai.\(owner.uuidString)."
        UserDefaults.standard.set(draft, forKey: prefix + "draft")
        UserDefaults.standard.set(attempt, forKey: prefix + "attempt")
        UserDefaults.standard.set(fingerprint, forKey: prefix + "fingerprint")
    }
}
