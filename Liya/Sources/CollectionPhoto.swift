import SwiftUI

struct CollectionPhoto: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    let catalogIndex: Int
    var contentMode: ContentMode = .fit
    var avatarName: String? = nil

    var body: some View {
        Group {
            if let media = session.collectionMedia(in: session.photos, at: catalogIndex) {
                NetworkPhoto(media: media) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure: unavailable
                    case .empty: placeholder
                    @unknown default: unavailable
                    }
                }
            } else if session.catalogHasLoaded || session.catalogError != nil {
                unavailable
            } else {
                placeholder
            }
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
