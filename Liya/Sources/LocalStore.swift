import Foundation
import Combine

struct VideoRequest: Equatable {
    let id = UUID()
    let index: Int
    var openNotes = false
}

struct MoodEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var mood: String
    var note: String
}

struct LocalComment: Codable, Identifiable {
    var id = UUID()
    var photoIndex: Int
    var text: String
    var date = Date()
}

struct LocalReport: Codable, Identifiable {
    var id = UUID()
    var photoIndex: Int
    var reason: String
    var date = Date()
    var videoIndex: Int? = nil
    var targetType: String? = nil
}

struct LocalVideoNote: Codable, Identifiable {
    var id = UUID()
    var videoIndex: Int
    var text: String
    var date = Date()
}

struct LocalDraft: Codable, Identifiable {
    var id = UUID()
    var text: String
    var date = Date()
    var attachments: [DraftAttachment]? = nil
    var mood: String? = nil
    var publishedLocally: Bool? = nil
    var tags: [String]? = nil
}

@MainActor
final class LocalStore: ObservableObject {
    @Published var inPreview = false
    @Published var videoRequest: VideoRequest?
    @Published var entries: [MoodEntry] = []
    @Published var pendingMoods: [MoodEntry] = []
    @Published var composeText = "" { didSet { defaults.set(composeText, forKey: "liya.composeText") } }
    @Published var composeTags: [String] = [] { didSet { defaults.set(composeTags, forKey: "liya.composeTags") } }
    @Published var composeAttachments: [DraftAttachment] = [] {
        didSet { if let data = try? JSONEncoder().encode(composeAttachments) { defaults.set(data, forKey: "liya.composeAttachments") } }
    }
    @Published var composeLoading = false
    @Published var drafts: [LocalDraft] = []
    @Published var comments: [LocalComment] = []
    @Published var likedPhotos: Set<Int> = []
    @Published var likedVideos: Set<Int> = []
    @Published var videoNotes: [LocalVideoNote] = []
    @Published var followedExamples: Set<Int> = []
    @Published var blockedExamples: Set<Int> = []
    @Published var messageDrafts: [String: String] = [:]
    @Published var reports: [LocalReport] = []
    @Published var avatar: DraftAttachment?
    @Published var nickname: String = "" { didSet { defaults.set(nickname, forKey: "liya.nickname") } }
    @Published var signature: String = "" { didSet { defaults.set(signature, forKey: "liya.signature") } }
    @Published var profileTags: [String] = []
    private let defaults = UserDefaults.standard

    init() {
        nickname = defaults.string(forKey: "liya.nickname") ?? ""
        signature = defaults.string(forKey: "liya.signature") ?? ""
        profileTags = defaults.stringArray(forKey: "liya.profileTags") ?? []
        if let data = defaults.data(forKey: "liya.moods"), let saved = try? JSONDecoder().decode([MoodEntry].self, from: data) { entries = saved }
        if let data = defaults.data(forKey: "liya.pendingMoods"), let saved = try? JSONDecoder().decode([MoodEntry].self, from: data) { pendingMoods = saved }
        composeText = defaults.string(forKey: "liya.composeText") ?? ""
        composeTags = defaults.stringArray(forKey: "liya.composeTags") ?? []
        if let data = defaults.data(forKey: "liya.composeAttachments"), let saved = try? JSONDecoder().decode([DraftAttachment].self, from: data) { composeAttachments = saved }
        if let data = defaults.data(forKey: "liya.drafts"), let saved = try? JSONDecoder().decode([LocalDraft].self, from: data) { drafts = saved }
        if let data = defaults.data(forKey: "liya.comments"), let saved = try? JSONDecoder().decode([LocalComment].self, from: data) { comments = saved }
        likedPhotos = Set(defaults.array(forKey: "liya.likedPhotos") as? [Int] ?? [])
        likedVideos = Set(defaults.array(forKey: "liya.likedVideos") as? [Int] ?? [])
        if let data = defaults.data(forKey: "liya.videoNotes"), let saved = try? JSONDecoder().decode([LocalVideoNote].self, from: data) { videoNotes = saved }
        followedExamples = Set(defaults.array(forKey: "liya.followedExamples") as? [Int] ?? [])
        blockedExamples = Set(defaults.array(forKey: "liya.blockedExamples") as? [Int] ?? [])
        messageDrafts = defaults.dictionary(forKey: "liya.messageDrafts") as? [String: String] ?? [:]
        if let data = defaults.data(forKey: "liya.reportDrafts"), let saved = try? JSONDecoder().decode([LocalReport].self, from: data) { reports = saved }
        if let data = defaults.data(forKey: "liya.avatar"), let saved = try? JSONDecoder().decode(DraftAttachment.self, from: data) { avatar = saved }
    }

    func savePendingMood(_ mood: String, note: String, date: Date) {
        pendingMoods.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
        pendingMoods.append(MoodEntry(date: date, mood: mood, note: note))
        if let data = try? JSONEncoder().encode(pendingMoods) { defaults.set(data, forKey: "liya.pendingMoods") }
    }

    func clearPendingMood(date: Date) {
        pendingMoods.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
        if let data = try? JSONEncoder().encode(pendingMoods) { defaults.set(data, forKey: "liya.pendingMoods") }
    }

    func saveMood(_ mood: String, note: String, date: Date) {
        entries.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
        entries.append(MoodEntry(date: date, mood: mood, note: note))
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: "liya.moods") }
    }

    func saveDraft(_ text: String, attachments: [DraftAttachment] = [], mood: String? = nil, published: Bool = false, tags: [String] = []) {
        drafts.insert(LocalDraft(text: text, attachments: attachments, mood: mood, publishedLocally: published, tags: tags), at: 0)
        persistDrafts()
    }

    func toggleLike(_ photoIndex: Int) {
        if likedPhotos.contains(photoIndex) { likedPhotos.remove(photoIndex) } else { likedPhotos.insert(photoIndex) }
        defaults.set(Array(likedPhotos), forKey: "liya.likedPhotos")
    }

    func saveProfileTags(_ tags: [String]) {
        profileTags = tags
        defaults.set(tags, forKey: "liya.profileTags")
    }

    func publishLocally(_ id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].publishedLocally = true
        persistDrafts()
    }

    func saveAvatar(_ item: DraftAttachment?) {
        avatar = item
        if let item, let data = try? JSONEncoder().encode(item) { defaults.set(data, forKey: "liya.avatar") }
        else { defaults.removeObject(forKey: "liya.avatar") }
    }

    func toggleFollow(_ index: Int) {
        if followedExamples.contains(index) { followedExamples.remove(index) } else { followedExamples.insert(index) }
        defaults.set(Array(followedExamples), forKey: "liya.followedExamples")
    }

    func setBlocked(_ index: Int, blocked: Bool) {
        if blocked {
            blockedExamples.insert(index)
            followedExamples.remove(index)
            defaults.set(Array(followedExamples), forKey: "liya.followedExamples")
        } else { blockedExamples.remove(index) }
        defaults.set(Array(blockedExamples), forKey: "liya.blockedExamples")
    }

    func saveMessageDraft(_ text: String, index: Int) {
        let key = String(index)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messageDrafts.removeValue(forKey: key) }
        else { messageDrafts[key] = text }
        defaults.set(messageDrafts, forKey: "liya.messageDrafts")
    }

    func saveReportDraft(index: Int, reason: String, targetType: String) {
        reports.append(LocalReport(photoIndex: targetType == "video" ? -1 : index, reason: reason, videoIndex: targetType == "video" ? index : nil, targetType: targetType))
        if let data = try? JSONEncoder().encode(reports) { defaults.set(data, forKey: "liya.reportDrafts") }
    }

    func deleteReport(_ id: UUID) {
        reports.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(reports) { defaults.set(data, forKey: "liya.reportDrafts") }
    }

    func toggleVideoLike(_ index: Int) {
        if likedVideos.contains(index) { likedVideos.remove(index) } else { likedVideos.insert(index) }
        defaults.set(Array(likedVideos), forKey: "liya.likedVideos")
    }

    func addVideoNote(_ text: String, index: Int) {
        videoNotes.append(LocalVideoNote(videoIndex: index, text: text))
        if let data = try? JSONEncoder().encode(videoNotes) { defaults.set(data, forKey: "liya.videoNotes") }
    }

    func deleteVideoNote(_ id: UUID) {
        videoNotes.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(videoNotes) { defaults.set(data, forKey: "liya.videoNotes") }
    }

    func deleteComment(_ id: UUID) {
        comments.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(comments) { defaults.set(data, forKey: "liya.comments") }
    }

    func addComment(_ text: String, photoIndex: Int) {
        comments.append(LocalComment(photoIndex: photoIndex, text: text))
        if let data = try? JSONEncoder().encode(comments) { defaults.set(data, forKey: "liya.comments") }
    }

    func updateDraft(_ id: UUID, text: String, attachments: [DraftAttachment], tags: [String]) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].text = text
        drafts[index].attachments = attachments
        drafts[index].tags = tags
        persistDrafts()
    }

    func deleteDraft(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        persistDrafts()
    }

    private func persistDrafts() {
        if let data = try? JSONEncoder().encode(drafts) { defaults.set(data, forKey: "liya.drafts") }
    }
}
