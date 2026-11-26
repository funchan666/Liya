import SwiftUI
import UIKit

struct JournalPostcardLink: View {
    var body: some View {
        NavigationLink { JournalPostcardsView() } label: {
            HStack(spacing: 14) {
                Image("journal-paper-daybreak").resizable().scaledToFill()
                    .frame(width: 92, height: 80).clipped().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Between days").font(LiyaType.sectionHeading).foregroundStyle(liyaInk)
                    Text("Pair two journal entries on a postcard.")
                        .font(LiyaType.detail).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Image("back").resizable().scaledToFit().frame(width: 14, height: 14)
                    .scaleEffect(x: -1, y: 1).accessibilityHidden(true)
            }.padding(.trailing, 14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.87), in: RoundedRectangle(cornerRadius: 18))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
    }
}

private struct JournalPostcardsView: View {
    @EnvironmentObject private var session: LiyaSession
    @EnvironmentObject private var checkout: CoinCheckout
    @Environment(\.locale) private var locale
    @State private var firstStamp: String?
    @State private var secondStamp: String?
    @State private var usePair = true
    @State private var readingEntries = false
    @State private var includeExcerpts = false
    @State private var exportedCard: PostcardImage?
    @State private var exportFailed = false
    private var entries: [JournalDayEntry] {
        session.moodEntries.filter { $0.journalOwnerID == session.userID && $0.recordedDate != nil }
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
                JournalPaperPrint(days: chosenDays, artwork: artwork, includeExcerpts: includeExcerpts)
                    .clipShape(RoundedRectangle(cornerRadius: 19))
                    .accessibilityElement(children: .combine)
                if entries.isEmpty {
                    if session.moodLoading {
                        HStack { LiyaLoadingIndicator(size: 24); Text("Loading journal…") }
                    } else if let error = session.moodError {
                        OfflineNote(text: error)
                        Button("Reload journal") { Task { await session.refreshMoods() } }.frame(minHeight: 44)
                    } else {
                        Text("Save a day in your mood diary to make your first postcard.")
                        NavigationLink("Open mood diary") { MoodDiaryView() }.frame(minHeight: 44)
                    }
                } else {
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
                                .font(LiyaType.action).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.plain)
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
                        Toggle("Include note excerpts", isOn: $includeExcerpts)
                    }
                    if exportFailed { Text("The postcard could not be prepared. Try sharing again.").font(.footnote) }
                    Button { sharePostcard() } label: {
                        Text("Share postcard").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(liyaInk, in: Capsule())
                    }.buttonStyle(.plain)
                }
                NavigationLink { WalletView() } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Postcard paper").font(.subheadline.weight(.semibold))
                        Text("Daybreak is free. Choose Tideglass in your wallet.").font(.footnote)
                    }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }.buttonStyle(.plain)
            }.padding(.top, 12).modifier(AdaptiveContainerMargins())
                .foregroundStyle(liyaInk).tint(liyaAccent)
        }.task(id: session.userID) {
            firstStamp = nil; secondStamp = nil; resetExcerptChoice(); exportedCard = nil
            if session.moodEntries.isEmpty { await session.refreshMoods() }
        }.sheet(item: $exportedCard) { card in
            PostcardActivitySheet(image: card.image)
        }
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
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let date = current.recordedDate {
                    Text(date, format: .dateTime.year().month(.abbreviated).day())
                        .font(.subheadline).multilineTextAlignment(.trailing)
                }
                Image("back").resizable().scaledToFit().frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90)).accessibilityHidden(true)
            }.padding(.horizontal, 14).frame(minHeight: 44)
                .modifier(JournalPickerSurface())
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

    private func resetExcerptChoice() { includeExcerpts = false; exportFailed = false; readingEntries = false }

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

private struct JournalPickerSurface: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        } else {
            content.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        #else
        content.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        #endif
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
            .foregroundStyle(ink).background(Color(red: 0.994, green: 0.978, blue: 0.944))
    }
}

private struct PostcardImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct PostcardActivitySheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
