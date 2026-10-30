import SwiftUI

struct ExampleAvatar: View {
    let index: Int
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let photo = Examples.photo(index) { Image(uiImage: photo).resizable().scaledToFill() }
            else { Image("app-mark").resizable().scaledToFill() }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct ExampleProfileView: View {
    @EnvironmentObject private var store: LocalStore
    let index: Int
    @State private var section = 0
    @State private var options = false

    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        PageHeader(title: "Example profile")
                        Button { options = true } label: { Image("more").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("More options")
                    }
                    if let photo = Examples.photo(index) {
                        GeometryReader { geometry in
                            Image(uiImage: photo).resizable().scaledToFill().frame(width: geometry.size.width, height: 240).clipped()
                        }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    Text("Example profile \(index + 1)").font(.title2.bold()).foregroundStyle(liyaInk)
                    OfflineNote(text: "Illustrative profile from supplied media. Follows, notes and blocks here are local to this device.")
                    HStack {
                        Button {
                            if !store.blockedExamples.contains(index) { store.toggleFollow(index) }
                        } label: {
                            Text(store.followedExamples.contains(index) ? "Following locally" : "Follow locally")
                                .font(.subheadline.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 46)
                                .background(liyaGradient, in: Capsule())
                        }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                        NavigationLink { ExampleChatView(index: index) } label: {
                            Text("Message").font(.subheadline.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 46).background(liyaGradient, in: Capsule())
                        }.buttonStyle(.plain).disabled(store.blockedExamples.contains(index))
                    }
                    SegmentedTabs(items: ["Post", "Video"], selection: $section)
                    if store.blockedExamples.contains(index) {
                        EmptyState(title: "Blocked locally", detail: "Unblock this example in More options to view its content.")
                    } else if section == 0 {
                        NavigationLink { ExamplePhotoDetail(index: index) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Example photo \(index + 1)").font(.headline).foregroundStyle(liyaInk)
                                if let photo = Examples.photo(index) { Image(uiImage: photo).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14)) }
                            }.padding(12).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 15))
                        }.buttonStyle(.plain)
                    } else {
                        EmptyState(title: "No linked videos", detail: "The supplied videos do not have profile associations.")
                    }
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.bottom, 24)
            }
        }.navigationBarHidden(true)
            .sheet(isPresented: $options) { ExampleOptionsView(index: index) }
    }
}

struct ExampleChatView: View {
    @EnvironmentObject private var store: LocalStore
    let index: Int
    @State private var draft = ""
    var body: some View {
        PageShell(title: "Example profile \(index + 1)") {
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
                    OfflineNote(text: "This is an example profile. Reports cannot be sent while the service is offline.")
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
    let index: Int
    var targetType = "profile"
    @State private var selected: String?
    @State private var saved = false
    private let reasons = ["Sexual content", "Harassment", "Discrimination", "Incorrect content", "Other"]
    var body: some View {
        PageShell(title: "Report type") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "This will save an unsent report draft on this device. No report is submitted.")
                ForEach(reasons, id: \.self) { reason in
                    Button { selected = reason; saved = false } label: {
                        HStack { Text(reason); Spacer(); if selected == reason { Text("Selected").font(.caption.bold()).foregroundStyle(liyaAccent) } }
                            .foregroundStyle(liyaInk).padding(16).frame(maxWidth: .infinity)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                PrimaryButton(title: "Save unsent draft", disabled: selected == nil || saved) {
                    guard let selected else { return }
                    store.saveReportDraft(index: index, reason: selected, targetType: targetType); saved = true
                }
                if saved { Text("Saved on this device · not submitted").font(.footnote).foregroundStyle(liyaAccent) }
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
