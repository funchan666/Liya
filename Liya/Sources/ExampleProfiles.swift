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
            Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
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

struct CuratedFollowButton<Label: View>: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    let id: String
    let label: (Bool, String) -> Label
    @State private var retryFollowing: Bool?
    @State private var attempt: UUID?

    init(id: String, @ViewBuilder label: @escaping (Bool, String) -> Label) {
        self.id = id
        self.label = label
    }

    var body: some View {
        let following = session.isFollowingCurated(id, store: store)
        let busy = attempt != nil || session.curatedFollowPending.contains(id) || (!session.curatedFollowsReady && session.curatedFollowsLoading)
        let retry = retryFollowing != nil || !session.curatedFollowsReady
        Button {
            guard attempt == nil, let owner = session.userID else { return }
            let request = UUID()
            attempt = request
            let desired = retryFollowing ?? !following
            let refreshOnly = !session.curatedFollowsReady
            Task {
                guard attempt == request, session.userID == owner else { return }
                if refreshOnly {
                    if session.catalogError != nil { await session.refreshCatalog() }
                    guard attempt == request, session.userID == owner else { return }
                    await session.refreshCuratedFollows(store: store)
                } else {
                    let saved = await session.setCuratedFollow(desired, id: id, store: store)
                    guard attempt == request, session.userID == owner else { return }
                    retryFollowing = saved ? nil : desired
                }
                guard attempt == request, session.userID == owner else { return }
                attempt = nil
            }
        } label: {
            label(following, retry ? "Try again" : (following ? "Following" : "Follow"))
                .opacity(busy ? 0.2 : 1)
                .overlay { if busy { LiyaLoadingIndicator(size: 20).accessibilityHidden(true) } }
        }
        .buttonStyle(.plain)
        .disabled(busy || id.isEmpty)
        .accessibilityAddTraits(following ? .isSelected : [])
        .onLiyaChange(of: id) { _ in retryFollowing = nil; attempt = nil }
        .onLiyaChange(of: session.userID) { _ in retryFollowing = nil; attempt = nil }
    }
}

struct ExampleProfileView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
    let index: Int
    var displayName: String? = nil
    var introduction: String? = nil
    var mediaID: String? = nil
    @State private var options: CollectionSafetyTarget?
    @State private var connectionNotice: ConnectionNotice?

    var body: some View {
        if let mediaID {
            if let current = session.photos.firstIndex(where: { $0.id == mediaID }) {
                profile(at: current)
            } else {
                PageShell(title: "Profile") {
                    EmptyState(title: "Profile unavailable", detail: "Please try again when the content has loaded.")
                }
            }
        } else {
            profile(at: index)
        }
    }

    private func profile(at index: Int) -> some View {
        let photoID = session.photos.indices.contains(index) ? session.photos[index].id : nil
        let pairedCreator = photoID.flatMap { session.curatedCreator(for: $0) }
        let name = pairedCreator?.name ?? displayName ?? "Liya collection"
        let bio = introduction ?? pairedCreator?.caption ?? ""
        let videos = session.videos.indices.filter { videoIndex in
            guard let photoID, let creator = session.curatedVideoCreators[session.videos[videoIndex].id] else { return false }
            return creator.photoID == photoID
        }
        return ProfileDetailLayout(name: name, introduction: bio, showOptions: {
            guard let photoID else { return }
            options = CollectionSafetyTarget(mediaID: photoID, name: name, kind: .profile, ownerID: session.userID)
        }) {
            if let avatarIndex = ExampleAvatar.photoIndex(for: index, in: session.photos) {
                CloudPhoto(index: avatarIndex, contentMode: .fill)
            } else {
                Color.clear
            }
        } actions: {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            CuratedFollowButton(id: photoID ?? "") { following, title in
                                ProfileDetailActionLabel(title: title, style: following ? .following : .follow)
                            }.disabled(store.blockedExamples.contains(index))
                            NavigationLink { ExampleChatView(index: index) } label: {
                                ProfileDetailActionLabel(title: "Message", style: .message)
                            }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                        }
                        HStack(spacing: 10) {
                            Button { connectionNotice = .unavailable } label: { ProfileDetailActionLabel(title: "Voice call", style: .voice) }
                            Button { connectionNotice = .unavailable } label: { ProfileDetailActionLabel(title: "Video call", style: .video) }
                        }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                    }
        } content: {
                    if store.blockedExamples.contains(index) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Profile blocked").font(.headline).foregroundStyle(liyaInk)
                            Text("Unblock this profile to see their posts again.").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
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
            .sheet(item: $options) { ExampleOptionsView(target: $0) }
            .sheet(item: $connectionNotice) { notice in
                ConnectionNoticeSheet(notice: notice) { connectionNotice = nil }.presentationDetents([.medium, .large])
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
    @State private var text = ""
    @State private var loaded = false
    @State private var connectionNotice: ConnectionNotice?
    private var name: String {
        guard session.photos.indices.contains(index) else { return "Liya collection" }
        let id = session.photos[index].id
        return session.curatedDisplayName(for: id)
    }
    var body: some View {
        PageShell(title: "Messages") {
            VStack(alignment: .leading, spacing: 18) {
                NavigationLink { ExampleProfileView(index: index) } label: {
                    HStack(spacing: 12) {
                        ExampleAvatar(index: index, size: 48)
                        Text(name).font(.headline).foregroundStyle(liyaInk)
                        Spacer(minLength: 0)
                    }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                VStack(spacing: 12) {
                    Image("profile-action-message").resizable().scaledToFit().frame(width: 76, height: 76).accessibilityHidden(true)
                    Text("Say hello").font(.headline).foregroundStyle(liyaInk)
                    Text("Start a conversation when you're ready.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Write a message…", text: $text, axis: .vertical).lineLimit(1...5)
                        .padding(12).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                    Button { connectionNotice = .unavailable } label: {
                        Text("Send").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).frame(minHeight: 44).background(liyaGradient, in: Capsule())
                    }.buttonStyle(.plain).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(.top, 12)
        }
        .onAppear { if !loaded { text = store.messageDrafts[String(index)] ?? ""; loaded = true } }
        .onLiyaChange(of: text) { value in if loaded { store.saveMessageDraft(value, index: index) } }
        .onDisappear { if loaded { store.saveMessageDraft(text, index: index) } }
        .sheet(item: $connectionNotice) { notice in
            ConnectionNoticeSheet(notice: notice) { connectionNotice = nil }.presentationDetents([.medium, .large])
        }
    }
}

struct CollectionSafetyTarget: Identifiable {
    enum Kind: String { case profile, post }

    let mediaID: String
    let name: String
    let kind: Kind
    let ownerID: UUID?
    var id: String { mediaID }
}

struct ExampleOptionsView: View {
    private enum Step { case menu, report, confirmBlock, received, draftSaved }

    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
    let target: CollectionSafetyTarget
    @State private var step = Step.menu
    @State private var reason: String?
    @State private var reportID = UUID()
    @State private var sending = false
    @State private var failed = false

    private var index: Int? {
        guard session.userID == target.ownerID else { return nil }
        return session.photos.firstIndex { $0.id == target.mediaID }
    }

    private var reportTitle: String { target.kind == .post ? "Report post" : "Report profile" }
    private var title: String {
        switch step {
        case .menu: return target.kind == .post ? "Post options" : "Profile options"
        case .report: return reportTitle
        case .confirmBlock: return "Block this profile?"
        case .received: return "Report received."
        case .draftSaved: return "Draft saved"
        }
    }

    var body: some View {
        SafetyPanel(title: title, subject: target.name,
                    back: step == .report || step == .confirmBlock ? { step = .menu } : nil,
                    close: { dismiss() }, busy: sending) {
            if let index {
                ExampleAvatar(index: index, size: 46)
            } else {
                Image("profile-home-people").resizable().scaledToFit().frame(width: 46, height: 46)
            }
        } content: {
            if step == .received || step == .draftSaved {
                if step == .draftSaved {
                    Text("Your report is saved in Settings under Unsent reports.")
                        .font(.subheadline).foregroundStyle(liyaInk.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                SafetySubmitButton(title: "Done") { dismiss() }
            } else if let index {
                switch step {
                case .menu:
                    VStack(spacing: 0) {
                        SafetyActionRow(title: reportTitle, kind: .report) { step = .report }
                        Divider().padding(.leading, 56)
                        if store.blockedExamples.contains(index) {
                            SafetyActionRow(title: "Unblock", kind: .unblock) { setBlocked(false) }
                        } else {
                            SafetyActionRow(title: "Block profile", kind: .block) { step = .confirmBlock }
                        }
                    }
                case .confirmBlock:
                    Text("Their photo posts will be hidden. You can unblock them in Settings.")
                        .font(.body).foregroundStyle(liyaInk.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    SafetySubmitButton(title: "Block profile", destructive: true) { setBlocked(true) }
                    SafetySecondaryButton(title: "Cancel") { step = .menu }
                case .report:
                    reportForm
                case .received, .draftSaved:
                    EmptyView()
                }
            } else {
                Text("This profile is no longer available.").font(.body).foregroundStyle(liyaInk)
                SafetySubmitButton(title: "Done") { dismiss() }
            }
        }
        .onLiyaChange(of: session.userID) { owner in if owner != target.ownerID { dismiss() } }
    }

    private var reportForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a reason").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
            SafetyReasonList(selected: reason) { choice in
                guard !sending, choice != reason else { return }
                reason = choice
                reportID = UUID()
                failed = false
            }.disabled(sending)
            if failed {
                Text("Couldn't confirm the report. Please try again.")
                    .font(.footnote.weight(.medium)).foregroundStyle(liyaInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SafetySubmitButton(title: sending ? "Sending…" : "Send report", busy: sending,
                               disabled: reason == nil || sending) { sendReport() }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { draftButton; supportLink }
                VStack(spacing: 0) { draftButton; supportLink }
            }
        }
    }

    private var draftButton: some View {
        SafetySecondaryButton(title: "Save draft") {
            guard let index, let reason, step == .report, !sending else { return }
            store.saveReportDraft(index: index, reason: reason, targetType: target.kind.rawValue)
            step = .draftSaved
        }.disabled(reason == nil || sending)
    }

    private var supportLink: some View {
        Link("Contact support", destination: URL(string: "mailto:Liya2026support@liya.vip")!)
            .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent)
            .fixedSize(horizontal: true, vertical: false).frame(minHeight: 44)
    }

    private func sendReport() {
        guard let reason, index != nil, !sending, step == .report else { return }
        sending = true
        failed = false
        Task {
            defer { sending = false }
            guard let index else { return }
            let received = await session.submitReport(id: reportID, index: index, targetType: target.kind.rawValue, reason: reason)
            guard session.userID == target.ownerID else { return }
            if received { step = .received } else { failed = true }
        }
    }

    private func setBlocked(_ block: Bool) {
        guard let index else { return }
        if block, let owner = target.ownerID {
            store.queueBlockedUnfollow(target.mediaID, owner: owner)
            Task {
                guard session.userID == owner, store.hasCloudSpace(for: owner) else { return }
                await session.setCuratedFollow(false, id: target.mediaID, store: store)
            }
        }
        store.setBlocked(index, blocked: block)
        dismiss()
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
