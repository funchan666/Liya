import SwiftUI

struct ComposeHome: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var savedMessage: String?
    @State private var publishing = false
    @State private var showCommunitySetup = false
    @AppStorage("liya.postAttempt") private var postAttempt = ""
    @AppStorage("liya.postFingerprint") private var postFingerprint = ""
    let showsBackButton: Bool

    init(showsBackButton: Bool = false) {
        self.showsBackButton = showsBackButton
    }

    private var hasContent: Bool {
        !store.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.composeAttachments.isEmpty
    }
    private var canShare: Bool {
        !publishing && !store.composeLoading && !social.loading && store.composeText.count <= 4000 && hasContent
    }
    private var canSave: Bool { !publishing && !store.composeLoading && hasContent }

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
            if showsBackButton {
                DuoControlRegion { _ in
                    HStack(spacing: 8) {
                        Button { dismiss() } label: {
                            Image("back").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Back to Square")
                        Image("publish-title").resizable().scaledToFit().frame(width: 150, height: 46).accessibilityLabel("Create")
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                }.frame(height: 48)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !showsBackButton {
                        Image("publish-title").resizable().scaledToFit().frame(width: 150, height: 46).accessibilityLabel("Create")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Share a moment").font(.title3.bold()).foregroundStyle(liyaInk)
                        TextField("What's on your mind?", text: Binding(get: { store.composeText }, set: { store.composeText = $0; savedMessage = nil }), axis: .vertical)
                            .lineLimit(5...12).padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                            .disabled(publishing)
                        if store.composeText.count > 4000 {
                            Text("Please keep your post under 4,000 characters.")
                                .font(.footnote).foregroundStyle(.red)
                        }
                    }
                    PostTagSelector(selection: $store.composeTags).disabled(publishing)
                    DraftMediaPicker(attachments: $store.composeAttachments, loading: $store.composeLoading, note: "Add up to 9 photos or videos.", compactButtons: true).disabled(publishing)
                    if let error = social.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button {
                        store.saveDraft(store.composeText.trimmingCharacters(in: .whitespacesAndNewlines), attachments: store.composeAttachments, published: true, tags: store.composeTags)
                        store.composeText = ""; store.composeAttachments = []; store.composeTags = []; savedMessage = "Moment saved."
                    } label: {
                        HStack(spacing: 8) {
                            if publishing { LiyaLoadingIndicator(size: 24) }
                            else { Image("profile-home-posts").resizable().scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true) }
                            Text(LocalizedStringKey(publishing ? "Saving…" : "Save moment")).font(.subheadline.weight(.bold))
                        }.foregroundStyle(canShare ? Color.white : liyaInk.opacity(0.58))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background {
                                if canShare { RoundedRectangle(cornerRadius: 18).fill(liyaGradient) }
                                else { RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.82)) }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(liyaAccent.opacity(canShare ? 0 : 0.15), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(!canShare)
                    Button {
                        store.saveDraft(store.composeText.trimmingCharacters(in: .whitespacesAndNewlines), attachments: store.composeAttachments, tags: store.composeTags)
                        store.composeText = ""; store.composeAttachments = []; store.composeTags = []; savedMessage = "Draft saved."
                    } label: {
                        HStack(spacing: 8) {
                            Image("profile-home-edit").resizable().scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true)
                            Text("Save draft").font(.subheadline.weight(.semibold))
                        }.foregroundStyle(canSave ? liyaAccent : liyaInk.opacity(0.58))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(liyaAccent.opacity(canSave ? 0.23 : 0.10), lineWidth: 1))
                    }.buttonStyle(.plain)
                        .disabled(!canSave)
                    if let savedMessage { Text(savedMessage).font(.footnote).foregroundStyle(liyaAccent) }
                    NavigationLink { DraftsView() } label: {
                        HStack { Text("Your drafts").fontWeight(.semibold); Spacer(); Text("\(store.drafts.filter { $0.publishedLocally != true }.count)") }
                            .foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(20).padding(.bottom, tabBarClearance + 24)
            }.scrollDismissesKeyboard(.interactively)
            }
        }.navigationBarHidden(true)
            .navigationDestination(isPresented: $showCommunitySetup) { CommunityJoinView() }
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
                OfflineNote(text: "Drafts are private and aren't synced to your account.")
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
                                Button("Save moment") { store.publishLocally(draft.id) }
                                    .font(.footnote.bold()).foregroundStyle(liyaAccent)
                                Button("Delete") { deletingDraft = draft }.font(.footnote.bold()).foregroundStyle(liyaAccent)
                            }
                            if isShared(draft), let owner = session.userID,
                               let status = social.moderationText(kind: "post", id: SocialAttempt.draftPostID(owner: owner, draft: draft)) {
                                Text(status).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(16).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }.padding(.top, 12)
        }.sheet(item: $previewVideo) { item in
            if item.isVideo { DraftVideoPreview(item: item) } else { DraftPhotoPreview(item: item) }
        }
        .sheet(item: $deletingDraft) { draft in
            LocalConfirmation(title: "Delete draft?", message: "This draft will be permanently removed.", action: "Delete") {
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
        PageShell(title: draft.publishedLocally == true ? "Edit post" : "Edit draft") {
            VStack(spacing: 16) {
                OfflineNote(text: "This draft is private and isn't synced to your account.")
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
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var section = 0
    @State private var deleteMessage: DraftMessageSelection?
    private var messageIndexes: [Int] { store.messageDrafts.keys.compactMap(Int.init).filter { !store.blockedExamples.contains($0) }.sorted() }
    private var visibleLikes: [Int] { store.likedPhotos.filter { !store.blockedExamples.contains($0) }.sorted() }
    private var visibleNotes: [LocalComment] { store.comments.filter { !store.blockedExamples.contains($0.photoIndex) } }
    private var hasLocalActivity: Bool {
        !session.likedMediaIDs.isEmpty || !visibleNotes.isEmpty || !visibleLikes.isEmpty || !store.videoNotes.isEmpty || !store.likedVideos.isEmpty
    }
    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image("message-title").resizable().scaledToFit().frame(width: 160, height: 46).accessibilityLabel("Messages")
                    SegmentedTabs(items: ["Message", "Interaction"], selection: $section)
                    if section == 0 {
                        if messageIndexes.isEmpty {
                            EmptyState(title: "No messages yet", detail: "Messaging is currently unavailable.")
                        }
                        if !messageIndexes.isEmpty { OfflineNote(text: "Earlier drafts for example profiles are private and have not been sent.") }
                        ForEach(messageIndexes, id: \.self) { index in
                            HStack(spacing: 12) {
                                NavigationLink { ExampleProfileView(index: index) } label: {
                                        ExampleAvatar(index: index)
                                }.buttonStyle(.plain).accessibilityLabel("View profile")
                                VStack(alignment: .leading, spacing: 4) {
                                    NavigationLink { ExampleProfileView(index: index) } label: {
                                            Text("Example profile \(index + 1)").font(.subheadline.bold()).foregroundStyle(liyaInk)
                                    }.buttonStyle(.plain)
                                    NavigationLink { ExampleChatView(index: index) } label: {
                                            Text("Draft · \(store.messageDrafts[String(index)] ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }.buttonStyle(.plain)
                                }
                                Spacer()
                                NavigationLink("Open") { ExampleChatView(index: index) }.font(.caption.bold()).foregroundStyle(liyaAccent)
                                Button { deleteMessage = DraftMessageSelection(id: index) } label: {
                                    Image("close").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel("Delete message draft")
                            }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        CommunityActivityView(hasLocalActivity: hasLocalActivity || !session.likesReady)
                        if hasLocalActivity {
                            Text("Your activity").font(.headline).foregroundStyle(liyaInk).padding(.top, 4)
                        }
                        if let error = session.likesError {
                            Text(error).font(.footnote).foregroundStyle(.red)
                            Button("Retry likes") { Task { await session.refreshLikes() } }.foregroundStyle(liyaAccent)
                        }
                        ForEach(session.photos.indices, id: \.self) { index in
                            if session.isLiked(kind: "photo", index: index) && !store.blockedExamples.contains(index) {
                                photoActivity(index: index, title: "You liked a post", note: nil)
                            }
                        }
                        ForEach(session.videos.indices, id: \.self) { index in
                            if session.isLiked(kind: "video", index: index) {
                                videoActivity(index: index, title: "You liked a video", note: nil)
                            }
                        }
                        ForEach(visibleLikes, id: \.self) { index in
                            photoActivity(index: index, title: "Saved like", note: nil)
                        }
                        ForEach(store.likedVideos.sorted(), id: \.self) { index in
                            videoActivity(index: index, title: "Saved like", note: nil)
                        }
                        ForEach(store.videoNotes.reversed()) { note in
                            videoActivity(index: note.videoIndex, title: "Private note", note: note.text)
                        }
                        ForEach(visibleNotes.reversed()) { comment in
                            photoActivity(index: comment.photoIndex, title: "Private note", note: comment.text)
                        }
                    }
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(20).padding(.bottom, tabBarClearance)
            }.refreshable {
                if section == 0 {
                    await social.refreshMessages(session)
                    if !social.realtimeConnected { social.watchMessages(session) }
                } else {
                    await social.refreshNotifications(session)
                }
            }
        }.navigationBarHidden(true).sheet(item: $deleteMessage) { item in
            LocalConfirmation(title: "Delete message draft?", message: "This unsent draft will be permanently removed.", action: "Delete") {
                store.saveMessageDraft("", index: item.id); deleteMessage = nil
            } cancel: { deleteMessage = nil }
            .presentationDetents([.medium])
        }
    }

    private func collectionName(_ index: Int) -> String {
        guard session.photos.indices.contains(index) else { return "Liya collection" }
        let id = session.photos[index].id
        return ExampleVideoCreator.byVideoID.values.first { $0.photoID == id }?.name ?? "Liya collection"
    }

    private func photoActivity(index: Int, title: String, note: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink { ExampleProfileView(index: index, displayName: collectionName(index)) } label: {
                ExampleAvatar(index: index, size: 44)
            }.buttonStyle(.plain).accessibilityLabel("View \(collectionName(index)) profile")
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink { ExampleProfileView(index: index, displayName: collectionName(index)) } label: {
                    Text(collectionName(index)).font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk).lineLimit(1)
                }.buttonStyle(.plain)
                NavigationLink {
                    if note == nil { ExamplePhotoDetail(index: index) } else { ExampleCommentsView(index: index) }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        if let note { Text(note).font(.caption).foregroundStyle(liyaInk).lineLimit(2) }
                    }.frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink {
                if note == nil { ExamplePhotoDetail(index: index) } else { ExampleCommentsView(index: index) }
            } label: {
                if ExamplePhotoAllocation.isPost(index, in: session.photos) {
                    CloudPhoto(index: index, contentMode: .fill).frame(width: 52, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                } else { Color.clear.frame(width: 52, height: 52) }
            }.buttonStyle(.plain).accessibilityLabel(note == nil ? "View post" : "View private note")
        }.padding(12).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
    }

    private func videoActivity(index: Int, title: String, note: String?) -> some View {
        let creator = session.videos.indices.contains(index) ? ExampleVideoCreator.byVideoID[session.videos[index].id] : nil
        let avatarIndex = creator.flatMap { creator in session.photos.firstIndex(where: { $0.id == creator.photoID }) }
        return HStack(spacing: 12) {
            if let avatarIndex {
                NavigationLink { ExampleProfileView(index: avatarIndex, displayName: creator?.name) } label: {
                    ExampleAvatar(index: avatarIndex, size: 44)
                }.buttonStyle(.plain).accessibilityLabel("View profile")
            } else {
                Image(note == nil ? "video-like-on" : "comment").resizable().scaledToFit().frame(width: 44, height: 44).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let avatarIndex {
                    NavigationLink { ExampleProfileView(index: avatarIndex, displayName: creator?.name) } label: {
                        Text(creator?.name ?? "Liya collection").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk).lineLimit(1)
                    }.buttonStyle(.plain)
                } else {
                    Text("Liya collection").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk).lineLimit(1)
                }
                Button { store.videoRequest = VideoRequest(index: index, openNotes: note != nil) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        if let note { Text(note).font(.caption).foregroundStyle(liyaInk).lineLimit(2) }
                    }.frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(note == nil ? "video-like-on" : "comment").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
        }.padding(12).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
    }
}
