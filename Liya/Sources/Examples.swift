import SwiftUI

/// Content images are fetched using a short-lived URL for the signed-in user.
struct CloudPhoto: View {
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    var contentMode: ContentMode = .fit
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure: unavailable
                    case .empty: Color.clear
                    @unknown default: unavailable
                    }
                }
            } else if failed {
                unavailable
            } else {
                Color.clear
            }
        }
        .task(id: "\(session.imageGeneration)-\(index)") {
            url = nil; failed = false
            do {
                let signedURL = try await session.mediaURL(kind: "photo", index: index)
                guard !Task.isCancelled else { return }
                url = signedURL
            } catch { if !Task.isCancelled { failed = true } }
        }
    }

    private var unavailable: some View {
        Text("Photo unavailable").font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}
