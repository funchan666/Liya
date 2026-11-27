import SwiftUI
import UIKit

struct SquareHome: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    var body: some View {
        ZStack {
            LiyaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        HostedArtwork("square-title").scaledToFit().frame(width: 145, height: 45).accessibilityLabel(words("Emotional Square"))
                        Spacer()
                    }
                    if let error = session.likesError {
                        Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red)
                        Button(words("Retry likes")) { Task { await session.refreshLikes() } }.foregroundStyle(liyaAccent)
                    }
                    NavigationLink { ComposeHome(showsBackButton: true) } label: {
                        HostedArtwork("square-prompt", labelWhileMissing: "Write a draft").scaledToFit().frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel(words("Write a draft"))
                    HStack(alignment: .top, spacing: 10) {
                        feature("diary-card", label: "Mood diary") { MoodDiaryView() }
                        feature("tree-card", label: "Mood tree hole") { TreeHoleView() }
                    }
                    JournalPostcardLink()
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 10) { wellbeingLinks }
                    } else {
                        HStack(alignment: .top, spacing: 10) { wellbeingLinks }
                    }
                    if store.drafts.contains(where: { $0.publishedLocally == true }) {
                        Text(verbatim: words("Unshared posts")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                        LazyVStack(spacing: 16) {
                            ForEach(store.drafts.filter { $0.publishedLocally == true }) { post in LocalPostCard(post: post) }
                        }
                    }
                    Text(verbatim: words("From the collection")).font(LiyaType.text(.footnote)).foregroundStyle(.secondary)
                    if session.catalogLoading {
                        Text(verbatim: words("Loading photos…")).font(LiyaType.text(.footnote)).foregroundStyle(.secondary)
                    } else if let error = session.catalogError {
                        OfflineNote(text: error)
                        Button(words("Try again")) { Task { await session.refreshCatalog() } }.foregroundStyle(liyaAccent)
                    } else if session.photos.isEmpty {
                        EmptyState(title: "No photos yet", detail: "There are no photos to show right now.")
                    }
                    LazyVStack(spacing: 16) {
                        ForEach(Array(session.photos.enumerated()), id: \.element.id) { index, photo in
                            if CollectionPhotoRoles.isPost(index, in: session.photos) && !store.hiddenCollectionProfiles.contains(index) {
                                CollectionPhotoCard(index: index, mediaID: photo.id)
                            }
                        }
                    }
                }.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28 + tabBarClearance)
            }.refreshable {
                let ids = session.photos.indices.compactMap { index in
                    CollectionPhotoRoles.isPost(index, in: session.photos) && !store.hiddenCollectionProfiles.contains(index)
                        ? session.photos[index].id : nil
                }
                await session.refreshMediaEngagement(ids: ids)
                await session.refreshLikes()
                await social.refresh(session)
            }
        }.navigationBarHidden(true)
    }

    private func feature<Destination: View>(_ image: String, label: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HostedArtwork(image, labelWhileMissing: label).scaledToFit().frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityLabel(words(label))
    }

    @ViewBuilder private var wellbeingLinks: some View {
        wellbeingLink("wellbeing-quiet", title: "A quiet moment", subtitle: "Take a gentle pause") { QuietMomentView() }
        wellbeingLink("wellbeing-reflections", title: "Mood reflections", subtitle: "Look back on your days") { MoodReflectionsView() }
    }

    private func wellbeingLink<Destination: View>(_ image: String, title: String, subtitle: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center) {
                    HostedArtwork(image).scaledToFit().frame(width: 76, height: 64).accessibilityHidden(true)
                    Spacer(minLength: 2)
                    HostedArtwork("back").scaledToFit().frame(width: 12, height: 12)
                        .scaleEffect(x: -1, y: 1).opacity(0.55).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(liyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: words(subtitle)).font(LiyaType.text(.caption)).foregroundStyle(liyaInk.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
                .background(.white.opacity(0.91), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(liyaAccent.opacity(0.11), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: words(title)))
            .accessibilityHint(Text(verbatim: words(subtitle)))
    }
}

struct MoodDiaryView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var checkout: CoinCheckout
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    @State private var date: Date
    @State private var month: Date
    @State private var mood = "mood-happy"
    @State private var note = ""
    @State private var saved = false
    @State private var dirty = false
    @State private var saving = false
    private let moods = [("mood-teal", "Tired"), ("mood-happy", "Happy"), ("mood-yellow", "Thoughtful"), ("mood-calm", "Calm"), ("mood-blue", "Blue"), ("mood-upset", "Upset")]

    init(initialDate: Date = Date()) {
        _date = State(initialValue: initialDate)
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: initialDate)?.start ?? initialDate)
    }

    var body: some View {
        let prism = checkout.isActive(.moodPrism)
        PageShell(title: "Mood Diary") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    diaryStat("diary-count", label: "Total record days", value: session.moodEntries.count)
                    diaryStat("diary-happy", label: "Happy days", value: session.moodEntries.filter { $0.feelingKey == "mood-happy" }.count)
                }
                JournalPostcardLink(openedFromDiary: true)
                NavigationLink { MoodReflectionsView() } label: {
                    HStack(spacing: 10) {
                        HostedArtwork("mood-calm").scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: words("Mood reflections")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                            Text(verbatim: words("Explore your recent entries")).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        HostedArtwork("back").scaledToFit().frame(width: 14, height: 14).scaleEffect(x: -1, y: 1).accessibilityHidden(true)
                    }.padding(12).frame(minHeight: 56).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                HStack(alignment: .center) {
                    Text(verbatim: words("Mood journal")).font(.system(.title3, design: .serif).bold().italic())
                        .foregroundStyle(prism ? liyaAccent : liyaInk)
                    Spacer(minLength: 8)
                    yearControl
                }
                monthSelector
                if !store.entries.isEmpty {
                    NavigationLink(words("Earlier entries")) { DeviceMoodHistory() }
                        .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                if session.moodLoading {
                    HStack(spacing: 8) { LiyaLoadingIndicator(size: 24); Text(verbatim: words("Loading journal…")).font(LiyaType.text(.footnote)).foregroundStyle(.secondary) }
                }
                if let error = session.moodError {
                    OfflineNote(text: error)
                    Button(words("Reload journal")) { Task { await session.refreshMoods() } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                }
                VStack(alignment: .leading, spacing: 14) {
                    MoodCalendar(selection: Binding(get: { date }, set: selectDate), month: month)
                        .disabled(saving || session.moodLoading)
                    moodSelector
                        .disabled(saving || session.moodLoading)
                    TextField(words("Add a note (optional)"), text: Binding(get: { note }, set: { note = $0; saved = false; dirty = true }), axis: .vertical)
                        .lineLimit(2...5).padding(12).font(LiyaType.detail)
                        .background(prism ? Color.white.opacity(0.88) : Color(red: 0.97, green: 0.96, blue: 0.99),
                                    in: RoundedRectangle(cornerRadius: 12))
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
                    if saved { Text(verbatim: words("Mood recorded")).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(liyaAccent) }
                }
                .padding(14)
                .background(prism ? Color(red: 0.93, green: 0.88, blue: 1) : Color.white.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: liyaInk.opacity(0.07), radius: 8, x: 0, y: 3)
            }.padding(.top, 12).modifier(AdaptiveContainerMargins())
        }.task { await session.refreshMoods(); loadEntry() }
            .onLiyaChange(of: session.moodEntries) { _ in if !dirty { loadEntry() } }
            .onDisappear { if dirty { store.savePendingMood(mood, note: note, date: date) } }
    }

    private var yearControl: some View {
        HStack(spacing: 0) {
            Button { moveYear(-1) } label: {
                HostedArtwork("back", labelWhileMissing: "Back").scaledToFit().frame(width: 12, height: 12).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(words("Previous year"))
            Text(month.formatted(.dateTime.year())).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                .monospacedDigit()
            Button { moveYear(1) } label: {
                HostedArtwork("back").scaledToFit().frame(width: 12, height: 12).scaleEffect(x: -1, y: 1).frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(Calendar.current.component(.year, from: month) >= Calendar.current.component(.year, from: Date()))
                .accessibilityLabel(words("Next year"))
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
                                    .font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(selected ? .white : liyaInk.opacity(0.55))
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
            Text(verbatim: words("How are you feeling?")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(moods.indices, id: \.self) { index in
                        let item = moods[index]
                        Button { mood = item.0; saved = false; dirty = true } label: {
                            HostedArtwork(item.0).scaledToFit().frame(width: 42, height: 42)
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
        let entry = session.moodEntries.first { $0.dayStamp == JournalDayEntry.dayKey(date) }
        let unsaved = store.pendingMoods.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        mood = unsaved?.mood ?? entry?.feelingKey ?? "mood-happy"
        note = unsaved?.note ?? entry?.reflectionText ?? ""
        dirty = unsaved != nil
        saved = false
    }

    private func diaryStat(_ image: String, label: String, value: Int) -> some View {
        HostedArtwork(image).aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { size in
                    Text("\(value)").font(LiyaType.text(.title2, weight: .semibold))
                        .foregroundStyle(.white).monospacedDigit()
                        .padding(.leading, size.size.width * 0.12).padding(.top, size.size.height * 0.49)
                }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(value)")
    }
}

private struct MoodReflectionsView: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    @State private var days = 7
    private let moods = [("mood-happy", "Happy"), ("mood-calm", "Calm"), ("mood-yellow", "Thoughtful"), ("mood-teal", "Tired"), ("mood-blue", "Blue"), ("mood-upset", "Upset")]

    private var recentEntries: [JournalDayEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let first = calendar.date(byAdding: .day, value: 1 - days, to: today) else { return [] }
        let lower = JournalDayEntry.dayKey(first), upper = JournalDayEntry.dayKey(today)
        return session.moodEntries.filter { $0.dayStamp >= lower && $0.dayStamp <= upper }.sorted { $0.dayStamp > $1.dayStamp }
    }

    var body: some View {
        PageShell(title: "Mood reflections") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    HostedArtwork("diary-happy").scaledToFit().frame(width: 90, height: 90).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: words("Your days, at a glance")).font(LiyaType.text(.title3, weight: .bold)).foregroundStyle(liyaInk)
                        Text(verbatim: words("A gentle look back at the moods you recorded.")).font(LiyaType.detail).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    periodButton("Last 7 days", count: 7)
                    periodButton("Last 30 days", count: 30)
                }
                if session.moodLoading {
                    HStack(spacing: 8) { LiyaLoadingIndicator(size: 24); Text(verbatim: words("Loading journal…")).font(LiyaType.text(.footnote)).foregroundStyle(.secondary) }
                } else if let error = session.moodError {
                    OfflineNote(text: error)
                    Button(words("Reload journal")) { Task { await session.refreshMoods() } }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                } else if recentEntries.isEmpty {
                    VStack(spacing: 12) {
                        HostedArtwork("empty-art").scaledToFit().frame(width: 78, height: 72).accessibilityHidden(true)
                        Text(verbatim: words("No moods recorded in this period")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk).multilineTextAlignment(.center)
                        Text(verbatim: words("Your reflections will appear after you record a mood."))
                            .font(LiyaType.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(24)
                    NavigationLink { MoodDiaryView() } label: {
                        Text(verbatim: words("Record a mood")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(minHeight: 48).background(liyaGradient, in: Capsule())
                    }.buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(verbatim: words("Moods you recorded")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                        HStack(spacing: 4) {
                            Text("\(recentEntries.count)").monospacedDigit()
                            Text(verbatim: words("recorded days"))
                        }.font(LiyaType.detail).foregroundStyle(.secondary)
                        ForEach(moods.indices, id: \.self) { index in
                            let item = moods[index]
                            let count = recentEntries.filter { $0.feelingKey == item.0 }.count
                            if count > 0 {
                                HStack(spacing: 10) {
                                    HostedArtwork(item.0).scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                                    Text(verbatim: words(item.1)).font(LiyaType.text(.subheadline, weight: .medium)).foregroundStyle(liyaInk)
                                    Spacer()
                                    Text("\(count)").font(LiyaType.text(.subheadline, weight: .semibold)).monospacedDigit().foregroundStyle(liyaAccent)
                                }.frame(minHeight: 38).accessibilityElement(children: .combine)
                            }
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
                    Text(verbatim: words("Recent entries")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                    LazyVStack(spacing: 10) {
                        ForEach(recentEntries) { entry in
                            if let day = entry.recordedDate {
                                NavigationLink { MoodDiaryView(initialDate: day) } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        HostedArtwork(entry.feelingKey).scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaInk)
                                            if entry.reflectionText.isEmpty {
                                                Text(verbatim: words(entry.feelingName)).font(LiyaType.detail).foregroundStyle(.secondary)
                                            } else {
                                                Text(entry.reflectionText).font(LiyaType.detail).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                                            }
                                        }
                                        Spacer(minLength: 4)
                                        HostedArtwork("back").scaledToFit().frame(width: 14, height: 14).scaleEffect(x: -1, y: 1).accessibilityHidden(true)
                                    }.padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(.top, 16).modifier(AdaptiveContainerMargins())
        }.task { await session.refreshMoods() }
    }

    private func periodButton(_ title: String, count: Int) -> some View {
        Button { days = count } label: {
            Text(verbatim: words(title)).font(LiyaType.text(.subheadline, weight: .semibold))
                .foregroundStyle(days == count ? .white : liyaAccent).frame(maxWidth: .infinity).frame(minHeight: 44)
                .background { if days == count { Capsule().fill(liyaGradient) } else { Capsule().fill(.white.opacity(0.85)) } }
        }.buttonStyle(.plain).accessibilityAddTraits(days == count ? .isSelected : [])
    }

}

private struct QuietMomentView: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.liyaTabActive) private var tabActive
    @State private var remaining = 60
    @State private var running = false
    @State private var deadline: Date?

    private var prompt: String {
        if remaining > 40 { return "Notice three things you can see." }
        if remaining > 20 { return "Notice two sounds around you." }
        return "Notice one sensation you can feel."
    }

    var body: some View {
        PageShell(title: "A quiet moment") {
            VStack(alignment: .center, spacing: 20) {
                HostedArtwork("mood-calm").scaledToFit().frame(width: 96, height: 96).accessibilityHidden(true)
                Text(verbatim: words("Make a little room for yourself")).font(LiyaType.text(.title2, weight: .bold)).foregroundStyle(liyaInk).multilineTextAlignment(.center)
                Text(verbatim: words("Take a minute to notice the world around you, at your own pace."))
                    .font(LiyaType.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
                VStack(spacing: 14) {
                    Text(verbatim: words(remaining == 0 ? "A moment just for you" : prompt))
                        .font(LiyaType.text(.title3, weight: .semibold)).foregroundStyle(liyaInk).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if remaining == 0 {
                        Text(verbatim: words("Finished")).font(LiyaType.text(.title2, weight: .semibold)).foregroundStyle(liyaAccent)
                    } else {
                        Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                            .font(LiyaType.text(.title2, weight: .semibold)).monospacedDigit().foregroundStyle(liyaAccent)
                    }
                    Text(verbatim: words(remaining == 0 ? "You can return whenever you need a pause." : "There is no perfect way to do this."))
                        .font(LiyaType.text(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 180).padding(16)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22))
                PrimaryButton(title: running ? "Pause" : (remaining == 60 ? "Begin" : (remaining == 0 ? "Begin again" : "Resume"))) {
                    if running { pause() } else { start() }
                }
                if remaining < 60 {
                    Button {
                        running = false; deadline = nil; remaining = 60
                    } label: {
                        Text(verbatim: words("Start over")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaAccent)
                            .frame(maxWidth: .infinity).frame(minHeight: 44)
                            .background(.white.opacity(0.85), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: 440).frame(maxWidth: .infinity).padding(.top, 32).modifier(AdaptiveContainerMargins())
        }
        .task(id: running) {
            while running && !Task.isCancelled {
                guard let deadline else { break }
                let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                remaining = seconds
                if seconds == 0 { running = false; self.deadline = nil; break }
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { break }
            }
        }
        .onLiyaChange(of: scenePhase) { phase in if phase != .active { pause() } }
        .onLiyaChange(of: tabActive) { active in if !active { pause() } }
        .onDisappear { pause() }
    }

    private func start() {
        guard scenePhase == .active, tabActive else { return }
        if remaining == 0 { remaining = 60 }
        deadline = Date().addingTimeInterval(TimeInterval(remaining))
        running = true
    }

    private func pause() {
        guard running else { return }
        if let deadline { remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow))) }
        self.deadline = nil
        running = false
    }
}

private struct TreeThought: Identifiable {
    let id: String
    let body: String
    let mood: String
    let post: SocialPost?
}

struct TreeHoleView: View {
    @Environment(\.liyaWords) private var words
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var social: SocialStore
    @AppStorage("liya.treeDraft") private var text = ""
    @AppStorage("liya.treeSubmissionID") private var submissionID = ""
    @AppStorage("liya.treeHiddenSuggestions") private var hiddenSuggestions = ""
    @AppStorage("liya.treeDraftMood") private var mood = "mood-calm"
    @State private var selectedThought: TreeThought?
    @State private var thoughtDetent: PresentationDetent = .fraction(0.48)
    @State private var notice: String?
    @State private var actionError: String?
    @State private var saving = false
    @State private var drifting = false
    private let moods = ["mood-teal", "mood-happy", "mood-yellow", "mood-calm", "mood-blue", "mood-upset"]

    private var thoughts: [TreeThought] {
        let community = social.posts.filter { $0.tags.contains("tree-hole") && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(30).map { post in
                TreeThought(id: post.id.uuidString, body: post.body,
                            mood: post.tags.first(where: { moods.contains($0) }) ?? "mood-calm", post: post)
            }
        let hidden = Set(hiddenSuggestions.split(separator: ",").map(String.init))
        let ideas = session.curatedTreePrompts.compactMap { item -> TreeThought? in
            let id = "suggestion-\(item.promptOrder)"
            return hidden.contains(id) ? nil : TreeThought(id: id, body: item.writingPrompt, mood: item.feelingKey, post: nil)
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
                        TextField(words("What would you like to let out?"), text: Binding(get: { text }, set: {
                            text = $0; submissionID = ""; notice = nil; actionError = nil
                        }), axis: .vertical)
                            .lineLimit(4...8).padding(16).foregroundStyle(.white)
                            .tint(.white)
                            .background(Color(red: 0.19, green: 0.22, blue: 0.35).opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                            .disabled(saving)
                        if text.count > 4000 { Text(verbatim: words("Please keep your thought under 4,000 characters.")).font(LiyaType.text(.footnote)).foregroundStyle(.white) }
                        PrimaryButton(title: saving ? "Saving…" : "Keep this thought", disabled: saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000) {
                            savePrivate()
                        }
                        if let error = actionError { Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.white).multilineTextAlignment(.center) }
                        if let notice { Text(verbatim: words(notice)).font(LiyaType.text(.footnote, weight: .medium)).foregroundStyle(.white) }
                        HStack(spacing: 18) {
                            NavigationLink(words("My private thoughts")) { TreeHistoryView() }
                        }.font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).frame(minHeight: 44)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24 + tabBarClearance)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height, alignment: .top)
                    .modifier(AdaptiveContainerMargins())
                }.scrollDismissesKeyboard(.interactively)
            }
        }.navigationBarHidden(true)
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
                Text(verbatim: words("Thoughts in the tree")).font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                if social.loading { LiyaLoadingIndicator(size: 22) }
                else { Button(words("Refresh")) { Task { await social.refresh(session) } }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(.white).frame(minHeight: 44) }
            }
            ForEach(0..<3, id: \.self) { row in
                let rowThoughts = thoughts.enumerated().filter { $0.offset % 3 == row }.map { $0.element }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(rowThoughts) { thought in
                            Button { selectedThought = thought } label: {
                                HStack(spacing: 7) {
                                    HostedArtwork(thought.mood).scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(thought.body).font(LiyaType.text(.subheadline, weight: .medium)).lineLimit(1)
                                        if thought.post == nil { Text(verbatim: words("Inspiration")).font(LiyaType.text(.caption2, weight: .semibold)).opacity(0.8) }
                                    }
                                    .frame(maxWidth: 205, alignment: .leading)
                                    HostedArtwork("more", renderingMode: .template).scaledToFit().foregroundStyle(.white).frame(width: 17, height: 17).accessibilityHidden(true)
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
                    Button { mood = item; submissionID = ""; notice = nil } label: {
                        HostedArtwork(item).scaledToFit().frame(width: 42, height: 42).frame(width: 52, height: 52)
                            .background(mood == item ? Color(red: 0.36, green: 0.29, blue: 0.58) : Color(red: 0.19, green: 0.22, blue: 0.35), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(mood == item ? .white.opacity(0.75) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(saving).accessibilityLabel(item.replacingOccurrences(of: "mood-", with: ""))
                        .accessibilityAddTraits(mood == item ? .isSelected : [])
                }
            }.frame(maxWidth: .infinity)
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
                text = ""; submissionID = ""; notice = "Saved privately."
            } else { actionError = session.treeError ?? "Couldn't confirm saving. Please try again." }
            saving = false
        }
    }
}

private struct TreeThoughtOptions: View {
    @Environment(\.liyaWords) private var words
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
                            HostedArtwork("back", labelWhileMissing: "Back").scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(words(mode == 0 ? "Close" : "Back"))
                        Spacer(minLength: 0)
                        Text(title).font(LiyaType.text(.headline)).foregroundStyle(liyaInk).lineLimit(1)
                        Spacer(minLength: 0)
                        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                    }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                }.frame(height: 48)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            HostedArtwork(thought.mood).scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: words(thought.post == nil ? "Inspiration" : "Community thought"))
                                    .font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(liyaAccent)
                                Text(thought.body).font(LiyaType.detail).foregroundStyle(liyaInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                        if mode == 1 && !sent {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: words("Why are you reporting this thought?")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                                Link(words("Email support: Liya2026support@liya.vip"), destination: URL(string: "mailto:Liya2026support@liya.vip")!)
                                    .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                                ForEach(reasons, id: \.self) { item in
                                    VideoSafetyReason(title: item, selected: reason == item) {
                                        reason = item; requestID = UUID(); error = nil
                                    }.disabled(busy)
                                }
                            }
                        } else if mode == 2 {
                            Text(verbatim: words("Their posts and messages will no longer be visible to you."))
                                .font(LiyaType.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if !social.isJoined(session) {
                                NavigationLink(words("Set up your profile to block")) { CommunityJoinView() }
                                    .foregroundStyle(liyaAccent).frame(minHeight: 44)
                            }
                        } else if mode == 3 {
                            Text(verbatim: words("This thought will be removed from the community and your profile."))
                                .font(LiyaType.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if sent { Text(verbatim: words("Report received.")).font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaAccent) }
                        if let error { Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
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
                        Button(words("Block member")) { showMode(2) }
                            .font(LiyaType.text(.subheadline, weight: .semibold)).foregroundStyle(liyaAccent)
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
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    @State private var deleting: TreeEntry?
    var body: some View {
        PageShell(title: "Your private thoughts") {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: "Only your account can read these thoughts.")
                if session.treeLoading { Text(verbatim: words("Loading…")).foregroundStyle(.secondary) }
                if let error = session.treeError {
                    Text(verbatim: words(error)).font(LiyaType.text(.footnote)).foregroundStyle(.red)
                    Button(words("Try again")) { Task { await session.refreshTreeEntries() } }.foregroundStyle(liyaAccent)
                } else if !session.treeLoading && session.treeEntries.isEmpty {
                    EmptyState(title: "No thoughts yet", detail: "Your saved thoughts will appear here.")
                }
                ForEach(session.treeEntries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HostedArtwork(entry.mood).scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                        Text(entry.body).foregroundStyle(liyaInk).frame(maxWidth: .infinity, alignment: .leading)
                        Button(words("Delete")) { deleting = entry }.font(LiyaType.text(.footnote, weight: .bold)).foregroundStyle(liyaAccent)
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
    @Environment(\.liyaWords) private var words
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
            Text(verbatim: words("Select date")).font(.system(.subheadline, design: .serif).bold().italic()).foregroundStyle(liyaInk)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(weekdays.indices, id: \.self) { index in
                    Text(weekdays[index]).font(LiyaType.text(.caption2, weight: .semibold)).foregroundStyle(liyaInk.opacity(0.45))
                        .frame(maxWidth: .infinity).frame(height: 20)
                }
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        let selected = Calendar.current.isDate(day, inSameDayAs: selection)
                        let future = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: Date())
                        let entry = session.moodEntries.first { $0.dayStamp == JournalDayEntry.dayKey(day) }
                        Button { selection = day } label: {
                            ZStack {
                                Circle().fill(selected ? liyaAccent : (future ? Color.gray.opacity(0.08) : liyaAccent.opacity(0.10)))
                                    .frame(width: 35, height: 35)
                                VStack(spacing: 0) {
                                    Text("\(Calendar.current.component(.day, from: day))").font(LiyaType.text(.caption, weight: .medium))
                                        .foregroundStyle(selected ? .white : (future ? liyaInk.opacity(0.3) : liyaAccent))
                                    if let entry {
                                        HostedArtwork(entry.feelingKey).scaledToFit().frame(width: 19, height: 19).accessibilityHidden(true)
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
                        Text(entry.date, style: .date).font(LiyaType.text(.headline))
                        Text(entry.note.isEmpty ? entry.mood.replacingOccurrences(of: "mood-", with: "") : entry.note)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.top, 12)
        }
    }
}


private struct CollectionPhotoCard: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var store: LocalStore
    @EnvironmentObject private var session: LiyaSession
    let index: Int
    let mediaID: String
    @State private var options: CollectionSafetyTarget?

    private var displayName: String {
        session.curatedDisplayName(for: mediaID)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NavigationLink { CollectionAuthorView(index: index, displayName: displayName, mediaID: mediaID) } label: {
                    HStack(spacing: 10) { CollectionPortrait(index: index, size: 42); VStack(alignment: .leading, spacing: 3) {
                        Text(displayName).font(LiyaType.text(.subheadline, weight: .semibold)).lineLimit(1)
                        Text(verbatim: words("Collection")).font(LiyaType.text(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    } }.foregroundStyle(liyaInk)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                CuratedFollowButton(id: mediaID) { following, title in
                    Text(verbatim: words(title))
                        .font(LiyaType.text(.caption, weight: .semibold)).foregroundStyle(liyaAccent)
                        .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 12).frame(minHeight: 44)
                        .background(liyaAccent.opacity(following ? 0.15 : 0.08), in: Capsule())
                }
                Button {
                    options = CollectionSafetyTarget(mediaID: mediaID, name: displayName, kind: .post, ownerID: session.userID)
                } label: { HostedArtwork("more", labelWhileMissing: "More").scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(words("More options"))
            }
            NavigationLink { CollectionPhotoDetail(mediaID: mediaID) } label: {
                GeometryReader { geometry in
                    CollectionPhoto(catalogIndex: index, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                .aspectRatio(4 / 5, contentMode: .fit).frame(maxWidth: 430)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .frame(maxWidth: .infinity)
            }.buttonStyle(.plain).accessibilityLabel(words("Open post"))
            MediaEngagementBar(mediaID: mediaID)
        }.modifier(LiyaFeedCardSurface())
            .sheet(item: $options) { CollectionSafetySheet(target: $0) }
    }
}

struct MediaEngagementBar: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    let mediaID: String
    @State private var showsComments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) { actions }
            }
            if session.mediaEngagementFailures.contains(mediaID) {
                Button(words("Retry counts")) {
                    Task { await session.refreshMediaEngagement(ids: [mediaID]) }
                }
                .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsComments) {
            NavigationStack { MediaCommentsView(mediaID: mediaID) }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder private var actions: some View {
        let totals = session.mediaEngagement[mediaID]
        let isLiked = session.likedMediaIDs.contains(mediaID)
        let placeholder = session.mediaEngagementFailures.contains(mediaID) ? "—" : "…"
        Button {
            Task { await session.toggleMediaLike(id: mediaID) }
        } label: {
            LiyaFeedActionLabel(title: isLiked ? "Liked" : "Like",
                                count: totals.map { $0.likeCount.formatted() } ?? placeholder,
                                icon: isLiked ? "video-like-on" : "video-like-off", active: isLiked)
        }
        .buttonStyle(.plain).disabled(!session.likesReady || session.likesLoading)
        .accessibilityAddTraits(isLiked ? .isSelected : [])
        Button { showsComments = true } label: {
            LiyaFeedActionLabel(title: "Comments", count: totals.map { $0.commentCount.formatted() } ?? placeholder,
                                icon: "profile-action-message")
        }.buttonStyle(.plain)
    }
}

struct SavedPhotoNotes: View {
    @Environment(\.liyaWords) private var words
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
                            Text(comment.date, style: .date).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                            Spacer()
                            Button(words("Delete")) { store.deleteComment(comment.id) }.font(LiyaType.text(.caption, weight: .bold)).foregroundStyle(liyaAccent)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                TextField(words("Write a private note"), text: $text, axis: .vertical).lineLimit(2...6).padding(14)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                PrimaryButton(title: "Save note", disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    store.addComment(text.trimmingCharacters(in: .whitespacesAndNewlines), photoIndex: index)
                    text = ""
                }
            }.padding(.top, 12)
        }
    }
}


struct CollectionPhotoDetail: View {
    @Environment(\.liyaWords) private var words
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    @State private var options: CollectionSafetyTarget?
    let mediaID: String

    private var index: Int? { session.photos.firstIndex { $0.id == mediaID } }
    private var displayName: String {
        session.curatedDisplayName(for: mediaID)
    }

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                DuoControlRegion { _ in
                    HStack {
                        Button { dismiss() } label: { HostedArtwork("back", labelWhileMissing: "Back").scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel(words("Back"))
                        Spacer(minLength: 0)
                        Text(verbatim: words("Post")).font(LiyaType.text(.headline)).foregroundStyle(liyaInk)
                        Spacer(minLength: 0)
                        Button {
                            options = CollectionSafetyTarget(mediaID: mediaID, name: displayName, kind: .post, ownerID: session.userID)
                        } label: { HostedArtwork("more", labelWhileMissing: "More").scaledToFit().frame(width: 20, height: 20).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel(words("Report or block")).disabled(index == nil)
                    }.padding(.horizontal, 12).modifier(AdaptiveContainerMargins())
                }.frame(height: 44)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let index, store.hiddenCollectionProfiles.contains(index) {
                            Text(verbatim: words("Unblock this profile to see their posts again."))
                                .font(LiyaType.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else if let index, CollectionPhotoRoles.isPost(index, in: session.photos) {
                            NavigationLink { CollectionAuthorView(index: index, displayName: displayName, mediaID: mediaID) } label: {
                                HStack(spacing: 10) {
                                    CollectionPortrait(index: index)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(displayName).font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(liyaInk)
                                        Text(verbatim: words("Collection")).font(LiyaType.text(.caption)).foregroundStyle(.secondary)
                                    }
                                }
                            }.buttonStyle(.plain)
                            CollectionPhoto(catalogIndex: index).frame(maxWidth: .infinity).frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            MediaEngagementBar(mediaID: mediaID)
                        } else if session.catalogLoading {
                            LiyaLoadingIndicator(size: 28).frame(maxWidth: .infinity)
                        } else {
                            Text(verbatim: words("This post is no longer available.")).font(LiyaType.detail).foregroundStyle(.secondary)
                        }
                        if let likesError = session.likesError {
                            Text(verbatim: words(likesError)).font(LiyaType.text(.footnote)).foregroundStyle(.secondary)
                            Button(words("Retry likes")) { Task { await session.refreshLikes() } }
                                .font(LiyaType.text(.footnote, weight: .semibold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                        }
                    }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 30 + tabBarClearance)
                        .modifier(AdaptiveContainerMargins())
                }
            }
        }
        .navigationBarHidden(true)
        .task(id: mediaID) { await session.refreshMediaEngagement(ids: [mediaID]) }
        .sheet(item: $options) { CollectionSafetySheet(target: $0) }
    }
}
