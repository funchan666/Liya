import SwiftUI
import UIKit

private let journalPaper = Color(red: 0.994, green: 0.978, blue: 0.944)
private let journalPlum = Color(red: 0.29, green: 0.18, blue: 0.30)

struct JournalPostcardLink: View {
    var openedFromDiary = false

    var body: some View {
        NavigationLink { JournalPostcardsView(openedFromDiary: openedFromDiary) } label: {
            HStack(spacing: 14) {
                Image(decorative: "journal-daybreak-stamp").resizable().scaledToFit()
                    .frame(width: 54, height: 43).rotationEffect(.degrees(-6))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Between days").font(LiyaType.sectionHeading).foregroundStyle(journalPlum)
                    Text("Pair two journal entries on a postcard.")
                        .font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.78))
                }.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                PostcardDisclosure().foregroundStyle(journalPlum)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(JournalGlassSurface())
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
    }
}

struct VideoJournalShortcut: View {
    var body: some View {
        NavigationLink { JournalPostcardsView(openedFromDiary: false) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    stamp
                    Text("Between days")
                        .font(.custom("InstrumentSerif-Regular", size: 21, relativeTo: .headline))
                    PostcardDisclosure()
                }
                .padding(.leading, 8).padding(.trailing, 12)
                .padding(.vertical, 4).fixedSize(horizontal: true, vertical: false)
                stamp.frame(width: 46)
            }
            .frame(minHeight: 44)
            .foregroundStyle(journalPlum)
            .modifier(JournalGlassSurface())
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityLabel("Between days")
    }

    private var stamp: some View {
        Image(decorative: "journal-daybreak-stamp").resizable().scaledToFit()
            .frame(width: 36, height: 32).rotationEffect(.degrees(-6))
    }
}

private struct PostcardDisclosure: View {
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        Image(decorative: "back").renderingMode(.template).resizable().scaledToFit()
            .frame(width: 12, height: 14)
            .scaleEffect(x: direction == .rightToLeft ? 1 : -1, y: 1)
    }
}

private struct PostcardActionStyle: ButtonStyle {
    var secondary = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .font(LiyaType.action)
            .foregroundStyle(secondary ? journalPlum : .white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(secondary ? journalPaper : journalPlum, in: shape)
            .overlay {
                if secondary { shape.strokeBorder(journalPlum.opacity(0.25)).allowsHitTesting(false) }
            }
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(shape)
    }
}

private struct JournalPostcardsView: View {
    let openedFromDiary: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var checkout: CoinCheckout
    @EnvironmentObject private var store: LocalStore
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var firstStamp: String?
    @State private var secondStamp: String?
    @State private var usePair = true
    @State private var readingEntries = false
    @State private var excerptConsent: [JournalDayEntry] = []
    private var includeExcerpts: Bool { !excerptConsent.isEmpty && excerptConsent == chosenDays }
    @State private var exportedCard: PostcardImage?
    @State private var exportFailed = false
    private var entries: [JournalDayEntry] {
        guard let owner = session.userID else { return [] }
        let syncedDays = session.moodEntries.filter { $0.journalOwnerID == owner && $0.recordedDate != nil }
        let archive = store.earlierJournalDays(for: owner)
        guard !archive.isEmpty else { return syncedDays }
        var byDate: [String: JournalDayEntry] = [:]
        for day in archive { byDate[day.dayStamp] = day }
        for day in syncedDays { byDate[day.dayStamp] = day }
        return byDate.values.sorted { $0.dayStamp > $1.dayStamp }
    }
    private var chosenDays: [JournalDayEntry] {
        let records = entries
        guard let latest = records.first else { return [] }
        let pair = usePair && records.count > 1
        let first = records.first { $0.id == firstStamp } ?? (pair ? records[1] : latest)
        guard pair, let second = records.first(where: { $0.id == secondStamp && $0.id != first.id })
                ?? records.first(where: { $0.id != first.id }) else { return [first] }
        return [first, second].sorted { $0.dayStamp < $1.dayStamp }
    }
    private var artwork: String {
        checkout.isActive(.tideglassPaper) ? "journal-paper-tideglass" : "journal-paper-daybreak"
    }

    var body: some View {
        PageShell(title: "Between days") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    JournalPaperPrint(days: chosenDays, artwork: artwork, includeExcerpts: includeExcerpts)
                        .accessibilityElement(children: .combine)
                    if entries.isEmpty {
                        emptyJournalActions.padding(.horizontal, 18).padding(.bottom, 18)
                    }
                }
                .background(journalPaper)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                if !entries.isEmpty {
                    if entries.count > 1 {
                        Toggle("Pair two days", isOn: $usePair)
                            .onLiyaChange(of: usePair) { _ in resetExcerptChoice() }
                    }
                    ForEach(Array(chosenDays.enumerated()), id: \.element.id) { index, entry in
                        dayPicker(entry, index: index)
                    }
                    if chosenDays.count == 2 {
                        Button {
                            readingEntries.toggle()
                        } label: {
                            Text(LocalizedStringKey(readingEntries ? "Close journal entries" : "Read both entries"))
                        }.buttonStyle(PostcardActionStyle(secondary: true))
                        if readingEntries {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(chosenDays) { day in journalReading(day).frame(minWidth: 170) }
                                }
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(chosenDays) { day in journalReading(day) }
                                }
                            }
                        }
                    }
                    if chosenDays.contains(where: { !$0.reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                        Toggle("Include note excerpts", isOn: Binding(
                            get: { includeExcerpts },
                            set: { excerptConsent = $0 ? chosenDays : [] }
                        ))
                    }
                    if exportFailed { Text("The postcard could not be prepared. Try sharing again.").font(LiyaType.text(.footnote)) }
                    Button("Share postcard", action: sharePostcard)
                        .buttonStyle(PostcardActionStyle())
                }
                NavigationLink { WalletView() } label: {
                    paperSelectionLabel
                }.buttonStyle(.plain).accessibilityElement(children: .combine)
            }.padding(.top, 12).modifier(AdaptiveContainerMargins())
                .foregroundStyle(liyaInk).tint(liyaAccent)
        }.task(id: session.userID) {
            if session.moodEntries.isEmpty { await session.refreshMoods() }
        }.onLiyaChange(of: session.userID) { _ in
            firstStamp = nil; secondStamp = nil; resetExcerptChoice(); exportedCard = nil
        }.sheet(item: $exportedCard) { card in
            PostcardActivitySheet(image: card.image)
        }
    }

    @ViewBuilder private var emptyJournalActions: some View {
        if session.moodLoading {
            HStack(spacing: 8) { LiyaLoadingIndicator(size: 24); Text("Loading journal…") }
        } else if let error = session.moodError {
            VStack(alignment: .leading, spacing: 12) {
                OfflineNote(text: error)
                Button("Try again") { Task { await session.refreshMoods() } }
                    .buttonStyle(PostcardActionStyle(secondary: true))
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Save a day in your mood diary to make your first postcard.")
                    .font(LiyaType.reading).foregroundStyle(journalPlum)
                    .fixedSize(horizontal: false, vertical: true)
                if openedFromDiary {
                    Button { dismiss() } label: { openDiaryLabel }
                        .buttonStyle(PostcardActionStyle())
                } else {
                    NavigationLink { MoodDiaryView() } label: { openDiaryLabel }
                        .buttonStyle(PostcardActionStyle())
                }
            }
        }
    }

    private var openDiaryLabel: some View {
        HStack(spacing: 12) {
            Text("Open mood diary").multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PostcardDisclosure()
        }
    }

    private var paperSelectionLabel: some View {
        HStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    Image(decorative: "journal-paper-tideglass").resizable().scaledToFill()
                        .frame(width: 43, height: 33).clipShape(RoundedRectangle(cornerRadius: 3))
                        .rotationEffect(.degrees(8)).offset(x: 4, y: -4)
                    Image(decorative: "journal-daybreak-stamp").resizable().scaledToFit()
                        .frame(width: 45, height: 35).rotationEffect(.degrees(-8)).offset(x: -3, y: 4)
                }.frame(width: 56, height: 49)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Postcard paper").font(LiyaType.sectionHeading).foregroundStyle(journalPlum)
                Text("Daybreak is free. Choose Tideglass in your wallet.")
                    .font(LiyaType.text(.footnote)).foregroundStyle(liyaInk.opacity(0.78))
            }.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PostcardDisclosure().foregroundStyle(journalPlum)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(JournalGlassSurface())
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func dayPicker(_ current: JournalDayEntry, index: Int) -> some View {
        let other = chosenDays.first(where: { $0.id != current.id })
        return Menu {
            ForEach(entries.filter { $0.id != other?.id }) { entry in
                if let date = entry.recordedDate {
                    Button {
                        firstStamp = index == 0 ? entry.id : other?.id
                        secondStamp = index == 0 ? other?.id : entry.id
                        resetExcerptChoice()
                    } label: { Text(date, format: .dateTime.year().month().day().weekday(.abbreviated)) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(LocalizedStringKey(chosenDays.count == 1 ? "Journal day" : (index == 0 ? "Earlier day" : "Later day")))
                    .font(LiyaType.text(.subheadline, weight: .semibold))
                Spacer()
                if let date = current.recordedDate {
                    Text(date, format: .dateTime.year().month(.abbreviated).day())
                        .font(LiyaType.detail).multilineTextAlignment(.trailing)
                }
                Image("back").resizable().scaledToFit().frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90)).accessibilityHidden(true)
            }.padding(.horizontal, 14).frame(minHeight: 44)
                .modifier(JournalGlassSurface())
        }
    }

    private func journalReading(_ entry: JournalDayEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = entry.recordedDate {
                Text(date, format: .dateTime.month().day().year()).font(LiyaType.detail)
            }
            Text(LocalizedStringKey(entry.feelingName)).font(LiyaType.sectionHeading)
            if !entry.reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: entry.reflectionText).font(LiyaType.reading)
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func resetExcerptChoice() { excerptConsent = []; exportFailed = false; readingEntries = false }

    @MainActor private func sharePostcard() {
        guard !chosenDays.isEmpty else { return }
        let print = JournalPaperPrint(days: chosenDays, artwork: artwork, includeExcerpts: includeExcerpts)
            .frame(width: 360).fixedSize(horizontal: false, vertical: true)
            .environment(\.locale, locale).environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .medium)
        let renderer = ImageRenderer(content: print)
        renderer.scale = 3
        guard let image = renderer.uiImage else { exportFailed = true; return }
        exportFailed = false
        exportedCard = PostcardImage(image: image)
    }
}

private struct JournalGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(journalPaper, in: shape)
                .overlay { shape.strokeBorder(journalPlum.opacity(0.22)).allowsHitTesting(false) }
        } else {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(journalPaper.opacity(0.80)).interactive(), in: shape)
                    .environment(\.colorScheme, .light)
            } else {
                material(content)
            }
        #else
            material(content)
        #endif
        }
    }

    private func material(_ content: Content) -> some View {
        content.background(.regularMaterial, in: shape)
            .background(journalPaper.opacity(0.86), in: shape)
            .environment(\.colorScheme, .light)
    }
}

private struct JournalPaperPrint: View {
    let days: [JournalDayEntry]
    let artwork: String
    let includeExcerpts: Bool
    private let ink = Color(red: 0.13, green: 0.14, blue: 0.22)
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(artwork).resizable().aspectRatio(contentMode: .fit).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text("Between days").font(LiyaType.journalTitle).foregroundStyle(ink)
                ForEach(days) { entry in
                    if let date = entry.recordedDate {
                        Divider()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                                .font(LiyaType.detail).foregroundStyle(ink.opacity(0.78))
                            Text(LocalizedStringKey(entry.feelingName)).font(LiyaType.sectionHeading)
                            if includeExcerpts {
                                let note = entry.reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !note.isEmpty {
                                    Text(verbatim: note.count > 100 ? String(note.prefix(100)) + "…" : note)
                                        .font(LiyaType.reading).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }.padding(18)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(ink).background(journalPaper)
    }
}

private struct PostcardImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct PostcardActivitySheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        sheet.excludedActivityTypes = [.saveToCameraRoll]
        return sheet
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
