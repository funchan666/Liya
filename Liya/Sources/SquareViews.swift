import SwiftUI
import UIKit

struct SquareHome: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image("square-title").resizable().scaledToFit().frame(width: 145, height: 45).accessibilityLabel("Emotional Square")
                        Spacer()
                        Text("Liya").font(.headline).foregroundStyle(liyaAccent)
                    }
                    OfflineNote(text: "Journal entries stay private. Community posts are visible to signed-in members.")
                    if let error = session.likesError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("Retry likes") { Task { await session.refreshLikes() } }.foregroundStyle(liyaAccent)
                    }
                    NavigationLink { ComposeHome() } label: {
                        Image("square-prompt").resizable().scaledToFit().frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("Write a draft")
                    HStack(alignment: .top, spacing: 10) {
                        feature("ai-card", label: "AI chat") { AutomaticChatView() }
                        feature("diary-card", label: "Mood diary") { MoodDiaryView() }
                        feature("tree-card", label: "Mood tree hole") { TreeHoleView() }
                    }
                    CommunityFeed()
                    if store.drafts.contains(where: { $0.publishedLocally == true }) {
                        Text("Your local posts").font(.headline).foregroundStyle(liyaInk)
                        LazyVStack(spacing: 16) {
                            ForEach(store.drafts.filter { $0.publishedLocally == true }) { post in LocalPostCard(post: post) }
                        }
                    }
                    Text("Example photos").font(.footnote).foregroundStyle(.secondary)
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
                            if !store.blockedExamples.contains(index) { ExamplePhotoRow(index: index) }
                        }
                    }
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
            }
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
    @State private var mood = "mood-happy"
    @State private var note = ""
    @State private var saved = false
    @State private var dirty = false
    @State private var saving = false
    private let moods = [("mood-happy", "Happy"), ("mood-calm", "Calm"), ("mood-upset", "Upset"), ("mood-blue", "Blue"), ("mood-teal", "Tired")]

    var body: some View {
        PageShell(title: "Mood Diary") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    diaryStat("Total record days", value: session.moodEntries.count, tint: .blue)
                    diaryStat("Happy days", value: session.moodEntries.filter { $0.mood == "mood-happy" }.count, tint: .pink)
                }
                Text("Mood journal").font(.title3.bold()).foregroundStyle(liyaInk)
                OfflineNote(text: "Saved entries belong to your account. Unsent drafts stay on this device.")
                if !store.entries.isEmpty {
                    NavigationLink("Earlier entries on this device") { DeviceMoodHistory() }.foregroundStyle(liyaAccent)
                }
                if session.moodLoading { Text("Loading journal…").font(.footnote).foregroundStyle(.secondary) }
                if let error = session.moodError {
                    OfflineNote(text: error)
                    Button("Reload journal") { Task { await session.refreshMoods() } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                MoodCalendar(selection: Binding(get: { date }, set: { newDate in
                    if dirty { store.savePendingMood(mood, note: note, date: date) }
                    date = newDate
                    loadEntry()
                })).disabled(saving || session.moodLoading)
                Text("How are you feeling?").font(.headline).foregroundStyle(liyaInk)
                HStack(spacing: 6) {
                    ForEach(moods.indices, id: \.self) { index in
                        let item = moods[index]
                        Button { mood = item.0; saved = false; dirty = true } label: {
                            Image(item.0).resizable().scaledToFit().frame(maxWidth: 52).padding(5)
                                .background(mood == item.0 ? liyaAccent.opacity(0.16) : .white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).disabled(saving || session.moodLoading).accessibilityLabel(item.1).accessibilityAddTraits(mood == item.0 ? .isSelected : [])
                    }
                }
                Text("Note").font(.headline).foregroundStyle(liyaInk)
                TextField("Add a few words", text: Binding(get: { note }, set: { note = $0; saved = false; dirty = true }), axis: .vertical).lineLimit(4...8).padding(14)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14)).disabled(saving || session.moodLoading)
                PrimaryButton(title: saving ? "Saving…" : "Save entry", disabled: saving || session.moodLoading || session.moodError != nil) {
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
                if saved { Text("Saved to your account").font(.footnote).foregroundStyle(liyaAccent) }
            }.padding(.top, 12)
        }.task { await session.refreshMoods(); loadEntry() }
            .onChange(of: session.moodEntries) { _ in if !dirty { loadEntry() } }
            .onDisappear { if dirty { store.savePendingMood(mood, note: note, date: date) } }
    }

    private func loadEntry() {
        let entry = session.moodEntries.first { $0.day == CloudMood.dayKey(date) }
        let unsaved = store.pendingMoods.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        mood = unsaved?.mood ?? entry?.mood ?? "mood-happy"
        note = unsaved?.note ?? entry?.note ?? ""
        dirty = unsaved != nil
        saved = false
    }

    private func diaryStat(_ title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
            Text("\(value)").font(.title2.bold())
        }.foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading).padding(14)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct TreeHoleView: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @AppStorage("liya.treeDraft") private var text = ""
    @AppStorage("liya.treeSubmissionID") private var submissionID = ""
    @State private var saved = false
    @State private var saving = false
    @AppStorage("liya.treeDraftMood") private var mood = "mood-calm"
    private let moods = ["mood-happy", "mood-calm", "mood-upset", "mood-blue", "mood-teal"]
    var body: some View {
        ZStack {
            LiyaBackground(name: "tree-background")
            GeometryReader { geometry in
             ScrollView {
              VStack(spacing: 14) {
                PageHeader(title: "Mood Tree Hole", light: true)
                Spacer(minLength: 32)
                Text("Let it out").font(.title2.bold()).foregroundStyle(.white)
                Text("Keep a thought in your private account space. Sharing is not connected.").font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    ForEach(moods, id: \.self) { item in
                        Button { mood = item; submissionID = ""; saved = false } label: {
                            Image(item).resizable().scaledToFit().frame(width: 38, height: 38).padding(5)
                                .background(mood == item ? .white.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(saving).accessibilityLabel(item.replacingOccurrences(of: "mood-", with: ""))
                            .accessibilityAddTraits(mood == item ? .isSelected : [])
                    }
                }
                TextField("What is on your mind?", text: Binding(get: { text }, set: { text = $0; submissionID = ""; saved = false }), axis: .vertical).lineLimit(4...8).padding(14)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                    .disabled(saving)
                PrimaryButton(title: saving ? "Saving…" : "Save privately to account", disabled: saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000) {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if UUID(uuidString: submissionID) == nil { submissionID = UUID().uuidString }
                    guard let id = UUID(uuidString: submissionID) else { return }
                    saving = true
                    Task {
                        if await session.saveTreeEntry(id: id, mood: mood, body: value) { text = ""; submissionID = ""; saved = true }
                        saving = false
                    }
                }
                if let error = session.treeError { Text(error).font(.footnote).foregroundStyle(.white) }
                if saved { Text("Saved privately to your account").font(.footnote).foregroundStyle(.white) }
                Button("Save as a device draft") {
                    store.saveDraft(text.trimmingCharacters(in: .whitespacesAndNewlines), mood: mood); text = ""; submissionID = ""; saved = false
                }.font(.subheadline.bold()).foregroundStyle(.white).frame(minHeight: 44)
                    .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                NavigationLink("Your private thoughts") { TreeHistoryView() }.font(.subheadline.bold()).foregroundStyle(.white).frame(minHeight: 44)
              }.padding(.horizontal, 20).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
             }
            }
        }.navigationBarHidden(true)
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
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private var days: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return [] }
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
        VStack(spacing: 10) {
            HStack {
                Button { moveMonth(-1) } label: { Image("back").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline).foregroundStyle(liyaInk)
                Spacer()
                Button { moveMonth(1) } label: { Image("back").resizable().scaledToFit().frame(width: 18, height: 18).scaleEffect(x: -1, y: 1).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Next month")
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays.indices, id: \.self) { index in
                    Text(weekdays[index]).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 25)
                }
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        Button { selection = day } label: {
                            VStack(spacing: 1) {
                                Text("\(Calendar.current.component(.day, from: day))").font(.subheadline)
                                if let entry = session.moodEntries.first(where: { $0.day == CloudMood.dayKey(day) }) {
                                    Image(entry.mood).resizable().scaledToFit().frame(width: 17, height: 17).accessibilityHidden(true)
                                }
                            }.foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selection) ? .white : liyaInk)
                                .frame(maxWidth: .infinity).frame(minHeight: 44)
                                .background(Calendar.current.isDate(day, inSameDayAs: selection) ? liyaAccent : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(day > Date()).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    } else { Color.clear.frame(height: 44).accessibilityHidden(true) }
                }
            }
        }.padding(10).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
    }
    private func moveMonth(_ amount: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: amount, to: month) { month = newMonth }
    }
}

private struct DeviceMoodHistory: View {
    @EnvironmentObject private var store: LocalStore
    var body: some View {
        PageShell(title: "Earlier device entries") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "These earlier entries are stored only on this device and have not been transferred to your account.")
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


private struct ExamplePhotoRow: View {
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    @State private var options = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NavigationLink { ExampleProfileView(index: index) } label: {
                    HStack(spacing: 8) { ExampleAvatar(index: index); VStack(alignment: .leading) {
                        Text("Example profile \(index + 1)").font(.subheadline.bold())
                        Text("Illustrative content").font(.caption).foregroundStyle(.secondary)
                    } }.foregroundStyle(liyaInk)
                }.buttonStyle(.plain)
                Spacer()
                Button { store.toggleFollow(index) } label: {
                    Text(store.followedExamples.contains(index) ? "Saved example" : "Save example")
                        .font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).background(liyaGradient, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel(store.followedExamples.contains(index) ? "Unfollow example locally" : "Follow example locally")
                Button { options = true } label: { Image("more").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("More options")
            }
            NavigationLink { ExamplePhotoDetail(index: index) } label: {
                CloudPhoto(index: index).frame(maxWidth: .infinity).frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).accessibilityLabel("Open example photo \(index + 1)")
            HStack(spacing: 18) {
                Button { Task { await session.toggleLike(kind: "photo", index: index) } } label: {
                    HStack(spacing: 6) {
                        Image("heart").resizable().scaledToFit().frame(width: 24, height: 24)
                        Text(session.isLiked(kind: "photo", index: index) ? "Liked" : "Like")
                    }.font(.caption).foregroundStyle(liyaInk)
                }.buttonStyle(.plain).disabled(!session.likesReady || session.likesLoading)
                NavigationLink { ExampleCommentsView(index: index) } label: {
                    HStack(spacing: 6) {
                        Image("comment").resizable().scaledToFit().frame(width: 24, height: 24)
                        Text("Local notes (\(store.comments.filter { $0.photoIndex == index }.count))")
                    }.font(.caption).foregroundStyle(liyaInk)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .sheet(isPresented: $options) { ExampleOptionsView(index: index, reportTarget: "post") }
    }
}


struct ExampleCommentsView: View {
    @EnvironmentObject private var store: LocalStore
    let index: Int
    @State private var text = ""
    var body: some View {
        PageShell(title: "Local notes") {
            VStack(alignment: .leading, spacing: 14) {
                OfflineNote(text: "Notes on example photos stay on this device and are not shared.")
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
    @State private var options = false
    let index: Int
    var body: some View {
        PageShell(title: "Example photo") {
            VStack(alignment: .leading, spacing: 14) {
                OfflineNote(text: "Illustrative photo · Likes are saved to your account. Private notes stay on this device.")
                if let error = session.likesError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Retry likes") { Task { await session.refreshLikes() } }.foregroundStyle(liyaAccent)
                }
                HStack {
                    NavigationLink { ExampleProfileView(index: index) } label: {
                        HStack { ExampleAvatar(index: index); Text("Example profile \(index + 1)").foregroundStyle(liyaInk); Spacer() }
                    }.buttonStyle(.plain)
                    Button { options = true } label: { Image("more").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("More options")
                }
                CloudPhoto(index: index).frame(maxWidth: .infinity).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 14))
                HStack {
                    Button { Task { await session.toggleLike(kind: "photo", index: index) } } label: {
                        Text(session.isLiked(kind: "photo", index: index) ? "Liked" : "Like").foregroundStyle(liyaAccent)
                    }.buttonStyle(.plain).disabled(!session.likesReady || session.likesLoading)
                    Spacer()
                    NavigationLink("Private notes") { ExampleCommentsView(index: index) }.foregroundStyle(liyaAccent)
                }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            }.padding(.top, 12)
        }.sheet(isPresented: $options) { ExampleOptionsView(index: index, reportTarget: "post") }
    }
}
