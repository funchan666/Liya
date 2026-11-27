import SwiftUI

struct ComposeHome: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.dismiss) private var dismiss
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @EnvironmentObject private var store: LocalStore
    @State private var savedMessage: String?
    let showsBackButton: Bool

    init(showsBackButton: Bool = false) {
        self.showsBackButton = showsBackButton
    }

    private var hasContent: Bool {
        !store.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.composeAttachments.isEmpty
    }
    private var canKeepMoment: Bool {
        !store.composeLoading && store.composeText.count <= 4000 && hasContent
    }
    private var canSave: Bool { !store.composeLoading && hasContent }

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
            if showsBackButton {
                DuoControlRegion { _ in
                    HStack(spacing: 8) {
                        Button { dismiss() } label: {
                            HostedArtwork("back", labelWhileMissing: "Back").scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(words("Back to Square"))
                        HostedArtwork("publish-title").scaledToFit().frame(width: 150, height: 46).accessibilityLabel(words("Create"))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                }.frame(height: 48)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !showsBackButton {
                        HostedArtwork("publish-title").scaledToFit().frame(width: 150, height: 46).accessibilityLabel(words("Create"))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: words("Keep a moment")).font(LiyaType.text(.title3, weight: .bold)).foregroundStyle(liyaInk)
                        TextField(words("What's on your mind?"), text: Binding(get: { store.composeText }, set: { store.composeText = $0; savedMessage = nil }), axis: .vertical)
                            .lineLimit(5...12).padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                        if store.composeText.count > 4000 {
                            Text(verbatim: words("Please keep your post under 4,000 characters."))
                                .font(LiyaType.text(.footnote)).foregroundStyle(.red)
                        }
                    }
                    PostTagSelector(selection: $store.composeTags)
                    DraftMediaPicker(attachments: $store.composeAttachments, loading: $store.composeLoading, note: "Add up to 9 photos or videos.", compactButtons: true)
                    Button {
                        store.saveDraft(store.composeText.trimmingCharacters(in: .whitespacesAndNewlines), attachments: store.composeAttachments, published: true, tags: store.composeTags)
                        store.composeText = ""; store.composeAttachments = []; store.composeTags = []; savedMessage = "Moment saved."
                    } label: {
                        HStack(spacing: 8) {
                            HostedArtwork("profile-home-posts").scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true)
                            Text(verbatim: words("Save moment")).font(LiyaType.text(.subheadline, weight: .bold))
                        }.foregroundStyle(canKeepMoment ? Color.white : liyaInk.opacity(0.58))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background {
                                if canKeepMoment { RoundedRectangle(cornerRadius: 18).fill(liyaGradient) }
                                else { RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.82)) }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(liyaAccent.opacity(canKeepMoment ? 0 : 0.15), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(!canKeepMoment)
                    Button {
                        store.saveDraft(store.composeText.trimmingCharacters(in: .whitespacesAndNewlines), attachments: store.composeAttachments, tags: store.composeTags)
                        store.composeText = ""; store.composeAttachments = []; store.composeTags = []; savedMessage = "Draft saved."
                    } label: {
                        HStack(spacing: 8) {
                            HostedArtwork("profile-home-edit").scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true)
                            Text(verbatim: words("Save draft")).font(LiyaType.text(.subheadline, weight: .semibold))
                        }.foregroundStyle(canSave ? liyaAccent : liyaInk.opacity(0.58))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(liyaAccent.opacity(canSave ? 0.23 : 0.10), lineWidth: 1))
                    }.buttonStyle(.plain)
                        .disabled(!canSave)
                    if let savedMessage { Text(verbatim: words(savedMessage)).font(LiyaType.text(.footnote)).foregroundStyle(liyaAccent) }
                    NavigationLink { DraftsView() } label: {
                        HStack { Text(verbatim: words("Your drafts")).fontWeight(.semibold); Spacer(); Text("\(store.drafts.filter { $0.publishedLocally != true }.count)") }
                            .foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(20).padding(.bottom, tabBarClearance + 24)
            }.scrollDismissesKeyboard(.interactively)
            }
        }.navigationBarHidden(true)
    }
}

struct DraftsView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var deletingDraft: MomentDraft?
    @State private var previewVideo: DraftAttachment?
    private var unpublished: [MomentDraft] { store.drafts.filter { $0.publishedLocally != true } }
    var body: some View {
        PageShell(title: "Your drafts") {
            VStack(spacing: 12) {
                OfflineNote(text: "Drafts are private and aren't synced to your account.")
                if let error = social.error { Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                if unpublished.isEmpty {
                    EmptyState(title: "No drafts yet", detail: "Save a thought to find it here later.")
                } else {
                    ForEach(unpublished) { draft in
                        VStack(alignment: .leading, spacing: 12) {
                            if let mood = draft.mood { HostedArtwork(mood).scaledToFit().frame(width: 32, height: 32).accessibilityLabel(words("Mood")) }
                            if !draft.text.isEmpty { Text(draft.text).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading) }
                            if let media = draft.attachments, !media.isEmpty {
                                ScrollView(.horizontal) { HStack { ForEach(media) { item in
                                    Button { previewVideo = item } label: {
                                        MediaThumbnail(item: item).frame(width: 72, height: 86).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain).accessibilityLabel(words(item.isVideo ? "Preview video" : "Preview photo"))
                                } } }
                            }
                            HStack {
                                Text(draft.date, style: .date).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                                Spacer()
                                NavigationLink(words("Edit")) { EditDraftView(draft: draft) }.font(LiyaType.text(.footnote, weight: .bold)).foregroundStyle(liyaAccent)
                                Button(words("Save moment")) { store.publishLocally(draft.id) }
                                    .font(LiyaType.text(.footnote, weight: .bold)).foregroundStyle(liyaAccent)
                                Button(words("Delete")) { deletingDraft = draft }.font(LiyaType.text(.footnote, weight: .bold)).foregroundStyle(liyaAccent)
                            }
                            if isShared(draft), let owner = session.userID,
                               let status = social.moderationText(kind: "post", id: SocialAttempt.draftPostID(owner: owner, draft: draft)) {
                                Text(verbatim: words(status)).font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
    private func isShared(_ draft: MomentDraft) -> Bool {
        guard let owner = session.userID else { return false }
        return social.posts.contains { $0.id == SocialAttempt.draftPostID(owner: owner, draft: draft) }
    }
}

struct EditDraftView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    let draft: MomentDraft
    @State private var text = ""
    @State private var attachments: [DraftAttachment] = []
    @State private var loading = false
    @State private var tags: [String] = []
    @State private var initialized = false
    var body: some View {
        PageShell(title: draft.publishedLocally == true ? "Edit post" : "Edit draft") {
            VStack(spacing: 16) {
                OfflineNote(text: "This draft is private and isn't synced to your account.")
                TextField(words("Your draft"), text: $text, axis: .vertical).lineLimit(7...12).padding(16)
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
    @Environment(\.liyaWords) private var words
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var section = 0
    @State private var deleteMessage: DraftMessageSelection?
    private var messageIndexes: [Int] { store.messageDrafts.keys.compactMap(Int.init).filter { !store.hiddenCollectionProfiles.contains($0) }.sorted() }
    private var visibleLikes: [Int] { store.likedPhotos.filter { !store.hiddenCollectionProfiles.contains($0) }.sorted() }
    private var visibleNotes: [SavedPhotoNote] { store.comments.filter { !store.hiddenCollectionProfiles.contains($0.photoIndex) } }
    private var hasLocalActivity: Bool {
        !session.likedMediaIDs.isEmpty || !visibleNotes.isEmpty || !visibleLikes.isEmpty || !store.videoNotes.isEmpty || !store.likedVideos.isEmpty
    }
    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack { inboxTitle; Spacer(minLength: 14); membersLink }
                        VStack(alignment: .leading, spacing: 8) { inboxTitle; membersLink }
                    }
                    SegmentedTabs(items: ["Message", "Interaction"], selection: $section)
                    if section == 0 {
                        CommunityInboxThreads(hasDrafts: !messageIndexes.isEmpty)
                        if !messageIndexes.isEmpty { Text(verbatim: words("Drafts")).font(LiyaType.sectionHeading).foregroundStyle(liyaInk) }
                        ForEach(messageIndexes, id: \.self) { index in
                            HStack(spacing: 12) {
                                NavigationLink { CollectionAuthorView(index: index) } label: {
                                        CollectionPortrait(index: index)
                                }.buttonStyle(.plain).accessibilityLabel(words("View profile"))
                                VStack(alignment: .leading, spacing: 4) {
                                    NavigationLink { CollectionAuthorView(index: index) } label: {
                                            Text(verbatim: collectionName(index)).font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(liyaInk)
                                    }.buttonStyle(.plain)
                                    NavigationLink { CommunityConversationView(collectionIndex: index, displayName: collectionName(index)) } label: {
                                            Text(verbatim: words.inserting(store.messageDrafts[String(index)] ?? "", into: "Draft · %@")).font(LiyaType.text(.caption)).foregroundStyle(.secondary).lineLimit(2)
                                    }.buttonStyle(.plain)
                                }
                                Spacer()
                                NavigationLink(words("Open")) { CommunityConversationView(collectionIndex: index, displayName: collectionName(index)) }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent)
                                Button { deleteMessage = DraftMessageSelection(id: index) } label: {
                                    HostedArtwork("close", labelWhileMissing: "Close").scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel(words("Delete message draft"))
                            }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        CommunityActivityView(hasLocalActivity: hasLocalActivity || !session.likesReady)
                        if hasLocalActivity {
                            Text(verbatim: words("Your activity")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk).padding(.top, 4)
                        }
                        if let error = session.likesError {
                            Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red)
                            Button(words("Retry likes")) { Task { await session.refreshLikes() } }.foregroundStyle(liyaAccent)
                        }
                        ForEach(session.photos.indices, id: \.self) { index in
                            if session.isLiked(kind: "photo", index: index) && !store.hiddenCollectionProfiles.contains(index) {
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
        }.task(id: session.userID) {
            if session.userID != nil { await social.refreshMessages(session) }
        }.navigationBarHidden(true).sheet(item: $deleteMessage) { item in
            LocalConfirmation(title: "Delete message draft?", message: "This unsent draft will be permanently removed.", action: "Delete") {
                store.saveMessageDraft("", index: item.id); deleteMessage = nil
            } cancel: { deleteMessage = nil }
            .presentationDetents([.medium])
        }
    }

    private var inboxTitle: some View {
        HostedArtwork("message-title").scaledToFit().frame(width: 160, height: 46).accessibilityLabel(words("Messages"))
    }

    private var membersLink: some View {
        NavigationLink { CommunityMembersView() } label: {
            HStack(spacing: 6) {
                HostedArtwork("profile-home-people").scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                Text(verbatim: words("Members")).font(LiyaType.text(.subheadline, weight: .bold))
            }
            .foregroundStyle(liyaInk).padding(.horizontal, 12).frame(minHeight: 44)
            .modifier(ContactBarSurface())
        }.buttonStyle(.plain)
    }

    private func collectionName(_ index: Int) -> String {
        guard session.photos.indices.contains(index) else { return "Liya collection" }
        let id = session.photos[index].id
        return session.curatedDisplayName(for: id)
    }

    private func photoActivity(index: Int, title: String, note: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink { CollectionAuthorView(index: index, displayName: collectionName(index)) } label: {
                CollectionPortrait(index: index, size: 44)
            }.buttonStyle(.plain).accessibilityLabel(words.inserting(collectionName(index), into: "View %@ profile"))
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink { CollectionAuthorView(index: index, displayName: collectionName(index)) } label: {
                    Text(collectionName(index)).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk).lineLimit(1)
                }.buttonStyle(.plain)
                NavigationLink {
                    photoActivityDestination(index: index, note: note)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(LiyaType.text(.caption, weight: .medium)).foregroundStyle(.secondary)
                        if let note { Text(note).font(LiyaType.text(.caption)).foregroundStyle(liyaInk).lineLimit(2) }
                    }.frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink {
                photoActivityDestination(index: index, note: note)
            } label: {
                if CollectionPhotoRoles.isPost(index, in: session.photos) {
                    CollectionPhoto(catalogIndex: index, contentMode: .fill).frame(width: 52, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                } else { Color.clear.frame(width: 52, height: 52) }
            }.buttonStyle(.plain).accessibilityLabel(words(note == nil ? words("View post") : "View private note"))
        }.padding(12).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func photoActivityDestination(index: Int, note: String?) -> some View {
        if note != nil {
            SavedPhotoNotes(index: index)
        } else if session.photos.indices.contains(index) {
            CollectionPhotoDetail(mediaID: session.photos[index].id)
        } else {
            PageShell(title: "Post") { Text(verbatim: words("This post is no longer available.")) }
        }
    }

    private func videoActivity(index: Int, title: String, note: String?) -> some View {
        let creator = session.videos.indices.contains(index) ? session.curatedVideoCreators[session.videos[index].id] : nil
        let authorName = creator.map { session.curatedDisplayName(for: $0.photoID) } ?? "Liya collection"
        let avatarIndex = creator.flatMap { creator in session.photos.firstIndex(where: { $0.id == creator.photoID }) }
        return HStack(spacing: 12) {
            if let avatarIndex {
                NavigationLink { CollectionAuthorView(index: avatarIndex, displayName: authorName, mediaID: creator?.photoID) } label: {
                    CollectionPortrait(index: avatarIndex, size: 44)
                }.buttonStyle(.plain).accessibilityLabel(words("View profile"))
            } else {
                HostedArtwork(note == nil ? "video-like-on" : "comment").scaledToFit().frame(width: 44, height: 44).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let avatarIndex {
                    NavigationLink { CollectionAuthorView(index: avatarIndex, displayName: authorName, mediaID: creator?.photoID) } label: {
                        Text(authorName).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk).lineLimit(1)
                    }.buttonStyle(.plain)
                } else {
                    Text(verbatim: words("Liya collection")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk).lineLimit(1)
                }
                Button { store.videoRequest = VideoRequest(index: index, openNotes: note != nil) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(LiyaType.text(.caption, weight: .medium)).foregroundStyle(.secondary)
                        if let note { Text(note).font(LiyaType.text(.caption)).foregroundStyle(liyaInk).lineLimit(2) }
                    }.frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HostedArtwork(note == nil ? "video-like-on" : "comment").scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
        }.padding(12).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
    }
}
