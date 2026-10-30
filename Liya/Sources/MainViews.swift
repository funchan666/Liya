import SwiftUI

struct ComposeHome: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var savedMessage: String?
    @State private var publishing = false
    @AppStorage("liya.postAttempt") private var postAttempt = ""
    @AppStorage("liya.postFingerprint") private var postFingerprint = ""
    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image("publish-title").resizable().scaledToFit().frame(width: 150, height: 46).accessibilityLabel("Create")
                    OfflineNote(text: "Posts and their attachments are visible to signed-in community members. Private drafts stay on this device.")
                    if !social.isJoined(session) && !social.loading {
                        NavigationLink("Create a community profile to post") { CommunityJoinView() }.foregroundStyle(liyaAccent)
                    }
                    Text("Your thoughts").font(.headline).foregroundStyle(liyaInk)
                    TextField("Share a moment or feeling…", text: Binding(get: { store.composeText }, set: { store.composeText = $0; savedMessage = nil }), axis: .vertical)
                        .lineLimit(7...12).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16)).disabled(publishing)
                    PostTagSelector(selection: $store.composeTags).disabled(publishing)
                    DraftMediaPicker(attachments: $store.composeAttachments, loading: $store.composeLoading, note: "Up to 9 items. Attachments are shared with your post.").disabled(publishing)
                    if let error = social.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    PrimaryButton(title: publishing ? "Publishing…" : "Share with community", disabled: publishing || store.composeLoading || !social.isJoined(session) || store.composeText.count > 4000 || (store.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.composeAttachments.isEmpty)) {
                        guard let owner = session.userID else { return }
                        let body = store.composeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let tags = store.composeTags; let files = store.composeAttachments
                        let stamp = SocialAttempt.fingerprint(owner: owner, text: body, tags: tags, files: files)
                        if stamp != postFingerprint || UUID(uuidString: postAttempt) == nil { postFingerprint = stamp; postAttempt = UUID().uuidString }
                        guard let id = UUID(uuidString: postAttempt) else { return }
                        publishing = true
                        Task {
                            if await social.publish(session, id: id, body: body, tags: tags, attachments: files) {
                                store.composeText = ""; store.composeAttachments = []; store.composeTags = []; postAttempt = ""; postFingerprint = ""; savedMessage = "Shared with the community."
                            }
                            publishing = false
                        }
                    }
                    Button("Save private draft") {
                        store.saveDraft(store.composeText.trimmingCharacters(in: .whitespacesAndNewlines), attachments: store.composeAttachments, tags: store.composeTags)
                        store.composeText = ""; store.composeAttachments = []; store.composeTags = []; savedMessage = "Private draft saved on this device."
                    }.font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(publishing || store.composeLoading || (store.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.composeAttachments.isEmpty))
                    if let savedMessage { Text(savedMessage).font(.footnote).foregroundStyle(liyaAccent) }
                    NavigationLink { DraftsView() } label: {
                        HStack { Text("Your drafts").fontWeight(.semibold); Spacer(); Text("\(store.drafts.filter { $0.publishedLocally != true }.count)") }
                            .foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(20)
            }
        }.navigationBarHidden(true)
    }
}

struct DraftsView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var deletingDraft: LocalDraft?
    @State private var previewVideo: DraftAttachment?
    @State private var publishingDraft: UUID?
    private var unpublished: [LocalDraft] { store.drafts.filter { $0.publishedLocally != true } }
    var body: some View {
        PageShell(title: "Your drafts") {
            VStack(spacing: 12) {
                OfflineNote(text: "Drafts are private and stored on this device.")
                if !social.isJoined(session) && !social.loading {
                    NavigationLink("Create a community profile to share") { CommunityJoinView() }.foregroundStyle(liyaAccent)
                }
                if let error = social.error { Text(error).font(.footnote).foregroundStyle(.red) }
                if unpublished.isEmpty {
                    EmptyState(title: "No drafts yet", detail: "Save a thought to find it here later.")
                } else {
                    ForEach(unpublished) { draft in
                        VStack(alignment: .leading, spacing: 12) {
                            if let mood = draft.mood { Image(mood).resizable().scaledToFit().frame(width: 32, height: 32).accessibilityLabel("Mood") }
                            if !draft.text.isEmpty { Text(draft.text).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading) }
                            if let media = draft.attachments, !media.isEmpty {
                                ScrollView(.horizontal) { HStack { ForEach(media) { item in
                                    Button { previewVideo = item } label: {
                                        MediaThumbnail(item: item).frame(width: 72, height: 86).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain).accessibilityLabel(item.isVideo ? "Preview video" : "Preview photo")
                                } } }
                            }
                            HStack {
                                Text(draft.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                NavigationLink("Edit") { EditDraftView(draft: draft) }.font(.footnote.bold()).foregroundStyle(liyaAccent)
                                Button(publishingDraft == draft.id ? "Sharing…" : (isShared(draft) ? "Shared" : "Share")) {
                                    guard let owner = session.userID else { return }
                                    publishingDraft = draft.id
                                    Task {
                                        _ = await social.publish(session, id: SocialAttempt.draftPostID(owner: owner, draft: draft), body: draft.text, tags: draft.tags ?? [], attachments: draft.attachments ?? [])
                                        publishingDraft = nil
                                    }
                                }.disabled(publishingDraft != nil || !social.isJoined(session) || isShared(draft))
                                    .font(.footnote.bold()).foregroundStyle(liyaAccent)
                                Button("Delete") { deletingDraft = draft }.font(.footnote.bold()).foregroundStyle(liyaAccent)
                            }
                        }.padding(16).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }.padding(.top, 12)
        }.sheet(item: $previewVideo) { item in
            if item.isVideo { DraftVideoPreview(item: item) } else { DraftPhotoPreview(item: item) }
        }
        .sheet(item: $deletingDraft) { draft in
            LocalConfirmation(title: "Delete draft?", message: "This removes the draft from this device.", action: "Delete") {
                store.deleteDraft(draft.id); deletingDraft = nil
            } cancel: { deletingDraft = nil }
            .presentationDetents([.medium])
        }
    }
    private func isShared(_ draft: LocalDraft) -> Bool {
        guard let owner = session.userID else { return false }
        return social.posts.contains { $0.id == SocialAttempt.draftPostID(owner: owner, draft: draft) }
    }
}

struct EditDraftView: View {
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    let draft: LocalDraft
    @State private var text = ""
    @State private var attachments: [DraftAttachment] = []
    @State private var loading = false
    @State private var tags: [String] = []
    @State private var initialized = false
    var body: some View {
        PageShell(title: draft.publishedLocally == true ? "Edit local post" : "Edit draft") {
            VStack(spacing: 16) {
                OfflineNote(text: "This draft is private and stays on this device.")
                TextField("Your draft", text: $text, axis: .vertical).lineLimit(7...12).padding(16)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                PostTagSelector(selection: $tags)
                DraftMediaPicker(attachments: $attachments, loading: $loading)
                PrimaryButton(title: "Save changes", disabled: loading || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)) {
                    store.updateDraft(draft.id, text: text.trimmingCharacters(in: .whitespacesAndNewlines), attachments: attachments, tags: tags)
                    dismiss()
                }
            }.padding(.top, 12)
        }.onAppear {
            guard !initialized else { return }
            text = draft.text; attachments = draft.attachments ?? []; tags = draft.tags ?? []; initialized = true
        }
    }
}

private struct DraftMessageSelection: Identifiable {
    let id: Int
}

struct MessagesHome: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @State private var section = 0
    @State private var deleteMessage: DraftMessageSelection?
    private var messageIndexes: [Int] { store.messageDrafts.keys.compactMap(Int.init).filter { !store.blockedExamples.contains($0) }.sorted() }
    private var visibleLikes: [Int] { store.likedPhotos.filter { !store.blockedExamples.contains($0) }.sorted() }
    private var visibleNotes: [LocalComment] { store.comments.filter { !store.blockedExamples.contains($0.photoIndex) } }
    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image("message-title").resizable().scaledToFit().frame(width: 160, height: 46).accessibilityLabel("Messages")
                    SegmentedTabs(items: ["Message", "Interaction"], selection: $section)
                    if section == 0 {
                        CommunityMessagesView()
                        if !messageIndexes.isEmpty { OfflineNote(text: "Earlier drafts for example profiles are private and have not been sent.") }
                        ForEach(messageIndexes, id: \.self) { index in
                            HStack(spacing: 12) {
                                NavigationLink { ExampleChatView(index: index) } label: {
                                    HStack(spacing: 12) {
                                        ExampleAvatar(index: index)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Example profile \(index + 1)").font(.subheadline.bold()).foregroundStyle(liyaInk)
                                            Text("Draft · \(store.messageDrafts[String(index)] ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        Spacer()
                                    }
                                }.buttonStyle(.plain)
                                Button { deleteMessage = DraftMessageSelection(id: index) } label: {
                                    Image("close").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel("Delete message draft")
                            }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        CommunityActivityView()
                        OfflineNote(text: "Example likes and earlier device-only activity are shown below. Private notes are not shared.")
                        if let error = session.likesError {
                            Text(error).font(.footnote).foregroundStyle(.red)
                            Button("Retry likes") { Task { await session.refreshLikes() } }.foregroundStyle(liyaAccent)
                        }
                        ForEach(session.photos.indices, id: \.self) { index in
                            if session.isLiked(kind: "photo", index: index) && !store.blockedExamples.contains(index) {
                                NavigationLink { ExamplePhotoDetail(index: index) } label: {
                                    HStack { ExampleAvatar(index: index); Text("Account like · example photo \(index + 1)"); Spacer() }
                                        .foregroundStyle(liyaInk).padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain)
                            }
                        }
                        ForEach(session.videos.indices, id: \.self) { index in
                            if session.isLiked(kind: "video", index: index) {
                                Button { store.videoRequest = VideoRequest(index: index) } label: {
                                    Text("Account like · example video \(index + 1)").foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain)
                            }
                        }
                        if session.likesReady && session.likedMediaIDs.isEmpty && visibleNotes.isEmpty && visibleLikes.isEmpty && store.videoNotes.isEmpty && store.likedVideos.isEmpty {
                            EmptyState(title: "No local activity", detail: "Likes and notes on example photos will appear here.")
                        }
                        ForEach(visibleLikes, id: \.self) { index in
                            NavigationLink { ExamplePhotoDetail(index: index) } label: {
                                HStack { ExampleAvatar(index: index); Text("Liked example photo \(index + 1)"); Spacer() }
                                    .foregroundStyle(liyaInk).padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                        ForEach(store.likedVideos.sorted(), id: \.self) { index in
                            Button { store.videoRequest = VideoRequest(index: index) } label: {
                                Text("Liked example video \(index + 1) locally").foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                        ForEach(store.videoNotes.reversed()) { note in
                            Button { store.videoRequest = VideoRequest(index: note.videoIndex, openNotes: true) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Private note · Video \(note.videoIndex + 1)").font(.subheadline.bold())
                                    Text(note.text).font(.caption).lineLimit(2)
                                }.foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                        ForEach(visibleNotes.reversed()) { comment in
                            NavigationLink { ExampleCommentsView(index: comment.photoIndex) } label: {
                                HStack { ExampleAvatar(index: comment.photoIndex); VStack(alignment: .leading) {
                                    Text("Private note · Photo \(comment.photoIndex + 1)").font(.subheadline.bold())
                                    Text(comment.text).font(.caption).lineLimit(2)
                                }; Spacer() }.foregroundStyle(liyaInk).padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(20)
            }
        }.navigationBarHidden(true).sheet(item: $deleteMessage) { item in
            LocalConfirmation(title: "Delete message draft?", message: "This removes the unsent draft from this device.", action: "Delete") {
                store.saveMessageDraft("", index: item.id); deleteMessage = nil
            } cancel: { deleteMessage = nil }
            .presentationDetents([.medium])
        }
    }
}
