import SwiftUI
import AVFoundation
import UIKit

struct ProfileDetailLayout<Hero: View, Actions: View, Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.profileDetailVisible) private var detailVisible
    let name: String
    let introduction: String
    let showOptions: () -> Void
    let hero: Hero
    let actions: Actions
    let content: Content

    init(name: String, introduction: String, showOptions: @escaping () -> Void,
         @ViewBuilder hero: () -> Hero, @ViewBuilder actions: () -> Actions,
         @ViewBuilder content: () -> Content) {
        self.name = name
        self.introduction = introduction
        self.showOptions = showOptions
        self.hero = hero()
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let heroHeight = min(max(geometry.size.width, 300), 460)
            ZStack(alignment: .top) {
                LiyaBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero.frame(width: geometry.size.width, height: heroHeight, alignment: .center)
                            .clipped()
                            .overlay(alignment: .bottom) {
                                LinearGradient(colors: [.clear, .white.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 64).allowsHitTesting(false)
                            }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(name).font(.title2.bold()).foregroundStyle(liyaInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if !introduction.isEmpty {
                                Text(introduction).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            actions
                            content
                        }
                        .frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
                        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 36)
                        .modifier(AdaptiveContainerMargins())
                    }
                }.ignoresSafeArea(edges: .top)
                DuoControlRegion { _ in
                    HStack {
                        Button { dismiss() } label: {
                            Image("back").renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white)
                                .frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Back")
                        Spacer(minLength: 0)
                        Text(name).font(.headline).foregroundStyle(.white).lineLimit(1)
                            .shadow(color: .black.opacity(0.7), radius: 4)
                        Spacer(minLength: 0)
                        Button(action: showOptions) {
                            Image("more").renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white)
                                .frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("More options")
                    }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                }.frame(height: 44)
            }
        }
        .navigationBarHidden(true)
        .onAppear { detailVisible.wrappedValue = true }
        .onDisappear { detailVisible.wrappedValue = false }
    }
}

struct ProfileContentTabs: View {
    @Binding var selection: Int
    var showPost = true
    var showVideo = true
    var body: some View {
        HStack(spacing: 28) {
            ForEach(Array(["Post", "Video"].enumerated()).filter { $0.offset == 0 ? showPost : showVideo }, id: \.offset) { index, title in
                Button { selection = index } label: {
                    Text(title).font(.subheadline.weight(selection == index ? .bold : .medium))
                        .foregroundStyle(selection == index ? liyaAccent : .secondary)
                        .underline(selection == index, color: liyaAccent)
                        .frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
            Spacer()
        }
    }
}

struct ProfileActionLabel: View {
    let title: String
    var warm = false
    var body: some View {
        Text(title).font(.subheadline.bold()).foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity).frame(minHeight: 46)
            .background {
                if warm {
                    Capsule().fill(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing))
                } else {
                    Capsule().fill(liyaGradient)
                }
            }
    }
}

struct ProfileDetailActionLabel: View {
    enum Style: Equatable { case follow, following, message, voice, video }
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let style: Style
    private var icon: String {
        switch style {
        case .follow, .following: return "profile-action-follow"
        case .message: return "profile-action-message"
        case .voice: return "profile-action-voice"
        case .video: return "profile-action-video"
        }
    }
    var body: some View {
        HStack(spacing: 7) {
            Image(icon).resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(style == .following ? liyaAccent : liyaInk)
        .frame(maxWidth: .infinity, minHeight: 54)
        .padding(.horizontal, 8)
        .background(style == .following ? Color(red: 0.93, green: 0.90, blue: 1.0) : Color.white.opacity(0.84),
                    in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(liyaAccent.opacity(style == .following ? 0.28 : 0.10), lineWidth: 1))
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(style == .following ? .isSelected : [])
    }
}

struct ProfileSingleVideoRow<Thumbnail: View>: View {
    let thumbnail: Thumbnail
    init(@ViewBuilder thumbnail: () -> Thumbnail) { self.thumbnail = thumbnail() }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                thumbnail.frame(width: 112, height: 126).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                videoDetails
            }
            VStack(alignment: .leading, spacing: 12) {
                thumbnail.frame(maxWidth: .infinity).frame(height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                videoDetails
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(liyaAccent.opacity(0.08), lineWidth: 1))
    }
    private var videoDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("profile-action-video").resizable().scaledToFit().frame(width: 34, height: 30).accessibilityHidden(true)
            Text("Video").font(.headline).foregroundStyle(liyaInk)
            Text("Watch this moment").font(.subheadline.weight(.medium)).foregroundStyle(liyaAccent)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
    }
}

// These IDs are fixed independently of catalog order so that a portrait can
// never also appear as another collection post. Photo 012 is the bundled
// default profile portrait and therefore belongs to the portrait pool too.
enum ExamplePhotoAllocation {
    private static let postIDs = (1...20).filter { $0 != 12 }.map { String(format: "example-photo-%03d", $0) }
    private static let portraitIDs = ["example-photo-012"] + (21...40).map { String(format: "example-photo-%03d", $0) }
    private static let authorPortraitIDs = (21...39).map { String(format: "example-photo-%03d", $0) }

    static func isPost(_ index: Int, in photos: [LiyaMedia]) -> Bool {
        guard photos.indices.contains(index), !portraitIDs.contains(photos[index].id) else { return false }
        let portraitKeys = Set(photos.filter { portraitIDs.contains($0.id) }.map(\.objectKey))
        return !portraitKeys.contains(photos[index].objectKey)
    }

    static func portraitIndex(for index: Int, in photos: [LiyaMedia]) -> Int? {
        guard photos.indices.contains(index) else { return nil }
        let portraitID: String
        if photos[index].id == "example-photo-012" {
            // An existing comment may still refer to this former post identity.
            portraitID = "example-photo-040"
        } else {
            guard isPost(index, in: photos), let position = postIDs.firstIndex(of: photos[index].id) else { return nil }
            portraitID = authorPortraitIDs[position]
        }
        guard let portraitIndex = photos.firstIndex(where: { $0.id == portraitID }) else { return nil }
        let postKeys = Set(photos.filter { postIDs.contains($0.id) }.map(\.objectKey))
        return postKeys.contains(photos[portraitIndex].objectKey) ? nil : portraitIndex
    }
}

struct ExampleAvatar: View {
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    var size: CGFloat = 44

    static func photoIndex(for index: Int, in photos: [LiyaMedia]) -> Int? {
        ExamplePhotoAllocation.portraitIndex(for: index, in: photos)
    }

    var body: some View {
        Group {
            if let photoIndex = Self.photoIndex(for: index, in: session.photos) {
                CloudPhoto(index: photoIndex, contentMode: .fill)
            } else {
                Color.clear
            }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct ExampleProfileView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
    let index: Int
    var displayName: String? = nil
    var introduction: String? = nil
    @State private var options = false
    @State private var callUnavailable = false
    @State private var confirmLocalFollow = false

    var body: some View {
        let photoID = session.photos.indices.contains(index) ? session.photos[index].id : nil
        let pairedCreator = ExampleVideoCreator.byVideoID.values.first { $0.photoID == photoID }
        let name = displayName ?? pairedCreator?.name ?? "Example profile \(index + 1)"
        let bio = introduction ?? pairedCreator?.caption ?? ""
        let videos = session.videos.indices.filter { videoIndex in
            guard let photoID, let creator = ExampleVideoCreator.byVideoID[session.videos[videoIndex].id] else { return false }
            return creator.photoID == photoID
        }
        return ProfileDetailLayout(name: name, introduction: bio, showOptions: { options = true }) {
            if let avatarIndex = ExampleAvatar.photoIndex(for: index, in: session.photos) {
                CloudPhoto(index: avatarIndex, contentMode: .fill)
            } else {
                Color.clear
            }
        } actions: {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                guard !store.blockedExamples.contains(index) else { return }
                                if store.followedExamples.contains(index) { store.toggleFollow(index) }
                                else { confirmLocalFollow = true }
                            } label: {
                                ProfileDetailActionLabel(title: store.followedExamples.contains(index) ? "Following" : "Follow", style: store.followedExamples.contains(index) ? .following : .follow)
                            }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                            NavigationLink { ExampleChatView(index: index) } label: {
                                ProfileDetailActionLabel(title: "Message", style: .message)
                            }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                        }
                        HStack(spacing: 10) {
                            Button { callUnavailable = true } label: { ProfileDetailActionLabel(title: "Voice call", style: .voice) }
                            Button { callUnavailable = true } label: { ProfileDetailActionLabel(title: "Video call", style: .video) }
                        }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                    }
        } content: {
                    if store.blockedExamples.contains(index) {
                        EmptyState(title: "Blocked", detail: "Unblock this example in More options to view its content.")
                    } else if !videos.isEmpty {
                            Text("Videos").font(.headline).foregroundStyle(liyaInk).padding(.top, 8)
                            if videos.count == 1, let videoIndex = videos.first {
                                Button { store.videoRequest = VideoRequest(index: videoIndex); dismiss() } label: {
                                    ProfileSingleVideoRow { CuratedVideoThumbnail(index: videoIndex) }
                                }.buttonStyle(.plain).accessibilityLabel("Play video")
                            } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                                ForEach(videos, id: \.self) { videoIndex in
                                    Button { store.videoRequest = VideoRequest(index: videoIndex); dismiss() } label: {
                                        CuratedVideoThumbnail(index: videoIndex).frame(height: 145).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain).accessibilityLabel("Play video")
                                }
                            }
                            }
                    }
        }
            .sheet(isPresented: $options) { ExampleOptionsView(index: index) }
            .sheet(isPresented: $callUnavailable) {
                LocalConfirmation(title: "Calling unavailable", message: "This profile isn't connected to a member account, so a call can't be placed.", action: "OK") {
                    callUnavailable = false
                } cancel: { callUnavailable = false }.presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $confirmLocalFollow) {
                LocalConfirmation(title: "Follow this profile?", message: "This profile isn't connected to a member account. Your follow won't be synced.", action: "Follow") {
                    if !store.blockedExamples.contains(index) && !store.followedExamples.contains(index) { store.toggleFollow(index) }
                    confirmLocalFollow = false
                } cancel: { confirmLocalFollow = false }.presentationDetents([.medium, .large])
            }
    }
}

private struct CuratedVideoThumbnail: View {
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            Image("play").resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .task(id: "\(session.catalogGeneration)-\(index)") {
                image = nil
                guard let url = try? await session.mediaURL(kind: "video", index: index), !Task.isCancelled else { return }
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 400)
                if let frame = try? await generator.image(at: .zero), !Task.isCancelled { image = UIImage(cgImage: frame.image) }
            }
    }
}

struct ExampleChatView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    private var name: String {
        guard session.photos.indices.contains(index) else { return "Collection" }
        let id = session.photos[index].id
        return ExampleVideoCreator.byVideoID.values.first { $0.photoID == id }?.name ?? "Collection"
    }
    var body: some View {
        PageShell(title: "Messages") {
            VStack(alignment: .leading, spacing: 18) {
                NavigationLink { ExampleProfileView(index: index) } label: {
                    HStack(spacing: 12) {
                        ExampleAvatar(index: index, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(.headline).foregroundStyle(liyaInk)
                            Text("Collection").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                VStack(spacing: 12) {
                    Image("profile-action-message").resizable().scaledToFit().frame(width: 76, height: 76).accessibilityHidden(true)
                    Text("This profile can't receive messages").font(.headline).foregroundStyle(liyaInk)
                    Text("Explore the community to start a conversation with a member.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink { CommunityMembersView() } label: {
                        Text("Find people").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 26).frame(minHeight: 46).background(liyaGradient, in: Capsule())
                    }.buttonStyle(.plain)
                }.frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 16)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20))
                if let draft = store.messageDrafts[String(index)], !draft.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unsent message").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(draft).font(.subheadline).foregroundStyle(liyaInk).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(.top, 12)
        }
    }
}

struct ExampleOptionsView: View {
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    let index: Int
    var reportTarget = "profile"
    var body: some View {
        NavigationStack {
            PageShell(title: "More options") {
                VStack(spacing: 14) {
                    NavigationLink { ReportDraftView(index: index, targetType: reportTarget) } label: { option(reportTarget == "post" ? "Report post" : "Report profile", image: "report") }
                        .buttonStyle(.plain)
                    Button {
                        store.setBlocked(index, blocked: !store.blockedExamples.contains(index)); dismiss()
                    } label: { option(store.blockedExamples.contains(index) ? "Unblock" : "Block", image: "setting-privacy") }
                        .buttonStyle(.plain)
                }.padding(.top, 12)
            }
        }
    }
    private func option(_ title: String, image: String) -> some View {
        HStack { Image(image).resizable().scaledToFit().frame(width: 28, height: 28); Text(title); Spacer() }
            .foregroundStyle(liyaInk).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ReportDraftView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    var targetType = "profile"
    @State private var selected: String?
    @State private var saved = false
    @State private var sending = false
    @State private var reportID = UUID()
    @State private var reportError: String?
    private let reasons = ["Sexual content", "Harassment", "Discrimination", "Incorrect content", "Other"]
    var body: some View {
        PageShell(title: "Report type") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "Send a report about this example content, or save an unsent draft. A review service has not yet been configured.")
                ForEach(reasons, id: \.self) { reason in
                    Button { selected = reason; saved = false; reportID = UUID(); reportError = nil } label: {
                        HStack { Text(reason); Spacer(); if selected == reason { Text("Selected").font(.caption.bold()).foregroundStyle(liyaAccent) } }
                            .foregroundStyle(liyaInk).padding(16).frame(maxWidth: .infinity)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(sending)
                }
                PrimaryButton(title: sending ? "Sending…" : "Send report", disabled: selected == nil || saved || sending) {
                    guard let selected else { return }
                    sending = true; reportError = nil
                    Task {
                        if await session.submitReport(id: reportID, index: index, targetType: targetType, reason: selected) { saved = true }
                        else { reportError = "The report could not be confirmed. Try again or save an unsent draft." }
                        sending = false
                    }
                }
                if let reportError { Text(reportError).font(.footnote).foregroundStyle(.red) }
                if saved { Text("Report received · review is not yet configured").font(.footnote).foregroundStyle(liyaAccent) }
                PrimaryButton(title: "Save unsent draft", disabled: selected == nil || saved || sending) {
                    guard let selected else { return }
                    store.saveReportDraft(index: index, reason: selected, targetType: targetType); reportError = "Draft saved. Your report has not been submitted."
                }
            }.padding(.top, 12)
        }
    }
}

struct SegmentedTabs: View {
    let items: [String]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                Button { selection = index } label: {
                    Text(LocalizedStringKey(items[index])).font(.subheadline.bold()).foregroundStyle(selection == index ? .white : liyaAccent)
                        .frame(maxWidth: .infinity).frame(minHeight: 42)
                        .background { if selection == index { Capsule().fill(liyaGradient) } }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(4).background(.white.opacity(0.86), in: Capsule())
    }
}
