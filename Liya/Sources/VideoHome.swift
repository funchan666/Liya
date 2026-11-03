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
        guard !unavailable, !loading, player.currentItem != nil else { return }
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

private enum VideoPanel: String, Identifiable {
    case notes, report
    var id: String { rawValue }
}

// The supplied photos and videos have no known author relationship. These
// stable display-only pairings are examples, not real user accounts.
struct ExampleVideoCreator {
    let name: String
    let photoID: String
    let caption: String

    static let byVideoID: [String: ExampleVideoCreator] = [
        "example-video-001": .init(name: "Maya Bennett", photoID: "example-photo-001", caption: "A little time by the sea."),
        "example-video-002": .init(name: "Elena Rivers", photoID: "example-photo-002", caption: "Some views are worth the climb."),
        "example-video-003": .init(name: "Sofia Hayes", photoID: "example-photo-003", caption: "Letting the noise wash away for a while."),
        "example-video-004": .init(name: "Theo Parker", photoID: "example-photo-004", caption: "Taking the long way, one step at a time."),
        "example-video-005": .init(name: "Nora Ellis", photoID: "example-photo-005", caption: "A moment to remember."),
        "example-video-006": .init(name: "Leo Martin", photoID: "example-photo-006", caption: "A little sunshine on an ordinary day."),
        "example-video-007": .init(name: "Iris Chen", photoID: "example-photo-007", caption: "Nature never stops surprising me."),
        "example-video-008": .init(name: "Noah Brooks", photoID: "example-photo-008", caption: "A ride with a view."),
        "example-video-009": .init(name: "Ava Morgan", photoID: "example-photo-009", caption: "A quiet moment above the city."),
        "example-video-010": .init(name: "Jules Carter", photoID: "example-photo-010", caption: "Finding a little peace on the water.")
    ]
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
                    Image("video-title").resizable().scaledToFit().frame(width: 145, height: 42).accessibilityLabel("Liya videos")
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
                            let creator = ExampleVideoCreator.byVideoID[session.videos[preview.index].id]
                            let photoIndex = creator.flatMap { person in session.photos.firstIndex(where: { $0.id == person.photoID }) }
                            HStack(alignment: .center, spacing: 8) {
                                NavigationLink {
                                    if let creator, let photoIndex {
                                        ExampleProfileView(index: photoIndex, displayName: creator.name, introduction: creator.caption)
                                    } else {
                                        PageShell(title: "Profile") {
                                            EmptyState(title: "Profile unavailable", detail: "Please try again when the content has loaded.")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        ExampleVideoAvatar(photoID: creator?.photoID)
                                        Text(creator?.name ?? "Liya collection")
                                            .font(.subheadline.weight(.semibold)).lineLimit(2)
                                    }
                                    .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View \(creator?.name ?? "profile")")
                                if let photoIndex {
                                    let following = store.followedExamples.contains(photoIndex)
                                    Button {
                                        guard !store.blockedExamples.contains(photoIndex) else { return }
                                        store.toggleFollow(photoIndex)
                                    } label: {
                                        Text(following ? "Following" : "Follow")
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
                                    .buttonStyle(.plain)
                                    .disabled(store.blockedExamples.contains(photoIndex))
                                    .opacity(store.blockedExamples.contains(photoIndex) ? 0.5 : 1)
                                    .accessibilityLabel(following ? "Unfollow \(creator?.name ?? "profile")" : "Follow \(creator?.name ?? "profile")")
                                    .accessibilityHint(store.blockedExamples.contains(photoIndex) ? "Unblock this profile before following." : "This follow is not synced to your account.")
                                }
                            }
                            if let caption = creator?.caption {
                                Text(caption).font(.subheadline).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
                    Spacer(minLength: 8)
                    VStack(spacing: 12) {
                        Button { Task { await session.toggleLike(kind: "video", index: preview.index) } } label: {
                            Image(session.isLiked(kind: "video", index: preview.index) ? "video-like-on" : "video-like-off")
                                .resizable().scaledToFit().frame(width: 48, height: 48)
                        }.buttonStyle(.plain).disabled(!session.likesReady || session.likesLoading || session.videos.isEmpty)
                            .accessibilityLabel(session.isLiked(kind: "video", index: preview.index) ? "Remove like" : "Like")
                        Text(session.isLiked(kind: "video", index: preview.index) ? "Liked" : "Like").font(.caption2)
                        Button { panel = .notes } label: { Image("comment").resizable().scaledToFit().frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("Video comments")
                        Button { panel = .report } label: { Image("report").resizable().scaledToFit().frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("Report options")
                    }
                }
                if let error = session.likesError {
                    Text(error).font(.footnote)
                    Button("Retry likes") { Task { await session.refreshLikes() } }.frame(minHeight: 44)
                }
               }.foregroundStyle(.white).padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity).frame(minHeight: available.height).modifier(AdaptiveContainerMargins())
              }.modifier(VideoScrollBounce())
            }
            .padding(.bottom, LiyaTabBarLayout.contentClearance)
        }
        .background {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.11)
                PlayerView(player: preview.player)
                    .offset(y: reduceMotion ? 0 : max(-28, min(28, swipeTranslation * 0.14)))
                    .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.85), value: swipeTranslation)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea(.container)
        }
        .overlay {
            if !session.catalogLoading && !preview.loading && !preview.unavailable && !session.videos.isEmpty {
                DuoControlRegion { _ in
                    Button { preview.toggle() } label: {
                        Image(preview.playing ? "pause" : "play")
                            .resizable().scaledToFit().frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preview.playing ? "Pause video" : "Play video")
                }
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
                if request.openNotes { panel = .notes }
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
            NavigationStack {
                if current == .notes { VideoCommentsView(index: preview.index) }
                else { VideoReportView(index: preview.index) }
            }
            .environment(\.liyaTabBarClearance, 0)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if let item = notification.object as? AVPlayerItem, item === preview.player.currentItem { preview.finished() }
        }
        .onDisappear { preview.resumeIfWanted(active: false) }
        .navigationBarHidden(true)
    }
}

private struct VideoCommentTarget: Identifiable {
    let id: String
    let mediaID: String
    let commentID: UUID?
    let presetKey: String?
    let ownerID: UUID?
    let photoIndex: Int?
    let name: String
    let body: String
}

private struct VideoCommentsView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let index: Int
    @State private var comments: [VideoComment] = []
    @State private var text = ""
    @State private var loading = false
    @State private var sending = false
    @State private var error: String?
    @State private var loadID = UUID()
    @State private var attempt = UUID()
    @State private var loadedDraft = false
    @State private var target: VideoCommentTarget?
    @State private var showProfileSetup = false
    @FocusState private var commentFocused: Bool
    private var mediaID: String? { session.videos.indices.contains(index) ? session.videos[index].id : nil }
    private var hasVisibleStarters: Bool {
        guard mediaID != nil, !session.photos.isEmpty else { return false }
        return (0..<2).contains { !store.blockedExamples.contains((10 + index * 2 + $0) % session.photos.count) }
    }
    private var draftKey: String { "liya.video.commentDraft.\(session.userID?.uuidString ?? "none").\(mediaID ?? "none")" }
    private let starters = [
        ["That view is something else.", "I could listen to the waves all day."],
        ["The walk looks so worth it.", "What a place to pause for a moment."],
        ["This feels like a breath of fresh air.", "A little reset for the day."],
        ["The mountains are incredible.", "The kind of walk you remember."],
        ["That looks like quite an adventure.", "What a moment to capture."],
        ["Love the light in this moment.", "A little sunshine makes a difference."],
        ["Nature really puts on a show.", "I would never forget that view."],
        ["A ride with a view like that? Yes please.", "Looks like a lovely way to spend the day."],
        ["That view is so peaceful.", "A quiet moment above the city."],
        ["The colour of the water is unreal.", "This looks like a lovely escape."]
    ]
    private let starterNames = ["Mia Lawson", "Jamie Reed", "Avery Kim", "Alex Morgan", "Sam Ellis", "Leah Brooks", "Jordan Blake", "Nina Hart", "Evan Cole", "Lucy Bell", "Owen Price", "Ivy Moore", "Max Turner", "Ella James", "Ryan Scott", "Zoe Hill", "Finn Carter", "Mila Grant", "Ethan Wells", "Chloe Lane"]

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                PageHeader(title: "Comments")
                    .padding(.top, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let mediaID, !session.photos.isEmpty {
                            ForEach(0..<2, id: \.self) { position in
                                let photoIndex = (10 + index * 2 + position) % session.photos.count
                                if !store.blockedExamples.contains(photoIndex) {
                                    let name = starterNames[(index * 2 + position) % starterNames.count]
                                    let body = starters[index % starters.count][position]
                                    let key = "\(mediaID):starter:\(position)"
                                    commentRow(name: name, body: body, imageIndex: photoIndex, personID: nil,
                                               target: VideoCommentTarget(id: key, mediaID: mediaID, commentID: nil, presetKey: key, ownerID: nil, photoIndex: photoIndex, name: name, body: body))
                                }
                            }
                        }
                        if loading {
                            LiyaLoadingIndicator(size: 28).frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                        if !loading && error == nil && comments.isEmpty && !hasVisibleStarters {
                            VStack(spacing: 10) {
                                Image("profile-action-message").resizable().scaledToFit().frame(width: 52, height: 52).accessibilityHidden(true)
                                Text("No comments yet").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                        }
                        ForEach(comments) { comment in
                            let name = comment.ownerID == session.userID ? "You" : (social.person(comment.ownerID)?.displayName ?? "Liya member")
                            let action = VideoCommentTarget(id: comment.id.uuidString, mediaID: comment.mediaID, commentID: comment.id, presetKey: nil, ownerID: comment.ownerID, photoIndex: nil, name: name, body: comment.body)
                            commentRow(name: name, body: comment.body, imageIndex: nil, personID: comment.ownerID, target: action)
                        }
                    }.frame(maxWidth: 620, alignment: .leading)
                        .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
                        .modifier(AdaptiveContainerMargins())
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { commentComposer }
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showProfileSetup) { CommunityJoinView() }
        .task(id: "\(session.userID?.uuidString ?? "none")-\(mediaID ?? "none")") { restoreDraft(); await load() }
        .onDisappear { persistDraft() }
        .onLiyaChange(of: social.syncGeneration) { _ in Task { await load() } }
        .sheet(item: $target, onDismiss: { Task { await load() } }) { value in NavigationStack { VideoCommentSafetyView(target: value) } }
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
        if let error {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                Button("Try again") { Task { if social.error != nil { await social.refresh(session) }; await load() } }
                    .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
            }
        }
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Share a thought…", text: Binding(get: { text }, set: { text = $0; attempt = UUID(); persistDraft() }), axis: .vertical)
                .lineLimit(1...4).padding(.horizontal, 14).padding(.vertical, 12)
                .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(liyaAccent.opacity(0.12), lineWidth: 1))
                .focused($commentFocused).disabled(sending).accessibilityLabel("Write a comment")
            Button(sending ? "Sending…" : "Send") { send() }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(liyaGradient.opacity(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000 ? 0.45 : 1), in: Capsule())
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
        }
        }.padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity)
            .background(.ultraThinMaterial).modifier(AdaptiveContainerMargins())
    }

    private func commentRow(name: String, body: String, imageIndex: Int?, personID: UUID?, target action: VideoCommentTarget) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageIndex {
                NavigationLink { ExampleProfileView(index: imageIndex, displayName: name) } label: { ExampleAvatar(index: imageIndex, size: 42) }.buttonStyle(.plain)
            } else if let personID {
                NavigationLink { CommunityPersonView(personID: personID) } label: { SocialAvatar(personID: personID).frame(width: 42, height: 42).clipShape(Circle()) }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let imageIndex {
                    NavigationLink(name) { ExampleProfileView(index: imageIndex, displayName: name) }.font(.subheadline.bold()).foregroundStyle(liyaInk)
                } else if let personID {
                    NavigationLink(name) { CommunityPersonView(personID: personID) }.font(.subheadline.bold()).foregroundStyle(liyaInk)
                }
                if action.presetKey != nil {
                    Text("Suggested").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                Text(body).font(.subheadline).foregroundStyle(liyaInk.opacity(0.9)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if personID == session.userID, let id = action.commentID {
                Button("Delete") { Task { if await social.deleteVideoComment(session, id: id) { await load() } else { error = "Couldn't delete this comment. Please try again." } } }
                    .font(.caption.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
            } else {
                Button { target = action } label: { Image("more").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Comment options")
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 18))
    }

    private func load() async {
        guard let mediaID, let owner = session.userID else { comments = []; loading = false; return }
        let request = UUID(); loadID = request; loading = true; error = nil
        do {
            let rows = try await social.videoComments(session, mediaID: mediaID)
            guard loadID == request, self.mediaID == mediaID, session.userID == owner else { return }
            comments = rows; loading = false
        } catch {
            guard loadID == request else { return }
            loading = false; self.error = "Couldn't load comments. Please try again."
        }
    }

    private func send() {
        guard !sending else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 2000 else { return }
        guard let mediaID, session.userID != nil else { error = "This video is unavailable. Please try again."; return }
        guard !social.loading else { error = "Your profile is still loading. Please try again."; return }
        guard social.error == nil else { error = "Couldn't load your profile. Please try again."; return }
        guard social.isJoined(session) else { commentFocused = false; showProfileSetup = true; return }
        sending = true; error = nil
        Task {
            if await social.sendVideoComment(session, id: attempt, mediaID: mediaID, body: body) {
                text = ""; attempt = UUID(); persistDraft(); await load()
            } else { error = "Couldn't send your comment. Your text is still here." }
            sending = false
        }
    }

    private func restoreDraft() {
        loadedDraft = false
        let saved = UserDefaults.standard.dictionary(forKey: draftKey)
        text = saved?["text"] as? String ?? ""
        attempt = (saved?["attempt"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        loadedDraft = true
    }

    private func persistDraft() {
        guard loadedDraft, session.userID != nil else { return }
        UserDefaults.standard.set(["text": text, "attempt": attempt.uuidString], forKey: draftKey)
    }
}

struct VideoSafetySheet<Content: View, Footer: View>: View {
    let title: String
    let back: () -> Void
    let content: Content
    let footer: Footer

    init(title: String, back: @escaping () -> Void,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.back = back
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            GeometryReader { geometry in
                let artworkHeight = geometry.size.width * 958 / 778
                VStack(spacing: 0) {
                    Image("panel-background").resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: artworkHeight)
                    Spacer(minLength: 0)
                }
            }.ignoresSafeArea(.container, edges: .bottom).allowsHitTesting(false).accessibilityHidden(true)
            VStack(spacing: 0) {
                DuoControlRegion { _ in
                    HStack {
                        Button(action: back) {
                            Image("back").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Back")
                        Spacer(minLength: 0)
                        Text(title).font(.headline).foregroundStyle(liyaInk).lineLimit(1)
                        Spacer(minLength: 0)
                        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                    }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                }.frame(height: 48)
                ScrollView {
                    content.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
                        .modifier(AdaptiveContainerMargins())
                }.safeAreaInset(edge: .bottom, spacing: 0) {
                    footer.frame(maxWidth: 620).frame(maxWidth: .infinity)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(.white.opacity(0.97))
                        .modifier(AdaptiveContainerMargins())
                }
            }
        }.navigationBarHidden(true)
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

private struct VideoCommentSafetyView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    let target: VideoCommentTarget
    @State private var mode = 0
    @State private var selected: String?
    @State private var requestID = UUID()
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?
    private let reasons = ["Sexual content", "Harassment", "Discrimination", "Incorrect content", "Other"]

    var body: some View {
        VideoSafetySheet(title: mode == 1 ? "Report comment" : mode == 2 ? "Block profile" : "Comment options", back: {
            guard !sending else { return }
            if mode == 0 { dismiss() } else { mode = 0; error = nil }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(target.name).font(.subheadline.bold()).foregroundStyle(liyaInk)
                Text(target.body).font(.subheadline).foregroundStyle(liyaInk).fixedSize(horizontal: false, vertical: true)
                if target.presetKey != nil { Text("Suggested content").font(.caption).foregroundStyle(.secondary) }
                if mode == 1 && !sent {
                    Text("Why are you reporting this comment?").font(.headline).foregroundStyle(liyaInk).padding(.top, 8)
                    VStack(spacing: 8) {
                        ForEach(reasons, id: \.self) { reason in
                            VideoSafetyReason(title: reason, selected: selected == reason) {
                                selected = reason; requestID = UUID(); error = nil
                            }.disabled(sending || sent)
                        }
                    }
                } else if mode == 2 {
                    Text(target.presetKey == nil ? "Their comments and other community content will no longer be visible to you." : "This suggested profile and its comments will be hidden here. This block is not synced.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    if target.ownerID != nil && !social.isJoined(session) {
                        NavigationLink("Create a community profile to block") { CommunityJoinView() }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }
                }
                if sent { Text("Report received.").font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        } footer: {
            VStack(spacing: 8) {
                if let error { Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true) }
                if mode == 0 {
                    PrimaryButton(title: "Report comment") { mode = 1 }
                    Button("Block this profile") { mode = 2 }.font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(maxWidth: .infinity, minHeight: 44)
                } else if mode == 1 {
                    if sent {
                        PrimaryButton(title: "Done") { dismiss() }
                    } else {
                        PrimaryButton(title: sending ? "Sending…" : "Send report", disabled: selected == nil || sending) { report() }
                    }
                } else {
                    PrimaryButton(title: sending ? "Blocking…" : "Block profile", disabled: sending || (target.ownerID != nil && !social.isJoined(session))) { block() }
                    Button("Cancel") { mode = 0; error = nil }.font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(maxWidth: .infinity, minHeight: 44).disabled(sending)
                }
            }
        }.interactiveDismissDisabled(sending)
    }

    private func report() {
        guard let reason = selected, !sending else { return }
        sending = true; error = nil
        Task {
            sent = await social.reportVideoComment(session, id: requestID, mediaID: target.mediaID, commentID: target.commentID, presetKey: target.presetKey, body: target.body, reason: reason)
            if !sent { error = "Couldn't confirm the report. Please try again." }
            sending = false
        }
    }

    private func block() {
        guard !sending else { return }
        if let photoIndex = target.photoIndex {
            store.setBlocked(photoIndex, blocked: true); dismiss(); return
        }
        guard let ownerID = target.ownerID else { error = "This profile is unavailable."; return }
        sending = true; error = nil
        Task {
            await social.setRelation(session, target: ownerID, table: "liya_blocks", enabled: true)
            sending = false
            if social.blocked.contains(ownerID) { dismiss() }
            else { error = social.error ?? "Couldn't block this profile. Please try again." }
        }
    }
}

private struct VideoReportView: View {
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
    let index: Int
    @State private var selected: String?
    @State private var requestID = UUID()
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?
    private let reasons = ["Sexual content", "Harassment", "Discrimination", "Incorrect content", "Other"]

    var body: some View {
        VideoSafetySheet(title: "Report video", back: { if !sending { dismiss() } }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(sent ? "Thank you for letting us know." : "Why are you reporting this video?")
                    .font(.headline).foregroundStyle(liyaInk).fixedSize(horizontal: false, vertical: true)
                if !sent {
                    VStack(spacing: 8) {
                        ForEach(reasons, id: \.self) { reason in
                            VideoSafetyReason(title: reason, selected: selected == reason) {
                                selected = reason; requestID = UUID(); error = nil
                            }.disabled(sending)
                        }
                    }
                }
                if sent { Text("Report received.").font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let error { Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                if sent { PrimaryButton(title: "Done") { dismiss() } } else {
                    PrimaryButton(title: sending ? "Sending…" : "Send report", disabled: selected == nil || sending) {
                        guard let selected else { return }
                        sending = true; error = nil
                        Task {
                            sent = await session.submitReport(id: requestID, index: index, targetType: "video", reason: selected)
                            if !sent { error = "Couldn't confirm the report. Please try again." }
                            sending = false
                        }
                    }
                }
            }
        }.interactiveDismissDisabled(sending)
    }
}
