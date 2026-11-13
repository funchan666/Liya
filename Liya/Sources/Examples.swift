import SwiftUI
import UIKit

/// Display supplied content directly from the app bundle.
struct CloudPhoto: View {
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    var contentMode: ContentMode = .fit
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                unavailable
            } else {
                Color.clear
            }
        }
        .task(id: "\(session.imageGeneration)-\(index)") {
            image = nil; failed = false
            do {
                let url = try await session.mediaURL(kind: "photo", index: index)
                guard !Task.isCancelled else { return }
                image = UIImage(contentsOfFile: url.path)
                failed = image == nil
            } catch { if !Task.isCancelled { failed = true } }
        }
    }

    private var unavailable: some View {
        Text("Photo unavailable").font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}
