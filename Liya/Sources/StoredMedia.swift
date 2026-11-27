import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct LiyaMediaFile: Hashable {
    enum Bucket: String, Hashable {
        case collection = "liya-example-media"
        case member = "liya-user-media"
    }

    let bucket: Bucket
    let path: String
    let viewer: UUID

    init?(bucket: Bucket, path: String, viewer: UUID?) {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let viewer, !path.isEmpty, !path.contains("\\"),
              segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        self.bucket = bucket
        self.path = path
        self.viewer = viewer
    }

    var storageURL: URL {
        LiyaMediaNetwork.projectURL
            .appendingPathComponent("storage/v1/object/authenticated")
            .appendingPathComponent(bucket.rawValue)
            .appendingPathComponent(path)
    }

    fileprivate var playbackURL: URL? {
        var parts = URLComponents()
        parts.scheme = "liya-video"
        parts.host = viewer.uuidString.lowercased()
        parts.path = "/\(bucket.rawValue)/\(path)"
        return parts.url
    }

    fileprivate init?(playbackURL: URL?) {
        guard let playbackURL, let parts = URLComponents(url: playbackURL, resolvingAgainstBaseURL: false),
              parts.scheme == "liya-video", let host = parts.host, let viewer = UUID(uuidString: host) else { return nil }
        let segments = parts.path.dropFirst().split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard segments.count == 2, let bucket = Bucket(rawValue: String(segments[0])) else { return nil }
        self.init(bucket: bucket, path: String(segments[1]), viewer: viewer)
    }
}

@MainActor
final class LiyaMovieReader: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    private weak var session: LiyaSession?
    private var transfers: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(session: LiyaSession) { self.session = session }

    func asset(for file: LiyaMediaFile) throws -> AVURLAsset {
        guard session?.userID == file.viewer, let url = file.playbackURL else { throw URLError(.userAuthenticationRequired) }
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return asset
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let file = LiyaMediaFile(playbackURL: request.request.url), let session else { return false }
        let id = ObjectIdentifier(request)
        transfers[id] = Task {
            defer { transfers[id] = nil }
            do {
                try await serve(request, file: file, session: session)
                if !Task.isCancelled && !request.isCancelled { request.finishLoading() }
            } catch {
                if !Task.isCancelled && !request.isCancelled { request.finishLoading(with: error) }
            }
        }
        return true
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        transfers.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }

    private func serve(_ request: AVAssetResourceLoadingRequest, file: LiyaMediaFile, session: LiyaSession) async throws {
        let demand = request.dataRequest
        var offset = demand.map { max($0.requestedOffset, $0.currentOffset) } ?? 0
        guard offset >= 0 else { throw URLError(.badServerResponse) }
        var end: Int64?
        if let demand, !demand.requestsAllDataToEndOfResource {
            let limit = demand.requestedOffset.addingReportingOverflow(Int64(demand.requestedLength))
            guard !limit.overflow else { throw URLError(.badServerResponse) }
            end = limit.partialValue
        }

        repeat {
            try Task.checkCancellation()
            let capacity: Int64 = demand == nil ? 1 : (offset == 0 ? 131_072 : 1_048_576)
            let remaining = (end ?? Int64.max) - offset
            guard remaining > 0 || request.contentInformationRequest != nil else { return }
            let length = max(1, min(capacity, remaining))
            let (bytes, response) = try await session.mediaResponse(for: file, range: offset...(offset + (length - 1)))
            try Task.checkCancellation()
            guard !request.isCancelled else { throw CancellationError() }

            if response.statusCode == 416, let header = response.value(forHTTPHeaderField: "Content-Range"),
               header.hasPrefix("bytes */"), let size = Int64(header.dropFirst(8)), size >= 0, offset >= size {
                try describe(request, file: file, response: response, size: size, seekable: true)
                return
            }
            if response.statusCode == 200 {
                let size = Int64(bytes.count)
                try describe(request, file: file, response: response, size: size, seekable: false)
                let stop = min(end ?? size, size)
                if let demand, offset < stop { demand.respond(with: bytes.subdata(in: Int(offset)..<Int(stop))) }
                return
            }

            let boundaries = response.value(forHTTPHeaderField: "Content-Range")?.split { " -/".contains($0) } ?? []
            guard response.statusCode == 206, boundaries.count == 4, boundaries[0] == "bytes",
                  Int64(boundaries[1]) == offset, let last = Int64(boundaries[2]), let size = Int64(boundaries[3]),
                  last >= offset, last < size, last - offset + 1 == Int64(bytes.count), Int64(bytes.count) <= length else {
                throw URLError(.badServerResponse)
            }
            try describe(request, file: file, response: response, size: size, seekable: true)
            guard let demand, remaining > 0 else { return }
            demand.respond(with: bytes)
            offset = last + 1
            end = min(end ?? size, size)
        } while offset < (end ?? Int64.max)
    }

    private func describe(_ request: AVAssetResourceLoadingRequest, file: LiyaMediaFile, response: HTTPURLResponse, size: Int64, seekable: Bool) throws {
        guard let info = request.contentInformationRequest else { return }
        let mimeType = response.mimeType.flatMap { UTType(mimeType: $0) }
        let fileType = UTType(filenameExtension: file.storageURL.pathExtension)
        let type = [mimeType, fileType].compactMap { $0 }.first { $0.conforms(to: .audiovisualContent) } ?? .movie
        if let allowed = info.allowedContentTypes, !allowed.isEmpty {
            guard let match = allowed.first(where: { UTType($0).map { type.conforms(to: $0) } ?? false }) else {
                throw URLError(.cannotDecodeContentData)
            }
            info.contentType = match
        } else { info.contentType = type.identifier }
        info.contentLength = size
        info.isByteRangeAccessSupported = seekable
    }
}
