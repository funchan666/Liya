import SwiftUI
import PhotosUI

struct ProfileHome: View {
    @EnvironmentObject private var store: LocalStore
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
                        if let avatar = store.avatar {
                            MediaThumbnail(item: avatar).frame(maxWidth: .infinity).frame(height: 220).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            Image("app-mark").resizable().scaledToFit().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                    }.accessibilityHidden(true)
                    Text(store.nickname.isEmpty ? "Your local profile" : store.nickname).font(.title2.bold()).foregroundStyle(liyaInk)
                    Text(store.signature.isEmpty ? "Add a little about yourself." : store.signature).font(.subheadline).foregroundStyle(.secondary)
                    if !store.profileTags.isEmpty { Text(store.profileTags.map { "# " + $0 }.joined(separator: "   ")).font(.caption).foregroundStyle(liyaAccent) }
                    HStack(spacing: 20) {
                        NavigationLink { FollowersView() } label: {
                            Text("Followers —").font(.caption.bold()).foregroundStyle(liyaInk)
                        }
                        NavigationLink { ExampleListView(title: "Following", blocked: false) } label: {
                            Text("Following \(store.followedExamples.count) locally").font(.caption.bold()).foregroundStyle(liyaInk)
                        }
                    }.buttonStyle(.plain)
                    OfflineNote(text: "Local preview · You are not signed in. Your profile and saved examples stay on this device.")
                    HStack(spacing: 12) {
                        NavigationLink { SettingsView() } label: { actionLabel("Settings") }
                        NavigationLink { EditProfileView() } label: { actionLabel("Edit profile") }
                    }.buttonStyle(.plain)
                    NavigationLink { ExampleListView(title: "Following", blocked: false) } label: {
                        HStack { Text("Following locally"); Spacer(); Text("\(store.followedExamples.count)") }
                            .font(.subheadline.bold()).foregroundStyle(liyaInk).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                    SegmentedTabs(items: ["Post", "Video"], selection: $section)
                    if section == 0 {
                        NavigationLink { DraftsView() } label: {
                            HStack { Text("Private drafts").font(.headline); Spacer(); Text("\(store.drafts.filter { $0.publishedLocally != true }.count)") }
                                .foregroundStyle(liyaInk).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                        if posts.isEmpty { EmptyState(title: "No local posts", detail: "Posts made on this device will appear here.") }
                        ForEach(posts) { post in LocalPostCard(post: post) }
                    } else {
                        if videos.isEmpty { EmptyState(title: "No local videos", detail: "Videos in your local posts will appear here.") }
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
    @EnvironmentObject private var store: LocalStore
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
    var body: some View {
        PageShell(title: "Edit profile") {
            VStack(alignment: .leading, spacing: 16) {
                OfflineNote(text: "Changes are saved locally and are not visible to other people.")
                PhotosPicker(selection: $selection, matching: .images) {
                    VStack(spacing: 8) {
                        if let avatar { MediaThumbnail(item: avatar).frame(width: 88, height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 16)) }
                        else { Image("avatar-camera").resizable().scaledToFit().frame(width: 75, height: 75) }
                        Text(loading ? "Loading…" : "Choose photo").font(.footnote.bold()).foregroundStyle(liyaAccent)
                    }.frame(maxWidth: .infinity).padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }.disabled(loading)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
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
                PrimaryButton(title: "Save locally", disabled: loading) { store.nickname = name; store.signature = signature; store.saveProfileTags(tags); store.saveAvatar(avatar); dismiss() }
            }.foregroundStyle(liyaInk).padding(.top, 12)
        }.onAppear {
            guard !initialized else { return }
            name = store.nickname; signature = store.signature; tags = store.profileTags; avatar = store.avatar; initialized = true
        }
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
                NavigationLink { InformationView(title: "About Liya", message: "Liya is currently a local preview.") } label: { settingsRow("About Us", image: "setting-help") }
                NavigationLink { InformationView(title: "Privacy Policy", message: "The privacy policy has not been published yet.") } label: { settingsRow("Privacy Policy", image: "setting-privacy") }
                OfflineNote(text: "No account is currently signed in.")
                Button("Exit local preview") { store.inPreview = false }
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
    var body: some View {
        PageShell(title: "Account & Security") {
            VStack(spacing: 14) {
                OfflineNote(text: "There is no signed-in account in this preview. Account deletion will be available when account services are connected.")
                PrimaryButton(title: "Delete account unavailable", disabled: true) { }
            }.padding(.top, 12)
        }
    }
}

struct FollowersView: View {
    var body: some View {
        PageShell(title: "Followers") {
            VStack(spacing: 14) {
                OfflineNote(text: "Followers require a connected account. No followers are simulated in this preview.")
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
                OfflineNote(text: "These settings apply only to this device.")
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

struct WalletView: View {
    var body: some View {
        PageShell(title: "My wallet") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("My wallet").font(.title.bold()).foregroundStyle(liyaInk)
                        Text("Balance unavailable").font(.headline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image("wallet-coin").resizable().scaledToFit().frame(width: 100, height: 100).accessibilityHidden(true)
                }
                OfflineNote(text: "Purchases and balance are not connected. No payment can be made in this preview.")
                EmptyState(title: "Products unavailable", detail: "Apple pricing and available products will appear when purchasing is configured.")
            }.padding(.top, 12)
        }
    }
}
