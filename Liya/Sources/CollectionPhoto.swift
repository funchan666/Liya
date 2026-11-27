import SwiftUI

struct CollectionPhoto: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    let catalogIndex: Int
    var contentMode: ContentMode = .fit
    var avatarName: String? = nil
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let url {
                NetworkPhoto(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure: unavailable
                    case .empty: placeholder
                    @unknown default: unavailable
                    }
                }
            } else if failed {
                unavailable
            } else {
                placeholder
            }
        }
        .task(id: "\(session.imageGeneration)-\(catalogIndex)") {
            url = nil; failed = false
            do {
                let signedURL = try await session.mediaURL(kind: "photo", index: catalogIndex)
                guard !Task.isCancelled else { return }
                url = signedURL
            } catch { if !Task.isCancelled { failed = true } }
        }
    }

    @ViewBuilder private var placeholder: some View {
        if let avatarName { MemberInitialsAvatar(name: avatarName) } else { Color.clear }
    }

    @ViewBuilder private var unavailable: some View {
        if let avatarName {
            MemberInitialsAvatar(name: avatarName)
        } else {
            Text(verbatim: words("Photo unavailable")).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}
