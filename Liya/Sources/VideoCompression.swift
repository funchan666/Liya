import Foundation
import AVFoundation

enum VideoCompression {
    // Leave headroom under the project's 50 MB per-object limit.
    static let uploadLimit: Int64 = 45_000_000
    struct Prepared {
        let url: URL
        let isTemporary: Bool
    }
    enum Failure: LocalizedError {
        case unreadable, tooLarge
        var errorDescription: String? {
            switch self {
            case .unreadable: return "This video could not be opened. The original remains on this device."
            case .tooLarge: return "The full video could not be compressed below the upload limit. Your original remains on this device."
            }
        }
    }

    static func prepare(_ source: URL) async throws -> Prepared {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size > 0 else { throw Failure.unreadable }
        if Int64(size) <= uploadLimit { return Prepared(url: source, isTemporary: false) }
        let asset = AVURLAsset(url: source)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
        let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard duration.isFinite, duration > 0, !sourceVideoTracks.isEmpty else { throw Failure.unreadable }
        for preset in [AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality, AVAssetExportPresetLowQuality] {
            try Task.checkCancellation()
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset), exporter.supportedFileTypes.contains(.mp4) else { continue }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("liya-\(UUID().uuidString).mp4")
            exporter.outputURL = output; exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true
            exporter.fileLengthLimit = uploadLimit
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    exporter.exportAsynchronously { continuation.resume() }
                }
            } onCancel: { exporter.cancelExport() }
            if Task.isCancelled { try? FileManager.default.removeItem(at: output); throw CancellationError() }
            if exporter.status == .completed,
               let outputSize = try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               outputSize > 0, Int64(outputSize) <= uploadLimit,
               let exportedDuration = try? await AVURLAsset(url: output).load(.duration) {
                let seconds = CMTimeGetSeconds(exportedDuration)
                // A size-limited export can truncate; never silently publish a partial video.
                let exportedAsset = AVURLAsset(url: output)
                let hasVideo = (try? await exportedAsset.loadTracks(withMediaType: .video))?.isEmpty == false
                let hasAudio = (try? await exportedAsset.loadTracks(withMediaType: .audio))?.isEmpty == false
                if seconds.isFinite && abs(seconds - duration) <= max(0.5, duration * 0.001) && hasVideo && (sourceAudioTracks.isEmpty || hasAudio) {
                    return Prepared(url: output, isTemporary: true)
                }
            }
            try? FileManager.default.removeItem(at: output)
        }
        throw Failure.tooLarge
    }
}
