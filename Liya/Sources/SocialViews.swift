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
    static func draftPostID(owner: UUID, draft: MomentDraft) -> UUID {
        let hash = fingerprint(owner: owner, target: draft.id, text: draft.text, tags: draft.tags ?? [], files: draft.attachments ?? [])
        let chars = Array(hash.prefix(32))
        let raw = String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
        return UUID(uuidString: raw)!
    }
}

struct MemberInitialsAvatar: View {
    let name: String

    private var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "" }
        let last = words.dropFirst().last?.first
        return (String(first) + (last.map { String($0) } ?? "")).uppercased()
    }

    var body: some View {
        Text(verbatim: initials)
            .font(LiyaType.text(.headline, weight: .semibold)).foregroundStyle(liyaInk)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(liyaAccent.opacity(0.12))
            .accessibilityHidden(true)
    }
}

struct SocialAvatar: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let personID: UUID
    var commentAuthor: SocialPerson? = nil
    private struct PortraitSource: Equatable {
        let viewer: UUID
        let member: UUID
        let path: String
    }
    @State private var signedPortrait: (source: PortraitSource, url: URL)?

    private var person: SocialPerson? {
        guard let viewer = session.userID, viewer == social.connectionsOwner, !social.blocked.contains(personID) else { return nil }
        if let commentAuthor { return commentAuthor.id == personID ? commentAuthor : nil }
        return social.person(personID)
    }

    private var source: PortraitSource? {
        guard let viewer = session.userID, let path = person?.avatarPath,
              path.hasPrefix(personID.uuidString.lowercased() + "/avatars/") else { return nil }
        return PortraitSource(viewer: viewer, member: personID, path: path)
    }

    @ViewBuilder private var placeholder: some View {
        if let person {
            MemberInitialsAvatar(name: person.displayName)
        } else {
            Image(decorative: "app-mark").resizable().scaledToFit()
        }
    }

    var body: some View {
        Group {
            if let source, let signedPortrait, signedPortrait.source == source {
                AsyncImage(url: signedPortrait.url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { placeholder }
                }.id(signedPortrait.url)
            } else { placeholder }
        }.clipped().accessibilityHidden(true)
            .task(id: source) { [source] in
                signedPortrait = nil
                guard let source, let url = try? await social.mediaURL(session, path: source.path),
                      !Task.isCancelled, source.viewer == session.userID else { return }
                signedPortrait = (source, url)
            }
    }
}

struct CommunityJoinView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var name = ""
    @State private var signature = ""
    @State private var initialized = false
    @State private var saving = false
    @State private var shareAvatar = false
    @State private var loadingProfile = true
    @State private var notice: String?
    @State private var profileLoadError: String?
    var body: some View {
        PageShell(title: "Community profile") {
            VStack(alignment: .leading, spacing: 15) {
                Text("Community profile changes may need review. Approved profile details are shown to other members. Messages stay private unless you choose to report one.")
                    .font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if loadingProfile { LiyaLoadingIndicator(size: 26).accessibilityLabel("Loading community profile") }
                if let owner = session.userID, let status = social.moderationText(kind: "profile", id: owner) {
                    Text(status).font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let notice { Text(notice).font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).fixedSize(horizontal: false, vertical: true) }
                Text("Community name").font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                TextField("Choose a name", text: $name).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).disabled(saving || loadingProfile || profileLoadError != nil)
                Text("Introduction").font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                TextField("A little about you", text: $signature, axis: .vertical).lineLimit(2...5).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).disabled(saving || loadingProfile || profileLoadError != nil)
                Button { shareAvatar.toggle() } label: {
                    HStack(spacing: 12) {
                        Image("avatar-camera").resizable().scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Share profile photo").font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                            Text(LocalizedStringKey(shareAvatar ? "Share with community" : "Not shared"))
                                .font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(shareAvatar ? "consent-on" : "consent-off").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                    }.padding(14).frame(maxWidth: .infinity, minHeight: 64)
                        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityLabel("Share profile photo")
                    .accessibilityValue(shareAvatar ? "On" : "Off").accessibilityAddTraits(shareAvatar ? .isSelected : [])
                    .disabled(saving || loadingProfile || profileLoadError != nil)
                if shareAvatar && session.profile?.avatarPath == nil { Text("Add an avatar to your account profile before sharing it.").font(LiyaType.text(.footnote)).foregroundStyle(.secondary) }
                if let profileLoadError {
                    Text(profileLoadError).font(LiyaType.text(.footnote)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await loadProfile() } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                if let error = social.error { Text(error).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                PrimaryButton(title: saving ? "Saving…" : "Save community profile", disabled: saving || loadingProfile || profileLoadError != nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || signature.count > 500 || (shareAvatar && session.profile?.avatarPath == nil)) {
                    saving = true
                    Task {
                        if await social.join(session, name: name, signature: signature, shareAvatar: shareAvatar), let owner = session.userID {
                            await social.refreshModeration(session)
                            notice = social.moderationText(kind: "profile", id: owner) ?? "Community profile saved."
                        }
                        saving = false
                    }
                }
            }.padding(.top, 12)
        }.task(id: session.userID) {
            initialized = false; name = ""; signature = ""; shareAvatar = false; notice = nil
            await loadProfile()
        }
    }
    private func loadProfile() async {
        guard !initialized, let owner = session.userID else { loadingProfile = false; return }
        loadingProfile = true; profileLoadError = nil
        do {
            let person = try await social.editableProfile(session)
            guard session.userID == owner, !Task.isCancelled else { return }
            if let person { name = person.displayName; signature = person.signature; shareAvatar = person.avatarPath != nil }
            else { name = session.profile?.displayName ?? ""; signature = session.profile?.signature ?? "" }
            initialized = true; loadingProfile = false
        } catch {
            guard session.userID == owner, !Task.isCancelled else { return }
            loadingProfile = false; profileLoadError = "Couldn't load your community profile. Please try again."
        }
    }
}

struct CommunityFeed: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    var body: some View {
        let controls = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("Community").font(LiyaType.text(.title3, weight: .bold)).foregroundStyle(liyaInk)
                Spacer(minLength: 0)
                if social.loading { LiyaLoadingIndicator(size: 24).accessibilityLabel("Loading community") }
            }.frame(minHeight: 44)
            controls {
                NavigationLink { CommunityMembersView() } label: {
                    HStack(spacing: 7) {
                        Image("nav-soft-profile").resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                        Text("Members").font(LiyaType.text(.subheadline, weight: .semibold))
                    }.foregroundStyle(liyaInk).frame(maxWidth: .infinity, minHeight: 46)
                        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                Button { Task { await social.refresh(session) } } label: {
                    Text("Refresh").font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaAccent)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).disabled(social.loading)
            }
            if let error = social.error {
                Text(error).font(LiyaType.text(.footnote)).foregroundStyle(.red)
            } else if !social.loading && social.posts.isEmpty {
                HStack(spacing: 14) {
                    Image("empty-art").resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A little quiet here").font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                        Text("Share a moment to get things started.").font(LiyaType.text(.footnote)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
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
            LazyVStack(alignment: .leading, spacing: 10) {
                if session.userID != nil, social.checkedMemberProfileOwner == session.userID, !social.canFollowMembers(session) {
                    NavigationLink { CommunityJoinView() } label: {
                        ProfileDetailActionLabel(title: "Set up community profile", style: .follow)
                    }.buttonStyle(.plain)
                }
                ForEach(social.directoryPeople) { person in
                    NavigationLink { CommunityPersonView(personID: person.id) } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(personID: person.id).frame(width: 46, height: 46).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: person.displayName).font(LiyaType.sectionHeading)
                                if !person.signature.isEmpty {
                                    Text(verbatim: person.signature).font(LiyaType.detail).lineLimit(2).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14).foregroundStyle(liyaInk).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
                if social.directoryFailed {
                    ConnectionRetryRow(message: "Please check your connection and try again.") {
                        await social.loadMemberDirectory(session, reset: social.directoryPeople.isEmpty)
                    }
                } else if social.directoryHasMore {
                    LiyaLoadingIndicator(size: 26).frame(maxWidth: .infinity, minHeight: 46)
                        .task(id: social.directoryAfter) {
                            if social.directoryAfter != nil { await social.loadMemberDirectory(session) }
                        }
                } else if social.directoryPeople.isEmpty {
                    InboxEmptyState(title: "No members yet")
                }
            }.padding(.vertical, 12)
        }.task(id: session.userID) { await social.loadMemberDirectory(session, reset: true) }
        .refreshable { await social.loadMemberDirectory(session, reset: true) }
    }
}

private struct CommunityPostCounts: Decodable {
    let likeCount: Int
    let commentCount: Int
    enum CodingKeys: String, CodingKey { case likeCount = "like_count", commentCount = "comment_count" }
}

struct CommunityPostCard: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let post: SocialPost
    @State private var deleting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NavigationLink { CommunityPersonView(personID: post.ownerID) } label: {
                    HStack(spacing: 8) {
                        SocialAvatar(personID: post.ownerID).frame(width: 40, height: 40).clipShape(Circle())
                        VStack(alignment: .leading) { Text(social.person(post.ownerID)?.displayName ?? "Liya member").font(LiyaType.text(.subheadline, weight: .bold)); Text("Community post").font(LiyaType.text(.caption)).foregroundStyle(.secondary) }
                    }.foregroundStyle(liyaInk)
                }.buttonStyle(.plain)
                Spacer()
                if post.ownerID == session.userID {
                    NavigationLink("Edit") { CommunityEditPostView(post: post) }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent)
                    Button("Delete") { deleting = true }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                } else {
                    NavigationLink("Report") { CommunityReportView(target: post.ownerID, post: post.id) }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
            }
            if post.ownerID == session.userID, let status = social.moderationText(kind: "post", id: post.id) {
                Text(status).font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !post.body.isEmpty { Text(post.body).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading) }
            if !post.tags.isEmpty { Text(post.tags.map { "# " + $0 }.joined(separator: "   ")).font(LiyaType.text(.caption)).foregroundStyle(liyaAccent) }
            SocialMediaStrip(post: post)
            CommunityPostEngagement(post: post)
        }.modifier(LiyaFeedCardSurface())
            .sheet(isPresented: $deleting) {
                LocalConfirmation(title: "Delete this post?", message: "The post and its comments will no longer be visible to the community.", action: "Delete") {
                    deleting = false; Task { _ = await social.deletePost(session, id: post.id) }
                } cancel: { deleting = false }.presentationDetents([.medium])
            }
    }
}

private struct CommunityPostEngagement: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let post: SocialPost
    var onOpenComments: () -> Void = {}
    @State private var busy = false
    @State private var counts: CommunityPostCounts?
    @State private var countsRequest = UUID()
    @State private var countsFailed = false
    @State private var showingComments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { engagementActions }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) { engagementActions }
            }
            if countsFailed {
                Button("Retry counts") { Task { await loadCounts() } }
                    .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
            }
        }
        .sheet(isPresented: $showingComments) {
            NavigationStack { CommunityCommentsView(post: post) }
                .environment(\.liyaTabBarClearance, 0)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .task(id: post.id) {
            async let like: Void = social.refreshPostLike(session, post: post.id)
            await loadCounts()
            await like
        }
        .onLiyaChange(of: social.syncGeneration) { _ in Task { await loadCounts() } }
    }

    @ViewBuilder private var engagementActions: some View {
        let placeholder = countsFailed ? "—" : "…"
        Button {
            busy = true; Task { await social.toggleLike(session, post: post.id); await loadCounts(); busy = false }
        } label: {
            LiyaFeedActionLabel(title: social.likes.contains(post.id) ? "Liked" : "Like",
                                count: counts.map { $0.likeCount.formatted() } ?? placeholder,
                                icon: social.likes.contains(post.id) ? "video-like-on" : "video-like-off",
                                active: social.likes.contains(post.id))
        }.buttonStyle(.plain).disabled(busy || social.loading)
            .accessibilityAddTraits(social.likes.contains(post.id) ? .isSelected : [])
        Button {
            onOpenComments()
            showingComments = true
        } label: {
            LiyaFeedActionLabel(title: "Comments", count: counts.map { $0.commentCount.formatted() } ?? placeholder, icon: "profile-action-message")
        }.buttonStyle(.plain)
    }

    private func loadCounts() async {
        let request = UUID()
        countsRequest = request
        countsFailed = false
        guard let owner = session.userID else { counts = nil; return }
        do {
            let rows: [CommunityPostCounts] = try await session.client
                .rpc("liya_post_counts", params: ["p_post_id": post.id.uuidString]).execute().value
            guard countsRequest == request, session.userID == owner else { return }
            counts = rows.first
            countsFailed = counts == nil
        } catch {
            guard countsRequest == request, !Task.isCancelled, session.userID == owner else { return }
            countsFailed = true
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
                if paths.count + additions.count > 9 { Text("Remove items to keep at most 9 attachments.").font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                if let error = social.error { Text(error).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
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
    @Environment(\.locale) private var locale
    let personID: UUID
    @State private var options = false
    @State private var section = 0
    @State private var preview: SocialMediaItem?
    @State private var followUpdateFailed = false
    private var profileCheckNeeded: Bool {
        !social.canFollowMembers(session) && (social.checkedMemberProfileOwner != session.userID || social.error != nil)
    }
    private var posts: [SocialPost] { social.posts.filter { $0.ownerID == personID } }
    private var videos: [SocialMediaItem] {
        posts.flatMap { post in
            post.mediaPaths.enumerated().compactMap { index, path in
                guard post.mediaKinds.indices.contains(index), post.mediaKinds[index] == "video" else { return nil }
                return SocialMediaItem(path: path, kind: "video", post: post)
            }
        }
    }
    var body: some View {
        Group {
            if let person = social.person(personID) {
                ProfileDetailLayout(name: person.displayName, introduction: person.signature, showOptions: { options = true }) {
                    SocialAvatar(personID: personID)
                } actions: {
                    if personID != session.userID {
                        VStack(spacing: 10) {
                            if !social.blocked.contains(personID) {
                                ProfileContactActions(recipient: .member(personID), name: person.displayName) { followAction }
                            }
                            if social.connectionsError != nil {
                                ConnectionRetryRow { await social.refresh(session) }
                            } else if profileCheckNeeded && !social.loading {
                                ConnectionRetryRow(message: "Couldn't load your profile. Please try again.") { await social.refresh(session) }
                            }
                            if followUpdateFailed {
                                Text("Couldn't update your follow. Please try again.").font(LiyaType.text(.footnote)).foregroundStyle(liyaInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        NavigationLink { CommunityJoinView() } label: {
                            Text("Edit community profile").font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 46)
                                .background(liyaGradient, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                } content: {
                    if let error = social.error, !followUpdateFailed, !profileCheckNeeded { Text(error).font(LiyaType.text(.footnote)).foregroundStyle(.secondary) }
                    if !posts.isEmpty {
                        ProfileContentTabs(selection: $section, showVideo: !videos.isEmpty)
                    }
                    if section == 1 && !videos.isEmpty {
                        if videos.count == 1, let item = videos.first {
                            Button { preview = item } label: {
                                ProfileSingleVideoRow { SocialMediaThumbnail(item: item) }
                            }.buttonStyle(.plain).accessibilityLabel("Play video")
                        } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(Array(videos.enumerated()), id: \.offset) { _, item in
                                Button { preview = item } label: {
                                    SocialMediaThumbnail(item: item).frame(height: 145).frame(maxWidth: .infinity)
                                        .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel("Play video")
                            }
                        }
                        }
                    } else {
                        ForEach(posts) { CommunityPostCard(post: $0) }
                    }
                }
            } else {
                PageShell(title: "Member") { EmptyState(title: "Member unavailable", detail: "This profile may no longer be visible to you.") }
            }
        }
        .task(id: session.userID) {
            followUpdateFailed = false
            await social.refresh(session)
        }
        .sheet(isPresented: $options) { CommunityProfileOptions(personID: personID) }
        .sheet(item: $preview) { item in SocialMediaPreview(item: item) }
    }

    @ViewBuilder private var followAction: some View {
        let canShowState = session.userID != nil && social.connectionsOwner == session.userID && social.connectionsReady
        let updating = social.changingFollows.contains(personID)
        let checkingProfile = !social.canFollowMembers(session) && social.loading
        if !canShowState || updating || checkingProfile || profileCheckNeeded {
            Group {
                if updating || checkingProfile || social.connectionsLoading {
                    LiyaLoadingIndicator(size: 25)
                } else {
                    Text("Follow").font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, minHeight: 54)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 17))
        } else if social.canFollowMembers(session) {
            let following = social.follows.contains(personID)
            Button {
                followUpdateFailed = false
                let owner = session.userID
                Task {
                    let saved = await social.setRelation(session, target: personID, table: "liya_follows", enabled: !following)
                    if session.userID == owner { followUpdateFailed = !saved }
                }
            } label: {
                ProfileDetailActionLabel(title: following ? String(localized: "Following", locale: locale) : String(localized: "Follow", locale: locale),
                                         style: following ? .following : .follow)
            }.buttonStyle(.plain).disabled(social.blocked.contains(personID))
                .accessibilityLabel(following ? Text("Unfollow") : Text("Follow"))
        } else {
            NavigationLink { CommunityJoinView() } label: {
                ProfileDetailActionLabel(title: String(localized: "Follow", locale: locale), style: .follow)
            }.buttonStyle(.plain).accessibilityHint("Set up your community profile to follow members.")
        }
    }

}

private struct CommunityProfileOptions: View {
    private enum Stage { case options, report, reportReceived, block }

    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    let personID: UUID
    private let startsAtReport: Bool
    @State private var stage: Stage
    @State private var showingEditor = false
    @State private var submittingBlock = false
    @State private var blockFailed = false
    @State private var reason: String?
    @State private var reportID = UUID()
    @State private var submittingReport = false
    @State private var reportFailed = false
    @AccessibilityFocusState private var reportFeedbackFocused: Bool

    init(personID: UUID, startsAtReport: Bool = false) {
        self.personID = personID
        self.startsAtReport = startsAtReport
        _stage = State(initialValue: startsAtReport ? .report : .options)
    }

    private var title: String {
        switch stage {
        case .options: return "Profile options"
        case .report, .reportReceived: return "Report member"
        case .block: return "Block this member?"
        }
    }

    private var canBlock: Bool {
        guard session.hasSavedMemberSession, let owner = session.userID, owner != personID,
              social.connectionsOwner == owner, social.person(personID) != nil else { return false }
        return social.canFollowMembers(session)
    }

    var body: some View {
        SafetyPanel(title: title, subject: social.person(personID)?.displayName,
                    back: (stage == .block || (stage == .report && !startsAtReport)) ? { backToOptions() } : nil,
                    close: { dismiss() }, busy: submittingBlock || submittingReport) {
            SocialAvatar(personID: personID)
        } content: {
            switch stage {
            case .options: options
            case .block: blockConfirmation
            case .report: reportForm
            case .reportReceived:
                Text("Report received.").font(LiyaType.text(.body, weight: .semibold)).foregroundStyle(liyaInk)
                    .accessibilityFocused($reportFeedbackFocused)
                    .onAppear { reportFeedbackFocused = true }
                SafetySubmitButton(title: "Done") { dismiss() }
            }
        }
        .onLiyaChange(of: session.userID) { _ in dismiss() }
        .onLiyaChange(of: personID) { _ in dismiss() }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { CommunityJoinView() }
        }
    }

    @ViewBuilder private var options: some View {
        if personID == session.userID {
            SafetyActionRow(title: "Edit community profile", kind: .edit) { showingEditor = true }
        } else {
            SafetyActionRow(title: "Report member", kind: .report) { stage = .report }
            Divider()
            if canBlock {
                SafetyActionRow(title: "Block member", kind: .block) { stage = .block }
            } else if social.loading {
                LiyaLoadingIndicator(size: 24).frame(maxWidth: .infinity, minHeight: 44)
            } else if session.hasSavedMemberSession, let owner = session.userID,
                      social.checkedMemberProfileOwner == owner, social.error == nil,
                      social.person(personID) != nil, !social.canFollowMembers(session) {
                SafetyActionRow(title: "Create a community profile to block", kind: .edit) { showingEditor = true }
            } else {
                ConnectionRetryRow(message: "Couldn't load your profile. Please try again.") { await social.refresh(session) }
            }
        }
    }

    private var blockConfirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Their comments and other community content will no longer be visible to you.")
                .font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.77)).fixedSize(horizontal: false, vertical: true)
            if blockFailed {
                Text("Couldn't block this profile. Please try again.").font(LiyaType.text(.footnote)).foregroundStyle(liyaInk)
            }
            SafetySubmitButton(title: submittingBlock ? "Blocking…" : "Block member",
                               destructive: true, busy: submittingBlock) { submitBlock() }
            SafetySecondaryButton(title: "Cancel") { backToOptions() }
                .disabled(submittingBlock)
        }
    }

    private var reportForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a reason")
                .font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.77)).fixedSize(horizontal: false, vertical: true)
            SafetyReasonList(selected: reason) { selected in
                guard selected != reason else { return }
                reason = selected
                reportID = UUID()
                reportFailed = false
            }
            .disabled(submittingReport)
            if reportFailed {
                Text("Couldn't confirm the report. Please try again.").font(LiyaType.text(.footnote)).foregroundStyle(liyaInk)
                    .fixedSize(horizontal: false, vertical: true).accessibilityFocused($reportFeedbackFocused)
                    .onAppear { reportFeedbackFocused = true }
            }
            SafetySubmitButton(title: submittingReport ? "Sending…" : "Send report",
                               busy: submittingReport, disabled: reason == nil) { submitReport() }
        }
    }

    private func submitReport() {
        guard stage == .report, !submittingReport, let reason else { return }
        guard session.hasSavedMemberSession, let owner = session.userID, owner != personID else {
            reportFailed = true
            return
        }
        let requestID = reportID
        let target = personID
        submittingReport = true
        reportFailed = false
        reportFeedbackFocused = false
        Task {
            guard session.userID == owner else { submittingReport = false; return }
            let received = await social.report(session, id: requestID, target: target, post: nil, reason: reason)
            submittingReport = false
            guard session.userID == owner, requestID == reportID else { return }
            if received { stage = .reportReceived } else { reportFailed = true }
        }
    }

    private func backToOptions() {
        guard !submittingBlock, !submittingReport else { return }
        stage = .options
        blockFailed = false
        reportFailed = false
    }

    private func submitBlock() {
        guard !submittingBlock else { return }
        guard let owner = session.userID, canBlock else { blockFailed = true; return }
        submittingBlock = true
        blockFailed = false
        Task {
            let saved = await social.setRelation(session, target: personID, table: "liya_blocks", enabled: true)
            submittingBlock = false
            guard session.userID == owner else { return }
            if saved { dismiss() } else { blockFailed = true }
        }
    }
}

struct CommunityReportView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let target: UUID
    let post: UUID?
    var comment: SocialComment? = nil
    var mediaComment: VideoComment? = nil
    var message: SocialMessage? = nil
    @State private var selected: String?
    @State private var id = UUID()
    @State private var sending = false
    @State private var sent = false
    @State private var failed = false
    private let reasons = ["Sexual content", "Harassment", "Discrimination", "Incorrect content", "Other"]
    var body: some View {
        PageShell(title: "Report") {
            VStack(alignment: .leading, spacing: 12) {
                if message != nil {
                    Text("Sending this report shares this message and its attachments with Liya for review. Other messages are not included.")
                        .font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(reasons, id: \.self) { reason in
                    Button { selected = reason; id = UUID(); failed = false } label: {
                        HStack { Text(reason); Spacer(); if selected == reason { Text("Selected").font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent) } }
                            .foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(sending || sent)
                }
                if failed { Text("Could not confirm your report. Please try again.").font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                if sent { Text("Report received.").font(LiyaType.text(.footnote)).foregroundStyle(liyaAccent) }
                PrimaryButton(title: sending ? "Sending…" : "Send report", disabled: selected == nil || sending || sent) {
                    guard let selected, !sending, !sent else { return }; sending = true
                    Task {
                        if let message { sent = await social.reportMessage(session, id: id, message: message, reason: selected) }
                        else if let comment { sent = await social.reportComment(session, id: id, comment: comment, reason: selected) }
                        else if let mediaComment {
                            sent = await social.reportVideoComment(session, id: id, mediaID: mediaComment.mediaID, commentID: mediaComment.id, presetKey: nil, body: mediaComment.body, reason: selected)
                        }
                        else { sent = await social.report(session, id: id, target: target, post: post, reason: selected) }
                        failed = !sent; sending = false
                    }
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
    @State private var loadedForAccount: UUID?
    @State private var text = ""
    @State private var sending = false
    @State private var loading = false
    @State private var failed = false
    @State private var loadID = UUID()
    @State private var attempt = UUID()
    @State private var loadedDraftKey: String?
    @State private var deleting: SocialComment?
    private var draftKey: String? {
        session.userID.map { "liya.social.commentDraft.\($0.uuidString).\(post.id.uuidString)" }
    }
    var body: some View {
        PageShell(title: "Comments") {
            VStack(alignment: .leading, spacing: 12) {
                if loading { Text("Loading comments…").foregroundStyle(.secondary) }
                if failed { Text("Couldn't load or save comments.").foregroundStyle(.red); Button("Try again") { Task { await load() } }.foregroundStyle(liyaAccent) }
                if !loading && !failed && comments.isEmpty { EmptyState(title: "No comments yet", detail: "Start the conversation.") }
                ForEach(loadedForAccount == session.userID ? comments : []) { comment in
                    VStack(alignment: .leading, spacing: 6) {
                        if let author = comment.author, author.id == comment.ownerID {
                            NavigationLink { CommunityPersonView(personID: comment.ownerID) } label: {
                                HStack(spacing: 10) {
                                    SocialAvatar(personID: comment.ownerID, commentAuthor: author)
                                        .frame(width: 36, height: 36).clipShape(Circle())
                                    Text(verbatim: author.displayName)
                                        .font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                                }.frame(minHeight: 44)
                            }.buttonStyle(.plain)
                        } else {
                            Text("Liya member").font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        Text(comment.body).foregroundStyle(liyaInk)
                        if comment.ownerID == session.userID, let status = social.moderationText(kind: "post_comment", id: comment.id) {
                            Text(status).font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if comment.ownerID == session.userID {
                            Button("Delete") { deleting = comment }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent)
                        } else {
                            NavigationLink("Report comment") { CommunityReportView(target: comment.ownerID, post: nil, comment: comment) }
                                .font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                if social.canCommentOnMedia(session) {
                    TextField("Write a comment", text: Binding(get: { text }, set: { text = $0; attempt = UUID() }), axis: .vertical).lineLimit(2...6).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).disabled(sending)
                    PrimaryButton(title: sending ? "Sending…" : "Send comment", disabled: sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000) {
                        guard let key = draftKey, key == loadedDraftKey else { return }
                        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let commentID = attempt
                        sending = true
                        persistDraft()
                        Task {
                            guard draftKey == key else { return }
                            let sent = await social.sendComment(session, id: commentID, post: post.id, body: body)
                            guard draftKey == key else { return }
                            if sent {
                                text = ""; attempt = UUID(); persistDraft()
                                await load()
                            } else { failed = true }
                            if draftKey == key { sending = false }
                        }
                    }
                } else { NavigationLink("Create a community profile to comment") { CommunityJoinView() }.foregroundStyle(liyaAccent) }
            }.padding(.top, 12)
        }
            .onLiyaChange(of: text) { _ in persistDraft() }
            .onLiyaChange(of: social.syncGeneration) { _ in Task { await load() } }
            .onDisappear { persistDraft() }
            .task(id: draftKey) { restoreDraft(); await load() }
            .sheet(item: $deleting) { comment in
                LocalConfirmation(title: "Delete this comment?", message: "The comment will be removed for everyone.", action: "Delete") {
                    deleting = nil; Task { if await social.deleteComment(session, id: comment.id) { await load() } else { failed = true } }
                } cancel: { deleting = nil }.presentationDetents([.medium])
            }
    }
    private func load() async {
        let currentLoad = UUID()
        let owner = session.userID
        loadID = currentLoad
        loading = true; failed = false; comments = []
        do {
            let result = try await social.comments(session, post: post.id)
            guard loadID == currentLoad, session.userID == owner, !Task.isCancelled else { return }
            loadedForAccount = owner
            comments = result
        } catch {
            guard loadID == currentLoad, session.userID == owner, !Task.isCancelled else { return }
            failed = true
        }
        if loadID == currentLoad { loading = false }
    }
    private func restoreDraft() {
        guard loadedDraftKey != draftKey else { return }
        loadedDraftKey = draftKey
        let saved = draftKey.flatMap { UserDefaults.standard.dictionary(forKey: $0) as? [String: String] }
        text = saved?["text"] ?? ""
        attempt = UUID(uuidString: saved?["attempt"] ?? "") ?? UUID()
        deleting = nil
        sending = false
    }
    private func persistDraft() {
        guard let key = loadedDraftKey, key == draftKey else { return }
        UserDefaults.standard.set(["text": text, "attempt": attempt.uuidString], forKey: key)
    }
}

struct SocialMediaItem: Identifiable {
    let path: String
    let kind: String
    let post: SocialPost?
    var id: String { path }
}

struct SocialMediaStrip: View {
    let post: SocialPost
    private var paths: [String] { post.mediaPaths }
    private var kinds: [String] { post.mediaKinds }
    @State private var preview: SocialMediaItem?
    var body: some View {
        if paths.count == 1, let path = paths.first {
            let item = SocialMediaItem(path: path, kind: kinds.first ?? "photo", post: post)
            Button { preview = item } label: {
                GeometryReader { geometry in
                    SocialMediaThumbnail(item: item).frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                .aspectRatio(4 / 5, contentMode: .fit).frame(maxWidth: 430)
                .clipShape(RoundedRectangle(cornerRadius: 17)).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).accessibilityLabel(item.kind == "video" ? "Open video" : "Open photo")
                .sheet(item: $preview) { item in SocialMediaPreview(item: item) }
        } else if !paths.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                        let item = SocialMediaItem(path: path, kind: kinds.indices.contains(index) ? kinds[index] : "photo", post: post)
                        Button { preview = item } label: { SocialMediaThumbnail(item: item).frame(width: 150, height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
                            .buttonStyle(.plain).accessibilityLabel(item.kind == "video" ? "Open video" : "Open photo")
                    }
                }
            }.sheet(item: $preview) { item in SocialMediaPreview(item: item) }
        }
    }
}

struct SocialMediaThumbnail: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let item: SocialMediaItem
    @State private var url: URL?
    @State private var videoCover: UIImage?
    @State private var failed = false
    init(item: SocialMediaItem) { self.item = item }
    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
            if item.kind == "video" {
                if let videoCover { Image(uiImage: videoCover).resizable().scaledToFill() }
                Image("play").resizable().scaledToFit().frame(width: 44, height: 44)
            }
            else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else if phase.error != nil { Text("Photo unavailable").font(LiyaType.text(.caption)) }
                    else { Color.clear }
                }
            } else if failed { Text("Photo unavailable").font(LiyaType.text(.caption)) }
        }.task(id: item.path) {
            videoCover = nil; url = nil; failed = false
            do {
                let value = try await social.mediaURL(session, path: item.path)
                guard !Task.isCancelled else { return }
                if item.kind == "video" {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: value))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 400, height: 400)
                    if let frame = try? await generator.image(at: .zero), !Task.isCancelled { videoCover = UIImage(cgImage: frame.image) }
                } else { url = value }
            }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}

struct SocialMediaPreview: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let item: SocialMediaItem
    @State private var url: URL?
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var playing = false
    init(item: SocialMediaItem) { self.item = item }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                PlayerView(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container).accessibilityHidden(true)
            }
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
                    if let post = item.post {
                        CommunityPostEngagement(post: post) {
                            player?.pause()
                            playing = false
                        }
                    }
                }.buttonStyle(.plain).padding(20).frame(width: size.width, height: size.height)
            }
        }.task {
            do {
                let value = try await social.mediaURL(session, path: item.path)
                guard !Task.isCancelled else { return }
                if item.kind == "video" { player = AVPlayer(url: value) } else { url = value }
            } catch { if !Task.isCancelled { failed = true } }
        }.onLiyaChange(of: phase) { if $0 != .active { player?.pause(); playing = false } }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
                if let endedItem = notification.object as? AVPlayerItem, endedItem === player?.currentItem {
                    player?.seek(to: .zero)
                    if playing && phase == .active { player?.play() }
                }
            }
            .onDisappear { player?.pause(); player = nil }
    }
}

private struct MessageDraft: Codable {
    var text: String
    var attachments: [DraftAttachment]
    var attempt: String
    var fingerprint: String
}

private struct InboxEmptyState: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image("empty-art").resizable().scaledToFit().frame(width: 104, height: 96).accessibilityHidden(true)
            Text(LocalizedStringKey(title)).font(LiyaType.text(.headline, weight: .semibold)).foregroundStyle(liyaInk)
            if let detail {
                Text(LocalizedStringKey(detail)).font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.58))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 54)
    }
}

private func activityDate(_ value: String) -> String? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fractional = formatter.date(from: value)
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = fractional ?? formatter.date(from: value) else { return nil }
    return Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .omitted)
}

struct CommunityInboxThreads: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let hasDrafts: Bool

    private var threads: [SocialMessage] {
        guard let owner = session.userID else { return [] }
        var seen = Set<UUID>()
        return social.messages.reversed().filter { message in
            guard message.senderID == owner || message.recipientID == owner else { return false }
            let peer = message.senderID == owner ? message.recipientID : message.senderID
            return !social.blocked.contains(peer) && seen.insert(peer).inserted
        }
    }

    var body: some View {
        let previews = threads
        if let owner = session.userID {
            if social.messageLoadError != nil {
                ConnectionRetryRow(message: "Messages are taking a moment") {
                    await social.refreshMessages(session)
                    if !social.realtimeConnected { social.watchMessages(session) }
                }
            }
            if previews.isEmpty && !hasDrafts && social.messageLoadError == nil {
                if social.messagesReady {
                    InboxEmptyState(title: "No messages yet")
                } else {
                    LiyaLoadingIndicator(size: 26).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            ForEach(previews) { message in
                let peer = message.senderID == owner ? message.recipientID : message.senderID
                NavigationLink { CommunityConversationView(personID: peer) } label: {
                    HStack(spacing: 12) {
                        SocialAvatar(personID: peer).frame(width: 46, height: 46).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: social.person(peer)?.displayName ?? String(localized: "Liya member"))
                                .font(LiyaType.sectionHeading).foregroundStyle(liyaInk)
                            if message.body.isEmpty {
                                Text("Photos and videos").font(LiyaType.detail).foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: message.body).lineLimit(2).font(LiyaType.detail).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if let date = activityDate(message.createdAt) {
                            Text(verbatim: date).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                        }
                    }.padding(14).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
        } else if !hasDrafts {
            InboxEmptyState(title: "No messages yet")
        }
    }
}

struct CommunityConversationView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.profileDetailVisible) private var detailVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editing: Bool

    private let recipient: ProfileContactRecipient
    private let collectionName: String?
    @State private var draft = MessageDraft(text: "", attachments: [], attempt: "", fingerprint: "")
    @State private var ownerID: UUID?
    @State private var sending = false
    @State private var showMutualNotice = false
    @State private var showingOptions = false
    @State private var visible = false
    @State private var failure: String?
    @State private var pickingMedia = false
    @State private var readingMedia = false
    @State private var deleting: SocialMessage?
    @State private var preview: SocialMediaItem?
    @State private var atBottom = true
    @State private var positioned = false
    @ScaledMetric(relativeTo: .headline) private var headerHeight: CGFloat = 54

    init(personID: UUID) {
        recipient = .member(personID)
        collectionName = nil
    }

    init(collectionIndex: Int, displayName: String) {
        recipient = .collection(collectionIndex)
        collectionName = displayName
    }

    private var name: String {
        switch recipient {
        case .collection: return collectionName ?? String(localized: "Liya collection", locale: locale)
        case .member(let id): return social.person(id)?.displayName ?? String(localized: "Liya member", locale: locale)
        }
    }

    private var history: [SocialMessage] {
        guard case .member(let peer) = recipient, let owner = session.userID, !social.blocked.contains(peer) else { return [] }
        return social.messages.filter {
            ($0.senderID == peer && $0.recipientID == owner) || ($0.senderID == owner && $0.recipientID == peer)
        }
    }

    private var blocked: Bool {
        switch recipient {
        case .member(let id): return social.blocked.contains(id)
        case .collection(let index): return store.hiddenCollectionProfiles.contains(index)
        }
    }

    private var canSend: Bool {
        ownerID != nil && !sending && !readingMedia && !blocked && draft.text.unicodeScalars.count <= 4000 &&
            (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.attachments.isEmpty)
    }

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                header
                transcript
            }
        }
        .navigationBarHidden(true)
        .onAppear { visible = true; detailVisible.wrappedValue = true; restore() }
        .onDisappear { visible = false; detailVisible.wrappedValue = false }
        .onLiyaChange(of: draft.text) { _ in failure = nil; persist() }
        .onLiyaChange(of: draft.attachments) { _ in failure = nil; persist() }
        .onLiyaChange(of: session.userID) { value in
            if ownerID != nil && value != ownerID { dismiss() } else { restore() }
        }
        .sheet(isPresented: $showingOptions, onDismiss: { if blocked { dismiss() } }) {
            switch recipient {
            case .member(let peer): CommunityProfileOptions(personID: peer)
            case .collection(let index):
                if session.photos.indices.contains(index) {
                    CollectionSafetySheet(target: CollectionSafetyTarget(mediaID: session.photos[index].id, name: name, kind: .profile, ownerID: ownerID))
                }
            }
        }
        .sheet(isPresented: $showMutualNotice) { MutualFollowNotice(action: .message) }
        .sheet(isPresented: $pickingMedia) {
            NavigationStack {
                PageShell(title: "Add media") {
                    DraftMediaPicker(attachments: $draft.attachments, loading: $readingMedia, compactButtons: true)
                        .padding(.vertical, 12)
                }
            }.presentationDetents([.medium, .large])
        }
        .sheet(item: $deleting) { message in
            LocalConfirmation(title: "Delete this message?", message: "This removes the message for both of you.", action: "Delete") {
                deleting = nil
                Task { if !(await social.deleteMessage(session, message: message)) { failure = "Couldn't delete the message. Please try again." } }
            } cancel: { deleting = nil }
            .presentationDetents([.medium])
        }
        .sheet(item: $preview) { item in SocialMediaPreview(item: item) }
    }

    private var header: some View {
        DuoControlRegion { _ in
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image("back").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Back")
                switch recipient {
                case .member(let id):
                    SocialAvatar(personID: id).frame(width: 36, height: 36).clipShape(Circle())
                case .collection(let index):
                    CollectionPortrait(index: index, size: 36)
                }
                Text(verbatim: name).font(LiyaType.sectionHeading).foregroundStyle(liyaInk)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button { editing = false; showingOptions = true } label: {
                    Image("more").resizable().scaledToFit().frame(width: 23, height: 23).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("More options")
            }.padding(.horizontal, 10).modifier(AdaptiveContainerMargins())
        }.frame(height: max(headerHeight, 54))
    }

    private var transcript: some View {
        let messages = history
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if case .member = recipient, social.messageLoadError != nil {
                        ConnectionRetryRow(message: "Couldn't load this conversation. Please try again.") {
                            await social.refreshMessages(session)
                            if !social.realtimeConnected { social.watchMessages(session) }
                        }
                    }
                    if messages.isEmpty {
                        switch recipient {
                        case .member where !social.messagesReady && social.messageLoadError == nil:
                            LiyaLoadingIndicator(size: 26).padding(.vertical, 50)
                        case .member where social.messageLoadError != nil:
                            EmptyView()
                        default:
                            InboxEmptyState(title: "No messages yet")
                        }
                    }
                    ForEach(messages) { message in bubble(message).id(message.id) }
                    Color.clear.frame(height: 1).accessibilityHidden(true)
                        .onAppear { atBottom = true }.onDisappear { atBottom = false }
                }
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, 12).modifier(AdaptiveContainerMargins())
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .task(id: session.userID) {
                restore()
                if case .member = recipient, session.userID != nil {
                    await social.refreshMessages(session)
                    if !social.realtimeConnected { social.watchMessages(session) }
                }
                if let last = history.last { proxy.scrollTo(last.id, anchor: .bottom); positioned = true }
            }
            .onLiyaChange(of: messages.last?.id) { id in
                guard let id, atBottom || !positioned || sending else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .bottom) }
                positioned = true
            }
        }
    }

    private func bubble(_ message: SocialMessage) -> some View {
        let mine = message.senderID == session.userID
        return VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 8) {
                if !message.body.isEmpty {
                    Text(verbatim: message.body).textSelection(.enabled).font(LiyaType.reading)
                        .foregroundStyle(mine ? .white : liyaInk).fixedSize(horizontal: false, vertical: true)
                }
                if !message.mediaPaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(message.mediaPaths.enumerated()), id: \.element) { index, path in
                                let kind = message.mediaKinds.indices.contains(index) ? message.mediaKinds[index] : "photo"
                                let item = SocialMediaItem(path: path, kind: kind, post: nil)
                                Button { preview = item } label: {
                                    SocialMediaThumbnail(item: item).frame(width: 120, height: 136)
                                        .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel(kind == "video" ? "Open video" : "Open photo")
                            }
                        }
                    }.frame(maxWidth: 264)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(mine ? Color(red: 0.27, green: 0.19, blue: 0.50) : Color.white.opacity(0.96),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack(spacing: 10) {
                if let date = activityDate(message.createdAt) {
                    Text(verbatim: date).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                }
                if mine {
                    Button("Delete") { deleting = message }
                } else {
                    NavigationLink("Report") { CommunityReportView(target: message.senderID, post: nil, message: message) }
                }
            }.buttonStyle(.plain).font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
        }
        .frame(maxWidth: 440, alignment: mine ? .trailing : .leading)
        .padding(mine ? .leading : .trailing, 24)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let failure {
                Text(LocalizedStringKey(failure)).font(LiyaType.text(.footnote)).foregroundStyle(liyaInk).padding(.horizontal, 10)
            } else if draft.text.unicodeScalars.count > 4000 {
                Text("Keep your message to 4,000 characters.").font(LiyaType.text(.footnote)).foregroundStyle(liyaInk)
            }
            if !draft.attachments.isEmpty {
                Button { pickingMedia = true } label: {
                    Text("\(draft.attachments.count) attachments selected").font(LiyaType.text(.footnote, weight: .bold))
                        .padding(.horizontal, 12).frame(minHeight: 44)
                }.disabled(sending).foregroundStyle(liyaAccent)
            }
            HStack(alignment: .bottom, spacing: 6) {
                if case .member = recipient {
                    Button { editing = false; pickingMedia = true } label: {
                        Image("avatar-camera").resizable().scaledToFit().frame(width: 26, height: 26).frame(width: 44, height: 44)
                    }.disabled(sending).accessibilityLabel("Add photos or videos")
                }
                TextField("Write a message…", text: $draft.text, axis: .vertical)
                    .focused($editing).lineLimit(1...5).padding(.leading, 7).padding(.vertical, 12)
                    .font(LiyaType.reading).foregroundStyle(liyaInk).disabled(sending)
                Button(action: send) {
                    Text(sending ? "Sending…" : "Send")
                        .font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Color(red: 0.27, green: 0.19, blue: 0.50).opacity(canSend || sending ? 1 : 0.57), in: Capsule())
                }.disabled(!canSend)
            }
        }
        .buttonStyle(.plain)
        .padding(7).modifier(ContactBarSurface())
        .frame(maxWidth: 620).frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.vertical, 7).modifier(AdaptiveContainerMargins())
    }

    private func send() {
        guard canSend, let owner = ownerID, session.userID == owner else { return }
        failure = nil
        guard case .member(let peer) = recipient else {
            persist()
            editing = false
            showMutualNotice = true
            return
        }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = SocialAttempt.fingerprint(owner: owner, target: peer, text: text, files: draft.attachments)
        if draft.fingerprint != stamp || UUID(uuidString: draft.attempt) == nil {
            draft.attempt = UUID().uuidString
            draft.fingerprint = stamp
        }
        guard let id = UUID(uuidString: draft.attempt) else { return }
        let files = draft.attachments
        persist()
        sending = true
        Task {
            defer { sending = false }
            do {
                try await social.sendMessage(session, id: id, target: peer, body: text, attachments: files)
                guard session.userID == owner, draft.attempt == id.uuidString else { return }
                let key = draftKey(owner, peer)
                guard let data = UserDefaults.standard.data(forKey: key),
                      let stored = try? JSONDecoder().decode(MessageDraft.self, from: data),
                      stored.attempt == id.uuidString, stored.fingerprint == stamp, stored.text == draft.text,
                      stored.attachments == files else { return }
                UserDefaults.standard.removeObject(forKey: key)
                if visible { draft = MessageDraft(text: "", attachments: [], attempt: "", fingerprint: "") }
            } catch MessageDeliveryError.mutualFollowRequired {
                guard session.userID == owner else { return }
                editing = false; showMutualNotice = true
            } catch {
                guard session.userID == owner, !Task.isCancelled else { return }
                failure = (error as? VideoCompression.Failure)?.errorDescription ?? "Couldn't send this message. Your draft is saved."
            }
        }
    }

    private func draftKey(_ owner: UUID, _ peer: UUID) -> String {
        "liya.social.messageDraft.\(owner.uuidString).\(peer.uuidString)"
    }

    private func restore() {
        guard ownerID == nil, let owner = session.userID else { return }
        switch recipient {
        case .member(let peer):
            if let saved = UserDefaults.standard.data(forKey: draftKey(owner, peer)),
               let previous = try? JSONDecoder().decode(MessageDraft.self, from: saved) { draft = previous }
        case .collection(let index):
            draft.text = store.messageDrafts[String(index)] ?? ""
        }
        ownerID = owner
    }

    private func persist() {
        guard let owner = ownerID, owner == session.userID else { return }
        switch recipient {
        case .member(let peer):
            let key = draftKey(owner, peer)
            if draft.text.isEmpty && draft.attachments.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else if let bytes = try? JSONEncoder().encode(draft) {
                UserDefaults.standard.set(bytes, forKey: key)
            }
        case .collection(let index):
            store.saveMessageDraft(draft.text, index: index)
        }
    }
}

private struct ConnectionRetryRow: View {
    var message: LocalizedStringKey = "Couldn't refresh your connections."
    let retry: () async -> Void
    @State private var retrying = false

    var body: some View {
        Button {
            guard !retrying else { return }
            retrying = true
            Task { await retry(); retrying = false }
        } label: {
            HStack(spacing: 12) {
                Text(message).font(LiyaType.text(.footnote)).foregroundStyle(liyaInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if retrying {
                    LiyaLoadingIndicator(size: 22)
                } else {
                    Text("Try again").font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 48)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain).disabled(retrying)
    }
}

struct CommunityRelationList: View {
    private struct ReportTarget: Identifiable { let id: UUID }

    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    let title: String
    let relation: String
    @State private var mutationFailed = false
    @State private var reportTarget: ReportTarget?
    private var isFollowing: Bool { relation == "following" }
    private var onlyCreators: Bool { relation == "creators" }
    private var showsCreators: Bool { isFollowing || onlyCreators }
    private var memberIDs: [UUID] {
        guard !onlyCreators, session.userID != nil, social.connectionsOwner == session.userID else { return [] }
        return isFollowing ? social.follows : social.followers
    }
    private var creators: [CuratedFollowedProfile] { showsCreators ? session.curatedFollowing(in: store) : [] }
    private var ready: Bool {
        guard session.userID != nil else { return false }
        let membersReady = onlyCreators || (social.connectionsOwner == session.userID && social.connectionsReady)
        return membersReady && (!showsCreators || session.curatedFollowsReady)
    }
    private var readFailed: Bool {
        let memberError = !onlyCreators && social.connectionsOwner == session.userID && social.connectionsError != nil
        return memberError || (showsCreators && (session.catalogError != nil || session.curatedFollowsError != nil))
    }
    private var emptyTitle: LocalizedStringKey {
        if onlyCreators { return "You haven’t followed any creators yet." }
        return isFollowing ? "You haven’t followed anyone yet." : "No followers yet"
    }

    var body: some View {
        PageShell(title: title) {
            if relation == "blocked" {
                blockedList
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if mutationFailed {
                        Text("Couldn't update your follow. Please try again.").font(LiyaType.text(.footnote)).foregroundStyle(liyaInk)
                    } else if readFailed {
                        ConnectionRetryRow { await refresh() }
                    } else if !ready {
                        LiyaLoadingIndicator().frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    if ready && !readFailed && memberIDs.isEmpty && creators.isEmpty {
                        VStack(spacing: 10) {
                            Image("profile-home-people").resizable().scaledToFit().frame(width: 76, height: 76)
                                .accessibilityHidden(true)
                            Text(emptyTitle).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                            if showsCreators {
                                Text("Tap Follow on a profile to add it here.").font(LiyaType.detail).foregroundStyle(.secondary)
                            }
                        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 36)
                    }
                    ForEach(memberIDs, id: \.self) { id in
                        relationRow {
                            if let person = social.person(id) {
                                NavigationLink { CommunityPersonView(personID: id) } label: {
                                    memberLabel(name: person.displayName, bio: person.signature) { SocialAvatar(personID: id) }
                                }.buttonStyle(.plain)
                            } else {
                                memberLabel(name: String(localized: "Liya member", locale: locale), bio: "") { Image("app-mark").resizable().scaledToFit() }
                            }
                        } accessory: {
                            if isFollowing {
                                unfollowButton(pending: social.changingFollows.contains(id)) {
                                    await social.setRelation(session, target: id, table: "liya_follows", enabled: false)
                                }
                            }
                        }
                    }
                    ForEach(creators, id: \.id) { creator in
                        relationRow {
                            NavigationLink { CollectionAuthorView(index: creator.index, displayName: creator.displayName, mediaID: creator.id) } label: {
                                memberLabel(name: creator.displayName, bio: "") { CollectionPortrait(index: creator.index, size: 46) }
                            }.buttonStyle(.plain)
                        } accessory: {
                            unfollowButton(pending: session.curatedFollowPending.contains(creator.id)) {
                                await session.setCuratedFollow(false, id: creator.id, store: store)
                            }
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .task(id: session.userID) { await refresh() }
        .refreshable { await refresh() }
        .sheet(item: $reportTarget) { target in
            CommunityProfileOptions(personID: target.id, startsAtReport: true)
        }
    }

    private var blockedList: some View {
        VStack(spacing: 12) {
            if let error = social.error {
                Text(error).foregroundStyle(.red)
                Button("Refresh") { Task { await social.refresh(session) } }.foregroundStyle(liyaAccent)
            }
            if social.blocked.isEmpty && !social.loading && social.error == nil {
                EmptyState(title: "Nothing here yet", detail: "Members will appear here when available.")
            }
            ForEach(social.blocked, id: \.self) { id in
                HStack {
                    if let person = social.person(id) {
                        NavigationLink(person.displayName) { CommunityPersonView(personID: id) }.foregroundStyle(liyaInk)
                    } else { Text("Blocked member · \(id.uuidString.prefix(8))").foregroundStyle(liyaInk) }
                    Spacer()
                    Button("Report") { reportTarget = ReportTarget(id: id) }
                        .foregroundStyle(liyaAccent).frame(minHeight: 44)
                    Button("Unblock") { Task { await social.setRelation(session, target: id, table: "liya_blocks", enabled: false) } }.foregroundStyle(liyaAccent)
                }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            }
        }.padding(.top, 12)
    }

    private func memberLabel<Avatar: View>(name: String, bio: String, @ViewBuilder avatar: () -> Avatar) -> some View {
        HStack(spacing: 12) {
            avatar().frame(width: 46, height: 46).clipShape(Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name).font(LiyaType.text(.headline)).foregroundStyle(liyaInk).lineLimit(2)
                if !bio.isEmpty { Text(verbatim: bio).font(LiyaType.text(.caption)).foregroundStyle(.secondary).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(Rectangle())
    }

    private func relationRow<Label: View, Accessory: View>(@ViewBuilder label: () -> Label,
                                                            @ViewBuilder accessory: () -> Accessory) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        return layout { label(); accessory() }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
    }

    private func unfollowButton(pending: Bool, action: @escaping () async -> Bool) -> some View {
        Button {
            mutationFailed = false
            let owner = session.userID
            Task {
                let saved = await action()
                if session.userID == owner { mutationFailed = !saved }
            }
        } label: {
            if pending {
                LiyaLoadingIndicator(size: 21).frame(minWidth: 64, minHeight: 44)
            } else {
                Text("Unfollow").font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(liyaInk)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(liyaAccent.opacity(0.07), in: Capsule())
            }
        }.buttonStyle(.plain).disabled(pending)
    }

    private func refresh() async {
        mutationFailed = false
        guard relation != "blocked" else { await social.refresh(session); return }
        if onlyCreators { await refreshCreators(); return }
        async let members: Void = social.refreshConnections(session)
        if isFollowing { await refreshCreators() }
        await members
    }

    private func refreshCreators() async {
        if session.catalogError != nil { await session.refreshCatalog() }
        await session.refreshCuratedFollows(store: store)
    }
}

struct CommunityActivityView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let hasLocalActivity: Bool

    init(hasLocalActivity: Bool = false) { self.hasLocalActivity = hasLocalActivity }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if social.notificationsLoading { LiyaLoadingIndicator(size: 28).frame(maxWidth: .infinity).padding(.vertical, 32) }
            if let error = social.notificationsError {
                Text(error).font(LiyaType.text(.footnote)).foregroundStyle(.red)
                Button("Try again") { Task { await social.refreshNotifications(session) } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
            }
            if social.notifications.isEmpty && !social.notificationsLoading && social.notificationsError == nil && !hasLocalActivity {
                InboxEmptyState(title: "No activity yet")
            }
            ForEach(social.notifications) { activity in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        NavigationLink { CommunityPersonView(personID: activity.actorID) } label: {
                            SocialAvatar(personID: activity.actorID).frame(width: 44, height: 44).clipShape(Circle())
                        }.buttonStyle(.plain).accessibilityLabel("View member profile")
                        VStack(alignment: .leading, spacing: 3) {
                            NavigationLink { CommunityPersonView(personID: activity.actorID) } label: {
                                Text(social.person(activity.actorID)?.displayName ?? "Liya member").font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(liyaInk)
                            }.buttonStyle(.plain)
                            if let date = activityDate(activity.createdAt) { Text(date).font(LiyaType.text(.caption2)).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if !activity.isRead { Button("Mark read") { Task { await social.markRead(session, id: activity.id) } }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent).frame(minHeight: 44) }
                    }
                    Text(activity.kind == "follow" ? "Started following you" : activity.kind == "like" ? "Liked your post" : activity.kind == "comment" ? "Commented on your post" : "Interacted with your post")
                        .font(LiyaType.detail).foregroundStyle(liyaInk)
                    if let postID = activity.postID, let post = social.posts.first(where: { $0.id == postID }) {
                        NavigationLink { CommunityCommentsView(post: post) } label: {
                            HStack(spacing: 10) {
                                Text(post.body.isEmpty ? "View post" : post.body).font(LiyaType.text(.caption)).lineLimit(2).foregroundStyle(liyaInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let path = post.mediaPaths.first {
                                    SocialMediaThumbnail(item: SocialMediaItem(path: path, kind: post.mediaKinds.first ?? "photo", post: post))
                                        .frame(width: 48, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }.padding(10).frame(maxWidth: .infinity).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityLabel("View post interaction")
                    }
                }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            }
        }.task { await social.refreshNotifications(session) }
    }
}
