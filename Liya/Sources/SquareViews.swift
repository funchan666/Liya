import SwiftUI
import UIKit

struct SquareHome: View {
    @EnvironmentObject private var store: LocalStore
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
                    OfflineNote(text: "Local preview · Your entries stay on this device. The community is not connected yet.")
                    NavigationLink { ComposeHome() } label: {
                        Image("square-prompt").resizable().scaledToFit().frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("Write a draft")
                    HStack(alignment: .top, spacing: 10) {
                        feature("ai-card", label: "AI chat") { AIChatView() }
                        feature("diary-card", label: "Mood diary") { MoodDiaryView() }
                        feature("tree-card", label: "Mood tree hole") { TreeHoleView() }
                    }
                    HStack { Text("Community").font(.title3.bold()); Spacer() }
                    if store.drafts.contains(where: { $0.publishedLocally == true }) {
                        Text("Your local posts").font(.headline).foregroundStyle(liyaInk)
                        LazyVStack(spacing: 16) {
                            ForEach(store.drafts.filter { $0.publishedLocally == true }) { post in LocalPostCard(post: post) }
                        }
                    }
                    Text("Example photos · The community service is not connected.").font(.footnote).foregroundStyle(.secondary)
                    LazyVStack(spacing: 16) {
                        ForEach(0..<Examples.photoCount, id: \.self) { index in
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

struct AIChatView: View {
    @AppStorage("liya.aiDraft") private var draft = ""
    var body: some View {
        ZStack {
            LiyaBackground(name: "color-background")
            GeometryReader { geometry in
              ScrollView {
               VStack(spacing: 16) {
                PageHeader(title: "AI chat", light: true)
                Image("ai-heading").resizable().scaledToFit().frame(width: 190, height: 72).accessibilityLabel("AI chat")
                Spacer()
                Text("AI chat is not connected yet.").font(.headline).foregroundStyle(.white)
                Text("Your words will not be sent until a service is configured.").font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Give me some positive energy", "How can I feel calmer?", "Tell me a heartwarming story"], id: \.self) { prompt in
                        Button { draft = draft.isEmpty ? prompt : draft + "\n" + prompt } label: {
                            Text(prompt).font(.subheadline).foregroundStyle(liyaInk).padding(10)
                                .background(.white.opacity(0.85), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                TextField("Write a message", text: $draft, axis: .vertical)
                    .lineLimit(1...4).padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                PrimaryButton(title: "Send unavailable", disabled: true) { }
               }.padding(.horizontal, 20).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
              }
            }
        }.navigationBarHidden(true)
    }
}

struct MoodDiaryView: View {
    @EnvironmentObject private var store: LocalStore
    @State private var date = Date()
    @State private var mood = "mood-happy"
    @State private var note = ""
    @State private var saved = false
    @State private var dirty = false
    private let moods = [("mood-happy", "Happy"), ("mood-calm", "Calm"), ("mood-upset", "Upset"), ("mood-blue", "Blue"), ("mood-teal", "Tired")]

    var body: some View {
        PageShell(title: "Mood Diary") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    diaryStat("Total record days", value: store.entries.count, tint: .blue)
                    diaryStat("Happy days", value: store.entries.filter { $0.mood == "mood-happy" }.count, tint: .pink)
                }
                Text("Mood journal").font(.title3.bold()).foregroundStyle(liyaInk)
                OfflineNote(text: "Your journal is stored only on this device.")
                MoodCalendar(selection: Binding(get: { date }, set: { newDate in
                    if dirty { store.savePendingMood(mood, note: note, date: date) }
                    date = newDate
                    loadEntry()
                }))
                Text("How are you feeling?").font(.headline).foregroundStyle(liyaInk)
                HStack(spacing: 6) {
                    ForEach(moods.indices, id: \.self) { index in
                        let item = moods[index]
                        Button { mood = item.0; saved = false; dirty = true } label: {
                            Image(item.0).resizable().scaledToFit().frame(maxWidth: 52).padding(5)
                                .background(mood == item.0 ? liyaAccent.opacity(0.16) : .white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityLabel(item.1).accessibilityAddTraits(mood == item.0 ? .isSelected : [])
                    }
                }
                Text("Note").font(.headline).foregroundStyle(liyaInk)
                TextField("Add a few words", text: Binding(get: { note }, set: { note = $0; saved = false; dirty = true }), axis: .vertical).lineLimit(4...8).padding(14)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                PrimaryButton(title: "Save entry") {
                    store.saveMood(mood, note: note, date: date)
                    store.clearPendingMood(date: date)
                    dirty = false; saved = true
                }
                if saved { Text("Saved on this device").font(.footnote).foregroundStyle(liyaAccent) }
            }.padding(.top, 12)
        }.onAppear(perform: loadEntry)
            .onDisappear { if dirty { store.savePendingMood(mood, note: note, date: date) } }
    }

    private func loadEntry() {
        let entry = store.entries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
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
    @AppStorage("liya.treeDraft") private var text = ""
    @State private var saved = false
    @State private var mood = "mood-calm"
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
                Text("Write privately for now. Sharing is not connected.").font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    ForEach(moods, id: \.self) { item in
                        Button { mood = item } label: {
                            Image(item).resizable().scaledToFit().frame(width: 38, height: 38).padding(5)
                                .background(mood == item ? .white.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel(item.replacingOccurrences(of: "mood-", with: ""))
                            .accessibilityAddTraits(mood == item ? .isSelected : [])
                    }
                }
                TextField("What is on your mind?", text: $text, axis: .vertical).lineLimit(4...8).padding(14)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                PrimaryButton(title: "Save as a private draft", disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    store.saveDraft(text.trimmingCharacters(in: .whitespacesAndNewlines), mood: mood); text = ""; saved = true
                }
                if saved { Text("Saved on this device").font(.footnote).foregroundStyle(.white) }
              }.padding(.horizontal, 20).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
             }
            }
        }.navigationBarHidden(true)
    }
}

private struct MoodCalendar: View {
    @EnvironmentObject private var store: LocalStore
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
                                if let entry = store.entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
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


private struct ExamplePhotoRow: View {
    @EnvironmentObject private var store: LocalStore
    let index: Int
    @State private var photo: UIImage?
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
                    Text(store.followedExamples.contains(index) ? "Following" : "Follow")
                        .font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).background(liyaGradient, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel(store.followedExamples.contains(index) ? "Unfollow example locally" : "Follow example locally")
                Button { options = true } label: { Image("more").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("More options")
            }
            if let photo {
                NavigationLink { ExamplePhotoDetail(index: index) } label: {
                    Image(uiImage: photo).resizable().scaledToFit().frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityLabel("Open example photo \(index + 1)")
            } else {
                Text("Photo unavailable").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            }
            HStack(spacing: 18) {
                Button { store.toggleLike(index) } label: {
                    HStack(spacing: 6) {
                        Image("heart").resizable().scaledToFit().frame(width: 24, height: 24)
                        Text(store.likedPhotos.contains(index) ? "Liked locally" : "Like locally")
                    }.font(.caption).foregroundStyle(liyaInk)
                }.buttonStyle(.plain)
                NavigationLink { ExampleCommentsView(index: index) } label: {
                    HStack(spacing: 6) {
                        Image("comment").resizable().scaledToFit().frame(width: 24, height: 24)
                        Text("Local notes (\(store.comments.filter { $0.photoIndex == index }.count))")
                    }.font(.caption).foregroundStyle(liyaInk)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .onAppear { photo = Examples.photo(index) }
            .onDisappear { photo = nil }
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
    @EnvironmentObject private var store: LocalStore
    @State private var options = false
    let index: Int
    var body: some View {
        PageShell(title: "Example photo") {
            VStack(alignment: .leading, spacing: 14) {
                OfflineNote(text: "Illustrative photo · Your interactions are saved only on this device.")
                HStack {
                    NavigationLink { ExampleProfileView(index: index) } label: {
                        HStack { ExampleAvatar(index: index); Text("Example profile \(index + 1)").foregroundStyle(liyaInk); Spacer() }
                    }.buttonStyle(.plain)
                    Button { options = true } label: { Image("more").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("More options")
                }
                if let photo = Examples.photo(index) { Image(uiImage: photo).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14)) }
                HStack {
                    Button { store.toggleLike(index) } label: {
                        Text(store.likedPhotos.contains(index) ? "Liked locally" : "Like locally").foregroundStyle(liyaAccent)
                    }.buttonStyle(.plain)
                    Spacer()
                    NavigationLink("Private notes") { ExampleCommentsView(index: index) }.foregroundStyle(liyaAccent)
                }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            }.padding(.top, 12)
        }.sheet(isPresented: $options) { ExampleOptionsView(index: index, reportTarget: "post") }
    }
}
