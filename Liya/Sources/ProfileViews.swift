import SwiftUI
import PhotosUI
import UIKit

struct ProfileHome: View {
    @Environment(\.locale) private var locale
    @Environment(\.liyaWords) private var words
    @Environment(\.liyaTabActive) private var tabActive
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var checkout: CoinCheckout
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var section = 0
    @State private var previewVideo: DraftAttachment?
    @State private var previewCommunityVideo: SocialMediaItem?
    @State private var profileOwner: UUID?
    @State private var ownPosts: [SocialPost] = []
    @State private var postsReady = false
    @State private var postsLoading = false
    @State private var postsUnavailable = false
    private var posts: [MomentDraft] { store.drafts.filter { $0.publishedLocally == true } }
    private var videos: [DraftAttachment] { posts.flatMap { $0.attachments ?? [] }.filter { $0.isVideo } }
    private var communityPosts: [SocialPost] { profileOwner == session.userID ? ownPosts : [] }
    private var communityVideos: [SocialMediaItem] {
        communityPosts.flatMap { post in
            post.mediaPaths.enumerated().compactMap { index, path in
                guard post.mediaKinds.indices.contains(index), post.mediaKinds[index] == "video" else { return nil }
                return SocialMediaItem(path: path, kind: "video", post: post)
            }
        }
    }
    var body: some View {
        ZStack {
            LiyaBackground()
            GeometryReader { geometry in
            let heroHeight = min(max(geometry.size.width * 0.95, 300), 440)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileHero(width: geometry.size.width, height: heroHeight, topInset: geometry.safeAreaInsets.top)
                    VStack(alignment: .leading, spacing: 12) {
                    Text(session.profile.flatMap { $0.displayName.isEmpty ? nil : $0.displayName } ?? words("Your profile"))
                        .font(LiyaType.text(.title2, weight: .bold)).foregroundStyle(checkout.isActive(.profileGlow) ? liyaAccent : liyaInk)
                    profileRelations
                    Text(session.profile.flatMap { $0.signature.isEmpty ? nil : $0.signature } ?? words("Add a little about yourself."))
                        .font(LiyaType.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let tags = session.profile?.tags, !tags.isEmpty { Text(tags.map { "# " + $0 }.joined(separator: "   ")).font(LiyaType.text(.caption)).foregroundStyle(liyaAccent) }
                    if let error = session.profileError {
                        Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red)
                        Button(words("Retry profile")) { Task { await session.refreshProfile() } }.foregroundStyle(liyaAccent)
                    }
                    HStack(spacing: 10) {
                        NavigationLink { SettingsView() } label: { ProfileHomeActionLabel(title: "Settings", icon: "profile-home-settings") }
                        NavigationLink { EditProfileView() } label: { ProfileHomeActionLabel(title: "Edit profile", icon: "profile-home-edit") }
                    }.buttonStyle(.plain)
                    ProfileHomeTabs(selection: $section)
                    if section == 0 {
                        if postsLoading && !postsReady { LiyaLoadingIndicator().frame(maxWidth: .infinity).padding(24) }
                        if postsUnavailable { profileNotice("Couldn't refresh your posts.") { await refreshProfileContent() } }
                        if postsReady && !postsUnavailable && communityPosts.isEmpty && posts.isEmpty {
                            profileEmpty(title: "No posts yet", detail: "Your posts will appear here.")
                        }
                        ForEach(communityPosts) { CommunityPostCard(post: $0) }
                        ForEach(posts) { post in LocalPostCard(post: post) }
                    } else {
                        if postsLoading && !postsReady { LiyaLoadingIndicator().frame(maxWidth: .infinity).padding(24) }
                        if postsUnavailable { profileNotice("Couldn't refresh your posts.") { await refreshProfileContent() } }
                        if postsReady && !postsUnavailable && videos.isEmpty && communityVideos.isEmpty {
                            profileEmpty(title: "No videos yet", detail: "Videos you share will appear here.")
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(Array(communityVideos.enumerated()), id: \.offset) { _, item in
                                Button { previewCommunityVideo = item } label: {
                                    SocialMediaThumbnail(item: item).frame(height: 145).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel(words("Play video"))
                            }
                            ForEach(videos) { item in
                                Button { previewVideo = item } label: {
                                    MediaThumbnail(item: item).frame(height: 145).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel(words("Preview video"))
                            }
                        }
                    }
                    }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity).padding(.horizontal, 20)
                        .padding(.bottom, 24 + tabBarClearance).modifier(AdaptiveContainerMargins())
                }
            }.refreshable { await refreshProfileContent() }.ignoresSafeArea(.container, edges: .top)
            }
        }.navigationBarHidden(true)
            .task(id: tabActive ? session.userID : nil) {
                guard tabActive, session.userID != nil else { return }
                await refreshProfileContent()
            }
            .sheet(item: $previewVideo) { item in DraftVideoPreview(item: item) }
            .sheet(item: $previewCommunityVideo) { item in SocialMediaPreview(item: item) }
    }

    private var profileRelations: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) { followersLink; Divider(); followingLink }
            } else {
                HStack(spacing: 0) {
                    followersLink
                    Divider().frame(height: 32)
                    followingLink
                }
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
    }

    private var memberCountsReady: Bool {
        session.userID != nil && social.connectionsOwner == session.userID && social.connectionsReady
    }

    private var followersLink: some View {
        NavigationLink { CommunityRelationList(title: "Followers", relation: "followers") } label: {
            ProfileHomeRelationLabel(title: "Followers", icon: "profile-home-people",
                                    count: memberCountsReady ? social.followers.count : nil,
                                    loading: social.connectionsLoading)
        }
    }

    private var followingLink: some View {
        NavigationLink { CommunityRelationList(title: "profile.following", relation: "following") } label: {
            ProfileHomeRelationLabel(title: "profile.following", icon: "profile-action-follow",
                                    count: followingCount, loading: social.connectionsLoading || session.catalogLoading || session.curatedFollowsLoading)
        }
    }

    private var followingCount: Int? {
        guard memberCountsReady, session.curatedFollowsReady else { return nil }
        return social.follows.count + session.curatedFollowing(in: store).count
    }

    private func profileEmpty(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            HostedArtwork("empty-art").scaledToFit().frame(width: 104, height: 96).accessibilityHidden(true)
            Text(verbatim: words(title)).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
            Text(verbatim: words(detail)).font(LiyaType.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 20)
    }

    private func profileNotice(_ title: String, retry: @escaping () async -> Void) -> some View {
        HStack(spacing: 12) {
            HostedArtwork("empty-art").scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
            Text(verbatim: words(title)).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(liyaInk).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { Task { await retry() } } label: {
                Text(verbatim: words("Try again")).font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(liyaAccent)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(liyaAccent.opacity(0.09), in: Capsule())
            }.buttonStyle(.plain)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
    }

    private func refreshProfileContent() async {
        profileOwner = session.userID
        ownPosts = []; postsReady = true; postsLoading = false; postsUnavailable = false
        async let members: Void = social.refreshConnections(session)
        if session.catalogError != nil { await session.refreshCatalog() }
        await session.refreshCuratedFollows(store: store)
        await members
    }

    private func profileHero(width: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        ZStack {
            Group {
                if let avatar = session.profileAvatar {
                    NetworkPhoto(media: avatar) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
                    }
                } else if let index = session.photos.firstIndex(where: { $0.id == "example-photo-012" }) {
                    CollectionPhoto(catalogIndex: index, contentMode: .fill)
                } else {
                    Color.clear
                }
            }.frame(width: width, height: height).clipped()
                .mask {
                    LinearGradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.68),
                        .init(color: .white.opacity(0.5), location: 0.86),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }.frame(width: width, height: height).clipped()
            .overlay(alignment: .top) {
                DuoControlRegion { _ in
                    HStack(spacing: 8) {
                        HostedArtwork("profile-title").scaledToFit().frame(width: 145, height: 44).accessibilityLabel(words("Profile"))
                        Spacer(minLength: 0)
                        NavigationLink { WalletView() } label: {
                            HStack(spacing: 6) {
                                HostedArtwork("wallet-coin").scaledToFit().frame(width: 31, height: 31).accessibilityHidden(true)
                                Group {
                                    if let balance = checkout.balance {
                                        Text(balance, format: .number)
                                    } else {
                                        Text(verbatim: words("My wallet"))
                                    }
                                }
                                .font(LiyaType.text(.subheadline, weight: .bold))
                                .monospacedDigit().foregroundStyle(.white).lineLimit(1)
                            }.padding(.leading, 7).padding(.trailing, 14).frame(minHeight: 46)
                                .background {
                                    if checkout.isActive(.profileGlow) {
                                        Capsule().fill(liyaGradient)
                                    } else {
                                        Capsule().fill(Color.black.opacity(0.48))
                                    }
                                }
                                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                        }.buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: words("My wallet")))
                        .accessibilityValue(checkout.balance.map { Text(verbatim: words.inserting($0.formatted(.number.locale(locale)), into: "%@ coins")) } ?? Text(verbatim: ""))
                    }.padding(.horizontal, 20).modifier(AdaptiveContainerMargins())
                }.frame(height: 48).padding(.top, topInset + 4)
            }
    }
}

private struct ProfileHomeRelationLabel: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.locale) private var locale
    let title: String
    let icon: String
    let count: Int?
    let loading: Bool

    var body: some View {
        HStack(spacing: 9) {
            HostedArtwork(icon).scaledToFit().frame(width: 31, height: 31).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if let count {
                    Text(count, format: .number)
                        .font(LiyaType.text(.title3, weight: .bold)).monospacedDigit()
                        .foregroundStyle(liyaInk)
                } else if loading {
                    LiyaLoadingIndicator(size: 16).accessibilityHidden(true)
                }
                Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: .medium))
                    .foregroundStyle(count == nil ? liyaInk : liyaInk.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: words(title)))
        .accessibilityValue(Text(verbatim: count.map { $0.formatted(.number.locale(locale)) } ?? ""))
    }
}

private struct ProfileHomeActionLabel: View {
    @Environment(\.liyaWords) private var words
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            HostedArtwork(icon).scaledToFit().frame(width: 31, height: 31).accessibilityHidden(true)
            Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(liyaInk).frame(maxWidth: .infinity, minHeight: 54).padding(.horizontal, 8)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(liyaAccent.opacity(0.12), lineWidth: 1))
    }
}

private struct ProfileHomeTabs: View {
    @Environment(\.liyaWords) private var words
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 10) {
            tab("Posts", icon: "profile-home-posts", index: 0)
            tab("Videos", icon: "profile-action-video", index: 1)
            Spacer(minLength: 0)
        }.padding(.top, 4)
    }

    private func tab(_ title: String, icon: String, index: Int) -> some View {
        Button { selection = index } label: {
            HStack(spacing: 6) {
                HostedArtwork(icon).scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
                Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: selection == index ? .semibold : .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selection == index ? liyaAccent : liyaInk.opacity(0.65))
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(selection == index ? liyaAccent.opacity(0.11) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? .isSelected : [])
    }
}

struct EditProfileView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.profileDetailVisible) private var detailVisible
    @State private var name = ""
    @State private var signature = ""
    @State private var tags: [String] = []
    @State private var tagInput = ""
    @State private var avatar: DraftAttachment?
    @State private var selection: PhotosPickerItem?
    @State private var loading = false
    @State private var error: String?
    @State private var initialized = false
    @State private var saving = false

    var body: some View {
        PageShell(title: "Edit profile") {
            VStack(alignment: .leading, spacing: 20) {
                photoSection
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: words("About you")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: words("Nickname")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                        TextField(words("What should we call you?"), text: $name)
                            .padding(14).frame(minHeight: 48)
                            .background(Color(red: 0.97, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 12))
                        if name.count > 80 { Text(verbatim: words("Keep your nickname under 80 characters.")).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(verbatim: words("Labels")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                            Spacer()
                            Text(verbatim: words.inserting(String(tags.count), into: "%@/6")).font(LiyaType.text(.caption)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        Button { tags.removeAll { $0 == tag } } label: {
                                            HStack(spacing: 5) {
                                                Text(verbatim: words.inserting(tag, into: "# %@")).font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(liyaAccent)
                                                HostedArtwork("close").scaledToFit().frame(width: 15, height: 15).accessibilityHidden(true)
                                            }.padding(.horizontal, 10).frame(minHeight: 44)
                                                .background(liyaAccent.opacity(0.09), in: Capsule())
                                        }.buttonStyle(.plain).accessibilityLabel(words.inserting(tag, into: "Remove label %@"))
                                    }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            TextField(words("Add a label"), text: $tagInput)
                                .padding(14).frame(minHeight: 48)
                                .background(Color(red: 0.97, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 12))
                            Button(words("Add")) { addTag() }
                                .font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaAccent)
                                .frame(minWidth: 48, minHeight: 48)
                                .disabled(tags.count >= 6 || tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: words("Introduction")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                        TextField(words("Share a little about yourself"), text: $signature, axis: .vertical)
                            .lineLimit(3...6).padding(14)
                            .background(Color(red: 0.97, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 12))
                        if signature.count > 500 { Text(verbatim: words("Keep your introduction under 500 characters.")).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                if let error { Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                if let error = session.profileError { Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                if session.profile == nil {
                    Button(words("Retry loading profile")) { Task { await session.refreshProfile(); initialize() } }
                        .font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                PrimaryButton(title: saving ? "Saving…" : "Save profile", disabled: loading || saving || session.profile == nil || !initialized || name.count > 80 || signature.count > 500) {
                    saving = true
                    Task {
                        if await session.saveProfile(name: name, signature: signature, tags: tags, avatar: avatar) {
                            store.nickname = name
                            store.signature = signature
                            store.saveProfileTags(tags)
                            if let avatar { store.saveAvatar(avatar) }
                            dismiss()
                        }
                        saving = false
                    }
                }
            }.padding(.top, 16).modifier(AdaptiveContainerMargins()).disabled(saving)
        }.onAppear { detailVisible.wrappedValue = true }
            .onDisappear { detailVisible.wrappedValue = false }
            .task { if session.profile == nil { await session.refreshProfile() }; initialize() }
            .onLiyaChange(of: session.profileLoading) { loading in if !loading { initialize() } }
            .onLiyaChange(of: selection) { item in
                guard let item else { return }
                loading = true; error = nil
                Task { @MainActor in
                    do {
                        if let photo = try await item.loadTransferable(type: ImportedPhoto.self) { avatar = photo.item }
                        else { error = "The photo could not be loaded. Please try again." }
                    } catch { self.error = "The photo could not be loaded. Please try again." }
                    selection = nil; loading = false
                }
            }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                profilePhoto
                    .frame(width: 80, height: 80).clipped().clipShape(Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: words("Profile photo")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                    Text(verbatim: words("Your account profile is private.")).font(LiyaType.text(.footnote)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $selection, matching: .images) {
                    Text(verbatim: words(loading ? "Loading…" : "Choose photo"))
                        .font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(liyaAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(liyaAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).disabled(loading || saving)
                CameraPhotoButton { item in avatar = item; error = nil } onError: { error = $0 }
                    .disabled(loading || saving)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private var profilePhoto: some View {
        if let avatar { MediaThumbnail(item: avatar) }
        else if let avatar = session.profileAvatar {
            NetworkPhoto(media: avatar) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
            }
        } else if let index = session.photos.firstIndex(where: { $0.id == "example-photo-012" }) {
            CollectionPhoto(catalogIndex: index, contentMode: .fill)
        } else { Color.clear }
    }

    private func addTag() {
        let value = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && !tags.contains(value) && tags.count < 6 { tags.append(value); tagInput = "" }
    }

    private func initialize() {
        guard !initialized, let profile = session.profile else { return }
        name = profile.displayName; signature = profile.signature; tags = profile.tags; initialized = true
    }
}

struct DeviceProfileView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Previous profile") {
            VStack(alignment: .leading, spacing: 14) {
                OfflineNote(text: "This earlier profile has not been uploaded.")
                if let avatar = store.avatar { MediaThumbnail(item: avatar).frame(width: 88, height: 88).clipped() }
                Text(store.nickname.isEmpty ? words("No nickname") : store.nickname).font(LiyaType.text(.headline))
                Text(store.signature.isEmpty ? words("No introduction") : store.signature)
                Text(store.profileTags.map { "# " + $0 }.joined(separator: "   ")).font(LiyaType.text(.caption))
            }.padding(.top, 12)
        }
    }
}

struct SettingsView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var calls: LiyaCalls
    @State private var confirmSignOut = false
    var body: some View {
        PageShell(title: "Settings") {
            VStack(alignment: .leading, spacing: 22) {
                SettingsGroup(title: "Account") {
                    NavigationLink { AccountView() } label: { SettingsRow("Account & Security", image: "setting-lock") }
                    SettingsDivider()
                    NavigationLink { PrivacyView() } label: { SettingsRow("Privacy", image: "setting-privacy") }
                }
                SettingsGroup(title: "Preferences") {
                    NavigationLink { LanguageSettingsView() } label: {
                        SettingsRow("Language", image: "setting-language")
                    }
                }
                SettingsGroup(title: "More") {
                    NavigationLink { SettingsYourSpaceView() } label: { SettingsRow("Your space", image: "setting-help") }
                    SettingsDivider()
                    NavigationLink { SettingsSupportView() } label: { SettingsRow("Help & legal", image: "setting-help") }
                }
                if let error = session.signOutError { Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
                Button { confirmSignOut = true } label: {
                    HStack(spacing: 8) {
                        if session.isSigningOut { LiyaLoadingIndicator(size: 24).accessibilityHidden(true) }
                        Text(verbatim: words(session.isSigningOut ? "Signing out…" : "Sign out")).font(LiyaType.text(.subheadline, weight: .semibold))
                    }.foregroundStyle(liyaAccent).frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
                }.disabled(session.isSigningOut || session.isDeletingAccount)
                NavigationLink { AccountView() } label: {
                    Text(verbatim: words("Delete account")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 50).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
                }.disabled(session.isSigningOut || session.isDeletingAccount)
            }.buttonStyle(.plain).padding(.top, 16).modifier(AdaptiveContainerMargins())
        }.sheet(isPresented: $confirmSignOut) {
            LocalConfirmation(title: "Sign out?", message: "Your local space will be available when you return on this device.", action: "Sign out") {
                confirmSignOut = false
                Task { _ = await session.signOutForAccountChange(store: store, social: social, calls: calls) }
            } cancel: { confirmSignOut = false }.presentationDetents([.medium, .large])
        }
    }

}

private struct LanguageSettingsView: View {
    @Environment(\.liyaWords) private var words
    private struct Option: Identifiable {
        let id: String
        let nativeName: String
        let englishName: String
    }
    @AppStorage("liya.language") private var language = "en"
    private let options: [Option] = [
        .init(id: "en", nativeName: "English", englishName: "English"),
        .init(id: "zh-Hans", nativeName: "简体中文", englishName: "Chinese"),
        .init(id: "es", nativeName: "Español", englishName: "Spanish"),
        .init(id: "fr", nativeName: "Français", englishName: "French"),
        .init(id: "ja", nativeName: "日本語", englishName: "Japanese")
    ]
    var body: some View {
        PageShell(title: "Language") {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: words("Choose your language")).font(LiyaType.text(.title3, weight: .bold)).foregroundStyle(liyaInk)
                Text(verbatim: words("Your selection applies to supported screens. Some content may remain in English."))
                    .font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(options) { option in
                        Button { language = option.id } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: option.nativeName).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                                    if option.id != "en" { Text(verbatim: words(option.englishName)).font(LiyaType.text(.caption)).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                HostedArtwork(language == option.id ? "consent-on" : "consent-off").scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                            }.padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 64)
                                .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityAddTraits(language == option.id ? .isSelected : [])
                    }
                }
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}

private struct SettingsYourSpaceView: View {
    var body: some View {
        PageShell(title: "Your space") {
            SettingsGroup(title: "Your content") {
                NavigationLink { DraftsView() } label: { SettingsRow("Private drafts", image: "diary-count") }
                SettingsDivider()
                NavigationLink { DeviceProfileView() } label: { SettingsRow("Previous profile", image: "nav-soft-profile") }
                SettingsDivider()
                NavigationLink { CommunityRelationList(title: "Followed creators", relation: "creators") } label: { SettingsRow("Followed creators", image: "profile-action-follow") }
            }.buttonStyle(.plain).padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}

private struct SettingsSupportView: View {
    var body: some View {
        PageShell(title: "Help & legal") {
            VStack(alignment: .leading, spacing: 22) {
                SettingsGroup(title: "Support") {
                    Link(destination: URL(string: "mailto:Liya2026support@liya.vip")!) {
                        SettingsRow("Email support: Liya2026support@liya.vip", image: "setting-help")
                    }
                    SettingsDivider()
                    NavigationLink { InformationView(title: "About Liya", message: "Liya is a place to share moments and connect with others.") } label: { SettingsRow("About Liya", image: "app-mark") }
                }
                SettingsGroup(title: "Legal") {
                    NavigationLink { LegalDocumentView(page: .privacy) } label: { SettingsRow("Privacy Policy", image: "setting-privacy") }
                    SettingsDivider()
                    NavigationLink { LegalDocumentView(page: .terms) } label: { SettingsRow("Terms of Service", image: "setting-lock") }
                }
            }.buttonStyle(.plain).padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    @Environment(\.liyaWords) private var words
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: words(title)).font(LiyaType.text(.caption, weight: .semibold)).tracking(0.8).textCase(.uppercase)
                .foregroundStyle(liyaInk.opacity(0.55)).padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 18))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var withIcon = true
    var body: some View {
        Divider().opacity(0.35).padding(.leading, withIcon ? 58 : 16)
    }
}

private struct SettingsRow: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.layoutDirection) private var layoutDirection
    let title: String
    var image: String?
    init(_ title: String, image: String? = nil) {
        self.title = title; self.image = image
    }
    var body: some View {
        HStack(spacing: 12) {
            if let image {
                HostedArtwork(image).scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
            }
            Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: .medium)).foregroundStyle(liyaInk)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HostedArtwork("back").scaledToFit().scaleEffect(x: layoutDirection == .rightToLeft ? 1 : -1, y: 1)
                .frame(width: 12, height: 12).opacity(0.42).accessibilityHidden(true)
        }.padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
    }
}

struct AccountView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var calls: LiyaCalls
    @State private var confirming = false
    @State private var checking = false
    private let deletionNotice = "Permanently remove your account and its data."

    var body: some View {
        PageShell(title: "Account & Security") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    HostedArtwork("setting-lock").scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: words("Your account")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                        if session.userID != nil, let label = session.savedAccountLabel(fallback: ""), !label.isEmpty {
                            Text(verbatim: label).font(LiyaType.detail).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).privacySensitive()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: words("Account actions")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                        .padding(.horizontal, 4)
                    Button { confirming = true } label: {
                        HStack(spacing: 12) {
                            HostedArtwork("setting-privacy").scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: words(session.isDeletingAccount || checking ? "Deleting account…" : "Delete account"))
                                    .font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(.red.opacity(0.85))
                                Text(verbatim: words(deletionNotice))
                                    .font(LiyaType.text(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if session.isDeletingAccount || checking { LiyaLoadingIndicator(size: 26).accessibilityHidden(true) }
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).disabled(session.isDeletingAccount || session.isSigningOut || checking || session.userID == nil)
                }
                if let error = session.deletionError { Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red) }
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
        .onLiyaChange(of: session.userID) { _ in confirming = false }
        .sheet(isPresented: $confirming) {
            LocalConfirmation(title: "Delete this account?", message: deletionNotice, action: "Delete account") {
                confirming = false
                guard let owner = session.userID, !checking else { return }
                checking = true
                Task {
                    defer { checking = false }
                    guard session.userID == owner else { return }
                    if await session.deleteAccount() {
                        calls.reset()
                        social.clearAccount()
                        store.inPreview = false
                        store.archiveAccountMaterial(owner)
                    }
                }
            } cancel: { confirming = false }.presentationDetents([.medium, .large])
        }
    }
}

struct PrivacyView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Privacy") {
            VStack(alignment: .leading, spacing: 18) {
                Text(verbatim: words("Manage the people and content you see."))
                    .font(LiyaType.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SettingsGroup(title: "Safety") {
                    NavigationLink { CommunityRelationList(title: "Blocked members", relation: "blocked") } label: {
                        SettingsRow("Blocked members", image: "setting-privacy")
                    }
                    SettingsDivider()
                    NavigationLink { HiddenCollectionProfilesView() } label: {
                        SettingsRow("Hidden collection profiles", image: "nav-soft-profile")
                    }
                    SettingsDivider()
                    NavigationLink { SubmittedReportsView() } label: {
                        SettingsRow("Submitted reports", image: "report")
                    }
                    SettingsDivider()
                    NavigationLink { ReportDraftsView() } label: {
                        SettingsRow("Unsent reports", image: "report")
                    }
                }.buttonStyle(.plain)
                Text(verbatim: words("Collection profile blocks and unsent reports are not synced."))
                    .font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}

private struct SubmittedReportsView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var reports: [SubmittedReport] = []
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var reportOwner: UUID?

    var body: some View {
        PageShell(title: "Submitted reports") {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: words("See the current status of reports you submitted from this account."))
                    .font(LiyaType.text(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(words("Refresh")) { Task { await load() } }
                    .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44).disabled(loading)
                if loading { LiyaLoadingIndicator(size: 28).accessibilityLabel(words("Loading reports")) }
                if let error {
                    Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Button(words("Try again")) { Task { await load() } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                } else if !loading && reports.isEmpty {
                    EmptyState(title: "No submitted reports", detail: "Reports sent from this account will appear here.")
                }
                ForEach(reportOwner == session.userID ? reports : []) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: words(reportTitle(report.kind))).font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(liyaInk)
                        Text(verbatim: words(report.reason)).font(LiyaType.detail).foregroundStyle(liyaInk)
                        Text(verbatim: words(reportStatus(report.status))).font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent)
                        Text(reportDate(report.createdAt)).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                Link(words("Email support: Liya2026support@liya.vip"), destination: URL(string: "mailto:Liya2026support@liya.vip")!)
                    .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }.task(id: session.userID) { await load() }
            .onLiyaChange(of: social.syncGeneration) { _ in Task { await load() } }
    }

    private func load() async {
        guard let owner = session.userID else { requestID = UUID(); reportOwner = nil; reports = []; loading = false; error = nil; return }
        if reportOwner != owner { reports = []; reportOwner = owner }
        let request = UUID(); requestID = request; loading = true; error = nil
        do {
            let result = try await social.submittedReports(session)
            guard session.userID == owner, requestID == request, !Task.isCancelled else { return }
            reports = result; loading = false
        } catch {
            guard session.userID == owner, requestID == request, !Task.isCancelled else { return }
            reports = []
            loading = false
            self.error = "Couldn't load your reports. Please try again."
        }
    }

    private func reportTitle(_ kind: String) -> String {
        switch kind {
        case "social": return "Community report"
        case "curated": return "Collection report"
        case "media_comment", "post_comment": return "Comment report"
        case "message": return "Message report"
        default: return "Report"
        }
    }

    private func reportStatus(_ status: String) -> String {
        switch status {
        case "pending": return "Received · awaiting review"
        case "resolved": return "Reviewed · action completed"
        case "dismissed": return "Reviewed · no action taken"
        default: return "Status unavailable"
        }
    }

    private func reportDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: value)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: value) else { return String(value.prefix(10)) }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct HiddenCollectionProfilesView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.locale) private var locale

    var body: some View {
        PageShell(title: "Hidden collection profiles") {
            VStack(spacing: 12) {
                if store.hiddenCollectionProfiles.isEmpty {
                    EmptyState(title: words("No hidden profiles"),
                               detail: words("Profiles you hide will appear here."))
                }
                ForEach(store.hiddenCollectionProfiles.sorted(), id: \.self) { index in
                    let photoID = session.photos.indices.contains(index) ? session.photos[index].id : nil
                    let name = photoID.map { session.curatedDisplayName(for: $0) }
                        ?? words("Liya collection")
                    HStack(spacing: 12) {
                        NavigationLink { CollectionAuthorView(index: index, displayName: name, mediaID: photoID) } label: {
                            HStack { CollectionPortrait(index: index); Text(verbatim: name).foregroundStyle(liyaInk) }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button { store.setBlocked(index, blocked: false) } label: {
                            Text(verbatim: words("Unblock")).font(LiyaType.text(.footnote, weight: .bold)).foregroundStyle(liyaAccent)
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(liyaAccent.opacity(0.08), in: Capsule())
                        }.buttonStyle(.plain)
                    }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.top, 12)
        }
    }
}

struct ReportDraftsView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Unsent reports") {
            VStack(spacing: 12) {
                OfflineNote(text: "These reports have not been submitted or reviewed.")
                if store.reports.isEmpty { EmptyState(title: "No report drafts", detail: "Unsent drafts will appear here.") }
                ForEach(store.reports) { report in
                    HStack {
                        VStack(alignment: .leading) { Text(report.videoIndex.map { "Example video \($0 + 1)" } ?? "Example \(report.targetType == "post" ? "post" : "profile") \(report.photoIndex + 1)").font(LiyaType.text(.headline)); Text(verbatim: words(report.reason)).font(LiyaType.detail) }
                        Spacer()
                        Button(words("Delete")) { store.deleteReport(report.id) }.font(LiyaType.text(.footnote, weight: .bold)).foregroundStyle(liyaAccent)
                    }.foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.top, 12)
        }
    }
}

struct InformationView: View {
    @Environment(\.liyaWords) private var words
    let title: String
    let message: String
    var body: some View {
        PageShell(title: title) {
            VStack(alignment: .leading, spacing: 14) {
                HostedArtwork(title == "About Liya" ? "app-mark" : "setting-help").scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
                Text(verbatim: words(title)).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                Text(verbatim: words(message)).font(LiyaType.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
                .padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}
