import SwiftUI
import UIKit
import CoreText
import CryptoKit
import Network

enum LiyaMediaNetwork {
    static let projectURL = URL(string: "https://hymfjhuglaqoftrcxfjx.supabase.co")!
    static let interfaceURL = projectURL.appendingPathComponent("storage/v1/object/public/liya-interface")
    static let edition = interfaceURL.appendingPathComponent("v1-00e15d2578c8")
    static let catalogDigest = "00e15d2578c8d4d6f6bbe100765b333e6a5ab7e65efbe74cd6c133ade6937d2d"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 50
        return URLSession(configuration: config)
    }()

    static func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == projectURL.scheme, url.host == projectURL.host,
              url.port == projectURL.port else { throw URLError(.badURL) }
        let authenticated = request.value(forHTTPHeaderField: "Authorization") != nil
        guard !authenticated || url.path.hasPrefix("/storage/v1/object/authenticated/") else { throw URLError(.badURL) }
        let redirectGuard: LiyaRedirectGuard? = authenticated ? LiyaRedirectGuard() : nil
        for attempt in 0...1 {
            do {
                try Task.checkCancellation()
                let (data, response) = try await session.data(for: request, delegate: redirectGuard)
                guard let http = response as? HTTPURLResponse, http.url?.scheme == projectURL.scheme,
                      http.url?.host == projectURL.host, http.url?.port == projectURL.port,
                      !authenticated || http.url == url else { throw URLError(.badServerResponse) }
                if attempt == 0, http.statusCode == 429 || (500...599).contains(http.statusCode) {
                    try await Task.sleep(nanoseconds: 700_000_000)
                    continue
                }
                return (data, http)
            } catch let error as URLError where attempt == 0 && (error.code == .timedOut || error.code == .networkConnectionLost) {
                try await Task.sleep(nanoseconds: 700_000_000)
            }
        }
        throw URLError(.badServerResponse)
    }

    static func data(at url: URL, digest: String? = nil) async throws -> Data {
        let (data, reply) = try await response(for: URLRequest(url: url))
        guard (200..<300).contains(reply.statusCode), !data.isEmpty else { throw URLError(.badServerResponse) }
        if let digest, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() != digest {
            throw URLError(.cannotDecodeContentData)
        }
        return data
    }
}

struct LiyaWording {
    var entries: [String: String] = [:]

    func callAsFunction(_ key: String) -> String {
        entries[key] ?? (key == "profile.following" ? "Following" : key)
    }

    func inserting(_ value: String, into key: String) -> String {
        let format = self(key)
        guard let token = ["%@", "%lld"].compactMap({ format.range(of: $0) }).first else { return format }
        return format.replacingCharacters(in: token, with: value)
    }
}

private struct LiyaWordingKey: EnvironmentKey {
    static let defaultValue = LiyaWording()
}

extension EnvironmentValues {
    var liyaWords: LiyaWording {
        get { self[LiyaWordingKey.self] }
        set { self[LiyaWordingKey.self] = newValue }
    }
}

@MainActor
final class InterfaceLibrary: ObservableObject {
    private struct Picture: Decodable {
        let file: String
        let width: Int
        let height: Int
        let scale: Int
        let sha256: String
    }

    private struct Typeface: Decodable {
        let file: String
        let name: String
        let sha256: String
    }

    private struct Catalog: Decodable {
        let images: [String: Picture]
        let fonts: [Typeface]
    }

    @Published private(set) var fontsReady = false
    @Published private(set) var connectionRevision = 0
    @Published private var catalog: Catalog?
    @Published private var wordingByLanguage: [String: [String: String]]?
    private var loadingWording = false
    private let cache = NSCache<NSString, UIImage>()
    private var downloads: [String: Task<UIImage, Error>] = [:]
    private var catalogRequest: Task<Catalog, Error>?
    private var registeringFonts = false
    private let monitor = NWPathMonitor()
    private var lastOnline: Bool?

    init() {
        cache.totalCostLimit = 48 * 1024 * 1024
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if online, self.lastOnline == false { self.connectionRevision += 1 }
                self.lastOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "liya.interface.connectivity"))
    }

    deinit { monitor.cancel() }

    func wording(in language: String) -> LiyaWording {
        LiyaWording(entries: wordingByLanguage?[language] ?? [:])
    }

    func prepareWording() async {
        guard wordingByLanguage == nil, !loadingWording else { return }
        loadingWording = true
        defer { loadingWording = false }
        let url = LiyaMediaNetwork.interfaceURL.appendingPathComponent("translations/v1-624140441db6/strings.json")
        let digest = "624140441db60d91bfd404c757e9f4374b232fde46b1b294688465d8a6da7191"
        do {
            let data = try await LiyaMediaNetwork.data(at: url, digest: digest)
            wordingByLanguage = try JSONDecoder().decode([String: [String: String]].self, from: data)
        } catch {
            return
        }
    }

    private func loadCatalog() async throws -> Catalog {
        if let catalog { return catalog }
        if let catalogRequest { return try await catalogRequest.value }
        let request = Task {
            let url = LiyaMediaNetwork.edition.appendingPathComponent("catalog.json")
            let bytes = try await LiyaMediaNetwork.data(at: url, digest: LiyaMediaNetwork.catalogDigest)
            return try JSONDecoder().decode(Catalog.self, from: bytes)
        }
        catalogRequest = request
        defer { catalogRequest = nil }
        let value = try await request.value
        catalog = value
        return value
    }

    func aspectRatio(for name: String) -> CGFloat? {
        guard let entry = catalog?.images[name], entry.height > 0 else { return nil }
        return CGFloat(entry.width) / CGFloat(entry.height)
    }

    func cachedImage(named name: String) -> UIImage? {
        cache.object(forKey: name as NSString)
    }

    func image(named name: String) async throws -> UIImage {
        if let image = cachedImage(named: name) { return image }
        if let download = downloads[name] { return try await download.value }
        let download = Task { () throws -> UIImage in
            let catalog = try await loadCatalog()
            guard let entry = catalog.images[name] else { throw URLError(.resourceUnavailable) }
            let url = LiyaMediaNetwork.edition.appendingPathComponent("art").appendingPathComponent(entry.file)
            let data = try await LiyaMediaNetwork.data(at: url, digest: entry.sha256)
            guard let image = UIImage(data: data, scale: CGFloat(entry.scale)) else { throw URLError(.cannotDecodeContentData) }
            return image
        }
        downloads[name] = download
        defer { downloads[name] = nil }
        let image = try await download.value
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: name as NSString, cost: cost)
        return image
    }

    func prepareFonts() async {
        guard !fontsReady, !registeringFonts else { return }
        registeringFonts = true
        defer { registeringFonts = false }
        do {
            let catalog = try await loadCatalog()
            try await withThrowingTaskGroup(of: (String, Data).self) { group in
                for font in catalog.fonts where UIFont(name: font.name, size: 16) == nil {
                    group.addTask {
                        let url = LiyaMediaNetwork.edition.appendingPathComponent("fonts").appendingPathComponent(font.file)
                        return (font.name, try await LiyaMediaNetwork.data(at: url, digest: font.sha256))
                    }
                }
                for try await (name, data) in group {
                    guard let provider = CGDataProvider(data: data as CFData),
                          let font = CGFont(provider), (font.postScriptName as String?) == name,
                          CTFontManagerRegisterGraphicsFont(font, nil) || UIFont(name: name, size: 16) != nil
                    else { throw URLError(.cannotDecodeContentData) }
                }
            }
            fontsReady = true
        } catch {
            fontsReady = false
        }
    }
}

struct HostedArtwork: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var library: InterfaceLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var picture: UIImage?
    @State private var resolvedName: String?
    private let name: String
    private let mode: Image.TemplateRenderingMode
    private let decorative: Bool
    private let labelWhileMissing: String?
    private let placeholderFill: Color

    init(_ name: String, renderingMode: Image.TemplateRenderingMode = .original, labelWhileMissing: String? = nil, placeholderFill: Color = .clear) {
        self.name = name
        self.mode = renderingMode
        self.decorative = false
        self.labelWhileMissing = labelWhileMissing
        self.placeholderFill = placeholderFill
    }

    init(decorative name: String, renderingMode: Image.TemplateRenderingMode = .original, placeholderFill: Color = .clear) {
        self.name = name
        self.mode = renderingMode
        self.decorative = true
        self.labelWhileMissing = nil
        self.placeholderFill = placeholderFill
    }

    var body: some View {
        Group {
            if let image = (resolvedName == name ? picture : nil) ?? library.cachedImage(named: name) {
                Image(uiImage: image).renderingMode(mode).resizable()
            } else if let labelWhileMissing {
                Text(verbatim: name == "apple-continue-english" ? labelWhileMissing : words(labelWhileMissing)).font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center).minimumScaleFactor(0.7)
            } else {
                placeholderFill.aspectRatio(library.aspectRatio(for: name), contentMode: .fit)
            }
        }
        .accessibilityHidden(decorative)
        .task(id: "\(name)/\(library.connectionRevision)/\(scenePhase == .background)") {
            guard scenePhase != .background else { return }
            if resolvedName == name, picture != nil { return }
            let result = try? await library.image(named: name)
            guard !Task.isCancelled else { return }
            resolvedName = name
            picture = result
        }
    }
}

struct NetworkPhoto<Content: View>: View {
    let media: LiyaMediaFile
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var library: InterfaceLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadedMedia: LiyaMediaFile?
    @State private var loadedGeneration: UUID?
    @State private var result: AsyncImagePhase = .empty

    init(media: LiyaMediaFile, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.media = media
        self.content = content
    }

    var body: some View {
        content(loadedMedia == media && loadedGeneration == session.imageGeneration && session.userID == media.viewer ? result : .empty)
            .task(id: "\(media.viewer)/\(media.bucket.rawValue)/\(media.path)/\(session.imageGeneration)/\(library.connectionRevision)/\(scenePhase == .background)") {
                guard scenePhase != .background, session.userID == media.viewer else { return }
                let generation = session.imageGeneration
                if loadedMedia == media, loadedGeneration == generation, result.image != nil { return }
                loadedMedia = media
                loadedGeneration = generation
                result = .empty
                do {
                    let (bytes, _) = try await session.mediaResponse(for: media)
                    guard let image = UIImage(data: bytes) else { throw URLError(.cannotDecodeContentData) }
                    guard !Task.isCancelled, session.userID == media.viewer, session.imageGeneration == generation else { return }
                    result = .success(Image(uiImage: image))
                } catch {
                    if !Task.isCancelled { result = .failure(error) }
                }
            }
    }
}
