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
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var muted = false
    private var timeObserver: Any?
    private var wantsPlayback = true
    private var reachedEnd = false
    private var isActive = false
    private var loadTask: Task<Void, Never>?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let length = self.player.currentItem?.duration.seconds ?? 0
                let elapsed = time.seconds
                self.duration = length.isFinite && length > 0 ? length : 0
                self.progress = elapsed.isFinite && self.duration > 0 ? min(max(elapsed / self.duration, 0), 1) : 0
            }
        }
    }

    deinit { loadTask?.cancel(); if let timeObserver { player.removeTimeObserver(timeObserver) } }

    func select(_ newIndex: Int, active: Bool, session: LiyaSession) {
        guard session.videos.indices.contains(newIndex) else { return }
        loadTask?.cancel()
        index = newIndex
        isActive = active
        player.replaceCurrentItem(with: nil)
        playing = false
        loading = true
        unavailable = false
        duration = 0
        progress = 0
        reachedEnd = false
        wantsPlayback = true
        loadTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            do {
                let url = try await session.mediaURL(kind: "video", index: newIndex)
                guard !Task.isCancelled else { return }
                self.loading = false
                self.player.replaceCurrentItem(with: AVPlayerItem(url: url))
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

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let value = min(max(fraction, 0), 1)
        progress = value
        player.seek(to: CMTime(seconds: value * duration, preferredTimescale: 600))
        if reachedEnd { reachedEnd = false }
    }

    func toggleMute() { muted.toggle(); player.isMuted = muted }

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
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ view: PlayerSurface, context: Context) { view.playerLayer.player = player }
}

private enum VideoPanel: String, Identifiable {
    case notes, report
    var id: String { rawValue }
}

struct VideoHome: View {
    let active: Bool
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @State private var panel: VideoPanel?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = VideoPreview()
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.11).ignoresSafeArea()
            PlayerView(player: preview.player).accessibilityHidden(true)
            DuoControlRegion { available in
              ScrollView {
               VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image("video-title").resizable().scaledToFit().frame(width: 145, height: 42).accessibilityLabel("Liya videos")
                    Spacer()
                    Text(session.videos.isEmpty ? "Videos" : "Example video \(preview.index + 1) / \(session.videos.count)").font(.caption.bold())
                }
                Spacer()
                if session.catalogLoading || preview.loading { Text("Loading videos…").font(.headline) }
                else if let error = session.catalogError {
                    Text(error).font(.headline)
                    Button("Try again") { Task { await session.refreshCatalog() } }.frame(minHeight: 44)
                } else if session.videos.isEmpty { Text("No videos yet.").font(.headline) }
                else if preview.unavailable {
                    Text("This video is unavailable.").font(.headline)
                    Button("Try again") { preview.select(preview.index, active: active, session: session) }.frame(minHeight: 44)
                }
                HStack {
                    Spacer()
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
                HStack {
                    Button { preview.toggle() } label: {
                        Image(preview.playing ? "pause" : "play").resizable().scaledToFit().frame(width: 48, height: 48)
                    }.buttonStyle(.plain).accessibilityLabel(preview.playing ? "Pause" : "Play")
                    Spacer()
                    Button { preview.select(preview.index - 1, active: active, session: session) } label: {
                        Image("back").renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white).frame(width: 20, height: 20).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).disabled(preview.index == 0).accessibilityLabel("Previous video")
                    Button { preview.select(preview.index + 1, active: active, session: session) } label: {
                        Image("back").renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white).scaleEffect(x: -1, y: 1).frame(width: 20, height: 20).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).disabled(preview.index >= session.videos.count - 1).accessibilityLabel("Next video")
                }
                HStack(spacing: 8) {
                    Button(preview.muted ? "Sound off" : "Sound on") { preview.toggleMute() }
                        .font(.caption.bold()).foregroundStyle(.white).frame(minWidth: 68, minHeight: 44)
                    VideoProgress(progress: preview.progress, enabled: preview.duration > 0) { preview.seek(to: $0) }
                    Text(timeLabel(preview.progress * preview.duration) + " / " + timeLabel(preview.duration))
                        .font(.caption.monospacedDigit()).foregroundStyle(.white)
                }
                Text("Example content · Community features are not connected.").font(.footnote)
               }.foregroundStyle(.white).padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity).frame(minHeight: available.height).modifier(AdaptiveContainerMargins())
              }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { value in
            if abs(value.translation.height) > abs(value.translation.width) {
                preview.select(preview.index + (value.translation.height < 0 ? 1 : -1), active: active, session: session)
            }
        })
        .onAppear {
            if preview.player.currentItem == nil { preview.select(preview.index, active: active && scenePhase == .active && panel == nil, session: session) }
            else { preview.resumeIfWanted(active: active && scenePhase == .active && panel == nil) }
        }
        .onChange(of: store.videoRequest) { request in
            if let request {
                preview.select(request.index, active: active && scenePhase == .active && panel == nil, session: session)
                if request.openNotes { panel = .notes }
            }
        }
        .onChange(of: active) { selected in
            preview.resumeIfWanted(active: selected && scenePhase == .active && panel == nil)
        }
        .onChange(of: scenePhase) { phase in preview.resumeIfWanted(active: active && phase == .active && panel == nil) }
        .onChange(of: panel) { current in preview.resumeIfWanted(active: active && scenePhase == .active && current == nil) }
        .onChange(of: session.catalogGeneration) { _ in
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
    private func timeLabel(_ value: Double) -> String {
        let seconds = value.isFinite ? max(0, Int(value)) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VideoProgress: View {
    let progress: Double
    let enabled: Bool
    let seek: (Double) -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.35)).frame(height: 4)
                Capsule().fill(.white).frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 4)
            }.frame(maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard enabled, geometry.size.width > 0 else { return }
                    seek(Double(value.location.x / geometry.size.width))
                })
        }.frame(height: 44).accessibilityElement().accessibilityLabel("Video progress")
            .accessibilityValue("\(Int(progress * 100)) percent")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction {
                case .increment: seek(progress + 0.05)
                case .decrement: seek(progress - 0.05)
                @unknown default: break
                }
            }
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
