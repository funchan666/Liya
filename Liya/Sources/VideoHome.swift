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
    private var reachedEnd = false
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
        reachedEnd = false
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
            if reachedEnd { player.seek(to: .zero); reachedEnd = false }
            player.play()
            playing = true
        }
    }

    func resumeIfWanted(active: Bool) {
        isActive = active
        if active && wantsPlayback && !unavailable && !loading && player.currentItem != nil { player.play(); playing = true } else { pause() }
    }
    func pause() { player.pause(); playing = false }
    func finished() { reachedEnd = true; wantsPlayback = false; pause() }
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
private struct ExampleVideoCreator {
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
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                            .frame(width: 44, height: 44).clipped()
                    } else {
                        Color.white.opacity(0.15)
                    }
                }
            } else {
                Color.white.opacity(0.15)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: "\(session.imageGeneration)-\(photoID ?? "")") {
            url = nil
            guard let photoID, let index = session.photos.firstIndex(where: { $0.id == photoID }) else { return }
            if let signedURL = try? await session.mediaURL(kind: "photo", index: index), !Task.isCancelled {
                url = signedURL
            }
        }
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
                Text("Curated videos · names are aliases")
                    .font(.caption2).shadow(color: .black.opacity(0.85), radius: 3)
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
                    VStack(alignment: .leading, spacing: 16) {
                        if session.videos.indices.contains(preview.index) {
                            let creator = ExampleVideoCreator.byVideoID[session.videos[preview.index].id]
                            HStack(spacing: 10) {
                                ExampleVideoAvatar(photoID: creator?.photoID)
                                Text(creator?.name ?? "Liya collection").font(.headline)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(creator?.name ?? "Liya collection")
                            if let caption = creator?.caption {
                                Text(caption).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
                    Spacer(minLength: 8)
                    VStack(spacing: 12) {
                        Button { Task { await session.toggleLike(kind: "video", index: preview.index) } } label: {
                            Image("heart").resizable().scaledToFit().frame(width: 44, height: 44)
                        }.buttonStyle(.plain).disabled(!session.likesReady || session.likesLoading || session.videos.isEmpty)
                            .accessibilityLabel(session.isLiked(kind: "video", index: preview.index) ? "Remove like" : "Like")
                        Text(session.isLiked(kind: "video", index: preview.index) ? "Liked" : "Like").font(.caption2)
                        Button { panel = .notes } label: { Image("comment").resizable().scaledToFit().frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("Private video notes")
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
                if current == .notes { VideoNotesView(index: preview.index) }
                else { ReportDraftView(index: preview.index, targetType: "video") }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if let item = notification.object as? AVPlayerItem, item === preview.player.currentItem { preview.finished() }
        }
        .onDisappear { preview.resumeIfWanted(active: false) }
        .navigationBarHidden(true)
    }
}

private struct VideoNotesView: View {
    @EnvironmentObject private var store: LocalStore
    let index: Int
    @State private var text = ""
    var body: some View {
        PageShell(title: "Video notes") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "These notes stay on this device and are not comments sent to a service.")
                ForEach(store.videoNotes.filter { $0.videoIndex == index }) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.text).foregroundStyle(liyaInk)
                        HStack {
                            Text(note.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Delete") { store.deleteVideoNote(note.id) }.font(.caption.bold()).foregroundStyle(liyaAccent)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                TextField("Write a private note", text: $text, axis: .vertical).lineLimit(2...6).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                PrimaryButton(title: "Save note", disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    store.addVideoNote(text.trimmingCharacters(in: .whitespacesAndNewlines), index: index); text = ""
                }
            }.padding(.top, 12)
        }
    }
}
