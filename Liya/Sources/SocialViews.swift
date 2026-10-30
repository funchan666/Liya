import SwiftUI
import AVFoundation
import CryptoKit

struct SocialAttempt {
    private struct Snapshot: Encodable { let owner: UUID; let target: UUID?; let text: String; let tags: [String]; let files: [UUID] }
    static func fingerprint(owner: UUID, target: UUID? = nil, text: String, tags: [String] = [], files: [DraftAttachment]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(Snapshot(owner: owner, target: target, text: text, tags: tags, files: files.map(\.id)))) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func draftPostID(owner: UUID, draft: LocalDraft) -> UUID {
        let hash = fingerprint(owner: owner, target: draft.id, text: draft.text, tags: draft.tags ?? [], files: draft.attachments ?? [])
        let chars = Array(hash.prefix(32))
        let raw = String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
        return UUID(uuidString: raw)!
    }
}

struct SocialAvatar: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let personID: UUID
    @State private var url: URL?
    private var path: String? { social.person(personID)?.avatarPath }
    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Image("app-mark").resizable().scaledToFit() }
            } else { Image("app-mark").resizable().scaledToFit() }
        }.clipped().accessibilityHidden(true)
            .task(id: path) {
                url = nil
                guard let path else { return }
                if let signed = try? await social.mediaURL(session, path: path), !Task.isCancelled { url = signed }
            }
    }
}

struct CommunityJoinView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var signature = ""
    @State private var initialized = false
    @State private var saving = false
    @State private var shareAvatar = false
    var body: some View {
        PageShell(title: "Community profile") {
            VStack(alignment: .leading, spacing: 15) {
                OfflineNote(text: "Your name, introduction and any avatar you choose to share are visible to other signed-in members. Posts and comments are shared with the community. Messages are private to their participants.")
                Text("Community name").font(.headline).foregroundStyle(liyaInk)
                TextField("Choose a name", text: $name).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                Text("Introduction").font(.headline).foregroundStyle(liyaInk)
                TextField("A little about you", text: $signature, axis: .vertical).lineLimit(2...5).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                Button(shareAvatar ? "Avatar visible to members · Change" : "Keep avatar private · Change") { shareAvatar.toggle() }
                    .font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                if shareAvatar && session.profile?.avatarPath == nil { Text("Add an avatar to your account profile before sharing it.").font(.footnote).foregroundStyle(.secondary) }
                if let error = social.error { Text(error).font(.footnote).foregroundStyle(.red) }
                PrimaryButton(title: saving ? "Saving…" : "Save community profile", disabled: saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || signature.count > 500 || (shareAvatar && session.profile?.avatarPath == nil)) {
                    saving = true
                    Task { if await social.join(session, name: name, signature: signature, shareAvatar: shareAvatar) { dismiss() }; saving = false }
                }
            }.padding(.top, 12).disabled(saving)
        }.onAppear {
            guard !initialized else { return }
            if let owner = session.userID, let person = social.person(owner) { name = person.displayName; signature = person.signature; shareAvatar = person.avatarPath != nil }
            else { name = session.profile?.displayName ?? ""; signature = session.profile?.signature ?? "" }
            initialized = true
        }
    }
}

struct CommunityFeed: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Community").font(.title3.bold()).foregroundStyle(liyaInk)
                HStack {
                    Button("Refresh") { Task { await social.refresh(session) } }.font(.subheadline.bold()).foregroundStyle(liyaAccent).disabled(social.loading).frame(minHeight: 44)
                    Spacer()
                    NavigationLink("Members") { CommunityMembersView() }.font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
            }
            if !social.isJoined(session) && !social.loading {
                NavigationLink { CommunityJoinView() } label: {
                    Text("Create a community profile").font(.subheadline.bold()).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48).background(liyaGradient, in: Capsule())
                }.buttonStyle(.plain)
            }
            if social.loading { Text("Loading community…").font(.footnote).foregroundStyle(.secondary) }
            if let error = social.error {
                Text(error).font(.footnote).foregroundStyle(.red)
                Button("Refresh community") { Task { await social.refresh(session) } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
            } else if !social.loading && social.posts.isEmpty {
                EmptyState(title: "No community posts yet", detail: "Share a thought when you are ready.")
            }
            LazyVStack(spacing: 14) { ForEach(social.posts) { post in CommunityPostCard(post: post) } }
        }
    }
}

struct CommunityMembersView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    var body: some View {
        PageShell(title: "Community members") {
            VStack(spacing: 12) {
                if social.loading { Text("Loading…") }
                if let error = social.error { Text(error).foregroundStyle(.red); Button("Try again") { Task { await social.refresh(session) } }.foregroundStyle(liyaAccent) }
                if !social.loading && social.people.filter({ $0.id != session.userID }).isEmpty && social.error == nil {
                    EmptyState(title: "No members yet", detail: "Other community members will appear here.")
                }
                ForEach(social.people.filter { $0.id != session.userID }) { person in
                    NavigationLink { CommunityPersonView(personID: person.id) } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(personID: person.id).frame(width: 44, height: 44).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) { Text(person.displayName).font(.headline); Text(person.signature).font(.caption).lineLimit(2).foregroundStyle(.secondary) }
                            Spacer()
                        }.foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 12)
        }.task { await social.refresh(session) }
    }
}

struct CommunityPostCard: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let post: SocialPost
    @State private var busy = false
    @State private var deleting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NavigationLink { CommunityPersonView(personID: post.ownerID) } label: {
                    HStack(spacing: 8) {
                        SocialAvatar(personID: post.ownerID).frame(width: 40, height: 40).clipShape(Circle())
                        VStack(alignment: .leading) { Text(social.person(post.ownerID)?.displayName ?? "Liya member").font(.subheadline.bold()); Text("Community post").font(.caption).foregroundStyle(.secondary) }
                    }.foregroundStyle(liyaInk)
                }.buttonStyle(.plain)
                Spacer()
                if post.ownerID == session.userID {
                    NavigationLink("Edit") { CommunityEditPostView(post: post) }.font(.caption.bold()).foregroundStyle(liyaAccent)
                    Button("Delete") { deleting = true }.font(.caption.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                } else {
                    NavigationLink("Report") { CommunityReportView(target: post.ownerID, post: post.id) }.font(.caption.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
            }
            if !post.body.isEmpty { Text(post.body).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading) }
            if !post.tags.isEmpty { Text(post.tags.map { "# " + $0 }.joined(separator: "   ")).font(.caption).foregroundStyle(liyaAccent) }
            SocialMediaStrip(paths: post.mediaPaths, kinds: post.mediaKinds)
            HStack(spacing: 20) {
                Button(social.likes.contains(post.id) ? "Liked" : "Like") {
                    busy = true; Task { await social.toggleLike(session, post: post.id); busy = false }
                }.disabled(busy || social.loading).foregroundStyle(liyaAccent).frame(minHeight: 44)
                NavigationLink("Comments") { CommunityCommentsView(post: post) }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                Spacer()
            }.font(.subheadline.bold())
        }.padding(14).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
            .sheet(isPresented: $deleting) {
                LocalConfirmation(title: "Delete this post?", message: "The post and its comments will no longer be visible to the community.", action: "Delete") {
                    deleting = false; Task { _ = await social.deletePost(session, id: post.id) }
                } cancel: { deleting = false }.presentationDetents([.medium])
            }
    }
}

struct CommunityEditPostView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    let post: SocialPost
    @State private var text = ""
    @State private var tags: [String] = []
    @State private var initialized = false
    @State private var saving = false
    @State private var paths: [String] = []
    @State private var kinds: [String] = []
    @State private var additions: [DraftAttachment] = []
    @State private var mediaLoading = false
    var body: some View {
        PageShell(title: "Edit post") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Your thought", text: $text, axis: .vertical).lineLimit(3...10).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                PostTagSelector(selection: $tags)
                ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                    HStack {
                        Text(kinds.indices.contains(index) && kinds[index] == "video" ? "Existing video \(index + 1)" : "Existing photo \(index + 1)")
                        Spacer()
                        Button("Remove") { paths.remove(at: index); kinds.remove(at: index) }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                DraftMediaPicker(attachments: $additions, loading: $mediaLoading, note: "The post can contain up to 9 photos and videos in total.")
                if paths.count + additions.count > 9 { Text("Remove items to keep at most 9 attachments.").font(.footnote).foregroundStyle(.red) }
                if let error = social.error { Text(error).font(.footnote).foregroundStyle(.red) }
                PrimaryButton(title: saving ? "Saving…" : "Save changes", disabled: saving || mediaLoading || paths.count + additions.count > 9 || text.count > 4000 || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && paths.isEmpty && additions.isEmpty)) {
                    saving = true
                    Task { if await social.updatePost(session, post: post, body: text.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags, paths: paths, kinds: kinds, additions: additions) { dismiss() }; saving = false }
                }
            }.padding(.top, 12).disabled(saving)
        }.onAppear { if !initialized { text = post.body; tags = post.tags; paths = post.mediaPaths; kinds = post.mediaKinds; initialized = true } }
    }
}

struct CommunityPersonView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let personID: UUID
    @State private var busy = false
    @State private var blocking = false
    var body: some View {
        PageShell(title: "Member") {
            VStack(alignment: .leading, spacing: 16) {
                if let person = social.person(personID) {
                    SocialAvatar(personID: personID).frame(width: 75, height: 75).clipShape(RoundedRectangle(cornerRadius: 18))
                    Text(person.displayName).font(.title2.bold()).foregroundStyle(liyaInk)
                    Text(person.signature.isEmpty ? "A Liya member" : person.signature).foregroundStyle(.secondary)
                    if personID != session.userID {
                        if !social.isJoined(session) { NavigationLink("Create a community profile to follow or block") { CommunityJoinView() }.font(.footnote.bold()).foregroundStyle(liyaAccent) }
                        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 20) {
                            Button(social.follows.contains(personID) ? "Unfollow" : "Follow") {
                                busy = true; Task { await social.setRelation(session, target: personID, table: "liya_follows", enabled: !social.follows.contains(personID)); busy = false }
                            }.disabled(busy || !social.isJoined(session)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                            NavigationLink("Message") { CommunityConversationView(personID: personID) }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                            NavigationLink("Report") { CommunityReportView(target: personID, post: nil) }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                        }.font(.subheadline.bold()) }
                        Button("Block member") { blocking = true }.disabled(!social.isJoined(session) || busy).foregroundStyle(liyaAccent).frame(minHeight: 44)
                    } else {
                        NavigationLink("Edit community profile") { CommunityJoinView() }.foregroundStyle(liyaAccent)
                    }
                    if let error = social.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    ForEach(social.posts.filter { $0.ownerID == personID }) { CommunityPostCard(post: $0) }
                } else {
                    EmptyState(title: "Member unavailable", detail: "This profile may no longer be visible to you.")
                }
            }.padding(.top, 12)
        }.sheet(isPresented: $blocking) {
            LocalConfirmation(title: "Block this member?", message: "You won't see each other's posts or messages until the block is removed.", action: "Block") {
                blocking = false; Task { await social.setRelation(session, target: personID, table: "liya_blocks", enabled: true) }
            } cancel: { blocking = false }.presentationDetents([.medium])
        }
    }
}

struct CommunityReportView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let target: UUID
    let post: UUID?
    @State private var selected: String?
    @State private var id = UUID()
    @State private var sending = false
    @State private var sent = false
    @State private var failed = false
    private let reasons = ["Sexual content", "Harassment", "Discrimination", "Incorrect content", "Other"]
    var body: some View {
        PageShell(title: "Report") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "Reports are stored for review. A review team has not yet been configured.")
                ForEach(reasons, id: \.self) { reason in
                    Button { selected = reason; id = UUID(); failed = false } label: {
                        HStack { Text(reason); Spacer(); if selected == reason { Text("Selected").font(.caption.bold()).foregroundStyle(liyaAccent) } }
                            .foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(sending || sent)
                }
                if failed { Text("Could not confirm your report. Please try again.").font(.footnote).foregroundStyle(.red) }
                if sent { Text("Report received. Review is not yet configured.").font(.footnote).foregroundStyle(liyaAccent) }
                PrimaryButton(title: sending ? "Sending…" : "Send report", disabled: selected == nil || sending || sent) {
                    guard let selected else { return }; sending = true
                    Task { sent = await social.report(session, id: id, target: target, post: post, reason: selected); failed = !sent; sending = false }
                }
            }.padding(.top, 12)
        }
    }
}

struct CommunityCommentsView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let post: SocialPost
    @State private var comments: [SocialComment] = []
    @State private var text = ""
    @State private var sending = false
    @State private var loading = false
    @State private var failed = false
    @State private var loadID = UUID()
    @State private var attempt = UUID()
    @State private var loadedDraft = false
    @State private var deleting: SocialComment?
    private var draftKey: String { "liya.social.commentDraft.\(session.userID?.uuidString ?? "none").\(post.id.uuidString)" }
    var body: some View {
        PageShell(title: "Comments") {
            VStack(alignment: .leading, spacing: 12) {
                if loading { Text("Loading comments…").foregroundStyle(.secondary) }
                if failed { Text("Couldn't load or save comments.").foregroundStyle(.red); Button("Try again") { Task { await load() } }.foregroundStyle(liyaAccent) }
                if !loading && !failed && comments.isEmpty { EmptyState(title: "No comments yet", detail: "Start the conversation.") }
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 6) {
                        NavigationLink(social.person(comment.ownerID)?.displayName ?? "Liya member") { CommunityPersonView(personID: comment.ownerID) }.font(.caption.bold()).foregroundStyle(liyaAccent)
                        Text(comment.body).foregroundStyle(liyaInk)
                        if comment.ownerID == session.userID {
                            Button("Delete") { deleting = comment }.font(.caption.bold()).foregroundStyle(liyaAccent)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                if social.isJoined(session) {
                    TextField("Write a comment", text: Binding(get: { text }, set: { text = $0; attempt = UUID() }), axis: .vertical).lineLimit(2...6).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).disabled(sending)
                    PrimaryButton(title: sending ? "Sending…" : "Send comment", disabled: sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000) {
                        let body = text.trimmingCharacters(in: .whitespacesAndNewlines); sending = true
                        persistDraft()
                        Task { if await social.sendComment(session, id: attempt, post: post.id, body: body) { text = ""; attempt = UUID(); persistDraft(); await load() } else { failed = true }; sending = false }
                    }
                } else { NavigationLink("Create a community profile to comment") { CommunityJoinView() }.foregroundStyle(liyaAccent) }
            }.padding(.top, 12)
        }.onAppear { restoreDraft() }
            .onChange(of: text) { _ in persistDraft() }
            .onChange(of: social.syncGeneration) { _ in Task { await load() } }
            .onDisappear { persistDraft() }
            .task { await load() }
            .sheet(item: $deleting) { comment in
                LocalConfirmation(title: "Delete this comment?", message: "The comment will be removed for everyone.", action: "Delete") {
                    deleting = nil; Task { if await social.deleteComment(session, id: comment.id) { await load() } else { failed = true } }
                } cancel: { deleting = nil }.presentationDetents([.medium])
            }
    }
    private func load() async {
        let currentLoad = UUID()
        loadID = currentLoad
        loading = true; failed = false; comments = []
        do {
            let result = try await social.comments(session, post: post.id)
            guard loadID == currentLoad, !Task.isCancelled else { return }
            comments = result
        } catch {
            guard loadID == currentLoad, !Task.isCancelled else { return }
            failed = true
        }
        if loadID == currentLoad { loading = false }
    }
    private func restoreDraft() {
        guard !loadedDraft else { return }
        if let saved = UserDefaults.standard.dictionary(forKey: draftKey) as? [String: String] {
            text = saved["text"] ?? ""; attempt = UUID(uuidString: saved["attempt"] ?? "") ?? UUID()
        }
        loadedDraft = true
    }
    private func persistDraft() {
        guard loadedDraft else { return }
        UserDefaults.standard.set(["text": text, "attempt": attempt.uuidString], forKey: draftKey)
    }
}

struct SocialMediaItem: Identifiable { let path: String; let kind: String; var id: String { path } }
struct SocialMediaStrip: View {
    let paths: [String]; let kinds: [String]
    @State private var preview: SocialMediaItem?
    var body: some View {
        if !paths.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                        let item = SocialMediaItem(path: path, kind: kinds.indices.contains(index) ? kinds[index] : "photo")
                        Button { preview = item } label: { SocialMediaThumbnail(item: item).frame(width: 150, height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
                            .buttonStyle(.plain).accessibilityLabel(item.kind == "video" ? "Open video" : "Open photo")
                    }
                }
            }.sheet(item: $preview) { item in SocialMediaPreview(item: item) }
        }
    }
}

private struct SocialMediaThumbnail: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let item: SocialMediaItem
    @State private var url: URL?
    @State private var failed = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
            if item.kind == "video" { Image("play").resizable().scaledToFit().frame(width: 44, height: 44) }
            else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else if phase.error != nil { Text("Photo unavailable").font(.caption) }
                    else { Color.clear }
                }
            } else if failed { Text("Photo unavailable").font(.caption) }
        }.task(id: item.path) {
            guard item.kind != "video" else { return }
            do { let value = try await social.mediaURL(session, path: item.path); if !Task.isCancelled { url = value } }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}

private struct SocialMediaPreview: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let item: SocialMediaItem
    @State private var url: URL?
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var playing = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player { PlayerView(player: player) }
            else if let url { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Text("Loading…").foregroundStyle(.white) } }
            else if failed { Text("Media unavailable").foregroundStyle(.white) }
            DuoControlRegion { size in
                VStack {
                    HStack { Button { dismiss() } label: { Image("close").resizable().scaledToFit().frame(width: 30, height: 30).frame(width: 44, height: 44) }.accessibilityLabel("Close media"); Spacer() }
                    Spacer()
                    if let player {
                        Button { if playing { player.pause() } else { player.play() }; playing.toggle() } label: {
                            Image(playing ? "pause" : "play").resizable().scaledToFit().frame(width: 48, height: 48)
                        }.accessibilityLabel(playing ? "Pause video" : "Play video")
                    }
                }.buttonStyle(.plain).padding(20).frame(width: size.width, height: size.height)
            }
        }.task {
            do {
                let value = try await social.mediaURL(session, path: item.path)
                guard !Task.isCancelled else { return }
                if item.kind == "video" { player = AVPlayer(url: value) } else { url = value }
            } catch { if !Task.isCancelled { failed = true } }
        }.onChange(of: phase) { if $0 != .active { player?.pause(); playing = false } }
            .onDisappear { player?.pause(); player = nil }
    }
}

private struct MessageDraft: Codable {
    var text: String
    var attachments: [DraftAttachment]
    var attempt: String
    var fingerprint: String
}

struct CommunityMessagesView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    private var peers: [UUID] {
        guard let owner = session.userID else { return [] }
        var result: [UUID] = []
        for message in social.messages.reversed() {
            let other = message.senderID == owner ? message.recipientID : message.senderID
            if !result.contains(other) { result.append(other) }
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conversations").font(.headline).foregroundStyle(liyaInk)
                Spacer()
                NavigationLink("Find members") { CommunityMembersView() }.font(.subheadline.bold()).foregroundStyle(liyaAccent)
            }
            if !social.isJoined(session) && !social.loading {
                NavigationLink("Create your community profile") { CommunityJoinView() }.foregroundStyle(liyaAccent).frame(minHeight: 44)
            }
            if social.messagesLoading { Text("Loading messages…").font(.footnote).foregroundStyle(.secondary) }
            if let error = social.messageError {
                Text(error).font(.footnote).foregroundStyle(.red)
                Button("Refresh messages") { Task { await social.refreshMessages(session) } }.foregroundStyle(liyaAccent)
            } else if !social.messagesLoading && peers.isEmpty {
                EmptyState(title: "No conversations yet", detail: "Visit a member's profile to start a free conversation.")
            }
            if !social.realtimeConnected { Button("Reconnect live updates") { social.watchMessages(session) }.font(.footnote.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44) }
            ForEach(peers, id: \.self) { id in
                NavigationLink { CommunityConversationView(personID: id) } label: {
                    HStack(spacing: 12) {
                        SocialAvatar(personID: id).frame(width: 44, height: 44).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(social.person(id)?.displayName ?? "Liya member").font(.subheadline.bold())
                            if let last = social.messages.last(where: { $0.senderID == id || $0.recipientID == id }) {
                                Text(last.body.isEmpty ? "Attachment" : last.body).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                            }
                        }; Spacer()
                    }.foregroundStyle(liyaInk).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }.task { await social.refreshMessages(session) }
    }
}

struct CommunityConversationView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let personID: UUID
    @State private var text = ""
    @State private var attachments: [DraftAttachment] = []
    @State private var mediaLoading = false
    @State private var sending = false
    @State private var loaded = false
    @State private var attempt = ""
    @State private var fingerprint = ""
    @State private var deleting: SocialMessage?
    private var key: String { "liya.social.messageDraft.\(session.userID?.uuidString ?? "none").\(personID.uuidString)" }
    private var conversation: [SocialMessage] {
        guard let owner = session.userID else { return [] }
        return social.messages.filter { ($0.senderID == owner && $0.recipientID == personID) || ($0.senderID == personID && $0.recipientID == owner) }
    }
    var body: some View {
        PageShell(title: social.person(personID)?.displayName ?? "Conversation") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "Messages are free and visible only to you and this member.")
                Button("Refresh messages") { Task { await social.refreshMessages(session) } }.font(.footnote.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                if let error = social.messageError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Refresh") { Task { await social.refreshMessages(session) } }.foregroundStyle(liyaAccent)
                }
                if social.messagesLoading { Text("Loading messages…").foregroundStyle(.secondary) }
                ForEach(conversation) { message in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message.senderID == session.userID ? "You" : (social.person(personID)?.displayName ?? "Member")).font(.caption.bold()).foregroundStyle(liyaAccent)
                        if !message.body.isEmpty { Text(message.body).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading) }
                        SocialMediaStrip(paths: message.mediaPaths, kinds: message.mediaKinds)
                        if message.senderID == session.userID { Button("Delete for everyone") { deleting = message }.font(.caption.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44) }
                    }.padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                }
                if social.isJoined(session) && social.person(personID) != nil {
                    TextField("Write a message", text: $text, axis: .vertical).lineLimit(1...6).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).disabled(sending)
                    DraftMediaPicker(attachments: $attachments, loading: $mediaLoading, note: "Up to 9 items. Attachments are sent privately with your message.").disabled(sending)
                    PrimaryButton(title: sending ? "Sending…" : "Send message", disabled: sending || mediaLoading || text.count > 4000 || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)) {
                        guard let owner = session.userID else { return }
                        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let stamp = SocialAttempt.fingerprint(owner: owner, target: personID, text: body, files: attachments)
                        if stamp != fingerprint || UUID(uuidString: attempt) == nil { fingerprint = stamp; attempt = UUID().uuidString }
                        guard let id = UUID(uuidString: attempt) else { return }
                        persist(); sending = true
                        Task {
                            if await social.sendMessage(session, id: id, target: personID, body: body, attachments: attachments) {
                                text = ""; attachments = []; attempt = ""; fingerprint = ""; persist()
                            }
                            sending = false
                        }
                    }
                } else if !social.isJoined(session) {
                    NavigationLink("Create a community profile to message") { CommunityJoinView() }.foregroundStyle(liyaAccent)
                } else {
                    Text("This member is no longer available.").foregroundStyle(.secondary)
                }
            }.padding(.top, 12)
        }.onAppear { restore() }
            .onChange(of: text) { _ in persist() }
            .onChange(of: attachments) { _ in persist() }
            .onDisappear { persist() }
            .task { await social.refreshMessages(session) }
            .sheet(item: $deleting) { message in
                LocalConfirmation(title: "Delete this message?", message: "The message will be removed for both participants.", action: "Delete") {
                    deleting = nil; Task { _ = await social.deleteMessage(session, message: message) }
                } cancel: { deleting = nil }.presentationDetents([.medium])
            }
    }
    private func restore() {
        guard !loaded else { return }
        if let data = UserDefaults.standard.data(forKey: key), let draft = try? JSONDecoder().decode(MessageDraft.self, from: data) {
            text = draft.text; attachments = draft.attachments; attempt = draft.attempt; fingerprint = draft.fingerprint
        }
        loaded = true
    }
    private func persist() {
        guard loaded else { return }
        let draft = MessageDraft(text: text, attachments: attachments, attempt: attempt, fingerprint: fingerprint)
        if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct CommunityRelationList: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let title: String
    let relation: String
    private var ids: [UUID] { relation == "blocked" ? social.blocked : relation == "followers" ? social.followers : social.follows }
    var body: some View {
        PageShell(title: title) {
            VStack(spacing: 12) {
                if let error = social.error { Text(error).foregroundStyle(.red); Button("Refresh") { Task { await social.refresh(session) } }.foregroundStyle(liyaAccent) }
                if ids.isEmpty && !social.loading && social.error == nil { EmptyState(title: "Nothing here yet", detail: "Members will appear here when available.") }
                ForEach(ids, id: \.self) { id in
                    HStack {
                        if let person = social.person(id) {
                            NavigationLink(person.displayName) { CommunityPersonView(personID: id) }.foregroundStyle(liyaInk)
                        } else { Text("Blocked member · \(id.uuidString.prefix(8))").foregroundStyle(liyaInk) }
                        Spacer()
                        if relation == "blocked" {
                            NavigationLink("Report") { CommunityReportView(target: id, post: nil) }.foregroundStyle(liyaAccent)
                            Button("Unblock") { Task { await social.setRelation(session, target: id, table: "liya_blocks", enabled: false) } }.foregroundStyle(liyaAccent)
                        } else if relation == "following" {
                            Button("Unfollow") { Task { await social.setRelation(session, target: id, table: "liya_follows", enabled: false) } }.foregroundStyle(liyaAccent)
                        }
                    }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.top, 12)
        }.task { await social.refresh(session) }
    }
}

struct CommunityActivityView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Community activity").font(.headline).foregroundStyle(liyaInk); Spacer(); Button("Refresh") { Task { await social.refreshNotifications(session) } }.foregroundStyle(liyaAccent) }
            if social.notificationsLoading { Text("Loading activity…").font(.footnote).foregroundStyle(.secondary) }
            if let error = social.notificationsError { Text(error).font(.footnote).foregroundStyle(.red) }
            if social.notifications.isEmpty && !social.notificationsLoading && social.notificationsError == nil { Text("No community activity yet.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(social.notifications) { activity in
                HStack {
                    NavigationLink { CommunityPersonView(personID: activity.actorID) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(social.person(activity.actorID)?.displayName ?? "Liya member").font(.subheadline.bold())
                            Text(activity.kind == "follow" ? "Started following you" : activity.kind == "like" ? "Liked your post" : "Commented on your post").font(.caption)
                        }.foregroundStyle(liyaInk)
                    }.buttonStyle(.plain)
                    Spacer()
                    if let postID = activity.postID, let post = social.posts.first(where: { $0.id == postID }) {
                        NavigationLink("Post") { CommunityCommentsView(post: post) }.font(.caption.bold()).foregroundStyle(liyaAccent)
                    }
                    if !activity.isRead { Button("Mark read") { Task { await social.markRead(session, id: activity.id) } }.font(.caption.bold()).foregroundStyle(liyaAccent) }
                }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            }
        }.task { await social.refreshNotifications(session) }
    }
}
