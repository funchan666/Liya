import SwiftUI
import UIKit

struct SquareHome: View {
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image("square-title").resizable().scaledToFit().frame(width: 145, height: 45).accessibilityLabel("Emotional Square")
                        Spacer()
                    }
                    if let error = session.likesError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("Retry likes") { Task { await session.refreshLikes() } }.foregroundStyle(liyaAccent)
                    }
                    NavigationLink { ComposeHome(showsBackButton: true) } label: {
                        Image("square-prompt").resizable().scaledToFit().frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("Write a draft")
                    HStack(alignment: .top, spacing: 10) {
                        feature("ai-card", label: "AI chat") { AutomaticChatView() }
                        feature("diary-card", label: "Mood diary") { MoodDiaryView() }
                        feature("tree-card", label: "Mood tree hole") { TreeHoleView() }
                    }
                    CommunityFeed()
                    if store.drafts.contains(where: { $0.publishedLocally == true }) {
                        Text("Unshared posts").font(.headline).foregroundStyle(liyaInk)
                        LazyVStack(spacing: 16) {
                            ForEach(store.drafts.filter { $0.publishedLocally == true }) { post in LocalPostCard(post: post) }
                        }
                    }
                    Text("From the collection").font(.footnote).foregroundStyle(.secondary)
                    if session.catalogLoading {
                        Text("Loading photos…").font(.footnote).foregroundStyle(.secondary)
                    } else if let error = session.catalogError {
                        OfflineNote(text: error)
                        Button("Try again") { Task { await session.refreshCatalog() } }.foregroundStyle(liyaAccent)
                    } else if session.photos.isEmpty {
                        EmptyState(title: "No photos yet", detail: "There are no photos to show right now.")
                    }
                    LazyVStack(spacing: 16) {
                        ForEach(session.photos.indices, id: \.self) { index in
                            if ExamplePhotoAllocation.isPost(index, in: session.photos) && !store.blockedExamples.contains(index) {
                                ExamplePhotoRow(index: index)
                            }
                        }
                    }
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28 + tabBarClearance)
            }.refreshable { await social.refresh(session) }
        }.navigationBarHidden(true)
    }

    private func feature<Destination: View>(_ image: String, label: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            Image(image).resizable().scaledToFit().frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct MoodDiaryView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @State private var date = Date()
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var mood = "mood-happy"
    @State private var note = ""
    @State private var saved = false
    @State private var dirty = false
    @State private var saving = false
    private let moods = [("mood-teal", "Tired"), ("mood-happy", "Happy"), ("mood-yellow", "Thoughtful"), ("mood-calm", "Calm"), ("mood-blue", "Blue"), ("mood-upset", "Upset")]

    var body: some View {
        PageShell(title: "Mood Diary") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    diaryStat("diary-count", label: "Total record days", value: session.moodEntries.count)
                    diaryStat("diary-happy", label: "Happy days", value: session.moodEntries.filter { $0.mood == "mood-happy" }.count)
                }
                HStack(alignment: .center) {
                    Text("Mood journal").font(.system(.title3, design: .serif).bold().italic()).foregroundStyle(liyaInk)
                    Spacer(minLength: 8)
                    yearControl
                }
                monthSelector
                if !store.entries.isEmpty {
                    NavigationLink("Earlier entries") { DeviceMoodHistory() }
                        .font(.footnote.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                if session.moodLoading {
                    HStack(spacing: 8) { LiyaLoadingIndicator(size: 24); Text("Loading journal…").font(.footnote).foregroundStyle(.secondary) }
                }
                if let error = session.moodError {
                    OfflineNote(text: error)
                    Button("Reload journal") { Task { await session.refreshMoods() } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                VStack(alignment: .leading, spacing: 14) {
                    MoodCalendar(selection: Binding(get: { date }, set: selectDate), month: month)
                        .disabled(saving || session.moodLoading)
                    moodSelector
                        .disabled(saving || session.moodLoading)
                    TextField("Add a note (optional)", text: Binding(get: { note }, set: { note = $0; saved = false; dirty = true }), axis: .vertical)
                        .lineLimit(2...5).padding(12).font(.subheadline)
                        .background(Color(red: 0.97, green: 0.96, blue: 0.99), in: RoundedRectangle(cornerRadius: 12))
                        .disabled(saving || session.moodLoading)
                    PrimaryButton(title: saving ? "Saving…" : "Record", disabled: saving || session.moodLoading || session.moodError != nil) {
                        let entryDate = date, entryMood = mood, entryNote = note
                        store.savePendingMood(entryMood, note: entryNote, date: entryDate)
                        saving = true
                        Task {
                            if await session.saveMood(entryMood, note: entryNote, date: entryDate) {
                                store.clearPendingMood(date: entryDate)
                                dirty = false; saved = true
                            }
                            saving = false
                        }
                    }
                    if saved { Text("Mood recorded").font(.footnote.weight(.medium)).foregroundStyle(liyaAccent) }
                }
                .padding(14)
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: liyaInk.opacity(0.07), radius: 8, x: 0, y: 3)
            }.padding(.top, 12).modifier(AdaptiveContainerMargins())
        }.task { await session.refreshMoods(); loadEntry() }
            .onLiyaChange(of: session.moodEntries) { _ in if !dirty { loadEntry() } }
            .onDisappear { if dirty { store.savePendingMood(mood, note: note, date: date) } }
    }

    private var yearControl: some View {
        HStack(spacing: 0) {
            Button { moveYear(-1) } label: {
                Image("back").resizable().scaledToFit().frame(width: 12, height: 12).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Previous year")
            Text(month.formatted(.dateTime.year())).font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
                .monospacedDigit()
            Button { moveYear(1) } label: {
                Image("back").resizable().scaledToFit().frame(width: 12, height: 12).scaleEffect(x: -1, y: 1).frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(Calendar.current.component(.year, from: month) >= Calendar.current.component(.year, from: Date()))
                .accessibilityLabel("Next year")
        }.disabled(saving || session.moodLoading)
    }

    private var monthSelector: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...12, id: \.self) { number in
                        if let candidate = monthDate(number) {
                            let selected = Calendar.current.isDate(candidate, equalTo: month, toGranularity: .month)
                            Button { changeMonth(candidate) } label: {
                                Text(candidate.formatted(.dateTime.month(.abbreviated)))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(selected ? .white : liyaInk.opacity(0.55))
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .background {
                                        if selected { Capsule().fill(liyaGradient) }
                                        else { Capsule().fill(.white.opacity(0.8)) }
                                    }
                            }.buttonStyle(.plain).disabled(candidate > Date() || saving || session.moodLoading)
                                .accessibilityLabel(candidate.formatted(.dateTime.month(.wide).year()))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .id(number)
                        }
                    }
                }
            }.onAppear { reader.scrollTo(Calendar.current.component(.month, from: month), anchor: .center) }
                .onLiyaChange(of: month) { value in reader.scrollTo(Calendar.current.component(.month, from: value), anchor: .center) }
        }
    }

    private var moodSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How are you feeling?").font(.subheadline.weight(.semibold)).foregroundStyle(liyaInk)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(moods.indices, id: \.self) { index in
                        let item = moods[index]
                        Button { mood = item.0; saved = false; dirty = true } label: {
                            Image(item.0).resizable().scaledToFit().frame(width: 42, height: 42)
                                .frame(width: 54, height: 54)
                                .background(mood == item.0 ? liyaAccent.opacity(0.14) : Color(red: 0.97, green: 0.97, blue: 0.98), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(mood == item.0 ? liyaAccent : .clear, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel(item.1).accessibilityAddTraits(mood == item.0 ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func selectDate(_ newDate: Date) {
        if dirty { store.savePendingMood(mood, note: note, date: date) }
        date = newDate
        month = Calendar.current.dateInterval(of: .month, for: newDate)?.start ?? newDate
        loadEntry()
    }

    private func monthDate(_ number: Int) -> Date? {
        var components = Calendar.current.dateComponents([.year], from: month)
        components.month = number; components.day = 1
        return Calendar.current.date(from: components)
    }

    private func changeMonth(_ newMonth: Date) {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: newMonth) else { return }
        let day = min(calendar.component(.day, from: date), range.count)
        guard let candidate = calendar.date(byAdding: .day, value: day - 1, to: newMonth) else { return }
        selectDate(min(candidate, calendar.startOfDay(for: Date())))
    }

    private func moveYear(_ offset: Int) {
        guard let next = Calendar.current.date(byAdding: .year, value: offset, to: month) else { return }
        let currentMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        changeMonth(min(next, currentMonth))
    }

    private func loadEntry() {
        let entry = session.moodEntries.first { $0.day == CloudMood.dayKey(date) }
        let unsaved = store.pendingMoods.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        mood = unsaved?.mood ?? entry?.mood ?? "mood-happy"
        note = unsaved?.note ?? entry?.note ?? ""
        dirty = unsaved != nil
        saved = false
    }

    private func diaryStat(_ image: String, label: String, value: Int) -> some View {
        Image(image).resizable().aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { size in
                    Text("\(value)").font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white).monospacedDigit()
                        .padding(.leading, size.size.width * 0.12).padding(.top, size.size.height * 0.49)
                }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(value)")
    }
}

private struct TreeThought: Identifiable {
    let id: String
    let body: String
    let mood: String
    let post: SocialPost?
}

struct TreeHoleView: View {
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @AppStorage("liya.treeDraft") private var text = ""
    @AppStorage("liya.treeSubmissionID") private var submissionID = ""
    @AppStorage("liya.treePublicAttempt") private var publicAttempt = ""
    @AppStorage("liya.treePublicFingerprint") private var publicFingerprint = ""
    @AppStorage("liya.treeHiddenSuggestions") private var hiddenSuggestions = ""
    @AppStorage("liya.treeDraftMood") private var mood = "mood-calm"
    @State private var selectedThought: TreeThought?
    @State private var thoughtDetent: PresentationDetent = .fraction(0.48)
    @State private var notice: String?
    @State private var actionError: String?
    @State private var saving = false
    @State private var drifting = false
    @State private var showCommunitySetup = false
    private let moods = ["mood-teal", "mood-happy", "mood-yellow", "mood-calm", "mood-blue", "mood-upset"]
    private let suggestions: [(String, String)] = [
        ("mood-calm", "Taking a breath before a busy day."),
        ("mood-blue", "Today was harder than I expected."),
        ("mood-happy", "A kind message made me smile."),
        ("mood-teal", "Trying to take things one step at a time."),
        ("mood-yellow", "I wish I could quiet my thoughts tonight."),
        ("mood-calm", "The little things helped today."),
        ("mood-happy", "I finally made time for an old friend."),
        ("mood-blue", "Missing someone a little extra today."),
        ("mood-teal", "A slow morning was just what I needed."),
        ("mood-upset", "That conversation is still on my mind."),
        ("mood-yellow", "Not every day needs a perfect ending."),
        ("mood-calm", "A walk helped me clear my head."),
        ("mood-happy", "There was sunshine on my way home."),
        ("mood-blue", "I am learning to ask for help."),
        ("mood-teal", "I need a little room to rest."),
        ("mood-upset", "Hoping tomorrow feels a bit lighter."),
        ("mood-calm", "Letting myself pause for a moment."),
        ("mood-happy", "Good coffee and a quiet afternoon."),
        ("mood-yellow", "Trying to be kinder to myself."),
        ("mood-blue", "Some feelings are hard to put into words.")
    ]

    private var thoughts: [TreeThought] {
        let community = social.posts.filter { $0.tags.contains("tree-hole") && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(30).map { post in
                TreeThought(id: post.id.uuidString, body: post.body,
                            mood: post.tags.first(where: { moods.contains($0) }) ?? "mood-calm", post: post)
            }
        let hidden = Set(hiddenSuggestions.split(separator: ",").map(String.init))
        let ideas = suggestions.enumerated().compactMap { index, item -> TreeThought? in
            let id = "suggestion-\(index)"
            return hidden.contains(id) ? nil : TreeThought(id: id, body: item.1, mood: item.0, post: nil)
        }
        return community + ideas
    }

    var body: some View {
        ZStack {
            LiyaBackground(name: "tree-background")
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 14) {
                        PageHeader(title: "Mood Tree Hole", light: true)
                        floatingThoughts
                        Spacer(minLength: max(30, geometry.size.height * 0.10))
                        moodPicker
                        TextField("What would you like to let out?", text: Binding(get: { text }, set: {
                            text = $0; submissionID = ""; publicAttempt = ""; publicFingerprint = ""; notice = nil; actionError = nil
                        }), axis: .vertical)
                            .lineLimit(4...8).padding(16).foregroundStyle(.white)
                            .tint(.white)
                            .background(Color(red: 0.19, green: 0.22, blue: 0.35).opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                            .disabled(saving)
                        if text.count > 4000 { Text("Please keep your thought under 4,000 characters.").font(.footnote).foregroundStyle(.white) }
                        PrimaryButton(title: saving ? "Saving…" : "Share to tree", disabled: saving || social.loading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000) {
                            if social.isJoined(session) { shareThought() }
                            else { showCommunitySetup = true }
                        }
                        Text("Visible to the community")
                            .font(.caption).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                        if let error = actionError ?? social.error { Text(error).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center) }
                        if let notice { Text(notice).font(.footnote.weight(.medium)).foregroundStyle(.white) }
                        HStack(spacing: 18) {
                            Button("Keep private") { savePrivate() }
                                .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000)
                            NavigationLink("My private thoughts") { TreeHistoryView() }
                        }.font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.9)).frame(minHeight: 44)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24 + tabBarClearance)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height, alignment: .top)
                    .modifier(AdaptiveContainerMargins())
                }.scrollDismissesKeyboard(.interactively)
            }
        }.navigationBarHidden(true)
            .navigationDestination(isPresented: $showCommunitySetup) { CommunityJoinView() }
            .task { await social.refresh(session) }
            .onAppear { drifting = !reduceMotion }
            .onLiyaChange(of: reduceMotion) { drifting = !$0 }
            .sheet(item: $selectedThought, onDismiss: { thoughtDetent = .fraction(0.48) }) { thought in
                NavigationStack {
                    TreeThoughtOptions(thought: thought, detent: $thoughtDetent) {
                        var hidden = Set(hiddenSuggestions.split(separator: ",").map(String.init))
                        hidden.insert(thought.id); hiddenSuggestions = hidden.sorted().joined(separator: ",")
                    }
                }.presentationDetents([.fraction(0.48), .large], selection: $thoughtDetent)
            }
    }

    private var floatingThoughts: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Thoughts in the tree").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                if social.loading { LiyaLoadingIndicator(size: 22) }
                else { Button("Refresh") { Task { await social.refresh(session) } }.font(.caption.bold()).foregroundStyle(.white).frame(minHeight: 44) }
            }
            ForEach(0..<3, id: \.self) { row in
                let rowThoughts = thoughts.enumerated().filter { $0.offset % 3 == row }.map { $0.element }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(rowThoughts) { thought in
                            Button { selectedThought = thought } label: {
                                HStack(spacing: 7) {
                                    Image(thought.mood).resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(thought.body).font(.subheadline.weight(.medium)).lineLimit(1)
                                        if thought.post == nil { Text("Inspiration").font(.caption2.weight(.semibold)).opacity(0.8) }
                                    }
                                    .frame(maxWidth: 205, alignment: .leading)
                                    Image("more").renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white).frame(width: 17, height: 17).accessibilityHidden(true)
                                }.foregroundStyle(.white).padding(.horizontal, 10).frame(minHeight: 46)
                                    .background(Color(red: 0.20, green: 0.25, blue: 0.43).opacity(0.86), in: Capsule())
                                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                            }.buttonStyle(.plain).accessibilityLabel(thought.body + (thought.post == nil ? ", inspiration" : ", community thought") + ", options")
                        }
                    }.offset(x: reduceMotion ? 0 : (drifting ? -5 : 5))
                        .animation(reduceMotion ? nil : .easeInOut(duration: row == 0 ? 4 : 5).repeatForever(autoreverses: true), value: drifting)
                }
            }
        }
    }

    private var moodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moods, id: \.self) { item in
                    Button { mood = item; submissionID = ""; publicAttempt = ""; publicFingerprint = ""; notice = nil } label: {
                        Image(item).resizable().scaledToFit().frame(width: 42, height: 42).frame(width: 52, height: 52)
                            .background(mood == item ? Color(red: 0.36, green: 0.29, blue: 0.58) : Color(red: 0.19, green: 0.22, blue: 0.35), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(mood == item ? .white.opacity(0.75) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(saving).accessibilityLabel(item.replacingOccurrences(of: "mood-", with: ""))
                        .accessibilityAddTraits(mood == item ? .isSelected : [])
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private func shareThought() {
        guard let owner = session.userID, social.isJoined(session), !saving else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = ["tree-hole", mood]
        let stamp = SocialAttempt.fingerprint(owner: owner, text: value, tags: tags, files: [])
        if stamp != publicFingerprint || UUID(uuidString: publicAttempt) == nil { publicFingerprint = stamp; publicAttempt = UUID().uuidString }
        guard let id = UUID(uuidString: publicAttempt) else { return }
        saving = true; notice = nil; actionError = nil
        Task {
            if await social.publish(session, id: id, body: value, tags: tags, attachments: []) {
                text = ""; submissionID = ""; publicAttempt = ""; publicFingerprint = ""; notice = "Your thought is shared."
            } else { actionError = social.error ?? "Couldn't confirm sharing. Please try again." }
            saving = false
        }
    }

    private func savePrivate() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saving, !value.isEmpty else { return }
        if UUID(uuidString: submissionID) == nil { submissionID = UUID().uuidString }
        guard let id = UUID(uuidString: submissionID) else { return }
        saving = true; notice = nil; actionError = nil
        Task {
            if await session.saveTreeEntry(id: id, mood: mood, body: value) {
                text = ""; submissionID = ""; publicAttempt = ""; publicFingerprint = ""; notice = "Saved privately."
            } else { actionError = session.treeError ?? "Couldn't confirm saving. Please try again." }
            saving = false
        }
    }
}

private struct TreeThoughtOptions: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    let thought: TreeThought
    @Binding var detent: PresentationDetent
    let hideSuggestion: () -> Void
    @State private var mode = 0
    @State private var reason: String?
    @State private var requestID = UUID()
    @State private var busy = false
    @State private var sent = false
    @State private var error: String?
    private let reasons = ["Sexual content", "Harassment", "Discrimination", "Incorrect content", "Other"]

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                DuoControlRegion { _ in
                    HStack {
                        Button { goBack() } label: {
                            Image("back").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(mode == 0 ? "Close" : "Back")
                        Spacer(minLength: 0)
                        Text(title).font(.headline).foregroundStyle(liyaInk).lineLimit(1)
                        Spacer(minLength: 0)
                        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                    }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                }.frame(height: 48)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(thought.mood).resizable().scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(thought.post == nil ? "Inspiration" : "Community thought")
                                    .font(.caption.weight(.semibold)).foregroundStyle(liyaAccent)
                                Text(thought.body).font(.subheadline).foregroundStyle(liyaInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                        if mode == 1 && !sent {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Why are you reporting this thought?").font(.headline).foregroundStyle(liyaInk)
                                ForEach(reasons, id: \.self) { item in
                                    VideoSafetyReason(title: item, selected: reason == item) {
                                        reason = item; requestID = UUID(); error = nil
                                    }.disabled(busy)
                                }
                            }
                        } else if mode == 2 {
                            Text("Their posts and messages will no longer be visible to you.")
                                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if !social.isJoined(session) {
                                NavigationLink("Set up your profile to block") { CommunityJoinView() }
                                    .foregroundStyle(liyaAccent).frame(minHeight: 44)
                            }
                        } else if mode == 3 {
                            Text("This thought will be removed from the community and your profile.")
                                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if sent { Text("Report received.").font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent) }
                        if let error { Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                        actions
                    }.frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
                        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                        .modifier(AdaptiveContainerMargins())
                }
            }
        }.navigationBarHidden(true).interactiveDismissDisabled(busy)
    }

    private var title: String {
        mode == 1 ? "Report thought" : mode == 2 ? "Block member" : mode == 3 ? "Delete thought" : "Thought options"
    }

    @ViewBuilder private var actions: some View {
        if let post = thought.post {
            if mode == 0 {
                if post.ownerID == session.userID {
                    PrimaryButton(title: "Delete thought") { showMode(3) }
                } else {
                    VStack(spacing: 8) {
                        PrimaryButton(title: "Report thought") { showMode(1) }
                        Button("Block member") { showMode(2) }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            } else if mode == 1 {
                if sent { PrimaryButton(title: "Done") { dismiss() } }
                else { PrimaryButton(title: busy ? "Sending…" : "Send report", disabled: busy || reason == nil) { report(post) } }
            } else if mode == 2 {
                PrimaryButton(title: busy ? "Blocking…" : "Block member", disabled: busy || !social.isJoined(session)) { block(post) }
            } else {
                PrimaryButton(title: busy ? "Deleting…" : "Confirm delete", disabled: busy) { delete(post) }
            }
        } else {
            PrimaryButton(title: "Hide suggestion") { hideSuggestion(); dismiss() }
        }
    }

    private func showMode(_ next: Int) {
        mode = next; error = nil
        if next == 1 { detent = .large }
    }

    private func goBack() {
        guard !busy else { return }
        if mode == 0 { dismiss() }
        else { mode = 0; error = nil; detent = .fraction(0.48) }
    }

    private func report(_ post: SocialPost) {
        guard let reason, !busy else { return }
        busy = true; error = nil
        Task {
            sent = await social.report(session, id: requestID, target: post.ownerID, post: post.id, reason: reason)
            if !sent { error = "Couldn't confirm your report. Please try again." }
            busy = false
        }
    }
    private func block(_ post: SocialPost) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            await social.setRelation(session, target: post.ownerID, table: "liya_blocks", enabled: true)
            busy = false
            if social.blocked.contains(post.ownerID) { dismiss() }
            else { error = social.error ?? "Couldn't block this member. Please try again." }
        }
    }
    private func delete(_ post: SocialPost) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            if await social.deletePost(session, id: post.id) { dismiss() }
            else { error = social.error ?? "Couldn't delete this thought. Please try again." }
            busy = false
        }
    }
}

private struct TreeHistoryView: View {
    @EnvironmentObject private var session: LiyaSession
    @State private var deleting: TreeEntry?
    var body: some View {
        PageShell(title: "Your private thoughts") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "Only your account can read these thoughts.")
                if session.treeLoading { Text("Loading…").foregroundStyle(.secondary) }
                if let error = session.treeError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Try again") { Task { await session.refreshTreeEntries() } }.foregroundStyle(liyaAccent)
                } else if !session.treeLoading && session.treeEntries.isEmpty {
                    EmptyState(title: "No thoughts yet", detail: "Your saved thoughts will appear here.")
                }
                ForEach(session.treeEntries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(entry.mood).resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                        Text(entry.body).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Delete") { deleting = entry }.font(.footnote.bold()).foregroundStyle(liyaAccent)
                    }.padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.top, 12)
        }.task { await session.refreshTreeEntries() }
            .sheet(item: $deleting) { entry in
                LocalConfirmation(title: "Delete this thought?", message: "This removes the saved thought from your account.", action: "Delete") {
                    deleting = nil; Task { await session.deleteTreeEntry(entry.id) }
                } cancel: { deleting = nil }.presentationDetents([.medium])
            }
    }
}

private struct MoodCalendar: View {
    @EnvironmentObject private var session: LiyaSession
    @Binding var selection: Date
    let month: Date
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private var days: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let start = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }.map(Optional.some)
    }
    private var weekdays: [String] {
        let calendar = Calendar.current
        let labels = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(labels[shift...] + labels[..<shift])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select date").font(.system(.subheadline, design: .serif).bold().italic()).foregroundStyle(liyaInk)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(weekdays.indices, id: \.self) { index in
                    Text(weekdays[index]).font(.caption2.weight(.semibold)).foregroundStyle(liyaInk.opacity(0.45))
                        .frame(maxWidth: .infinity).frame(height: 20)
                }
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        let selected = Calendar.current.isDate(day, inSameDayAs: selection)
                        let future = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: Date())
                        let entry = session.moodEntries.first { $0.day == CloudMood.dayKey(day) }
                        Button { selection = day } label: {
                            ZStack {
                                Circle().fill(selected ? liyaAccent : (future ? Color.gray.opacity(0.08) : liyaAccent.opacity(0.10)))
                                    .frame(width: 35, height: 35)
                                VStack(spacing: 0) {
                                    Text("\(Calendar.current.component(.day, from: day))").font(.caption.weight(.medium))
                                        .foregroundStyle(selected ? .white : (future ? liyaInk.opacity(0.3) : liyaAccent))
                                    if let entry {
                                        Image(entry.mood).resizable().scaledToFit().frame(width: 19, height: 19).accessibilityHidden(true)
                                    }
                                }
                            }.frame(maxWidth: .infinity).frame(minHeight: 44)
                        }.buttonStyle(.plain).disabled(future)
                            .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (entry == nil ? "" : ", mood recorded"))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    } else { Color.clear.frame(height: 44).accessibilityHidden(true) }
                }
            }
        }
    }
}

private struct DeviceMoodHistory: View {
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Earlier entries") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "These earlier entries have not been added to your account.")
                ForEach(store.entries.sorted { $0.date > $1.date }) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.date, style: .date).font(.headline)
                        Text(entry.note.isEmpty ? entry.mood.replacingOccurrences(of: "mood-", with: "") : entry.note)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.top, 12)
        }
    }
}


private struct PhotoCounts: Decodable {
    let likeCount: Int
    let commentCount: Int
    enum CodingKeys: String, CodingKey { case likeCount = "like_count", commentCount = "comment_count" }
}

@MainActor private final class PhotoEngagement: ObservableObject {
    @Published private(set) var counts: PhotoCounts?
    private var request = UUID()

    func refresh(_ session: LiyaSession, index: Int) async {
        guard let owner = session.userID, session.photos.indices.contains(index) else { counts = nil; return }
        let mediaID = session.photos[index].id
        let current = UUID(); request = current
        do {
            let rows: [PhotoCounts] = try await session.client.rpc("liya_photo_counts", params: ["p_media_id": mediaID]).execute().value
            guard request == current, session.userID == owner,
                  session.photos.indices.contains(index), session.photos[index].id == mediaID else { return }
            counts = rows.first
        } catch {
            if request == current { counts = nil }
        }
    }
}

// Sample engagement is kept separate from real account activity and keyed by
// media ID so catalog reordering cannot move it to a different post.
private struct ExamplePhotoSample {
    let likes: Int
    let comments: [String]

    static let byID: [String: ExamplePhotoSample] = [
        "example-photo-001": .init(likes: 38, comments: ["This has such a quiet feel to it.", "The details make this one memorable."]),
        "example-photo-002": .init(likes: 74, comments: ["These colours are beautiful together.", "I keep noticing something new in this photo.", "What a lovely moment to keep."]),
        "example-photo-003": .init(likes: 21, comments: ["There is something so peaceful about this."]),
        "example-photo-004": .init(likes: 56, comments: ["This made me pause for a second.", "Such a natural little moment."]),
        "example-photo-005": .init(likes: 19, comments: ["I love the light here.", "This has a story all of its own."]),
        "example-photo-006": .init(likes: 91, comments: ["The atmosphere is wonderful.", "A beautiful bit of everyday life.", "I could look at this for ages."]),
        "example-photo-007": .init(likes: 43, comments: ["This feels like a deep breath.", "The colours are so lovely."]),
        "example-photo-008": .init(likes: 27, comments: ["A little moment worth remembering."]),
        "example-photo-009": .init(likes: 64, comments: ["There is so much feeling in this.", "I really like the mood of this photo."]),
        "example-photo-010": .init(likes: 32, comments: ["This one brought a smile to my day.", "It feels wonderfully candid."]),
        "example-photo-011": .init(likes: 83, comments: ["What a beautiful scene.", "The little details are my favourite part.", "This feels like a memory in the making."]),
        "example-photo-013": .init(likes: 46, comments: ["There is a lovely calmness here.", "This is such a nice capture."]),
        "example-photo-014": .init(likes: 17, comments: ["Something about this feels really comforting."]),
        "example-photo-015": .init(likes: 69, comments: ["The whole mood of this is lovely.", "Thank you for sharing this moment."]),
        "example-photo-016": .init(likes: 35, comments: ["I love the way this feels so unhurried.", "A beautiful moment to look back on."]),
        "example-photo-017": .init(likes: 52, comments: ["This has such a lovely energy.", "The composition is wonderful.", "It feels like a little escape."]),
        "example-photo-018": .init(likes: 24, comments: ["This is the kind of moment I would keep too."]),
        "example-photo-019": .init(likes: 61, comments: ["So much character in one photo.", "I love how natural this feels."]),
        "example-photo-020": .init(likes: 29, comments: ["A small moment with a lot of warmth.", "This really brightened my day."])
    ]
}

private struct ExamplePhotoRow: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    let index: Int
    @State private var options = false
    @StateObject private var engagement = PhotoEngagement()
    private var sample: ExamplePhotoSample? {
        guard session.photos.indices.contains(index) else { return nil }
        return ExamplePhotoSample.byID[session.photos[index].id]
    }
    private var displayName: String {
        let photoID = session.photos.indices.contains(index) ? session.photos[index].id : nil
        return ExampleVideoCreator.byVideoID.values.first { $0.photoID == photoID }?.name ?? "Liya collection"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NavigationLink { ExampleProfileView(index: index, displayName: displayName) } label: {
                    HStack(spacing: 8) { ExampleAvatar(index: index); VStack(alignment: .leading) {
                        Text(displayName).font(.subheadline.bold())
                        Text("Collection").font(.caption).foregroundStyle(.secondary)
                    } }.foregroundStyle(liyaInk)
                }.buttonStyle(.plain)
                Spacer()
                Button { store.toggleFollow(index) } label: {
                    Text(store.followedExamples.contains(index) ? "Following" : "Follow")
                        .font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).background(liyaGradient, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel(store.followedExamples.contains(index) ? "Unfollow example" : "Follow example")
                Button { options = true } label: { Image("more").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("More options")
            }
            NavigationLink { ExamplePhotoDetail(index: index) } label: {
                CloudPhoto(index: index).frame(maxWidth: .infinity).frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).accessibilityLabel("Open post")
            HStack(spacing: 18) {
                Button { Task { await session.toggleLike(kind: "photo", index: index); await engagement.refresh(session, index: index) } } label: {
                    HStack(spacing: 6) {
                        Image(session.isLiked(kind: "photo", index: index) ? "video-like-on" : "video-like-off")
                            .resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                        Text("\(session.isLiked(kind: "photo", index: index) ? "Liked" : "Like") · \(engagement.counts.map { String($0.likeCount) } ?? "—")")
                    }.font(.caption.weight(.medium))
                        .foregroundStyle(session.isLiked(kind: "photo", index: index) ? liyaAccent : liyaInk)
                        .frame(minHeight: 44)
                }.buttonStyle(.plain).disabled(!session.likesReady || session.likesLoading)
                    .accessibilityAddTraits(session.isLiked(kind: "photo", index: index) ? .isSelected : [])
                NavigationLink { ExamplePhotoDetail(index: index) } label: {
                    HStack(spacing: 6) {
                        Image("comment").resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                        Text("Comments · \(engagement.counts.map { String($0.commentCount) } ?? "—")")
                    }.font(.caption.weight(.medium)).foregroundStyle(liyaInk).frame(minHeight: 44)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            if let sample {
                Text("Sample: \(sample.likes) likes · \(sample.comments.count) comments")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .sheet(isPresented: $options) { ExampleOptionsView(index: index, reportTarget: "post") }
            .onLiyaChange(of: session.catalogGeneration) { _ in Task { await engagement.refresh(session, index: index) } }
            .onLiyaChange(of: social.syncGeneration) { _ in Task { await engagement.refresh(session, index: index) } }
            .onAppear { Task { await engagement.refresh(session, index: index) } }
    }
}


struct ExampleCommentsView: View {
    @EnvironmentObject private var store: LocalStore
    let index: Int
    @State private var text = ""
    var body: some View {
        PageShell(title: "Private notes") {
            VStack(alignment: .leading, spacing: 14) {
                OfflineNote(text: "These notes are private and are not shared.")
                ForEach(store.comments.filter { $0.photoIndex == index }) { comment in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(comment.text).foregroundStyle(liyaInk)
                        HStack {
                            Text(comment.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Delete") { store.deleteComment(comment.id) }.font(.caption.bold()).foregroundStyle(liyaAccent)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                TextField("Write a private note", text: $text, axis: .vertical).lineLimit(2...6).padding(14)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                PrimaryButton(title: "Save note", disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    store.addComment(text.trimmingCharacters(in: .whitespacesAndNewlines), photoIndex: index)
                    text = ""
                }
            }.padding(.top, 12)
        }
    }
}


struct ExamplePhotoDetail: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @State private var options = false
    @State private var showProfileSetup = false
    @State private var comments: [VideoComment] = []
    @State private var comment = ""
    @State private var attempt = UUID()
    @State private var loading = false
    @State private var sending = false
    @State private var error: String?
    @State private var loadID = UUID()
    @StateObject private var engagement = PhotoEngagement()
    let index: Int
    private var mediaID: String? { session.photos.indices.contains(index) ? session.photos[index].id : nil }
    private var sample: ExamplePhotoSample? { mediaID.flatMap { ExamplePhotoSample.byID[$0] } }
    private var displayName: String {
        ExampleVideoCreator.byVideoID.values.first { $0.photoID == mediaID }?.name ?? "Liya collection"
    }
    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                DuoControlRegion { _ in
                    HStack {
                        Button { dismiss() } label: { Image("back").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("Back")
                        Spacer(minLength: 0)
                        Text("Post").font(.headline).foregroundStyle(liyaInk)
                        Spacer(minLength: 0)
                        Button { options = true } label: { Image("more").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("Report or block")
                    }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                }.frame(height: 44)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        NavigationLink { ExampleProfileView(index: index, displayName: displayName) } label: {
                            HStack(spacing: 10) {
                                ExampleAvatar(index: index)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(displayName).font(.subheadline.bold()).foregroundStyle(liyaInk)
                                    Text("Collection").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        if ExamplePhotoAllocation.isPost(index, in: session.photos) {
                            CloudPhoto(index: index).frame(maxWidth: .infinity).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Text("This post is no longer available.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 22) {
                            Button { Task { await session.toggleLike(kind: "photo", index: index); await engagement.refresh(session, index: index) } } label: {
                                HStack(spacing: 6) {
                                    Image(session.isLiked(kind: "photo", index: index) ? "video-like-on" : "video-like-off")
                                        .resizable().scaledToFit().frame(width: 23, height: 23).accessibilityHidden(true)
                                    Text("\(session.isLiked(kind: "photo", index: index) ? "Liked" : "Like") · \(engagement.counts.map { String($0.likeCount) } ?? "—")")
                                }
                            }.buttonStyle(.plain).disabled(!session.likesReady || session.likesLoading)
                            HStack(spacing: 6) {
                                Image("comment").resizable().scaledToFit().frame(width: 23, height: 23)
                                Text("Comments · \(engagement.counts.map { String($0.commentCount) } ?? "—")")
                            }
                            Spacer(minLength: 0)
                        }.font(.subheadline.weight(.semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                        if let sample {
                            Text("Sample: \(sample.likes) likes · \(sample.comments.count) comments")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let likesError = session.likesError {
                            Text(likesError).font(.footnote).foregroundStyle(.red)
                            Button("Retry likes") { Task { await session.refreshLikes() } }.foregroundStyle(liyaAccent)
                        }
                        Text("Comments").font(.headline).foregroundStyle(liyaInk)
                        if let sample {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Sample comments").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(Array(sample.comments.enumerated()), id: \.offset) { _, text in
                                    Text(text).font(.subheadline).foregroundStyle(liyaInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if loading { LiyaLoadingIndicator(size: 24) }
                        if !loading && error == nil && comments.isEmpty && sample == nil { Text("Be the first to share a thought.").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(comments) { item in
                            HStack(alignment: .top, spacing: 10) {
                                NavigationLink { CommunityPersonView(personID: item.ownerID) } label: {
                                    SocialAvatar(personID: item.ownerID).frame(width: 36, height: 36).clipShape(Circle())
                                }.buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 4) {
                                    NavigationLink(item.ownerID == session.userID ? "You" : (social.person(item.ownerID)?.displayName ?? "Liya member")) { CommunityPersonView(personID: item.ownerID) }
                                        .font(.caption.bold()).foregroundStyle(liyaAccent)
                                    Text(item.body).font(.subheadline).foregroundStyle(liyaInk).fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if item.ownerID == session.userID {
                                    Button("Delete") { Task { if await social.deleteVideoComment(session, id: item.id) { await refresh() } else { error = "Couldn't delete this comment. Please try again." } } }
                                        .font(.caption.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                                }
                            }
                        }
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                            Button("Try again") { Task { await refresh() } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                        }
                        HStack(alignment: .bottom, spacing: 10) {
                            TextField("Write a comment…", text: Binding(get: { comment }, set: { comment = $0; attempt = UUID() }), axis: .vertical)
                                .lineLimit(1...4).padding(12).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16)).disabled(sending)
                            Button(sending ? "Sending…" : "Send") { send() }
                                .font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 16).frame(minHeight: 44)
                                .background(liyaGradient.opacity(sending || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || comment.count > 2000 ? 0.45 : 1), in: Capsule())
                                .disabled(sending || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || comment.count > 2000)
                        }
                    }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 30 + tabBarClearance)
                        .modifier(AdaptiveContainerMargins())
                }.scrollDismissesKeyboard(.interactively)
            }
        }.navigationBarHidden(true)
            .navigationDestination(isPresented: $showProfileSetup) { CommunityJoinView() }
            .sheet(isPresented: $options) { ExampleOptionsView(index: index, reportTarget: "post") }
            .task(id: mediaID) { await refresh() }
            .onLiyaChange(of: social.syncGeneration) { _ in Task { await refresh() } }
    }

    private func refresh() async {
        guard let mediaID, let owner = session.userID else { comments = []; return }
        let current = UUID(); loadID = current; loading = true; error = nil
        do {
            let rows = try await social.videoComments(session, mediaID: mediaID)
            guard loadID == current, self.mediaID == mediaID, session.userID == owner else { return }
            comments = rows; loading = false
        } catch {
            guard loadID == current else { return }
            loading = false; self.error = "Couldn't load comments. Please try again."
        }
        await engagement.refresh(session, index: index)
    }

    private func send() {
        let body = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sending, !body.isEmpty, body.count <= 2000, let mediaID else { return }
        guard !social.loading, social.error == nil else { error = "Couldn't load your profile. Please try again."; return }
        guard social.isJoined(session) else { showProfileSetup = true; return }
        sending = true; error = nil
        Task {
            if await social.sendVideoComment(session, id: attempt, mediaID: mediaID, body: body) {
                comment = ""; attempt = UUID(); await refresh()
            } else { error = "Couldn't send your comment. Your text is still here." }
            sending = false
        }
    }
}
