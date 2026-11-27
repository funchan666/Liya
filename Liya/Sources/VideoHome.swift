import SwiftUI
import AVFoundation
import UIKit

@MainActor
final class VideoPreview: ObservableObject {
    let player = AVPlayer()
    @Published var index = 0
    @Published var playing = false
    @Published var unavailable = false
    @Published var loading = false
    @Published private(set) var requestedIndex = 0
    private var wantsPlayback = true
    private var isActive = false
    private var loadTask: Task<Void, Never>?

    deinit { loadTask?.cancel() }

    func select(_ newIndex: Int, active: Bool, session: LiyaSession) {
        guard session.videos.indices.contains(newIndex) else { return }
        loadTask?.cancel()
        requestedIndex = newIndex
        isActive = active
        player.pause()
        playing = false
        loading = true
        unavailable = false
        wantsPlayback = true
        loadTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            do {
                let url = try await session.mediaURL(kind: "video", index: newIndex)
                guard !Task.isCancelled else { return }
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                guard !Task.isCancelled else { return }
                guard playable else {
                    self.loading = false
                    self.unavailable = true
                    return
                }
                self.player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                self.index = newIndex
                self.loading = false
                self.resumeIfWanted(active: self.isActive)
            } catch {
                guard !Task.isCancelled else { return }
                self.loading = false
                self.unavailable = true
            }
        }
    }

    func clear() {
        loadTask?.cancel(); player.replaceCurrentItem(with: nil)
        loading = false; playing = false; unavailable = false
    }

    func toggle() {
        guard isActive, !unavailable, !loading, player.currentItem != nil else { return }
        if playing {
            wantsPlayback = false
            pause()
        } else {
            wantsPlayback = true
            player.play()
            playing = true
        }
    }

    func resumeIfWanted(active: Bool) {
        isActive = active
        if active && wantsPlayback && !unavailable && !loading && player.currentItem != nil { player.play(); playing = true } else { pause() }
    }
    func pause() { player.pause(); playing = false }
    func finished() {
        player.seek(to: .zero)
        resumeIfWanted(active: isActive)
    }
}

final class PlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.clipsToBounds = true
        return view
    }
    func updateUIView(_ view: PlayerSurface, context: Context) { view.playerLayer.player = player }
}

private enum VideoPanel: Hashable, Identifiable {
    case comments(String)
    case report(mediaID: String, ownerID: UUID)

    var id: Self { self }
}

struct CollectionVideoAuthor: Decodable {
    let videoID: String
    let name: String
    let photoID: String
    let caption: String
    enum CodingKeys: String, CodingKey {
        case videoID = "video_id", name = "display_name", photoID = "photo_id", caption
    }
}

private struct VideoAuthorPortrait: View {
    @EnvironmentObject private var session: LiyaSession
    let photoID: String?

    var body: some View {
        Group {
            if let photoID, let index = session.photos.firstIndex(where: { $0.id == photoID }) {
                CollectionPortrait(index: index, size: 44)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct VideoScrollBounce: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.scrollBounceBehavior(.basedOnSize, axes: .vertical)
        } else {
            content
        }
    }
}

struct VideoHome: View {
    @Environment(\.liyaWords) private var words
    let active: Bool
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @State private var panel: VideoPanel?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var preview = VideoPreview()
    @GestureState private var swipeTranslation: CGFloat = 0

    private var canTapVideo: Bool {
        active && scenePhase == .active && panel == nil && !session.catalogLoading &&
            session.catalogError == nil && !preview.loading && !preview.unavailable &&
            session.videos.indices.contains(preview.index) && preview.player.currentItem != nil
    }

    private var playbackTapSurface: some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture(perform: preview.toggle)
    }

    var body: some View {
        ZStack {
            if session.catalogLoading || preview.loading {
                DuoControlRegion { _ in
                    LiyaLoadingIndicator(size: 68)
                        .accessibilityLabel(words("Loading video"))
                }
                .allowsHitTesting(false)
            }
            DuoControlRegion { available in
              ScrollView {
               VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HostedArtwork("video-title").scaledToFit().frame(width: 145, height: 42)
                        .allowsHitTesting(false).accessibilityLabel(words("Liya videos"))
                    Spacer(minLength: 4)
                    VideoJournalShortcut()
                }
                Spacer(minLength: 16)
                if session.catalogLoading || preview.loading { EmptyView() }
                else if let error = session.catalogError {
                    Text(verbatim: words(error)).font(LiyaType.text(.headline))
                    Button(words("Try again")) { Task { await session.refreshCatalog() } }.frame(minHeight: 44)
                } else if session.videos.isEmpty { Text(verbatim: words("No videos yet.")).font(LiyaType.text(.headline)) }
                else if preview.unavailable {
                    Text(verbatim: words("This video is unavailable.")).font(LiyaType.text(.headline))
                    Button(words("Try again")) { preview.select(preview.requestedIndex, active: active && scenePhase == .active && panel == nil, session: session) }.frame(minHeight: 44)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        if session.videos.indices.contains(preview.index) {
                            let creator = session.curatedVideoCreators[session.videos[preview.index].id]
                            let photoIndex = creator.flatMap { person in session.photos.firstIndex(where: { $0.id == person.photoID }) }
                            let authorName = creator.map { session.curatedDisplayName(for: $0.photoID) } ?? "Liya collection"
                            HStack(alignment: .center, spacing: 8) {
                                NavigationLink {
                                    if let creator, let photoIndex {
                                        CollectionAuthorView(index: photoIndex, displayName: authorName, introduction: creator.caption, mediaID: creator.photoID)
                                    } else {
                                        PageShell(title: "Profile") {
                                            EmptyState(title: "Profile unavailable", detail: "Please try again when the content has loaded.")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        VideoAuthorPortrait(photoID: creator?.photoID)
                                        Text(authorName)
                                            .font(LiyaType.text(.subheadline, weight: .semibold)).lineLimit(2)
                                    }
                                    .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(words.inserting(authorName, into: "View %@"))
                                if let creator, let photoIndex {
                                    CuratedFollowButton(id: creator.photoID) { following, title in
                                        Text(verbatim: words(title))
                                            .font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(.white)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .padding(.horizontal, 12).frame(minHeight: 36)
                                            .background {
                                                if following {
                                                    Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                                                } else {
                                                    Capsule().fill(liyaGradient)
                                                }
                                            }
                                            .frame(minHeight: 44)
                                    }
                                    .disabled(store.hiddenCollectionProfiles.contains(photoIndex))
                                    .opacity(store.hiddenCollectionProfiles.contains(photoIndex) ? 0.5 : 1)
                                }
                            }
                            if let caption = creator?.caption {
                                Text(caption).font(LiyaType.detail).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                                    .allowsHitTesting(false)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
                    Spacer(minLength: 8)
                    if session.videos.indices.contains(preview.index) {
                        engagementRail(for: session.videos[preview.index])
                    }
                }
                if let error = session.likesError {
                    Text(verbatim: words(error)).font(LiyaType.text(.footnote))
                    Button(words("Retry likes")) { Task { await session.refreshLikes() } }.frame(minHeight: 44)
                }
               }
               .foregroundStyle(.white)
               .padding(20)
               .frame(maxWidth: 620)
               .frame(maxWidth: .infinity)
               .modifier(AdaptiveContainerMargins())
               .padding(.bottom, LiyaTabBarLayout.contentClearance)
               .frame(maxWidth: .infinity, minHeight: available.height)
               .background {
                   if canTapVideo {
                       playbackTapSurface.accessibilityRepresentation {
                           Button(action: preview.toggle) {
                               Text(verbatim: words(preview.playing ? "Pause video" : "Play video"))
                           }
                       }
                   }
               }
              }.modifier(VideoScrollBounce())
            }
        }
        .background {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.11)
                PlayerView(player: preview.player)
                    .offset(y: reduceMotion ? 0 : max(-28, min(28, swipeTranslation * 0.14)))
                    .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.85), value: swipeTranslation)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if canTapVideo { playbackTapSurface.accessibilityHidden(true) }
            }
            .ignoresSafeArea(.container)
        }
        .overlay {
            if canTapVideo && !preview.playing {
                DuoControlRegion { _ in
                    HostedArtwork(decorative: "play").scaledToFit()
                        .frame(width: 56, height: 56)
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .updating($swipeTranslation) { value, state, _ in
                    if abs(value.translation.height) > abs(value.translation.width) * 1.3 {
                        state = value.translation.height
                    }
                }
                .onEnded { value in
                    guard abs(value.translation.height) > 60,
                          abs(value.translation.height) > abs(value.translation.width) * 1.3 else { return }
                    let current = preview.loading ? preview.requestedIndex : preview.index
                    let target = current + (value.translation.height < 0 ? 1 : -1)
                    preview.select(target, active: active && scenePhase == .active && panel == nil, session: session)
                }
        )
        .onAppear {
            if preview.player.currentItem == nil { preview.select(preview.index, active: active && scenePhase == .active && panel == nil, session: session) }
            else { preview.resumeIfWanted(active: active && scenePhase == .active && panel == nil) }
        }
        .onLiyaChange(of: store.videoRequest) { request in
            if let request {
                preview.select(request.index, active: active && scenePhase == .active && panel == nil, session: session)
                if request.openNotes, session.videos.indices.contains(request.index) {
                    panel = .comments(session.videos[request.index].id)
                }
            }
        }
        .onLiyaChange(of: active) { selected in
            preview.resumeIfWanted(active: selected && scenePhase == .active && panel == nil)
        }
        .onLiyaChange(of: scenePhase) { phase in preview.resumeIfWanted(active: active && phase == .active && panel == nil) }
        .onLiyaChange(of: panel) { current in preview.resumeIfWanted(active: active && scenePhase == .active && current == nil) }
        .onLiyaChange(of: session.catalogGeneration) { _ in
            if session.videos.isEmpty { preview.clear() }
            else { preview.select(min(preview.index, session.videos.count - 1), active: active && scenePhase == .active && panel == nil, session: session) }
        }
        .sheet(item: $panel) { current in
            switch current {
            case .comments(let mediaID):
                NavigationStack { MediaCommentsView(mediaID: mediaID) }
                    .environment(\.liyaTabBarClearance, 0)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case let .report(mediaID, ownerID):
                VideoReportView(mediaID: mediaID, ownerID: ownerID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if let item = notification.object as? AVPlayerItem, item === preview.player.currentItem { preview.finished() }
        }
        .onDisappear { preview.resumeIfWanted(active: false) }
        .navigationBarHidden(true)
    }

    private func engagementRail(for video: CatalogMediaAsset) -> some View {
        let counts = session.mediaEngagement[video.id]
        let liked = session.likedMediaIDs.contains(video.id)
        let failed = session.mediaEngagementFailures.contains(video.id)
        return VStack(spacing: 12) {
            Button { Task { await session.toggleMediaLike(id: video.id) } } label: {
                metric(liked ? "Liked" : "Like", icon: liked ? "video-like-on" : "video-like-off",
                       count: counts?.likeCount, failed: failed)
            }
            .disabled(!session.likesReady || session.likesLoading)
            .accessibilityLabel(words(liked ? "Remove like" : "Like"))
            .accessibilityValue(countValue(counts?.likeCount))
            .accessibilityAddTraits(liked ? .isSelected : [])

            Button { panel = .comments(video.id) } label: {
                metric("Comments", icon: "comment", count: counts?.commentCount, failed: failed)
            }
            .accessibilityLabel(words("Comments"))
            .accessibilityValue(countValue(counts?.commentCount))

            Button {
                if let owner = session.userID { panel = .report(mediaID: video.id, ownerID: owner) }
            } label: {
                HostedArtwork("report").scaledToFit().frame(width: 44, height: 44)
            }
            .disabled(session.userID == nil)
            .accessibilityLabel(words("Report options"))

            if failed {
                Button(words("Try again")) { Task { await session.refreshMediaEngagement(ids: [video.id]) } }
                    .font(LiyaType.text(.caption, weight: .semibold)).frame(minHeight: 44)
                    .accessibilityHint(words("Refresh likes and comments"))
            }
        }
        .buttonStyle(.plain)
        .disabled(session.catalogLoading || preview.index != preview.requestedIndex)
        .task(id: active && scenePhase == .active ? video.id : nil) {
            guard active, scenePhase == .active, !session.catalogLoading else { return }
            await session.refreshMediaEngagement(ids: [video.id])
        }
    }

    private func metric(_ title: String, icon: String, count: Int?, failed: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                HostedArtwork(decorative: icon).scaledToFit().frame(width: 28, height: 28)
                if let count { Text(count, format: .number) }
                else { Text(verbatim: failed ? "—" : "…") }
            }.font(LiyaType.text(.subheadline, weight: .bold)).monospacedDigit()
            Text(verbatim: words(title)).font(LiyaType.text(.caption, weight: .semibold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 5)
        .frame(minWidth: 52, minHeight: 44)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
        .contentShape(Rectangle())
    }

    private func countValue(_ count: Int?) -> Text {
        if let count { return Text(count, format: .number) }
        return Text(verbatim: words("Count unavailable"))
    }
}

private enum MediaThreadComment: Identifiable {
    case editorial(EditorialMediaComment)
    case member(VideoComment)

    var id: String {
        switch self {
        case .editorial(let comment): return comment.id
        case .member(let comment): return comment.id.uuidString
        }
    }

    var memberComment: VideoComment? {
        if case .member(let comment) = self { return comment }
        return nil
    }

    var memberAuthor: SocialPerson? {
        guard let member = memberComment, let author = member.author, author.id == member.ownerID else { return nil }
        return author
    }

    var bodyText: String {
        switch self {
        case .editorial(let comment): return comment.body
        case .member(let comment): return comment.body
        }
    }

    var mediaID: String {
        switch self {
        case .editorial(let comment): return comment.mediaID
        case .member(let comment): return comment.mediaID
        }
    }

    var authorName: String? {
        switch self {
        case .editorial(let comment): return comment.displayName
        case .member: return memberAuthor?.displayName
        }
    }
}

private struct MediaCommentAvatar: View {
    @EnvironmentObject private var session: LiyaSession
    let comment: MediaThreadComment

    @ViewBuilder
    var body: some View {
        switch comment {
        case .member(let member):
            if let author = comment.memberAuthor {
                SocialAvatar(personID: member.ownerID, commentAuthor: author)
            } else {
                MemberInitialsAvatar(name: "")
            }
        case .editorial(let credit):
            if let portraitID = credit.portraitMediaID,
               let index = CollectionPhotoRoles.portraitIndex(forMediaID: portraitID, in: session.photos) {
                CollectionPhoto(catalogIndex: index, contentMode: .fill, avatarName: credit.displayName)
                    .id(portraitID)
            } else {
                MemberInitialsAvatar(name: credit.displayName)
            }
        }
    }
}

struct MediaCommentsView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    let mediaID: String
    @State private var comments: [MediaThreadComment] = []
    @State private var text = ""
    @State private var loading = true
    @State private var sending = false
    @State private var deleting: Set<UUID> = []
    @State private var error: String?
    @State private var loadFailed = false
    @State private var loadID = UUID()
    @State private var attempt = UUID()
    @State private var loadedDraftKey: String?
    @State private var target: MediaThreadComment?
    @State private var reportedCommentIDs: Set<String> = []
    @State private var showProfileSetup = false
    @FocusState private var commentFocused: Bool

    private var draftKey: String? {
        guard let owner = session.userID else { return nil }
        return "liya.video.commentDraft.\(owner.uuidString).\(mediaID)"
    }

    private var canSend: Bool {
        !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 2000
    }

    private var displayedCommentCount: Int? {
        if !loading, !loadFailed, session.userID != nil { return comments.count }
        return session.mediaEngagement[mediaID]?.commentCount
    }

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                DuoControlRegion { _ in
                    HStack(spacing: 4) {
                        Button { dismiss() } label: {
                            HostedArtwork("back").scaledToFit().frame(width: 20, height: 20)
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).disabled(sending).accessibilityLabel(words("Back"))
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Text(verbatim: words("Comments")).font(LiyaType.text(.headline))
                            if let count = displayedCommentCount {
                                Text(count, format: .number).font(LiyaType.text(.subheadline, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }.accessibilityElement(children: .combine)
                        Spacer(minLength: 0)
                        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                    }.modifier(AdaptiveContainerMargins())
                }.frame(height: 44).padding(.top, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if loading && comments.isEmpty {
                            LiyaLoadingIndicator(size: 28).frame(maxWidth: .infinity).padding(.vertical, 24)
                        } else if error == nil && comments.isEmpty {
                            VStack(spacing: 10) {
                                HostedArtwork(decorative: "profile-action-message").scaledToFit().frame(width: 52, height: 52)
                                Text(verbatim: words("No comments yet")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                        }
                        ForEach(comments) { comment in commentRow(comment) }
                    }.frame(maxWidth: 620, alignment: .leading)
                        .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
                        .modifier(AdaptiveContainerMargins())
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await refreshThread() }
                .safeAreaInset(edge: .bottom, spacing: 0) { commentComposer }
            }
        }
        .navigationBarHidden(true)
        .interactiveDismissDisabled(sending)
        .navigationDestination(isPresented: $showProfileSetup) { CommunityJoinView() }
        .task(id: draftKey) {
            restoreDraft()
            target = nil
            reportedCommentIDs = []
            comments = []
            await refreshThread()
        }
        .onLiyaChange(of: social.syncGeneration) { _ in Task { await load() } }
        .sheet(item: $target) { comment in
            MediaCommentSafetyView(comment: comment, alreadyReported: reportedCommentIDs.contains(comment.id)) {
                reportedCommentIDs.insert(comment.id)
            }
        }
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if loadFailed {
                        Button(words("Try again")) { Task { await refreshThread() } }
                            .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(words("Write a comment"), text: Binding(get: { text }, set: {
                    text = $0; attempt = UUID(); persistDraft()
                }), axis: .vertical)
                    .lineLimit(1...4).padding(.horizontal, 14).padding(.vertical, 12)
                    .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(liyaAccent.opacity(0.12), lineWidth: 1))
                    .focused($commentFocused).disabled(sending).accessibilityLabel(words("Write a comment"))
                Button(words(sending ? "Sending…" : "Send")) { send() }
                    .font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(liyaGradient.opacity(canSend ? 1 : 0.45), in: Capsule())
                    .disabled(!canSend)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity)
            .background(.ultraThinMaterial).modifier(AdaptiveContainerMargins())
    }

    private func commentRow(_ comment: MediaThreadComment) -> some View {
        let member = comment.memberComment
        let mine = member != nil && member?.ownerID == session.userID
        return HStack(alignment: .top, spacing: 12) {
            MediaCommentAvatar(comment: comment).frame(width: 38, height: 38).clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Group {
                    if let person = comment.memberAuthor {
                        NavigationLink { CommunityPersonView(personID: person.id) } label: {
                            if mine { Text(verbatim: words("You")) } else { Text(verbatim: person.displayName) }
                        }.buttonStyle(.plain)
                    } else if mine { Text(verbatim: words("You")) }
                    else if case .editorial(let credit) = comment {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: credit.displayName)
                            Text(verbatim: words("Collection")).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    else { Text(verbatim: words("Liya member")) }
                }.font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                Text(verbatim: comment.bodyText).font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.9))
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                if reportedCommentIDs.contains(comment.id) {
                    Text(verbatim: words("Report received.")).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(liyaAccent)
                }
                if mine, let member, let status = social.moderationText(kind: "media_comment", id: member.id) {
                    Text(verbatim: words(status)).font(LiyaType.text(.footnote)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let member, mine {
                Button(words("Delete")) { delete(member) }
                    .font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                    .disabled(deleting.contains(member.id))
            } else {
                Button { commentFocused = false; target = comment } label: {
                    HostedArtwork(decorative: member == nil ? "safety-report" : "more").scaledToFit()
                        .frame(width: 18, height: 18).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(member == nil ? Text(verbatim: words("Report comment")) : Text(verbatim: words("Comment options")))
                    .disabled(member == nil && reportedCommentIDs.contains(comment.id))
            }
        }.padding(.vertical, 12)
    }

    private func refreshThread() async {
        await session.refreshMediaEngagement(ids: [mediaID])
        guard !Task.isCancelled else { return }
        await load()
    }

    private func load() async {
        let request = UUID()
        loadID = request
        guard let owner = session.userID else {
            comments = []; loading = false; error = "Your session has expired. Please sign in again."
            return
        }
        loading = true; loadFailed = false; error = nil
        async let published = social.editorialComments(session, mediaID: mediaID)
        async let members = social.videoComments(session, mediaID: mediaID)
        let publishedRows = try? await published
        let memberRows = try? await members
        guard !Task.isCancelled, loadID == request, session.userID == owner else { return }
        comments = (publishedRows ?? []).map(MediaThreadComment.editorial)
                 + (memberRows ?? []).map(MediaThreadComment.member)
        loading = false
        loadFailed = publishedRows == nil || memberRows == nil
        if loadFailed {
            error = "Couldn't load comments. Please try again."
        } else {
            session.confirmVisibleMediaComments(comments.count, mediaID: mediaID)
        }
    }

    private func delete(_ comment: VideoComment) {
        guard let owner = session.userID, deleting.insert(comment.id).inserted else { return }
        Task {
            let success = await social.deleteVideoComment(session, id: comment.id, mediaID: comment.mediaID)
            guard session.userID == owner else { return }
            deleting.remove(comment.id)
            if !success { error = "Couldn't delete this comment. Please try again." }
        }
    }

    private func send() {
        guard canSend, let owner = session.userID else { return }
        guard !social.loading else { error = "Your profile is still loading. Please try again."; return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = attempt
        sending = true; error = nil
        Task {
            defer { sending = false }
            if !social.canCommentOnMedia(session) {
                await social.refresh(session)
                guard session.userID == owner else { return }
                if !social.canCommentOnMedia(session) {
                    if let failure = social.error { error = failure }
                    else { commentFocused = false; showProfileSetup = true }
                    return
                }
            }
            let success = await social.sendVideoComment(session, id: id, mediaID: mediaID, body: body)
            guard session.userID == owner else { return }
            if success {
                text = ""; attempt = UUID(); persistDraft()
            } else {
                error = "Couldn't send your comment. Your text is still here."
            }
        }
    }

    private func restoreDraft() {
        loadedDraftKey = draftKey
        let saved = loadedDraftKey.flatMap { UserDefaults.standard.dictionary(forKey: $0) }
        text = saved?["text"] as? String ?? ""
        attempt = (saved?["attempt"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
    }

    private func persistDraft() {
        guard let key = loadedDraftKey, key == draftKey else { return }
        if text.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
        else { UserDefaults.standard.set(["text": text, "attempt": attempt.uuidString], forKey: key) }
    }
}

struct VideoSafetyReason: View {
    @Environment(\.liyaWords) private var words
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: selected ? .semibold : .medium)).foregroundStyle(liyaInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected { Text(verbatim: words("Selected")).font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(liyaAccent) }
            }.padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? liyaAccent.opacity(0.09) : Color(red: 0.96, green: 0.96, blue: 0.98), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(liyaAccent.opacity(selected ? 0.35 : 0), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MediaCommentSafetyView: View {
    @Environment(\.liyaWords) private var words
    private enum Step {
        case options, report, block

        var title: String {
            switch self {
            case .options: return "Comment options"
            case .report: return "Report comment"
            case .block: return "Block profile"
            }
        }
    }

    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let comment: MediaThreadComment
    let alreadyReported: Bool
    let reportReceived: () -> Void
    @State private var step: Step
    @State private var selected: String?
    @State private var requestID = UUID()
    @State private var sending = false
    @State private var error: String?
    @State private var showProfileSetup = false

    init(comment: MediaThreadComment, alreadyReported: Bool, reportReceived: @escaping () -> Void) {
        self.comment = comment
        self.alreadyReported = alreadyReported
        self.reportReceived = reportReceived
        _step = State(initialValue: comment.memberComment == nil ? .report : .options)
    }

    private var profileName: String {
        comment.authorName ?? words("Liya member")
    }

    var body: some View {
        SafetyPanel(title: step.title, subject: profileName,
                    back: step == .options || comment.memberComment == nil ? nil : { changeStep(.options) },
                    close: { dismiss() }, busy: sending) {
            MediaCommentAvatar(comment: comment).frame(width: 44, height: 44).clipShape(Circle())
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: comment.bodyText).font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.76))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                switch step {
                case .options:
                    VStack(spacing: 0) {
                        SafetyActionRow(title: "Report comment", kind: .report) { changeStep(.report) }
                            .disabled(alreadyReported)
                        Divider()
                        SafetyActionRow(title: "Block profile", kind: .block) { changeStep(.block) }
                    }
                case .report:
                    SafetyReasonList(selected: selected) { reason in
                        guard !sending, selected != reason else { return }
                        selected = reason
                        requestID = UUID()
                        error = nil
                    }.disabled(sending)
                    feedback
                    SafetySubmitButton(title: sending ? "Sending…" : "Send report", busy: sending,
                                       disabled: selected == nil || sending, action: report)
                case .block:
                    Text(verbatim: words("Their comments and other community content will no longer be visible to you."))
                        .font(LiyaType.detail).foregroundStyle(liyaInk).fixedSize(horizontal: false, vertical: true)
                    feedback
                    if social.canCommentOnMedia(session) {
                        SafetySubmitButton(title: sending ? "Blocking…" : "Block profile", destructive: true,
                                           busy: sending, disabled: sending, action: block)
                    } else if social.loading {
                        LiyaLoadingIndicator(size: 24).frame(maxWidth: .infinity, minHeight: 44)
                    } else if session.userID == nil || social.checkedMemberProfileOwner != session.userID || social.error != nil {
                        Text(verbatim: words("Couldn't load your profile. Please try again."))
                            .font(LiyaType.text(.footnote)).foregroundStyle(liyaInk)
                        SafetySecondaryButton(title: "Try again") { Task { await social.refresh(session) } }
                    } else {
                        SafetySubmitButton(title: "Create a community profile to block") { showProfileSetup = true }
                    }
                }
            }
        }
        .onLiyaChange(of: session.userID) { _ in dismiss() }
        .sheet(isPresented: $showProfileSetup) {
            NavigationStack { CommunityJoinView() }
                .environment(\.liyaTabBarClearance, 0)
                .presentationDetents([.large])
        }
    }

    @ViewBuilder private var feedback: some View {
        if let error {
            Text(verbatim: words(error)).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(liyaInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func changeStep(_ destination: Step) {
        guard !sending else { return }
        error = nil
        step = destination
    }

    private func report() {
        guard let reason = selected, let owner = session.userID, !sending, !alreadyReported else { return }
        sending = true
        error = nil
        Task {
            let saved = await social.reportVideoComment(session, id: requestID, mediaID: comment.mediaID,
                                                        commentID: comment.memberComment?.id,
                                                        presetKey: comment.memberComment == nil ? comment.id : nil,
                                                        body: comment.bodyText, reason: reason)
            guard session.userID == owner else { return }
            if saved {
                reportReceived()
                dismiss()
            } else {
                sending = false
                error = "Couldn't confirm the report. Please try again."
            }
        }
    }

    private func block() {
        guard let owner = session.userID, let member = comment.memberComment,
              social.canCommentOnMedia(session), !sending else { return }
        sending = true
        error = nil
        Task {
            let blocked = await social.blockMediaCommenter(session, ownerID: member.ownerID)
            guard session.userID == owner else { return }
            sending = false
            if blocked { dismiss() }
            else { error = "Couldn't block this profile. Please try again." }
        }
    }
}

private struct VideoReportView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
    let mediaID: String
    let ownerID: UUID
    @State private var selected: String?
    @State private var requestID = UUID()
    @State private var sending = false
    @State private var sent = false
    @State private var failed = false

    private var targetIndex: Int? {
        guard session.userID == ownerID else { return nil }
        return session.videos.firstIndex { $0.id == mediaID }
    }

    var body: some View {
        SafetyPanel(title: sent ? "Report received." : "Report video",
                    subject: session.curatedVideoCreators[mediaID]?.name,
                    back: nil, close: { dismiss() }, busy: sending) {
            HostedArtwork("safety-report").scaledToFit().padding(6)
        } content: {
            if sent {
                SafetySubmitButton(title: "Done") { dismiss() }
            } else if targetIndex == nil {
                Text(verbatim: words("This video is unavailable.")).font(LiyaType.detail).foregroundStyle(liyaInk)
                SafetySecondaryButton(title: "Close") { dismiss() }
            } else {
                Text(verbatim: words("Choose a reason")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                SafetyReasonList(selected: selected) { reason in
                    guard !sending, reason != selected else { return }
                    selected = reason
                    requestID = UUID()
                    failed = false
                }.disabled(sending)
                if failed {
                    Text(verbatim: words("Couldn't confirm the report. Please try again."))
                        .font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(liyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SafetySubmitButton(title: sending ? "Sending…" : "Send report", busy: sending,
                                   disabled: selected == nil || sending, action: submit)
            }
        }
        .onLiyaChange(of: session.userID) { account in if account != ownerID { dismiss() } }
    }

    private func submit() {
        guard let reason = selected, !sending, !sent else { return }
        sending = true
        failed = false
        Task {
            defer { sending = false }
            guard let index = targetIndex else { return }
            let saved = await session.submitReport(id: requestID, index: index, targetType: "video", reason: reason)
            guard session.userID == ownerID else { return }
            sent = saved
            failed = !saved
        }
    }
}
