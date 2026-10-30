import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import UIKit
import AVFoundation

struct DraftAttachment: Codable, Identifiable, Equatable {
    let id: UUID
    let filename: String
    let isVideo: Bool
}

enum DraftFiles {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiyaDraftMedia", isDirectory: true)
    }
    static func url(_ item: DraftAttachment) -> URL { directory.appendingPathComponent(item.filename) }
    static func copy(_ file: URL, video: Bool) throws -> DraftAttachment {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let ext = file.pathExtension.isEmpty ? (video ? "mov" : "jpg") : file.pathExtension
        let item = DraftAttachment(id: id, filename: "\(id.uuidString).\(ext)", isVideo: video)
        try FileManager.default.copyItem(at: file, to: url(item))
        return item
    }
}

struct ImportedPhoto: Transferable {
    let item: DraftAttachment
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { file in
            ImportedPhoto(item: try DraftFiles.copy(file.file, video: false))
        }
    }
}

private struct ImportedMovie: Transferable {
    let item: DraftAttachment
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { file in
            ImportedMovie(item: try DraftFiles.copy(file.file, video: true))
        }
    }
}

struct DraftMediaPicker: View {
    @Binding var attachments: [DraftAttachment]
    @Binding var loading: Bool
    @State private var selection: [PhotosPickerItem] = []
    @State private var errorMessage: String?
    @State private var preview: DraftAttachment?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos and videos").font(.headline).foregroundStyle(liyaInk)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    if attachments.count < 9 {
                        PhotosPicker(selection: $selection, maxSelectionCount: 9 - attachments.count,
                                     matching: .any(of: [.images, .videos])) {
                            VStack(spacing: 5) {
                                Image("avatar-camera").resizable().scaledToFit().frame(width: 42, height: 42)
                                Text("Add media").font(.caption.bold()).foregroundStyle(liyaAccent)
                            }.frame(width: 100, height: 120).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                        }.disabled(loading).accessibilityLabel("Add photos or videos")
                    }
                    ForEach(attachments) { item in
                        ZStack(alignment: .topTrailing) {
                            Button { preview = item } label: {
                                MediaThumbnail(item: item).frame(width: 100, height: 120).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel(item.isVideo ? "Preview video" : "Preview photo")
                            Button { attachments.removeAll { $0.id == item.id } } label: {
                                Image("close").resizable().scaledToFit().frame(width: 25, height: 25).padding(4)
                            }.buttonStyle(.plain).accessibilityLabel("Remove attachment")
                        }
                    }
                }
            }
            if loading { Text("Loading selected media…").font(.footnote).foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            Text("Up to 9 items. Media stays on this device.").font(.footnote).foregroundStyle(.secondary)
        }.sheet(item: $preview) { item in
            if item.isVideo { DraftVideoPreview(item: item) } else { DraftPhotoPreview(item: item) }
        }
        .onChange(of: selection) { items in
            guard !items.isEmpty, !loading else { return }
            loading = true
            errorMessage = nil
            Task { @MainActor in
                var failed = false
                for item in items.prefix(max(0, 9 - attachments.count)) {
                    do {
                        let movie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                        if movie, let value = try await item.loadTransferable(type: ImportedMovie.self) {
                            attachments.append(value.item)
                        } else if !movie, let value = try await item.loadTransferable(type: ImportedPhoto.self) {
                            attachments.append(value.item)
                        } else { failed = true }
                    } catch { failed = true }
                }
                selection = []
                loading = false
                if failed { errorMessage = "Some media could not be loaded. Please try selecting it again." }
            }
        }
    }
}

struct MediaThumbnail: View {
    let item: DraftAttachment
    @State private var videoCover: UIImage?
    var body: some View {
        ZStack {
            Color.black.opacity(0.1)
            if item.isVideo {
                if let videoCover { Image(uiImage: videoCover).resizable().scaledToFill() }
                Image("play").resizable().scaledToFit().frame(width: 42, height: 42)
            } else if let image = UIImage(contentsOfFile: DraftFiles.url(item).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text("Unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityLabel(item.isVideo ? "Video attachment" : "Photo attachment")
            .task(id: item.id) {
                guard item.isVideo else { return }
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: DraftFiles.url(item)))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 400)
                if let frame = try? await generator.image(at: .zero), !Task.isCancelled {
                    videoCover = UIImage(cgImage: frame.image)
                }
            }
    }
}


struct DraftVideoPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let item: DraftAttachment
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var reachedEnd = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player { PlayerView(player: player).accessibilityHidden(true) }
            DuoControlRegion { size in
              ScrollView {
               VStack {
                HStack {
                    Button { dismiss() } label: { Image("close").resizable().scaledToFit().frame(width: 30, height: 30).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Close video")
                    Spacer()
                    Text("Private draft video").foregroundStyle(.white).font(.headline)
                }
                Spacer()
                if player == nil { Text("Video unavailable").foregroundStyle(.white) }
                Button {
                    guard let player else { return }
                    if playing { player.pause() } else {
                        if reachedEnd { player.seek(to: .zero); reachedEnd = false }
                        player.play()
                    }
                    playing.toggle()
                } label: { Image(playing ? "pause" : "play").resizable().scaledToFit().frame(width: 50, height: 50) }
                    .buttonStyle(.plain).accessibilityLabel(playing ? "Pause video" : "Play video")
               }.padding(20).frame(maxWidth: .infinity).frame(minHeight: size.height)
              }
            }
        }.onAppear {
            let url = DraftFiles.url(item)
            if FileManager.default.fileExists(atPath: url.path) { player = AVPlayer(url: url) }
        }.onChange(of: scenePhase) { phase in
            if phase != .active { player?.pause(); playing = false }
        }.onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if let item = notification.object as? AVPlayerItem, item === player?.currentItem { playing = false; reachedEnd = true }
        }.onDisappear { player?.pause(); player = nil; playing = false }
    }
}
