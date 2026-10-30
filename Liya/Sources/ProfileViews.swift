import SwiftUI
import PhotosUI

struct ProfileHome: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @State private var section = 0
    @State private var previewVideo: DraftAttachment?
    private var posts: [LocalDraft] { store.drafts.filter { $0.publishedLocally == true } }
    private var videos: [DraftAttachment] { posts.flatMap { $0.attachments ?? [] }.filter { $0.isVideo } }
    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Image("profile-title").resizable().scaledToFit().frame(width: 145, height: 44).accessibilityLabel("Profile"); Spacer()
                        NavigationLink { WalletView() } label: {
                            Text("Wallet").font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 10).background(liyaGradient, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                    Group {
                        if let url = session.profileAvatarURL {
                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                                .frame(maxWidth: .infinity).frame(height: 220).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            Image("app-mark").resizable().scaledToFit().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                    }.accessibilityHidden(true)
                    Text(session.profile.flatMap { $0.displayName.isEmpty ? nil : $0.displayName } ?? "Your profile").font(.title2.bold()).foregroundStyle(liyaInk)
                    Text(session.profile.flatMap { $0.signature.isEmpty ? nil : $0.signature } ?? "Add a little about yourself.").font(.subheadline).foregroundStyle(.secondary)
                    if let tags = session.profile?.tags, !tags.isEmpty { Text(tags.map { "# " + $0 }.joined(separator: "   ")).font(.caption).foregroundStyle(liyaAccent) }
                    HStack(spacing: 20) {
                        NavigationLink { CommunityRelationList(title: "Followers", relation: "followers") } label: {
                            Text("Followers \(social.followers.count)").font(.caption.bold()).foregroundStyle(liyaInk)
                        }
                        NavigationLink { CommunityRelationList(title: "Following", relation: "following") } label: {
                            Text("Following \(social.follows.count)").font(.caption.bold()).foregroundStyle(liyaInk)
                        }
                    }.buttonStyle(.plain)
                    if let error = session.profileError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("Retry profile") { Task { await session.refreshProfile() } }.foregroundStyle(liyaAccent)
                    }
                    OfflineNote(text: "Your account profile is private. Your separate community profile is visible to other members.")
                    NavigationLink(social.isJoined(session) ? "Edit community profile" : "Create community profile") { CommunityJoinView() }.font(.footnote.bold()).foregroundStyle(liyaAccent)
                    NavigationLink { DeviceProfileView() } label: { Text("View previous device profile").font(.footnote.bold()).foregroundStyle(liyaAccent) }
                    HStack(spacing: 12) {
                        NavigationLink { SettingsView() } label: { actionLabel("Settings") }
                        NavigationLink { EditProfileView() } label: { actionLabel("Edit profile") }
                    }.buttonStyle(.plain)
                    NavigationLink { ExampleListView(title: "Saved examples", blocked: false) } label: {
                        HStack { Text("Saved examples on this device"); Spacer(); Text("\(store.followedExamples.count)") }
                            .font(.subheadline.bold()).foregroundStyle(liyaInk).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                    SegmentedTabs(items: ["Post", "Video"], selection: $section)
                    if section == 0 {
                        if let owner = session.userID {
                            ForEach(social.posts.filter { $0.ownerID == owner }) { CommunityPostCard(post: $0) }
                        }
                        NavigationLink { DraftsView() } label: {
                            HStack { Text("Private drafts").font(.headline); Spacer(); Text("\(store.drafts.filter { $0.publishedLocally != true }.count)") }
                                .foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                        if posts.isEmpty { EmptyState(title: "No local posts", detail: "Posts made on this device will appear here.") }
                        ForEach(posts) { post in LocalPostCard(post: post) }
                    } else {
                        if let owner = session.userID {
                            ForEach(social.posts.filter { $0.ownerID == owner && $0.mediaKinds.contains("video") }) { CommunityPostCard(post: $0) }
                        }
                        if videos.isEmpty && !social.posts.contains(where: { $0.ownerID == session.userID && $0.mediaKinds.contains("video") }) { EmptyState(title: "No videos yet", detail: "Videos you share will appear here.") }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(videos) { item in
                                Button { previewVideo = item } label: {
                                    MediaThumbnail(item: item).frame(height: 135).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel("Preview local video")
                            }
                        }
                    }
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(20)
            }
        }.navigationBarHidden(true).sheet(item: $previewVideo) { item in DraftVideoPreview(item: item) }
    }
    private func actionLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 46).background(liyaGradient, in: Capsule())
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
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
            VStack(alignment: .leading, spacing: 16) {
                OfflineNote(text: "Your profile and selected photo are saved privately to your account.")
                PhotosPicker(selection: $selection, matching: .images) {
                    VStack(spacing: 8) {
                        if let avatar { MediaThumbnail(item: avatar).frame(width: 88, height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 16)) }
                        else if let url = session.profileAvatarURL {
                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                                .frame(width: 88, height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                        } else { Image("avatar-camera").resizable().scaledToFit().frame(width: 75, height: 75) }
                        Text(loading ? "Loading…" : "Choose photo").font(.footnote.bold()).foregroundStyle(liyaAccent)
                    }.frame(maxWidth: .infinity).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }.disabled(loading || saving)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if let error = session.profileError { Text(error).font(.footnote).foregroundStyle(.red) }
                Text("Nickname").font(.headline)
                TextField("Enter a nickname", text: $name).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                Text("Labels").font(.headline)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            Button { tags.removeAll { $0 == tag } } label: {
                                HStack(spacing: 5) {
                                    Text("# \(tag)").font(.caption.bold()).foregroundStyle(liyaAccent)
                                    Image("close").resizable().scaledToFit().frame(width: 15, height: 15).accessibilityHidden(true)
                                }.padding(10).background(.white.opacity(0.9), in: Capsule())
                            }.buttonStyle(.plain).accessibilityLabel("Remove label \(tag)")
                        }
                    }
                }
                HStack {
                    TextField("Add a label", text: $tagInput).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                    Button("Add") {
                        let value = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty && !tags.contains(value) && tags.count < 6 { tags.append(value); tagInput = "" }
                    }.font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(minWidth: 44, minHeight: 44)
                }
                Text("Introduction").font(.headline)
                TextField("Add an introduction", text: $signature, axis: .vertical).lineLimit(3...6).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                if session.profile == nil {
                    Button("Retry loading profile") { Task { await session.refreshProfile(); initialize() } }.foregroundStyle(liyaAccent)
                }
                PrimaryButton(title: saving ? "Saving…" : "Save profile", disabled: loading || saving || session.profile == nil || !initialized) {
                    saving = true
                    Task {
                        if await session.saveProfile(name: name, signature: signature, tags: tags, avatar: avatar) { dismiss() }
                        saving = false
                    }
                }
            }.foregroundStyle(liyaInk).padding(.top, 12).disabled(saving)
        }.task { if session.profile == nil { await session.refreshProfile() }; initialize() }
            .onChange(of: session.profileLoading) { loading in if !loading { initialize() } }
            .onChange(of: selection) { item in
                guard let item else { return }
                loading = true; error = nil
                Task { @MainActor in
                    do {
                        if let photo = try await item.loadTransferable(type: ImportedPhoto.self) { avatar = photo.item }
                        else { error = "The photo could not be loaded. Please try again." }
                    } catch { error = "The photo could not be loaded. Please try again." }
                    selection = nil; loading = false
                }
            }
    }
    private func initialize() {
        guard !initialized, let profile = session.profile else { return }
        name = profile.displayName; signature = profile.signature; tags = profile.tags; initialized = true
    }
}

struct DeviceProfileView: View {
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Previous device profile") {
            VStack(alignment: .leading, spacing: 14) {
                OfflineNote(text: "This earlier profile remains on this device and has not been uploaded.")
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
    var body: some View {
        PageShell(title: "Settings") {
            VStack(spacing: 10) {
                NavigationLink { AccountView() } label: { settingsRow("Account & Security", image: "setting-lock") }
                NavigationLink { InformationView(title: "Notifications", message: "Notifications are not connected.") } label: { settingsRow("Notifications", image: "setting-notification") }
                NavigationLink { PrivacyView() } label: { settingsRow("Privacy", image: "setting-privacy") }
                NavigationLink { InformationView(title: "Language", message: "This preview is in English.") } label: { settingsRow("Language", image: "setting-language") }
                NavigationLink { InformationView(title: "Help & Support", message: "A support channel has not been configured.") } label: { settingsRow("Help & Support", image: "setting-help") }
                NavigationLink { InformationView(title: "About Liya", message: "Liya is an early service; some social features are not connected yet.") } label: { settingsRow("About Us", image: "setting-help") }
                NavigationLink { LegalDocumentView(page: .privacy) } label: { settingsRow("Privacy Policy", image: "setting-privacy") }
                NavigationLink { LegalDocumentView(page: .terms) } label: { settingsRow("Terms of Service", image: "setting-help") }
                OfflineNote(text: "Your anonymous account is connected. Local preview items remain on this device.")
                Button("Back to welcome") { store.inPreview = false }
                    .font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white.opacity(0.85), in: Capsule())
            }.buttonStyle(.plain).padding(.top, 12)
        }
    }
    private func settingsRow(_ title: String, image: String) -> some View {
        HStack(spacing: 14) {
            Image(image).resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
            Text(title).foregroundStyle(liyaInk); Spacer()
        }.frame(minHeight: 55).padding(.horizontal, 14).background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AccountView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var checkout: CoinCheckout
    @State private var confirming = false
    @State private var checking = false
    @State private var purchaseError: String?
    var body: some View {
        PageShell(title: "Account & Security") {
            VStack(spacing: 14) {
                OfflineNote(text: "This anonymous account cannot be recovered after deletion. Cloud posts, messages, uploads and coins will be permanently removed. Device-only drafts remain on this device.")
                if let error = session.deletionError ?? purchaseError { Text(error).font(.footnote).foregroundStyle(.red) }
                PrimaryButton(title: session.isDeletingAccount ? "Deleting account…" : (checking ? "Checking purchases…" : "Delete account"), disabled: session.isDeletingAccount || checking || session.userID == nil) {
                    confirming = true
                }
            }.padding(.top, 12)
        }.sheet(isPresented: $confirming) {
            LocalConfirmation(title: "Delete this account?", message: "Your cloud account, posts, messages, uploaded media and coins will be permanently deleted. This anonymous account cannot be restored. Device-only drafts remain on this device.", action: "Delete account") {
                confirming = false; checking = true; purchaseError = nil
                Task {
                    guard let owner = session.userID else { checking = false; return }
                    if await checkout.hasUnfinishedPurchase(for: owner) {
                        purchaseError = "An Apple purchase is still pending or cannot be matched. Resolve it before deleting this account."
                    } else if await session.deleteAccount() {
                        social.clearAccount(); store.inPreview = false
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
            VStack(spacing: 12) {
                OfflineNote(text: "Community blocks are saved to your account. Example blocks and unsent report drafts stay on this device.")
                NavigationLink { CommunityRelationList(title: "Blocked members", relation: "blocked") } label: {
                    HStack { Text("Blocked members"); Spacer() }.foregroundStyle(liyaInk).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                NavigationLink { ExampleListView(title: "Blocked examples", blocked: true) } label: {
                    HStack { Text("Blocked examples"); Spacer(); Text("\(store.blockedExamples.count)") }
                        .foregroundStyle(liyaInk).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                NavigationLink { ReportDraftsView() } label: {
                    HStack { Text("Unsent report drafts"); Spacer(); Text("\(store.reports.count)") }
                        .foregroundStyle(liyaInk).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }.padding(.top, 12)
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
                OfflineNote(text: "Example relationships are saved only on this device.")
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
    var body: some View { PageShell(title: title) { OfflineNote(text: message).padding(.top, 12) } }
}
