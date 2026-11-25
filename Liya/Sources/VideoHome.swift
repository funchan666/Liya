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

// The supplied photos and videos have no known author relationship. These
// stable display-only pairings are examples, not real user accounts.
struct ExampleVideoCreator: Decodable {
    let videoID: String
    let name: String
    let photoID: String
    let caption: String
    enum CodingKeys: String, CodingKey {
        case videoID = "video_id", name = "display_name", photoID = "photo_id", caption
    }
}

private struct ExampleVideoAvatar: View {
    @EnvironmentObject private var session: LiyaSession
    let photoID: String?

    var body: some View {
        Group {
            if let photoID, let index = session.photos.firstIndex(where: { $0.id == photoID }) {
                ExampleAvatar(index: index, size: 44)
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
                        .accessibilityLabel("Loading video")
                }
                .allowsHitTesting(false)
            }
            DuoControlRegion { available in
              ScrollView {
               VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image("video-title").resizable().scaledToFit().frame(width: 145, height: 42)
                        .allowsHitTesting(false).accessibilityLabel("Liya videos")
                    Spacer()
                }
                Spacer(minLength: 16)
                if session.catalogLoading || preview.loading { EmptyView() }
                else if let error = session.catalogError {
                    Text(error).font(.headline)
                    Button("Try again") { Task { await session.refreshCatalog() } }.frame(minHeight: 44)
                } else if session.videos.isEmpty { Text("No videos yet.").font(.headline) }
                else if preview.unavailable {
                    Text("This video is unavailable.").font(.headline)
                    Button("Try again") { preview.select(preview.requestedIndex, active: active && scenePhase == .active && panel == nil, session: session) }.frame(minHeight: 44)
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
                                        ExampleProfileView(index: photoIndex, displayName: authorName, introduction: creator.caption, mediaID: creator.photoID)
                                    } else {
                                        PageShell(title: "Profile") {
                                            EmptyState(title: "Profile unavailable", detail: "Please try again when the content has loaded.")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        ExampleVideoAvatar(photoID: creator?.photoID)
                                        Text(authorName)
                                            .font(.subheadline.weight(.semibold)).lineLimit(2)
                                    }
                                    .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View \(authorName)")
                                if let creator, let photoIndex {
                                    CuratedFollowButton(id: creator.photoID) { following, title in
                                        Text(LocalizedStringKey(title))
                                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
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
                                    .disabled(store.blockedExamples.contains(photoIndex))
                                    .opacity(store.blockedExamples.contains(photoIndex) ? 0.5 : 1)
                                }
                            }
                            if let caption = creator?.caption {
                                Text(caption).font(.subheadline).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
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
                    Text(error).font(.footnote)
                    Button("Retry likes") { Task { await session.refreshLikes() } }.frame(minHeight: 44)
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
                               Text(preview.playing ? "Pause video" : "Play video")
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
                // The visible picture can extend beyond the scrollable controls on Duo.
                if canTapVideo { playbackTapSurface.accessibilityHidden(true) }
            }
            .ignoresSafeArea(.container)
        }
        .overlay {
            if canTapVideo && !preview.playing {
                DuoControlRegion { _ in
                    Image(decorative: "play").resizable().scaledToFit()
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

    private func engagementRail(for video: LiyaMedia) -> some View {
        let counts = session.mediaEngagement[video.id]
        let liked = session.likedMediaIDs.contains(video.id)
        let failed = session.mediaEngagementFailures.contains(video.id)
        return VStack(spacing: 12) {
            Button { Task { await session.toggleMediaLike(id: video.id) } } label: {
                metric(icon: liked ? "video-like-on" : "video-like-off", count: counts?.likeCount, failed: failed)
            }
            .disabled(!session.likesReady || session.likesLoading)
            .accessibilityLabel(liked ? "Remove like" : "Like")
            .accessibilityValue(countValue(counts?.likeCount))
            .accessibilityAddTraits(liked ? .isSelected : [])

            Button { panel = .comments(video.id) } label: {
                metric(icon: "comment", count: counts?.commentCount, failed: failed)
            }
            .accessibilityLabel("Comments")
            .accessibilityValue(countValue(counts?.commentCount))

            Button {
                if let owner = session.userID { panel = .report(mediaID: video.id, ownerID: owner) }
            } label: {
                Image("report").resizable().scaledToFit().frame(width: 44, height: 44)
            }
            .disabled(session.userID == nil)
            .accessibilityLabel("Report options")

            if failed {
                Button("Try again") { Task { await session.refreshMediaEngagement(ids: [video.id]) } }
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
                    .accessibilityHint("Refresh likes and comments")
            }
        }
        .buttonStyle(.plain)
        .disabled(session.catalogLoading || preview.index != preview.requestedIndex)
        .task(id: active && scenePhase == .active ? video.id : nil) {
            guard active, scenePhase == .active, !session.catalogLoading else { return }
            await session.refreshMediaEngagement(ids: [video.id])
        }
    }

    private func metric(icon: String, count: Int?, failed: Bool) -> some View {
        VStack(spacing: 2) {
            Image(decorative: icon).resizable().scaledToFit().frame(width: 44, height: 44)
            Group {
                if let count { Text(count, format: .number) }
                else { Text(verbatim: failed ? "—" : "…") }
            }
            .font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(.black.opacity(0.64), in: Capsule())
        }
        .contentShape(Rectangle())
    }

    private func countValue(_ count: Int?) -> Text {
        if let count { return Text(count, format: .number) }
        return Text("Count unavailable")
    }
}

struct MediaCommentsView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    let mediaID: String
    @State private var comments: [VideoComment] = []
    @State private var text = ""
    @State private var loading = true
    @State private var sending = false
    @State private var deleting: Set<UUID> = []
    @State private var error: String?
    @State private var loadFailed = false
    @State private var loadID = UUID()
    @State private var attempt = UUID()
    @State private var loadedDraftKey: String?
    @State private var target: VideoComment?
    @State private var reportedCommentID: UUID?
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

    private var replyIdeas: [CloudVideoPrompt] {
        guard let index = session.videos.firstIndex(where: { $0.id == mediaID }) else { return [] }
        return session.curatedVideoPrompts.filter { prompt in
            guard prompt.videoID == mediaID else { return false }
            guard !session.photos.isEmpty else { return true }
            let authorIndex = (10 + index * 2 + prompt.position) % session.photos.count
            return !store.blockedExamples.contains(authorIndex)
        }
    }

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                DuoControlRegion { _ in
                    HStack(spacing: 4) {
                        Button { dismiss() } label: {
                            Image("back").resizable().scaledToFit().frame(width: 20, height: 20)
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).disabled(sending).accessibilityLabel("Back")
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Text("Comments").font(.headline)
                            if let count = displayedCommentCount {
                                Text(count, format: .number).font(.subheadline.weight(.semibold)).monospacedDigit()
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
                                Image(decorative: "profile-action-message").resizable().scaledToFit().frame(width: 52, height: 52)
                                Text("No comments yet").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                            if !replyIdeas.isEmpty && text.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Reply ideas").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    ForEach(replyIdeas) { idea in
                                        Button {
                                            text = idea.body; attempt = UUID(); persistDraft(); commentFocused = true
                                        } label: {
                                            Text(verbatim: idea.body).font(.subheadline).foregroundStyle(liyaInk)
                                                .multilineTextAlignment(.leading).padding(.horizontal, 12)
                                                .frame(minHeight: 44).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
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
            reportedCommentID = nil
            comments = []
            await refreshThread()
        }
        .onLiyaChange(of: social.syncGeneration) { _ in Task { await load() } }
        .sheet(item: $target) { comment in
            MediaCommentSafetyView(comment: comment) { reportedCommentID = comment.id }
        }
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if loadFailed {
                        Button("Try again") { Task { await refreshThread() } }
                            .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Write a comment", text: Binding(get: { text }, set: {
                    text = $0; attempt = UUID(); persistDraft()
                }), axis: .vertical)
                    .lineLimit(1...4).padding(.horizontal, 14).padding(.vertical, 12)
                    .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(liyaAccent.opacity(0.12), lineWidth: 1))
                    .focused($commentFocused).disabled(sending).accessibilityLabel("Write a comment")
                Button(sending ? "Sending…" : "Send") { send() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(liyaGradient.opacity(canSend ? 1 : 0.45), in: Capsule())
                    .disabled(!canSend)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity)
            .background(.ultraThinMaterial).modifier(AdaptiveContainerMargins())
    }

    private func commentRow(_ comment: VideoComment) -> some View {
        let mine = comment.ownerID == session.userID
        let person = social.person(comment.ownerID)
        return HStack(alignment: .top, spacing: 12) {
            SocialAvatar(personID: comment.ownerID).frame(width: 38, height: 38).clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Group {
                    if let person {
                        NavigationLink { CommunityPersonView(personID: person.id) } label: {
                            if mine { Text("You") } else { Text(verbatim: person.displayName) }
                        }.buttonStyle(.plain)
                    } else if mine { Text("You") }
                    else { Text("Liya member") }
                }.font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                Text(verbatim: comment.body).font(.subheadline).foregroundStyle(liyaInk.opacity(0.9))
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                if reportedCommentID == comment.id {
                    Text("Report received.").font(.footnote.weight(.medium)).foregroundStyle(liyaAccent)
                }
                if mine, let status = social.moderationText(kind: "media_comment", id: comment.id) {
                    Text(LocalizedStringKey(status)).font(.footnote).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if mine {
                Button("Delete") { delete(comment) }
                    .font(.caption.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                    .disabled(deleting.contains(comment.id))
            } else {
                Button { commentFocused = false; target = comment } label: {
                    Image("more").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Comment options")
            }
        }.padding(.vertical, 12)
    }

    private func refreshThread() async {
        async let counts: Void = session.refreshMediaEngagement(ids: [mediaID])
        await load()
        await counts
    }

    private func load() async {
        let request = UUID()
        loadID = request
        guard let owner = session.userID else {
            comments = []; loading = false; error = "Your session has expired. Please sign in again."
            return
        }
        loading = true; loadFailed = false; error = nil
        do {
            let rows = try await social.videoComments(session, mediaID: mediaID)
            guard !Task.isCancelled, loadID == request, session.userID == owner else { return }
            comments = rows; loading = false
        } catch {
            guard !Task.isCancelled, loadID == request, session.userID == owner else { return }
            loading = false; loadFailed = true; self.error = "Couldn't load comments. Please try again."
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
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(.subheadline.weight(selected ? .semibold : .medium)).foregroundStyle(liyaInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected { Text("Selected").font(.caption.weight(.semibold)).foregroundStyle(liyaAccent) }
            }.padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? liyaAccent.opacity(0.09) : Color(red: 0.96, green: 0.96, blue: 0.98), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(liyaAccent.opacity(selected ? 0.35 : 0), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MediaCommentSafetyView: View {
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
    let comment: VideoComment
    let reportReceived: () -> Void
    @State private var step = Step.options
    @State private var selected: String?
    @State private var requestID = UUID()
    @State private var sending = false
    @State private var error: String?
    @State private var showProfileSetup = false

    private var profileName: String {
        social.person(comment.ownerID)?.displayName ?? String(localized: "Liya member", locale: locale)
    }

    var body: some View {
        SafetyPanel(title: step.title, subject: profileName,
                    back: step == .options ? nil : { changeStep(.options) },
                    close: { dismiss() }, busy: sending) {
            SocialAvatar(personID: comment.ownerID).frame(width: 44, height: 44).clipShape(Circle())
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: comment.body).font(.subheadline).foregroundStyle(liyaInk.opacity(0.76))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                switch step {
                case .options:
                    VStack(spacing: 0) {
                        SafetyActionRow(title: "Report comment", kind: .report) { changeStep(.report) }
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
                    Link("Contact support", destination: URL(string: "mailto:Liya2026support@liya.vip")!)
                        .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent)
                        .frame(maxWidth: .infinity, minHeight: 44).disabled(sending)
                case .block:
                    Text("Their comments and other community content will no longer be visible to you.")
                        .font(.subheadline).foregroundStyle(liyaInk).fixedSize(horizontal: false, vertical: true)
                    feedback
                    if social.canCommentOnMedia(session) {
                        SafetySubmitButton(title: sending ? "Blocking…" : "Block profile", destructive: true,
                                           busy: sending, disabled: sending, action: block)
                    } else if social.loading {
                        LiyaLoadingIndicator(size: 24).frame(maxWidth: .infinity, minHeight: 44)
                    } else if session.userID == nil || social.checkedMemberProfileOwner != session.userID || social.error != nil {
                        Text("Couldn't load your profile. Please try again.")
                            .font(.footnote).foregroundStyle(liyaInk)
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
            Text(LocalizedStringKey(error)).font(.footnote.weight(.medium)).foregroundStyle(liyaInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func changeStep(_ destination: Step) {
        guard !sending else { return }
        error = nil
        step = destination
    }

    private func report() {
        guard let reason = selected, let owner = session.userID, !sending else { return }
        sending = true
        error = nil
        Task {
            let saved = await social.reportVideoComment(session, id: requestID, mediaID: comment.mediaID,
                                                        commentID: comment.id, presetKey: nil,
                                                        body: comment.body, reason: reason)
            guard session.userID == owner else { return }
            sending = false
            if saved {
                reportReceived()
                dismiss()
            } else {
                error = "Couldn't confirm the report. Please try again."
            }
        }
    }

    private func block() {
        guard let owner = session.userID, social.canCommentOnMedia(session), !sending else { return }
        sending = true
        error = nil
        Task {
            let blocked = await social.blockMediaCommenter(session, ownerID: comment.ownerID)
            guard session.userID == owner else { return }
            sending = false
            if blocked { dismiss() }
            else { error = "Couldn't block this profile. Please try again." }
        }
    }
}

private struct VideoReportView: View {
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
            Image("safety-report").resizable().scaledToFit().padding(6)
        } content: {
            if sent {
                SafetySubmitButton(title: "Done") { dismiss() }
            } else if targetIndex == nil {
                Text("This video is unavailable.").font(.subheadline).foregroundStyle(liyaInk)
                SafetySecondaryButton(title: "Close") { dismiss() }
            } else {
                Text("Choose a reason").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                SafetyReasonList(selected: selected) { reason in
                    guard !sending, reason != selected else { return }
                    selected = reason
                    requestID = UUID()
                    failed = false
                }.disabled(sending)
                if failed {
                    Text("Couldn't confirm the report. Please try again.")
                        .font(.footnote.weight(.medium)).foregroundStyle(liyaInk)
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
