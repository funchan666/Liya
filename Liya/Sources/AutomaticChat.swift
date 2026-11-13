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
 @Published private(set) var consentLoaded = true
 @Published private(set) var consentGranted = false
 @Published private(set) var updatingConsent = false
 @Published var error: String? = "AI chat is unavailable right now."
 func loadConsent(_ session: LiyaSession) async { consentLoaded = true; consentGranted = false }
 func setConsent(_ session: LiyaSession, granted: Bool) async -> Bool { error = "AI chat is unavailable right now."; return false }
 func load(_ session: LiyaSession) async { error = "AI chat is unavailable right now." }
 func send(_ session: LiyaSession, id: UUID, text: String) async -> Bool { error = "AI chat is unavailable right now."; return false }
 func stop() { loading = false; sending = false; waiting = false }
 func resetConsent() { consentLoaded = true; consentGranted = false }
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
    @State private var showingConsent = false
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
                HStack {
                    Spacer()
                    Button { showingConsent = true } label: {
                        HStack(spacing: 4) {
                            Image("setting-privacy").resizable().scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
                            Text("AI privacy").font(.caption.weight(.semibold))
                        }.foregroundStyle(.white).padding(.horizontal, 10).frame(minHeight: 44)
                            .background(.white.opacity(0.14), in: Capsule())
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).modifier(AdaptiveContainerMargins())
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
                sendTask?.cancel(); pendingRequest = nil; chat.stop(); chat.resetConsent(); restoreDraft()
                await chat.loadConsent(session)
                await chat.load(session)
            }
            .onLiyaChange(of: draft) { _ in persistDraft() }
            .onDisappear { persistDraft(); sendTask?.cancel(); pendingRequest = nil; chat.stop() }
            .sheet(isPresented: $showingConsent) {
                AIPrivacySheet(chat: chat) {
                    sendTask?.cancel(); pendingRequest = nil
                }.presentationDetents([.fraction(0.65), .large]).presentationDragIndicator(.visible)
            }
    }

    private func submit() {
        guard canSend, let owner = session.userID, draftOwner == owner else { return }
        guard chat.consentLoaded else { Task { await chat.loadConsent(session); if chat.consentLoaded && !chat.consentGranted { showingConsent = true } }; return }
        guard chat.consentGranted else { showingConsent = true; return }
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

private struct AIPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: LiyaSession
    @ObservedObject var chat: AutomaticChat
    let onWithdraw: () -> Void
    @State private var showPolicy = false

    var body: some View {
        ZStack {
            LiyaBackground()
            DuoControlRegion { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Image("ai-heading").resizable().scaledToFit().frame(width: 145, height: 52).accessibilityHidden(true)
                        Text("Your AI privacy").font(.title2.bold()).foregroundStyle(liyaInk)
                        Text("AI chat is currently unavailable.")
                            .font(.subheadline).foregroundStyle(liyaInk.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
                        Text("Liya AI is an automated companion, not a person or professional support.")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Read Privacy Policy") { showPolicy = true }
                            .font(.footnote.weight(.semibold)).underline().foregroundStyle(liyaAccent).frame(minHeight: 44)
                        if let error = chat.error { Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(liyaInk) }
                        if chat.consentGranted {
                            PrimaryButton(title: chat.updatingConsent ? "Updating…" : "Withdraw AI consent", disabled: chat.updatingConsent) {
                                onWithdraw()
                                Task { if await chat.setConsent(session, granted: false) { dismiss() } }
                            }
                        } else {
                            PrimaryButton(title: chat.updatingConsent ? "Updating…" : "Agree and continue", disabled: chat.updatingConsent) {
                                Task { if await chat.setConsent(session, granted: true) { dismiss() } }
                            }
                        }
                        Button("Not now") { dismiss() }.font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.padding(24).frame(maxWidth: 460).frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }.sheet(isPresented: $showPolicy) { NavigationStack { LegalDocumentView(page: .privacy) } }
    }
}
