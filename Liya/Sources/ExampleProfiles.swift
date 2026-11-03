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
            let heroHeight = min(max(geometry.size.width * 0.95, 300), 440)
            ZStack(alignment: .top) {
                LiyaBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero.frame(width: geometry.size.width, height: heroHeight, alignment: .top)
                            .clipped()
                            .overlay(alignment: .bottom) {
                                LinearGradient(colors: [.clear, .white.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 110).allowsHitTesting(false)
                            }
                        VStack(alignment: .leading, spacing: 14) {
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
                        .padding(.horizontal, 20).padding(.bottom, 36)
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
    var body: some View {
        HStack(spacing: 28) {
            ForEach(Array(["Post", "Video"].enumerated()), id: \.offset) { index, title in
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

struct ExampleAvatar: View {
    let index: Int
    var size: CGFloat = 44
    var body: some View {
        CloudPhoto(index: index, contentMode: .fill)
            .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct ExampleProfileView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @Environment(\.dismiss) private var dismiss
    let index: Int
    var displayName: String? = nil
    var introduction: String? = nil
    @State private var section = 0
    @State private var options = false

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
            CloudPhoto(index: index, contentMode: .fill)
        } actions: {
                    HStack(spacing: 10) {
                        Button {
                            if !store.blockedExamples.contains(index) { store.toggleFollow(index) }
                        } label: {
                            Text(store.followedExamples.contains(index) ? "Following" : "Follow")
                                .font(.subheadline.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 46)
                                .background(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing), in: Capsule())
                        }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                        NavigationLink { ExampleChatView(index: index) } label: {
                            Text("Message").font(.subheadline.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 46).background(liyaGradient, in: Capsule())
                        }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                    }
        } content: {
                    Text("Curated profile · follows and message drafts stay on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                    ProfileContentTabs(selection: $section)
                    if store.blockedExamples.contains(index) {
                        EmptyState(title: "Blocked locally", detail: "Unblock this example in More options to view its content.")
                    } else if section == 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) { ExampleAvatar(index: index); Text(name).font(.subheadline.bold()).foregroundStyle(liyaInk) }
                            if !bio.isEmpty { Text(bio).font(.subheadline).foregroundStyle(liyaInk) }
                            NavigationLink { ExamplePhotoDetail(index: index) } label: {
                                CloudPhoto(index: index, contentMode: .fill).frame(maxWidth: .infinity).frame(height: 260)
                                    .clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    } else {
                        if videos.isEmpty {
                            EmptyState(title: "No videos yet", detail: "Videos will appear here when available.")
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
    let index: Int
    @State private var draft = ""
    var body: some View {
        PageShell(title: "Messages") {
            VStack(spacing: 16) {
                NavigationLink { ExampleProfileView(index: index) } label: {
                    HStack { ExampleAvatar(index: index); Text("Example profile \(index + 1)").font(.headline); Spacer() }
                        .foregroundStyle(liyaInk).padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                OfflineNote(text: store.blockedExamples.contains(index) ? "This example is blocked locally. Unblock it before editing a message draft." : "Messaging is not connected. Your text is a private draft and will not be delivered.")
                EmptyState(title: "No messages", detail: "Messages will appear after the service is connected.")
                TextField("Write a private draft", text: $draft, axis: .vertical).lineLimit(2...6).padding(14)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).disabled(store.blockedExamples.contains(index))
                PrimaryButton(title: "Save draft", disabled: store.blockedExamples.contains(index) || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    store.saveMessageDraft(draft, index: index)
                }
                if store.messageDrafts[String(index)] == draft && !draft.isEmpty { Text("Saved on this device").font(.footnote).foregroundStyle(liyaAccent) }
            }.padding(.top, 12)
        }.onAppear { draft = store.messageDrafts[String(index)] ?? "" }
            .onDisappear { if !store.blockedExamples.contains(index) { store.saveMessageDraft(draft, index: index) } }
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
                    OfflineNote(text: "This is an illustrative profile. You can report its associated example content; blocks remain on this device.")
                    NavigationLink { ReportDraftView(index: index, targetType: reportTarget) } label: { option(reportTarget == "post" ? "Report post" : "Report profile", image: "report") }
                        .buttonStyle(.plain)
                    Button {
                        store.setBlocked(index, blocked: !store.blockedExamples.contains(index)); dismiss()
                    } label: { option(store.blockedExamples.contains(index) ? "Unblock locally" : "Block locally", image: "setting-privacy") }
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
                OfflineNote(text: "Send a report about this example content, or keep an unsent draft on this device. Reports are stored for review; a review service has not yet been configured.")
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
                    store.saveReportDraft(index: index, reason: selected, targetType: targetType); reportError = "Draft saved on this device; it has not been submitted."
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
                    Text(items[index]).font(.subheadline.bold()).foregroundStyle(selection == index ? .white : liyaAccent)
                        .frame(maxWidth: .infinity).frame(minHeight: 42)
                        .background { if selection == index { Capsule().fill(liyaGradient) } }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(4).background(.white.opacity(0.86), in: Capsule())
    }
}
