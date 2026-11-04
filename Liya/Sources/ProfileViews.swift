import SwiftUI
import PhotosUI
import UserNotifications
import UIKit

private struct ProfileRelationRow: Decodable {
    let ownerID: UUID
    let targetID: UUID
    enum CodingKeys: String, CodingKey { case ownerID = "owner_id", targetID = "target_id" }
}

struct ProfileHome: View {
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var section = 0
    @State private var previewVideo: DraftAttachment?
    @State private var previewCommunityVideo: SocialMediaItem?
    @State private var profileOwner: UUID?
    @State private var profileLoadID = UUID()
    @State private var ownPosts: [SocialPost] = []
    @State private var postsReady = false
    @State private var postsLoading = false
    @State private var postsUnavailable = false
    @State private var relationCounts: (followers: Int, following: Int)?
    @State private var relationsUnavailable = false
    private var posts: [LocalDraft] { store.drafts.filter { $0.publishedLocally == true } }
    private var videos: [DraftAttachment] { posts.flatMap { $0.attachments ?? [] }.filter { $0.isVideo } }
    private var communityPosts: [SocialPost] { profileOwner == session.userID ? ownPosts : [] }
    private var communityVideos: [SocialMediaItem] {
        communityPosts.flatMap { post in
            post.mediaPaths.enumerated().compactMap { index, path in
                guard post.mediaKinds.indices.contains(index), post.mediaKinds[index] == "video" else { return nil }
                return SocialMediaItem(path: path, kind: "video")
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
                    Text(session.profile.flatMap { $0.displayName.isEmpty ? nil : $0.displayName } ?? "Your profile").font(.title2.bold()).foregroundStyle(liyaInk)
                    profileRelations
                    if relationsUnavailable {
                        profileNotice("Couldn't refresh your connections.") { await refreshProfileContent() }
                    }
                    Text(session.profile.flatMap { $0.signature.isEmpty ? nil : $0.signature } ?? "Add a little about yourself.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let tags = session.profile?.tags, !tags.isEmpty { Text(tags.map { "# " + $0 }.joined(separator: "   ")).font(.caption).foregroundStyle(liyaAccent) }
                    if let error = session.profileError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("Retry profile") { Task { await session.refreshProfile() } }.foregroundStyle(liyaAccent)
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
                                }.buttonStyle(.plain).accessibilityLabel("Play video")
                            }
                            ForEach(videos) { item in
                                Button { previewVideo = item } label: {
                                    MediaThumbnail(item: item).frame(height: 145).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel("Preview video")
                            }
                        }
                    }
                    }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity).padding(.horizontal, 20)
                        .padding(.bottom, 24 + tabBarClearance).modifier(AdaptiveContainerMargins())
                }
            }.refreshable { await refreshProfileContent() }.ignoresSafeArea(.container, edges: .top)
            }
        }.navigationBarHidden(true)
            .task(id: session.userID) { await refreshProfileContent() }
            .onLiyaChange(of: social.syncGeneration) { _ in Task { await refreshProfileContent() } }
            .onLiyaChange(of: social.loading) { loading in
                if !loading { Task { await refreshProfileContent() } }
            }
            .sheet(item: $previewVideo) { item in DraftVideoPreview(item: item) }
            .sheet(item: $previewCommunityVideo) { item in SocialMediaPreview(item: item) }
    }

    private var profileRelations: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { followersLink; followingLink }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 6) { followersLink; followingLink }
        }.frame(maxWidth: .infinity, alignment: .leading).buttonStyle(.plain)
    }

    private var followersLink: some View {
        NavigationLink { CommunityRelationList(title: "Followers", relation: "followers") } label: {
            ProfileHomeRelationLabel(title: "Followers", count: profileOwner == session.userID ? relationCounts.map { String($0.followers) } : nil, unavailable: relationsUnavailable)
        }
    }

    private var followingLink: some View {
        NavigationLink { CommunityRelationList(title: "Following", relation: "following") } label: {
            ProfileHomeRelationLabel(title: "Following", count: profileOwner == session.userID ? relationCounts.map { String($0.following) } : nil, unavailable: relationsUnavailable)
        }
    }

    private func profileEmpty(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image("empty-art").resizable().scaledToFit().frame(width: 104, height: 96).accessibilityHidden(true)
            Text(LocalizedStringKey(title)).font(.headline).foregroundStyle(liyaInk)
            Text(LocalizedStringKey(detail)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 20)
    }

    private func profileNotice(_ title: String, retry: @escaping () async -> Void) -> some View {
        HStack(spacing: 12) {
            Image("empty-art").resizable().scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
            Text(LocalizedStringKey(title)).font(.footnote.weight(.medium)).foregroundStyle(liyaInk).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { Task { await retry() } } label: {
                Text("Try again").font(.caption.weight(.semibold)).foregroundStyle(liyaAccent)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(liyaAccent.opacity(0.09), in: Capsule())
            }.buttonStyle(.plain)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
    }

    private func refreshProfileContent() async {
        guard let owner = session.userID else { return }
        let request = UUID()
        profileLoadID = request
        if profileOwner != owner {
            profileOwner = owner; ownPosts = []; postsReady = false; relationCounts = nil
        }
        postsLoading = true; postsUnavailable = false; relationsUnavailable = false
        do {
            var rows: [SocialPost] = []
            var offset = 0
            while true {
                let page: [SocialPost] = try await session.client.from("liya_posts")
                    .select("id,owner_id,body,tags,media_paths,media_kinds,created_at,updated_at")
                    .eq("owner_id", value: owner.uuidString).order("created_at", ascending: false)
                    .order("id", ascending: false).range(from: offset, to: offset + 499).execute().value
                rows.append(contentsOf: page)
                if page.count < 500 { break }; offset += 500
            }
            guard session.userID == owner, profileLoadID == request else { return }
            ownPosts = rows; postsReady = true; postsLoading = false
        } catch {
            guard session.userID == owner, profileLoadID == request else { return }
            postsLoading = false; postsUnavailable = true
        }
        do {
            func countRelations(column: String, order: String) async throws -> Int {
                var count = 0
                while true {
                    let page: [ProfileRelationRow] = try await session.client.from("liya_follows")
                        .select("owner_id,target_id").eq(column, value: owner.uuidString)
                        .order(order).range(from: count, to: count + 499).execute().value
                    count += page.count
                    if page.count < 500 { return count }
                }
            }
            let followers = try await countRelations(column: "target_id", order: "owner_id")
            let following = try await countRelations(column: "owner_id", order: "target_id")
            guard session.userID == owner, profileLoadID == request else { return }
            relationCounts = (followers, following)
        } catch {
            guard session.userID == owner, profileLoadID == request else { return }
            relationsUnavailable = true
        }
    }

    private func profileHero(width: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        ZStack {
            Group {
                if let url = session.profileAvatarURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Image("profile-default-photo").resizable().scaledToFill() }
                    }
                } else {
                    Image("profile-default-photo").resizable().scaledToFill()
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
                        Image("profile-title").resizable().scaledToFit().frame(width: 145, height: 44).accessibilityLabel("Profile")
                        Spacer(minLength: 0)
                        NavigationLink { WalletView() } label: {
                            HStack(spacing: 6) {
                                Image("wallet-coin").resizable().scaledToFit().frame(width: 31, height: 31).accessibilityHidden(true)
                                Text(session.coinBalance.map { $0.formatted() } ?? "—")
                                    .font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.white).lineLimit(1)
                            }.padding(.leading, 7).padding(.trailing, 14).frame(minHeight: 46)
                                .background(Color.black.opacity(0.48), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel("Wallet, \(session.coinBalance.map { $0.formatted() } ?? "balance unavailable") coins")
                    }.padding(.horizontal, 20).modifier(AdaptiveContainerMargins())
                }.frame(height: 48).padding(.top, topInset + 4)
            }
    }
}

private struct ProfileHomeRelationLabel: View {
    let title: String
    let count: String?
    let unavailable: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image("profile-home-people").resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
            if let count { Text(count).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(liyaInk) }
            else if unavailable { Text("Unavailable").font(.caption2.weight(.medium)).foregroundStyle(.secondary) }
            else { LiyaLoadingIndicator(size: 16) }
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10).frame(minHeight: 44)
        .background(.white.opacity(0.74), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileHomeActionLabel: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(icon).resizable().scaledToFit().frame(width: 31, height: 31).accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(liyaInk).frame(maxWidth: .infinity, minHeight: 54).padding(.horizontal, 8)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(liyaAccent.opacity(0.12), lineWidth: 1))
    }
}

private struct ProfileHomeTabs: View {
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
                Image(icon).resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
                Text(title).font(.subheadline.weight(selection == index ? .semibold : .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selection == index ? liyaAccent : liyaInk.opacity(0.65))
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(selection == index ? liyaAccent.opacity(0.11) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? .isSelected : [])
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var session: LiyaSession
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
                    Text("About you").font(.headline).foregroundStyle(liyaInk)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nickname").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                        TextField("What should we call you?", text: $name)
                            .padding(14).frame(minHeight: 48)
                            .background(Color(red: 0.97, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 12))
                        if name.count > 80 { Text("Keep your nickname under 80 characters.").font(.footnote).foregroundStyle(.red) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Labels").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                            Spacer()
                            Text("\(tags.count)/6").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        Button { tags.removeAll { $0 == tag } } label: {
                                            HStack(spacing: 5) {
                                                Text("# \(tag)").font(.caption.weight(.semibold)).foregroundStyle(liyaAccent)
                                                Image("close").resizable().scaledToFit().frame(width: 15, height: 15).accessibilityHidden(true)
                                            }.padding(.horizontal, 10).frame(minHeight: 44)
                                                .background(liyaAccent.opacity(0.09), in: Capsule())
                                        }.buttonStyle(.plain).accessibilityLabel("Remove label \(tag)")
                                    }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("Add a label", text: $tagInput)
                                .padding(14).frame(minHeight: 48)
                                .background(Color(red: 0.97, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 12))
                            Button("Add") { addTag() }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent)
                                .frame(minWidth: 48, minHeight: 48)
                                .disabled(tags.count >= 6 || tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Introduction").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                        TextField("Share a little about yourself", text: $signature, axis: .vertical)
                            .lineLimit(3...6).padding(14)
                            .background(Color(red: 0.97, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 12))
                        if signature.count > 500 { Text("Keep your introduction under 500 characters.").font(.footnote).foregroundStyle(.red) }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if let error = session.profileError { Text(error).font(.footnote).foregroundStyle(.red) }
                if session.profile == nil {
                    Button("Retry loading profile") { Task { await session.refreshProfile(); initialize() } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                PrimaryButton(title: saving ? "Saving…" : "Save profile", disabled: loading || saving || session.profile == nil || !initialized || name.count > 80 || signature.count > 500) {
                    saving = true
                    Task {
                        if await session.saveProfile(name: name, signature: signature, tags: tags, avatar: avatar) { dismiss() }
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
                    Text("Profile photo").font(.headline).foregroundStyle(liyaInk)
                    Text("Your account profile is private.").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $selection, matching: .images) {
                    Text(loading ? "Loading…" : "Choose photo")
                        .font(.caption.weight(.semibold)).foregroundStyle(liyaAccent)
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
        else if let url = session.profileAvatarURL {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                Image("profile-default-photo").resizable().scaledToFill()
            }
        } else { Image("profile-default-photo").resizable().scaledToFill() }
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
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Previous profile") {
            VStack(alignment: .leading, spacing: 14) {
                OfflineNote(text: "This earlier profile has not been uploaded.")
                if let avatar = store.avatar { MediaThumbnail(item: avatar).frame(width: 88, height: 88).clipped() }
                Text(store.nickname.isEmpty ? "No nickname" : store.nickname).font(.headline)
                Text(store.signature.isEmpty ? "No introduction" : store.signature)
                Text(store.profileTags.map { "# " + $0 }.joined(separator: "   ")).font(.caption)
            }.padding(.top, 12)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var checkout: CoinCheckout
    @EnvironmentObject private var calls: LiyaCalls
    @State private var confirmSignOut = false
    @State private var signingOut = false
    @State private var signOutError: String?
    var body: some View {
        PageShell(title: "Settings") {
            VStack(alignment: .leading, spacing: 22) {
                SettingsGroup(title: "Account") {
                    NavigationLink { AccountView() } label: { SettingsRow("Account & Security", image: "setting-lock") }
                    SettingsDivider()
                    NavigationLink { PrivacyView() } label: { SettingsRow("Privacy", image: "setting-privacy") }
                    SettingsDivider()
                    NavigationLink { CommunityJoinView() } label: {
                        SettingsRow(social.isJoined(session) ? "Community profile" : "Set up community profile", image: "setting-privacy")
                    }
                }
                SettingsGroup(title: "Preferences") {
                    NavigationLink { NotificationSettingsView() } label: {
                        SettingsRow("Notifications", image: "setting-notification")
                    }
                    SettingsDivider()
                    NavigationLink { LanguageSettingsView() } label: {
                        SettingsRow("Language", image: "setting-language")
                    }
                }
                SettingsGroup(title: "More") {
                    NavigationLink { SettingsYourSpaceView() } label: { SettingsRow("Your space", image: "setting-help") }
                    SettingsDivider()
                    NavigationLink { SettingsSupportView() } label: { SettingsRow("Help & legal", image: "setting-help") }
                }
                if let error = signOutError ?? session.signOutError { Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.red) }
                Button { confirmSignOut = true } label: {
                    HStack(spacing: 8) {
                        if signingOut { LiyaLoadingIndicator(size: 24).accessibilityHidden(true) }
                        Text(LocalizedStringKey(signingOut ? "Signing out…" : "Sign out")).font(.subheadline.weight(.semibold))
                    }.foregroundStyle(liyaAccent).frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
                }.disabled(signingOut || session.isDeletingAccount)
                NavigationLink { AccountView() } label: {
                    Text("Delete account").font(.subheadline.weight(.semibold)).foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 50).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
                }.disabled(signingOut || session.isDeletingAccount)
            }.buttonStyle(.plain).padding(.top, 16).modifier(AdaptiveContainerMargins())
        }.sheet(isPresented: $confirmSignOut) {
            LocalConfirmation(title: "Sign out?", message: session.isGuest ? "This guest account has no recovery method. If you sign out, you won't be able to return to it." : "You can sign in again with the same account whenever you're ready.", action: "Sign out") {
                confirmSignOut = false; signingOut = true; signOutError = nil
                Task { await signOut() }
            } cancel: { confirmSignOut = false }.presentationDetents([.medium, .large])
        }
    }

    private func signOut() async {
        defer { signingOut = false }
        guard let owner = session.userID else { return }
        guard calls.call == nil else { signOutError = "End your call before signing out."; return }
        guard !(await checkout.hasUnfinishedPurchase(for: owner)) else {
            signOutError = "A purchase is still pending. Resolve it before signing out."; return
        }
        guard await LiyaVoIP.shared.unregisterForSignOut() else {
            signOutError = "Couldn't disconnect call notifications. Please try again."; return
        }
        if await session.signOut() {
            await calls.reset(); social.clearAccount(); store.inPreview = false; store.archiveAccountMaterial(owner)
        } else {
            await LiyaVoIP.shared.updateRegistration()
        }
    }
}

private struct LanguageSettingsView: View {
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
                Text("Choose your language").font(.title3.bold()).foregroundStyle(liyaInk)
                Text("Your selection applies to supported screens. Some content may remain in English.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(options) { option in
                        Button { language = option.id } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: option.nativeName).font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                                    if option.id != "en" { Text(LocalizedStringKey(option.englishName)).font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(language == option.id ? "consent-on" : "consent-off")
                                    .resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                            }.padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 64)
                                .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityAddTraits(language == option.id ? .isSelected : [])
                    }
                }
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}

private struct NotificationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        PageShell(title: "Notifications") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image("setting-notification").resizable().scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device alerts").font(.headline).foregroundStyle(liyaInk)
                        Text(LocalizedStringKey(statusText)).font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
                Text("Push delivery for messages and activity is not available yet. Call notifications have separate settings.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error { Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.red) }
                if status == .notDetermined {
                    PrimaryButton(title: busy ? "Checking…" : "Allow notifications", disabled: busy) {
                        busy = true; error = nil
                        Task {
                            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
                            catch { self.error = "Couldn't update notification access. Please try again." }
                            await refresh(); busy = false
                        }
                    }
                } else if status != nil {
                    PrimaryButton(title: "Open system settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else {
                    LiyaLoadingIndicator(size: 24)
                }
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }.task { await refresh() }
            .onLiyaChange(of: scenePhase) { phase in if phase == .active { Task { await refresh() } } }
    }
    private var statusText: String {
        switch status {
        case .notDetermined: return "Not requested"
        case .denied: return "Notifications off"
        case .authorized, .provisional, .ephemeral: return "Notifications allowed"
        default: return "Checking access…"
        }
    }
    private func refresh() async { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
}

private struct SettingsYourSpaceView: View {
    var body: some View {
        PageShell(title: "Your space") {
            SettingsGroup(title: "Your content") {
                NavigationLink { DraftsView() } label: { SettingsRow("Private drafts", image: "diary-count") }
                SettingsDivider()
                NavigationLink { DeviceProfileView() } label: { SettingsRow("Previous profile", image: "nav-soft-profile") }
                SettingsDivider()
                NavigationLink { ExampleListView(title: "Saved examples", blocked: false) } label: { SettingsRow("Saved collection", image: "video-like-on") }
            }.buttonStyle(.plain).padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}

private struct SettingsSupportView: View {
    var body: some View {
        PageShell(title: "Help & legal") {
            VStack(alignment: .leading, spacing: 22) {
                SettingsGroup(title: "Support") {
                    NavigationLink { InformationView(title: "Help & Support", message: "A support channel has not been configured.") } label: { SettingsRow("Help & Support", image: "setting-help") }
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
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title)).font(.caption.weight(.semibold)).tracking(0.8).textCase(.uppercase)
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
    @Environment(\.layoutDirection) private var layoutDirection
    let title: String
    var image: String?
    init(_ title: String, image: String? = nil) {
        self.title = title; self.image = image
    }
    var body: some View {
        HStack(spacing: 12) {
            if let image {
                Image(image).resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
            }
            Text(LocalizedStringKey(title)).font(.subheadline.weight(.medium)).foregroundStyle(liyaInk)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Image("back").resizable().scaledToFit().scaleEffect(x: layoutDirection == .rightToLeft ? 1 : -1, y: 1)
                .frame(width: 12, height: 12).opacity(0.42).accessibilityHidden(true)
        }.padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
    }
}

struct AccountView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var checkout: CoinCheckout
    @EnvironmentObject private var calls: LiyaCalls
    @State private var confirming = false
    @State private var checking = false
    @State private var purchaseError: String?
    var body: some View {
        PageShell(title: "Account & Security") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image("setting-lock").resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.isGuest ? "Guest account" : "Your account").font(.headline).foregroundStyle(liyaInk)
                        Text(session.isGuest ? "No recovery method is linked." : "Your sign-in method keeps your account accessible.").font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))

                Text(session.isGuest ? "You can't return to this account after signing out or deleting it." : "You can sign in again unless you delete your account.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Account actions").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                        .padding(.horizontal, 4)
                    Button { confirming = true } label: {
                        HStack(spacing: 12) {
                            Image("setting-privacy").resizable().scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(session.isDeletingAccount ? "Deleting account…" : (checking ? "Checking purchases…" : "Delete account")))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.red.opacity(0.85))
                                Text("Permanently remove your account and its data.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if session.isDeletingAccount || checking { LiyaLoadingIndicator(size: 26).accessibilityHidden(true) }
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).disabled(session.isDeletingAccount || checking || session.userID == nil)
                }
                if let error = session.deletionError ?? purchaseError { Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.red) }
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }.sheet(isPresented: $confirming) {
            LocalConfirmation(title: "Delete this account?", message: "Your account, posts, messages, uploaded media and coins will be permanently deleted. This account cannot be restored.", action: "Delete account") {
                confirming = false; checking = true; purchaseError = nil
                Task {
                    guard let owner = session.userID else { checking = false; return }
                    if calls.call != nil {
                        purchaseError = "End your call before deleting your account."
                    } else if await checkout.hasUnfinishedPurchase(for: owner) {
                        purchaseError = "An Apple purchase is still pending or cannot be matched. Resolve it before deleting this account."
                    } else if await session.deleteAccount() {
                        await calls.reset(); social.clearAccount(); store.inPreview = false; store.archiveAccountMaterial(owner)
                    }
                    checking = false
                }
            } cancel: { confirming = false }.presentationDetents([.medium])
        }
    }
}

struct FollowersView: View {
    var body: some View {
        PageShell(title: "Followers") {
            VStack(spacing: 14) {
                OfflineNote(text: "Following between real accounts is not connected yet. No followers are simulated.")
                EmptyState(title: "Followers unavailable", detail: "Your followers will appear when the service is connected.")
            }.padding(.top, 12)
        }
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Privacy") {
            VStack(alignment: .leading, spacing: 18) {
                Text("Manage the people and content you see.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SettingsGroup(title: "Safety") {
                    NavigationLink { CommunityRelationList(title: "Blocked members", relation: "blocked") } label: {
                        SettingsRow("Blocked members", image: "setting-privacy")
                    }
                    SettingsDivider()
                    NavigationLink { ExampleListView(title: "Blocked examples", blocked: true) } label: {
                        SettingsRow("Hidden collection profiles", image: "nav-soft-profile")
                    }
                    SettingsDivider()
                    NavigationLink { ReportDraftsView() } label: {
                        SettingsRow("Unsent reports", image: "report")
                    }
                }.buttonStyle(.plain)
                Text("Collection profile blocks and unsent reports are not synced.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}

struct ExampleListView: View {
    @EnvironmentObject private var store: LocalStore
    let title: String
    let blocked: Bool
    private var indexes: [Int] { (blocked ? store.blockedExamples : store.followedExamples).sorted() }
    var body: some View {
        PageShell(title: title) {
            VStack(spacing: 12) {
                OfflineNote(text: "Example relationships are not synced to your account.")
                if indexes.isEmpty { EmptyState(title: "No examples", detail: "There is nothing to show here yet.") }
                ForEach(indexes, id: \.self) { index in
                    HStack {
                        NavigationLink { ExampleProfileView(index: index) } label: {
                            HStack { ExampleAvatar(index: index); Text("Example profile \(index + 1)").foregroundStyle(liyaInk) }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button(blocked ? "Unblock" : "Unfollow") {
                            if blocked { store.setBlocked(index, blocked: false) } else { store.toggleFollow(index) }
                        }.font(.footnote.bold()).foregroundStyle(liyaAccent)
                    }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.top, 12)
        }
    }
}

struct ReportDraftsView: View {
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Unsent reports") {
            VStack(spacing: 12) {
                OfflineNote(text: "These reports have not been submitted or reviewed.")
                if store.reports.isEmpty { EmptyState(title: "No report drafts", detail: "Unsent drafts will appear here.") }
                ForEach(store.reports) { report in
                    HStack {
                        VStack(alignment: .leading) { Text(report.videoIndex.map { "Example video \($0 + 1)" } ?? "Example \(report.targetType == "post" ? "post" : "profile") \(report.photoIndex + 1)").font(.headline); Text(report.reason).font(.subheadline) }
                        Spacer()
                        Button("Delete") { store.deleteReport(report.id) }.font(.footnote.bold()).foregroundStyle(liyaAccent)
                    }.foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.top, 12)
        }
    }
}

struct InformationView: View {
    let title: String
    let message: String
    var body: some View {
        PageShell(title: title) {
            VStack(alignment: .leading, spacing: 14) {
                Image(title == "About Liya" ? "app-mark" : "setting-help")
                    .resizable().scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
                Text(LocalizedStringKey(title)).font(.headline).foregroundStyle(liyaInk)
                Text(LocalizedStringKey(message)).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
                .padding(.top, 16).modifier(AdaptiveContainerMargins())
        }
    }
}
