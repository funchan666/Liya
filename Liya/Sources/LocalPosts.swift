import SwiftUI
import UIKit

struct PostTagSelector: View {
    @Environment(\.liyaWords) private var words
    @Binding var selection: [String]
    private let choices = ["Little Moments", "How I Feel", "Good Vibes"]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(choices + selection.filter { !choices.contains($0) }, id: \.self) { tag in
                    Button {
                        if selection.contains(tag) { selection.removeAll { $0 == tag } } else { selection.append(tag) }
                    } label: {
                        Text(verbatim: words.inserting(tag, into: "# %@")).font(LiyaType.text(.caption)).foregroundStyle(selection.contains(tag) ? liyaAccent : .secondary)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(selection.contains(tag) ? liyaAccent.opacity(0.13) : .white.opacity(0.75), in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(selection.contains(tag) ? .isSelected : [])
                }
            }
        }
    }
}

struct LocalPostCard: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let post: MomentDraft
    @State private var preview: DraftAttachment?
    @State private var confirmingDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NavigationLink { DeviceProfileView() } label: {
                    HStack(spacing: 10) {
                        if let sharedPost { SocialAvatar(personID: sharedPost.ownerID).frame(width: 42, height: 42).clipShape(Circle()) }
                        else if let avatar = store.avatar { MediaThumbnail(item: avatar).frame(width: 42, height: 42).clipShape(Circle()) }
                        else { HostedArtwork("app-mark").scaledToFill().frame(width: 42, height: 42).clipShape(Circle()) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.nickname.isEmpty ? words("Your profile") : store.nickname).font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(liyaInk)
                            Text(verbatim: words(isShared ? "Submitted to community" : "Private moment")).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(.plain)
                Spacer()
                NavigationLink { EditDraftView(draft: post) } label: { Text(verbatim: words("Edit")).font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent).frame(minHeight: 44) }
                    .buttonStyle(.plain)
                Button(words("Delete")) { confirmingDelete = true }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
            }
            if !post.text.isEmpty { Text(post.text).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading) }
            if let tags = post.tags, !tags.isEmpty { Text(tags.map { "# " + $0 }.joined(separator: "   ")).font(LiyaType.text(.caption)).foregroundStyle(liyaAccent) }
            if let sharedPost {
                SocialMediaStrip(post: sharedPost)
            } else if let attachments = post.attachments, !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { item in
                            Button { preview = item } label: {
                                MediaThumbnail(item: item).frame(width: 190, height: 180).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel(words(item.isVideo ? "Open video" : "Open photo"))
                        }
                    }
                }
            }
            if isShared, let owner = session.userID,
               let status = social.moderationText(kind: "post", id: SocialAttempt.draftPostID(owner: owner, draft: post)) {
                Text(verbatim: words(status)).font(LiyaType.text(.footnote)).foregroundStyle(.secondary)
            }
        }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .sheet(item: $preview) { item in
                if item.isVideo { DraftVideoPreview(item: item) } else { DraftPhotoPreview(item: item) }
            }
            .sheet(isPresented: $confirmingDelete) {
                LocalConfirmation(title: "Delete post?", message: "This unshared post will be removed. Its original media remains in Photos.", action: "Delete") {
                    store.deleteDraft(post.id); confirmingDelete = false
                } cancel: { confirmingDelete = false }
                .presentationDetents([.medium])
            }
    }
    private var sharedPost: SocialPost? {
        guard let owner = session.userID else { return nil }
        let id = SocialAttempt.draftPostID(owner: owner, draft: post)
        return social.posts.first { $0.id == id }
    }
    private var isShared: Bool { sharedPost != nil }
}

struct DraftPhotoPreview: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.dismiss) private var dismiss
    let item: DraftAttachment
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = UIImage(contentsOfFile: DraftFiles.url(item).path) {
                Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(words("Private photo"))
            } else { Text(verbatim: words("Photo unavailable")).foregroundStyle(.white) }
            DuoControlRegion { size in
              VStack {
                HStack {
                    Button { dismiss() } label: { HostedArtwork("close", labelWhileMissing: "Close").scaledToFit().frame(width: 30, height: 30).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel(words("Close photo"))
                    Spacer()
                }
                Spacer()
              }.padding(20).frame(width: size.width, height: size.height)
            }
        }
    }
}
