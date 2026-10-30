import SwiftUI
import UIKit

struct PostTagSelector: View {
    @Binding var selection: [String]
    private let choices = ["Game Time", "Catch Moment", "New Player"]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { tag in
                    Button {
                        if selection.contains(tag) { selection.removeAll { $0 == tag } } else { selection.append(tag) }
                    } label: {
                        Text("# \(tag)").font(.caption).foregroundStyle(selection.contains(tag) ? liyaAccent : .secondary)
                            .padding(.horizontal, 10).frame(minHeight: 36)
                            .background(selection.contains(tag) ? liyaAccent.opacity(0.13) : .white.opacity(0.75), in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(selection.contains(tag) ? .isSelected : [])
                }
            }
        }
    }
}

struct LocalPostCard: View {
    @EnvironmentObject private var store: LocalStore
    let post: LocalDraft
    @State private var preview: DraftAttachment?
    @State private var confirmingDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let avatar = store.avatar { MediaThumbnail(item: avatar).frame(width: 42, height: 42).clipShape(Circle()) }
                else { Image("app-mark").resizable().scaledToFill().frame(width: 42, height: 42).clipShape(Circle()) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.nickname.isEmpty ? "Your local profile" : store.nickname).font(.subheadline.bold()).foregroundStyle(liyaInk)
                    Text("On this device · not shared").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink { EditDraftView(draft: post) } label: { Text("Edit").font(.caption.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44) }
                    .buttonStyle(.plain)
                Button("Delete") { confirmingDelete = true }.font(.caption.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
            }
            if !post.text.isEmpty { Text(post.text).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading) }
            if let tags = post.tags, !tags.isEmpty { Text(tags.map { "# " + $0 }.joined(separator: "   ")).font(.caption).foregroundStyle(liyaAccent) }
            if let attachments = post.attachments, !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { item in
                            Button { preview = item } label: {
                                MediaThumbnail(item: item).frame(width: 190, height: 180).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel(item.isVideo ? "Open video" : "Open photo")
                        }
                    }
                }
            }
        }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .sheet(item: $preview) { item in
                if item.isVideo { DraftVideoPreview(item: item) } else { DraftPhotoPreview(item: item) }
            }
            .sheet(isPresented: $confirmingDelete) {
                LocalConfirmation(title: "Delete local post?", message: "The post will be removed from this device. Its original media remains in Photos.", action: "Delete") {
                    store.deleteDraft(post.id); confirmingDelete = false
                } cancel: { confirmingDelete = false }
                .presentationDetents([.medium])
            }
    }
}

struct DraftPhotoPreview: View {
    @Environment(\.dismiss) private var dismiss
    let item: DraftAttachment
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = UIImage(contentsOfFile: DraftFiles.url(item).path) {
                Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Private photo")
            } else { Text("Photo unavailable").foregroundStyle(.white) }
            VStack {
                HStack {
                    Button { dismiss() } label: { Image("close").resizable().scaledToFit().frame(width: 30, height: 30).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Close photo")
                    Spacer()
                }
                Spacer()
            }.padding(20)
        }
    }
}
