import SwiftUI
import AVFoundation
import UIKit

struct ProfileDetailLayout<Hero: View, Actions: View, Content: View>: View {
    @Environment(\.liyaWords) private var words
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
                            Text(name).font(LiyaType.text(.title2, weight: .bold)).foregroundStyle(liyaInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if !introduction.isEmpty {
                                Text(introduction).font(LiyaType.detail).foregroundStyle(.secondary)
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
                            HostedArtwork("back", renderingMode: .template).scaledToFit().foregroundStyle(.white)
                                .frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(words("Back"))
                        Spacer(minLength: 0)
                        Text(name).font(LiyaType.text(.headline)).foregroundStyle(.white).lineLimit(1)
                            .shadow(color: .black.opacity(0.7), radius: 4)
                        Spacer(minLength: 0)
                        Button(action: showOptions) {
                            HostedArtwork("more", renderingMode: .template).scaledToFit().foregroundStyle(.white)
                                .frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(words("More options"))
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
    @Environment(\.liyaWords) private var words
    @Binding var selection: Int
    var showPost = true
    var showVideo = true
    var body: some View {
        HStack(spacing: 28) {
            ForEach(Array(["Post", "Video"].enumerated()).filter { $0.offset == 0 ? showPost : showVideo }, id: \.offset) { index, title in
                Button { selection = index } label: {
                    Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: selection == index ? .bold : .medium))
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
    @Environment(\.liyaWords) private var words
    let title: String
    var warm = false
    var body: some View {
        Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(.white)
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
    @Environment(\.liyaWords) private var words
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
        HStack(spacing: 8) {
            HostedArtwork(icon).scaledToFit().frame(width: 31, height: 31).accessibilityHidden(true)
            Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: .bold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(style == .message ? Color.white : liyaInk)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: style == .voice || style == .video ? 48 : 54)
        .background {
            if style == .message {
                Capsule().fill(Color(red: 0.27, green: 0.19, blue: 0.50))
            } else if style == .follow || style == .following {
                Capsule().fill(style == .following ? Color(red: 0.93, green: 0.90, blue: 1.0) : .white)
                    .overlay { Capsule().strokeBorder(liyaAccent.opacity(0.18)) }
            }
        }
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityAddTraits(style == .following ? .isSelected : [])
    }
}

enum ProfileContactAction: String, Identifiable {
    case message, voice, video
    var id: Self { self }
}

struct MutualFollowNotice: View {
    @Environment(\.liyaWords) private var words
    let action: ProfileContactAction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SafetyPanel(title: "Follow each other first", subject: nil, back: nil, close: { dismiss() }) {
            HostedArtwork("profile-action-follow").scaledToFit()
        } content: {
            Text(verbatim: words(detail)).font(LiyaType.reading).foregroundStyle(liyaInk.opacity(0.84))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button { dismiss() } label: {
                Text(verbatim: words("Got it")).font(LiyaType.action).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(red: 0.27, green: 0.19, blue: 0.50), in: Capsule())
            }.buttonStyle(.plain)
        }
    }

    private var detail: String {
        switch action {
        case .message: return "You can send this message once you both follow each other."
        case .voice: return "You can start a voice call once you both follow each other."
        case .video: return "You can start a video call once you both follow each other."
        }
    }
}

enum ProfileContactRecipient {
    case member(UUID)
    case collection(Int)
}

private enum ProfileContactFeedback: Identifiable {
    case mutual(ProfileContactAction)
    case unavailable(ProfileContactAction, reason: String, offersSettings: Bool = false)
    var id: String {
        switch self {
        case .mutual(let action): return action.rawValue
        case .unavailable(let action, let reason, _): return action.rawValue + reason
        }
    }
}

struct ProfileContactActions<Follow: View>: View {
    @Environment(\.liyaWords) private var words
    let recipient: ProfileContactRecipient
    let name: String
    @ViewBuilder let follow: () -> Follow
    @EnvironmentObject private var calls: LiyaCalls
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var notice: ProfileContactFeedback?
    @State private var dialTask: Task<Void, Never>?
    @State private var checking: ProfileContactAction?
    @State private var waitingCallID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            actionLayout {
                follow()
                NavigationLink {
                    switch recipient {
                    case .member(let id): CommunityConversationView(personID: id)
                    case .collection(let index): CommunityConversationView(collectionIndex: index, displayName: name)
                    }
                } label: {
                    ProfileDetailActionLabel(title: "Message", style: .message)
                }.buttonStyle(.plain)
            }
            actionLayout {
                callButton(.voice)
                if typeSize.isAccessibilitySize {
                    Divider().accessibilityHidden(true)
                } else {
                    Divider().frame(height: 25).accessibilityHidden(true)
                }
                callButton(.video)
            }
            .modifier(ContactBarSurface())
        }
        .sheet(item: $notice) { feedback in
            switch feedback {
            case .mutual(let action):
                MutualFollowNotice(action: action)
            case .unavailable(let action, let reason, let offersSettings):
                SafetyPanel(title: "Call unavailable", subject: nil, back: nil, close: { notice = nil }) {
                    HostedArtwork(action == .video ? "profile-action-video" : "profile-action-voice").scaledToFit()
                } content: {
                    Text(verbatim: words(reason)).font(LiyaType.reading).foregroundStyle(liyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                    actionLayout {
                        feedbackButton("Close") { notice = nil }
                        if offersSettings, let settings = URL(string: UIApplication.openSettingsURLString) {
                            feedbackButton("Open Settings") {
                                notice = nil
                                openURL(settings)
                            }
                        }
                    }
                }
            }
        }
        .onDisappear { cancelPendingCheck() }
        .onLiyaChange(of: scenePhase) { phase in
            if phase == .background { cancelPendingCheck() }
        }
        .fullScreenCover(item: waitingCall) { call in
            LiyaCallScreen(call: call).interactiveDismissDisabled()
        }
    }

    private var waitingCall: Binding<LiyaCall?> {
        Binding {
            guard let current = calls.call, current.id == waitingCallID else { return nil }
            return current
        } set: { updated in
            if updated == nil, let id = waitingCallID { calls.cancel(id) }
            waitingCallID = updated?.id
        }
    }

    private var actionLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
    }

    private func feedbackButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: words(title)).font(LiyaType.action).foregroundStyle(liyaInk)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 48)
                .modifier(ContactBarSurface()).contentShape(Capsule())
        }.buttonStyle(.plain)
    }

    private func cancelPendingCheck() {
        dialTask?.cancel()
        dialTask = nil
        checking = nil
    }

    private func callButton(_ action: ProfileContactAction) -> some View {
        let video = action == .video
        return Button {
            switch recipient {
            case .member(let id):
                guard checking == nil else { return }
                checking = action
                dialTask = Task {
                    let result = await calls.start(session, social: social, peer: id, kind: video ? .video : .voice, displayName: name)
                    guard !Task.isCancelled else {
                        if case .started(let id) = result { calls.cancel(id) }
                        return
                    }
                    checking = nil
                    dialTask = nil
                    switch result {
                    case .started(let id): waitingCallID = id
                    case .cancelled: break
                    case .notMutual: notice = .mutual(action)
                    case .failure(let reason):
                        notice = .unavailable(action, reason: reason)
                    case .permissionDenied(let reason):
                        notice = .unavailable(action, reason: reason, offersSettings: true)
                    }
                }
            case .collection:
                notice = .mutual(action)
            }
        } label: {
            ProfileDetailActionLabel(title: video ? "Video call" : "Voice call", style: video ? .video : .voice)
                .opacity(checking == action ? 0.26 : 1)
                .overlay { if checking == action { LiyaLoadingIndicator(size: 22).accessibilityHidden(true) } }
        }.buttonStyle(.plain).disabled(checking != nil)
    }
}

struct ContactBarSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape = RoundedRectangle(cornerRadius: 21, style: .continuous)

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.white, in: shape)
                .overlay { shape.strokeBorder(liyaInk.opacity(0.12)).allowsHitTesting(false) }
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26, *) {
                content.glassEffect(.regular.tint(Color.white.opacity(0.58)), in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
            #else
            content.background(.regularMaterial, in: shape)
            #endif
        }
    }
}

struct ProfileSingleVideoRow<Thumbnail: View>: View {
    @Environment(\.liyaWords) private var words
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
            HostedArtwork("profile-action-video").scaledToFit().frame(width: 34, height: 30).accessibilityHidden(true)
            Text(verbatim: words("Video")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
            Text(verbatim: words("Watch this moment")).font(LiyaType.text(.subheadline, weight: .medium)).foregroundStyle(liyaAccent)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
    }
}

enum CollectionPhotoRoles {
    private static let postIDs = (1...20).filter { $0 != 12 }.map { String(format: "example-photo-%03d", $0) }
    private static let portraitIDs = ["example-photo-012"] + (21...40).map { String(format: "example-photo-%03d", $0) }
    private static let authorPortraitIDs = (21...39).map { String(format: "example-photo-%03d", $0) }

    static func isPost(_ index: Int, in photos: [CatalogMediaAsset]) -> Bool {
        guard photos.indices.contains(index), !portraitIDs.contains(photos[index].id) else { return false }
        let portraitKeys = Set(photos.filter { portraitIDs.contains($0.id) }.map(\.storageObjectPath))
        return !portraitKeys.contains(photos[index].storageObjectPath)
    }

    static func portraitIndex(for index: Int, in photos: [CatalogMediaAsset]) -> Int? {
        guard photos.indices.contains(index) else { return nil }
        let portraitID: String
        if photos[index].id == "example-photo-012" {
            portraitID = "example-photo-040"
        } else {
            guard isPost(index, in: photos), let position = postIDs.firstIndex(of: photos[index].id) else { return nil }
            portraitID = authorPortraitIDs[position]
        }
        return portraitIndex(forMediaID: portraitID, in: photos)
    }

    static func portraitIndex(forMediaID portraitID: String, in photos: [CatalogMediaAsset]) -> Int? {
        guard authorPortraitIDs.contains(portraitID) || portraitID == "example-photo-040",
              let portraitIndex = photos.firstIndex(where: { $0.id == portraitID }) else { return nil }
        let postKeys = Set(photos.filter { postIDs.contains($0.id) }.map(\.storageObjectPath))
        return postKeys.contains(photos[portraitIndex].storageObjectPath) ? nil : portraitIndex
    }
}

struct CollectionPortrait: View {
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    var size: CGFloat = 44

    static func photoIndex(for index: Int, in photos: [CatalogMediaAsset]) -> Int? {
        CollectionPhotoRoles.portraitIndex(for: index, in: photos)
    }

    var body: some View {
        Group {
            if let photoIndex = Self.photoIndex(for: index, in: session.photos) {
                CollectionPhoto(catalogIndex: photoIndex, contentMode: .fill)
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

struct CollectionAuthorView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
    let index: Int
    var displayName: String? = nil
    var introduction: String? = nil
    var mediaID: String? = nil
    @State private var options: CollectionSafetyTarget?

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
        let name = photoID.map { session.curatedDisplayName(for: $0) } ?? displayName ?? "Liya collection"
        let bio = introduction ?? pairedCreator?.caption ?? ""
        let videos = session.videos.indices.filter { videoIndex in
            guard let photoID, let creator = session.curatedVideoCreators[session.videos[videoIndex].id] else { return false }
            return creator.photoID == photoID
        }
        let videoIDs = videos.map { session.videos[$0].id }
        return ProfileDetailLayout(name: name, introduction: bio, showOptions: {
            guard let photoID else { return }
            options = CollectionSafetyTarget(mediaID: photoID, name: name, kind: .profile, ownerID: session.userID)
        }) {
            if let avatarIndex = CollectionPortrait.photoIndex(for: index, in: session.photos) {
                CollectionPhoto(catalogIndex: avatarIndex, contentMode: .fill)
            } else {
                Color.clear
            }
        } actions: {
            if let photoID, !store.hiddenCollectionProfiles.contains(index) {
                ProfileContactActions(recipient: .collection(index), name: name) {
                    CuratedFollowButton(id: photoID) { following, title in
                        ProfileDetailActionLabel(title: title, style: following ? .following : .follow)
                    }
                }
            }
        } content: {
                    if store.hiddenCollectionProfiles.contains(index) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: words("Profile blocked")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                            Text(verbatim: words("Unblock this profile to see their posts again.")).font(LiyaType.detail).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    } else if !videos.isEmpty {
                        Text(verbatim: words("Videos")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk).padding(.top, 8)
                        ForEach(videos, id: \.self) { videoIndex in
                            VStack(alignment: .leading, spacing: 6) {
                                Button { store.videoRequest = VideoRequest(index: videoIndex); dismiss() } label: {
                                    ProfileSingleVideoRow { CuratedVideoThumbnail(index: videoIndex) }
                                }.buttonStyle(.plain).accessibilityLabel(words("Play video"))
                                MediaEngagementBar(mediaID: session.videos[videoIndex].id)
                            }
                        }
                    }
        }
        .task(id: videoIDs) {
            guard !store.hiddenCollectionProfiles.contains(index), !videoIDs.isEmpty else { return }
            await session.refreshMediaEngagement(ids: videoIDs)
        }
        .sheet(item: $options) { CollectionSafetySheet(target: $0) }
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
            HostedArtwork("play").scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
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

struct CollectionSafetyTarget: Identifiable {
    enum Kind: String { case profile, post }

    let mediaID: String
    let name: String
    let kind: Kind
    let ownerID: UUID?
    var id: String { mediaID }
}

struct CollectionSafetySheet: View {
    @Environment(\.liyaWords) private var words
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
                CollectionPortrait(index: index, size: 46)
            } else {
                HostedArtwork("profile-home-people").scaledToFit().frame(width: 46, height: 46)
            }
        } content: {
            if step == .received || step == .draftSaved {
                if step == .draftSaved {
                    Text(verbatim: words("Your report is saved in Settings under Unsent reports."))
                        .font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                SafetySubmitButton(title: "Done") { dismiss() }
            } else if let index {
                switch step {
                case .menu:
                    VStack(spacing: 0) {
                        SafetyActionRow(title: reportTitle, kind: .report) { step = .report }
                        Divider().padding(.leading, 56)
                        if store.hiddenCollectionProfiles.contains(index) {
                            SafetyActionRow(title: "Unblock", kind: .unblock) { setBlocked(false) }
                        } else {
                            SafetyActionRow(title: "Block profile", kind: .block) { step = .confirmBlock }
                        }
                    }
                case .confirmBlock:
                    Text(verbatim: words("Their photo posts will be hidden. You can unblock them in Settings."))
                        .font(LiyaType.reading).foregroundStyle(liyaInk.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    SafetySubmitButton(title: "Block profile", destructive: true) { setBlocked(true) }
                    SafetySecondaryButton(title: "Cancel") { step = .menu }
                case .report:
                    reportForm
                case .received, .draftSaved:
                    EmptyView()
                }
            } else {
                Text(verbatim: words("This profile is no longer available.")).font(LiyaType.reading).foregroundStyle(liyaInk)
                SafetySubmitButton(title: "Done") { dismiss() }
            }
        }
        .onLiyaChange(of: session.userID) { owner in if owner != target.ownerID { dismiss() } }
    }

    private var reportForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: words("Choose a reason")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
            SafetyReasonList(selected: reason) { choice in
                guard !sending, choice != reason else { return }
                reason = choice
                reportID = UUID()
                failed = false
            }.disabled(sending)
            if failed {
                Text(verbatim: words("Couldn't confirm the report. Please try again."))
                    .font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(liyaInk)
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
        Link(words("Contact support"), destination: URL(string: "mailto:Liya2026support@liya.vip")!)
            .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent)
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
    @Environment(\.liyaWords) private var words
    let items: [String]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                Button { selection = index } label: {
                    Text(verbatim: words(items[index])).font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(selection == index ? .white : liyaAccent)
                        .frame(maxWidth: .infinity).frame(minHeight: 42)
                        .background { if selection == index { Capsule().fill(liyaGradient) } }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(4).background(.white.opacity(0.86), in: Capsule())
    }
}
