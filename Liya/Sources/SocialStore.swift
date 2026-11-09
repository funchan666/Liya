import Foundation
import Combine
import Supabase

struct SocialPerson: Codable, Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let signature: String
    let avatarPath: String?
    enum CodingKeys: String, CodingKey { case id, signature; case displayName = "display_name", avatarPath = "avatar_path" }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id); try container.encode(displayName, forKey: .displayName); try container.encode(signature, forKey: .signature)
        if let avatarPath { try container.encode(avatarPath, forKey: .avatarPath) } else { try container.encodeNil(forKey: .avatarPath) }
    }
}

struct SocialPost: Decodable, Identifiable {
    let id: UUID
    let ownerID: UUID
    let body: String
    let tags: [String]
    let mediaPaths: [String]
    let mediaKinds: [String]
    let createdAt: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case id, body, tags; case ownerID = "owner_id", mediaPaths = "media_paths", mediaKinds = "media_kinds", createdAt = "created_at", updatedAt = "updated_at"
    }
}

struct SocialComment: Codable, Identifiable, Equatable {
    let id: UUID
    let ownerID: UUID
    let postID: UUID
    let body: String
    enum CodingKeys: String, CodingKey { case id, body; case ownerID = "owner_id", postID = "post_id" }
}

struct VideoComment: Decodable, Identifiable {
    let id: UUID
    let mediaID: String
    let ownerID: UUID
    let body: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, body
        case mediaID = "media_id", ownerID = "owner_id", createdAt = "created_at"
    }
}

private struct VideoCommentInsert: Encodable {
    let id: UUID; let mediaID: String; let ownerID: UUID; let body: String
    enum CodingKeys: String, CodingKey { case id, body; case mediaID = "media_id", ownerID = "owner_id" }
}

private struct VideoCommentReport: Codable, Equatable {
    let id: UUID; let reporterID: UUID; let mediaID: String; let commentID: UUID?; let presetKey: String?
    let bodySnapshot: String; let reason: String
    enum CodingKeys: String, CodingKey {
        case id, reason; case reporterID = "reporter_id", mediaID = "media_id", commentID = "comment_id", presetKey = "preset_key", bodySnapshot = "body_snapshot"
    }
}

struct SocialMessage: Decodable, Identifiable {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let body: String
    let mediaPaths: [String]
    let mediaKinds: [String]
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, body; case senderID = "sender_id", recipientID = "recipient_id", mediaPaths = "media_paths", mediaKinds = "media_kinds", createdAt = "created_at"
    }
}

struct SocialNotification: Decodable, Identifiable {
    let id: Int64
    let ownerID: UUID
    let actorID: UUID
    let kind: String
    let postID: UUID?
    let isRead: Bool
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, kind; case ownerID = "owner_id", actorID = "actor_id", postID = "post_id", isRead = "is_read", createdAt = "created_at"
    }
}

private struct SocialPostInput: Encodable {
    let id: UUID; let ownerID: UUID; let body: String; let tags: [String]; let mediaPaths: [String]; let mediaKinds: [String]
    enum CodingKeys: String, CodingKey { case id, body, tags; case ownerID = "owner_id", mediaPaths = "media_paths", mediaKinds = "media_kinds" }
}
private struct SocialMessageInput: Encodable {
    let id: UUID; let senderID: UUID; let recipientID: UUID; let body: String; let mediaPaths: [String]; let mediaKinds: [String]
    enum CodingKeys: String, CodingKey { case id, body; case senderID = "sender_id", recipientID = "recipient_id", mediaPaths = "media_paths", mediaKinds = "media_kinds" }
}
private struct SocialRelation: Codable {
    let ownerID: UUID; let targetID: UUID
    enum CodingKeys: String, CodingKey { case ownerID = "owner_id", targetID = "target_id" }
}
private struct PostLike: Codable {
    let ownerID: UUID; let postID: UUID
    enum CodingKeys: String, CodingKey { case ownerID = "owner_id", postID = "post_id" }
}
private struct SocialReport: Codable, Equatable {
    let id: UUID; let reporterID: UUID; let targetUser: UUID; let postID: UUID?; let reason: String
    enum CodingKeys: String, CodingKey { case id, reason; case reporterID = "reporter_id", targetUser = "target_user", postID = "post_id" }
}

private struct PostCommentReport: Codable, Equatable {
    let id: UUID; let reporterID: UUID; let commentID: UUID; let postID: UUID
    let targetUser: UUID; let bodySnapshot: String; let reason: String
    enum CodingKeys: String, CodingKey {
        case id, reason; case reporterID = "reporter_id", commentID = "comment_id", postID = "post_id"
        case targetUser = "target_user", bodySnapshot = "body_snapshot"
    }
}

private struct MessageReport: Codable, Equatable {
    let id: UUID; let reporterID: UUID; let messageID: UUID; let targetUser: UUID
    let bodySnapshot: String; let mediaPaths: [String]; let mediaKinds: [String]; let reason: String
    enum CodingKeys: String, CodingKey {
        case id, reason; case reporterID = "reporter_id", messageID = "message_id", targetUser = "target_user"
        case bodySnapshot = "body_snapshot", mediaPaths = "media_paths", mediaKinds = "media_kinds"
    }
}

private struct ModerationStatus: Decodable {
    let kind: String; let contentID: UUID; let status: String
    enum CodingKeys: String, CodingKey { case kind, status; case contentID = "content_id" }
}

private struct ProfileSubmission: Decodable {
    let displayName: String; let signature: String; let avatarPath: String?
    enum CodingKeys: String, CodingKey { case signature; case displayName = "display_name", avatarPath = "avatar_path" }
}

struct SubmittedReport: Decodable, Identifiable {
    let kind: String; let reportID: UUID; let status: String; let reason: String; let createdAt: String
    var id: String { "\(kind):\(reportID.uuidString)" }
    enum CodingKeys: String, CodingKey { case kind, status, reason; case reportID = "report_id", createdAt = "created_at" }
}

@MainActor
final class SocialStore: ObservableObject {
    @Published private(set) var people: [SocialPerson] = []
    @Published private(set) var posts: [SocialPost] = []
    @Published private(set) var follows: [UUID] = []
    @Published private(set) var followers: [UUID] = []
    @Published private(set) var blocked: [UUID] = []
    @Published private(set) var likes: Set<UUID> = []
    @Published private(set) var messages: [SocialMessage] = []
    @Published private(set) var notifications: [SocialNotification] = []
    @Published private(set) var notificationsLoading = false
    @Published private(set) var syncGeneration = UUID()
    @Published private(set) var realtimeConnected = false
    @Published private(set) var moderationStatuses: [String: String] = [:]
    @Published private(set) var moderationAvailable = false
    @Published var notificationsError: String?
    @Published private(set) var loading = false
    @Published private(set) var messagesLoading = false
    @Published private(set) var messagesReady = false
    @Published var error: String?
    @Published var messageError: String?
    @Published var messageLoadError: String?
    private var messageTask: Task<Void, Never>?
    private var watchID = UUID()
    private var accountGeneration = UUID()
    private var moderationGeneration = UUID()
    private var refreshMessagesAgain = false
    private var refreshNotificationsAgain = false
    private var refreshAgain = false

    func person(_ id: UUID) -> SocialPerson? { people.first { $0.id == id } }
    func isJoined(_ session: LiyaSession) -> Bool { session.userID.map { person($0) != nil } ?? false }
    func moderationText(kind: String, id: UUID) -> String? {
        guard moderationAvailable else { return "Review status unavailable." }
        switch moderationStatuses["\(kind):\(id.uuidString.lowercased())"] {
        case "pending": return kind == "profile" ? "Changes awaiting review · only approved profile details are public." : "Awaiting review · visible to you and reviewers."
        case "rejected": return kind == "profile" ? "Changes not approved · only approved profile details are public. Contact support if needed." : "Not approved · visible to you and reviewers. Contact support if needed."
        case "hidden": return "Your community profile is hidden. Contact support if you need help."
        default: return nil
        }
    }

    func refreshModeration(_ session: LiyaSession) async {
        guard let owner = session.userID else { return }
        let generation = accountGeneration
        let request = UUID(); moderationGeneration = request
        do {
            let rows: [ModerationStatus] = try await pages { offset in
                try await session.client.rpc("liya_my_moderation_status", params: [String: String]())
                    .order("kind").order("content_id").range(from: offset, to: offset + 499).execute().value
            }
            guard session.userID == owner, accountGeneration == generation, moderationGeneration == request else { return }
            moderationStatuses = Dictionary(rows.map { ("\($0.kind):\($0.contentID.uuidString.lowercased())", $0.status) }, uniquingKeysWith: { _, last in last })
            moderationAvailable = true
        } catch {
            guard session.userID == owner, accountGeneration == generation, moderationGeneration == request else { return }
            moderationStatuses = [:]; moderationAvailable = false
        }
    }

    func submittedReports(_ session: LiyaSession) async throws -> [SubmittedReport] {
        guard let owner = session.userID else { throw SocialError.conflict }
        let result: [SubmittedReport] = try await pages { offset in
            try await session.client.rpc("liya_my_report_status", params: [String: String]())
                .order("created_at", ascending: false).order("kind").order("report_id")
                .range(from: offset, to: offset + 499).execute().value
        }
        guard session.userID == owner else { throw SocialError.conflict }
        return result
    }

    func pendingProfile(_ session: LiyaSession) async throws -> SocialPerson? {
        guard let owner = session.userID else { throw SocialError.conflict }
        let generation = accountGeneration
        let rows: [ProfileSubmission] = try await session.client.rpc("liya_my_profile_submission", params: [String: String]())
            .limit(1).execute().value
        guard session.userID == owner, generation == accountGeneration else { throw SocialError.conflict }
        return rows.first.map { SocialPerson(id: owner, displayName: $0.displayName, signature: $0.signature, avatarPath: $0.avatarPath) }
    }

    func editableProfile(_ session: LiyaSession) async throws -> SocialPerson? {
        guard let owner = session.userID else { throw SocialError.conflict }
        if let pending = try await pendingProfile(session) { return pending }
        let generation = accountGeneration
        let rows: [SocialPerson] = try await session.client.from("liya_people")
            .select("id,display_name,signature,avatar_path").eq("id", value: owner.uuidString).limit(1).execute().value
        guard session.userID == owner, accountGeneration == generation else { throw SocialError.conflict }
        return rows.first
    }

    func clearAccount() {
        accountGeneration = UUID(); loading = false; messagesLoading = false; messagesReady = false
        refreshAgain = false; refreshMessagesAgain = false
        watchID = UUID(); messageTask?.cancel(); messageTask = nil; realtimeConnected = false
        people = []; posts = []; likes = []; follows = []; followers = []; blocked = []
        moderationStatuses = [:]; moderationAvailable = false; moderationGeneration = UUID()
        messages = []; notifications = []; error = nil; messageError = nil; messageLoadError = nil; notificationsError = nil
        syncGeneration = UUID()
    }

    private func pages<T>(_ load: (Int) async throws -> [T]) async throws -> [T] {
        var result: [T] = []; var offset = 0
        while true {
            let page = try await load(offset); result.append(contentsOf: page)
            if page.count < 500 { return result }; offset += 500
        }
    }

    func refresh(_ session: LiyaSession) async {
        guard let owner = session.userID else { return }
        if loading { refreshAgain = true; return }
        let generation = accountGeneration
        loading = true; error = nil
        defer {
            if accountGeneration == generation {
                loading = false
                if refreshAgain { refreshAgain = false; Task { await refresh(session) } }
            }
        }
        do {
            let newPeople: [SocialPerson] = try await pages { offset in
                try await session.client.from("liya_people").select("id,display_name,signature,avatar_path").order("id").range(from: offset, to: offset + 499).execute().value
            }
            let newPosts: [SocialPost] = try await pages { offset in
                try await session.client.from("liya_posts").select("id,owner_id,body,tags,media_paths,media_kinds,created_at,updated_at").order("created_at", ascending: false).order("id", ascending: false).range(from: offset, to: offset + 499).execute().value
            }
            let relations: [SocialRelation] = try await pages { offset in
                try await session.client.from("liya_follows").select("owner_id,target_id").order("owner_id").order("target_id").range(from: offset, to: offset + 499).execute().value
            }
            let blocks: [SocialRelation] = try await pages { offset in
                try await session.client.from("liya_blocks").select("owner_id,target_id").eq("owner_id", value: owner.uuidString).order("target_id").range(from: offset, to: offset + 499).execute().value
            }
            let liked: [PostLike] = try await pages { offset in
                try await session.client.from("liya_post_likes").select("owner_id,post_id").eq("owner_id", value: owner.uuidString).order("post_id").range(from: offset, to: offset + 499).execute().value
            }
            guard session.userID == owner, accountGeneration == generation else { return }
            people = newPeople; posts = newPosts
            follows = relations.filter { $0.ownerID == owner }.map(\.targetID)
            followers = relations.filter { $0.targetID == owner }.map(\.ownerID)
            blocked = blocks.map(\.targetID); likes = Set(liked.map(\.postID))
            await refreshModeration(session)
        } catch {
            if owner == session.userID && accountGeneration == generation {
                people = []; posts = []; likes = []; follows = []; followers = []; blocked = []
                self.error = "Couldn't load the community. Please try again."
            }
        }
    }

    func join(_ session: LiyaSession, name: String, signature: String, shareAvatar: Bool) async -> Bool {
        guard let owner = session.userID else { return false }
        let person = SocialPerson(id: owner, displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), signature: signature, avatarPath: shareAvatar ? session.profile?.avatarPath : nil)
        do {
            try await session.client.from("liya_people").upsert(person, onConflict: "id").execute()
            let result: SocialPerson = try await session.client.from("liya_people").select("id,display_name,signature,avatar_path").eq("id", value: owner.uuidString).single().execute().value
            guard owner == session.userID else { return false }
            if result != person {
                guard try await pendingProfile(session) == person else { throw SocialError.conflict }
            }
            people.removeAll { $0.id == owner }; people.append(result)
            await refresh(session); return true
        } catch { self.error = "Couldn't save your community profile. Please try again."; return false }
    }

    private func upload(_ session: LiyaSession, owner: UUID, id: UUID, attachments: [DraftAttachment]) async throws -> ([String], [String]) {
        var paths: [String] = []; var kinds: [String] = []
        for item in attachments {
            let original = DraftFiles.url(item)
            let prepared: VideoCompression.Prepared
            if item.isVideo { prepared = try await VideoCompression.prepare(original) }
            else { prepared = VideoCompression.Prepared(url: original, isTemporary: false) }
            defer { if prepared.isTemporary { try? FileManager.default.removeItem(at: prepared.url) } }
            let ext = prepared.url.pathExtension.lowercased()
            let path = "\(owner.uuidString.lowercased())/social/\(id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext.isEmpty ? (item.isVideo ? "mov" : "jpg") : ext)"
            try await session.client.storage.from("liya-user-media").upload(path, fileURL: prepared.url)
            paths.append(path); kinds.append(item.isVideo ? "video" : "photo")
        }
        return (paths, kinds)
    }

    func publish(_ session: LiyaSession, id: UUID, body: String, tags: [String], attachments: [DraftAttachment]) async -> Bool {
        guard let owner = session.userID, isJoined(session) else { error = "Create your community profile first."; return false }
        do {
            let existing: [SocialPost] = try await session.client.from("liya_posts").select("id,owner_id,body,tags,media_paths,media_kinds,created_at,updated_at").eq("id", value: id.uuidString).execute().value
            if let post = existing.first {
                guard post.ownerID == owner && post.body == body && post.tags == tags && post.mediaPaths.count == attachments.count else { throw SocialError.conflict }
                await refresh(session); return true
            }
            let (paths, kinds) = try await upload(session, owner: owner, id: id, attachments: attachments)
            let input = SocialPostInput(id: id, ownerID: owner, body: body, tags: tags, mediaPaths: paths, mediaKinds: kinds)
            do { try await session.client.from("liya_posts").insert(input).execute() } catch { /* Read back uncertain inserts. */ }
            let saved: [SocialPost] = try await session.client.from("liya_posts").select("id,owner_id,body,tags,media_paths,media_kinds,created_at,updated_at").eq("id", value: id.uuidString).execute().value
            guard let post = saved.first, post.ownerID == owner, post.body == body, post.tags == tags, post.mediaPaths == paths, session.userID == owner else { throw SocialError.conflict }
            await refresh(session); return true
        } catch {
            self.error = (error as? VideoCompression.Failure)?.errorDescription ?? "Couldn't confirm your post. Your text and attachments are still here; please try again."
            return false
        }
    }

    func updatePost(_ session: LiyaSession, post: SocialPost, body: String, tags: [String], paths: [String], kinds: [String], additions: [DraftAttachment]) async -> Bool {
        guard let owner = session.userID, post.ownerID == owner, paths.count == kinds.count, paths.count + additions.count <= 9 else { return false }
        struct Edit: Encodable {
            let body: String; let tags: [String]; let mediaPaths: [String]; let mediaKinds: [String]
            enum CodingKeys: String, CodingKey { case body, tags; case mediaPaths = "media_paths", mediaKinds = "media_kinds" }
        }
        do {
            let (newPaths, newKinds) = try await upload(session, owner: owner, id: post.id, attachments: additions)
            let finalPaths = paths + newPaths; let finalKinds = kinds + newKinds
            let saved: SocialPost = try await session.client.from("liya_posts").update(Edit(body: body, tags: tags, mediaPaths: finalPaths, mediaKinds: finalKinds))
                .eq("id", value: post.id.uuidString).eq("updated_at", value: post.updatedAt)
                .select("id,owner_id,body,tags,media_paths,media_kinds,created_at,updated_at").single().execute().value
            guard saved.body == body && saved.tags == tags && saved.mediaPaths == finalPaths && saved.mediaKinds == finalKinds else { throw SocialError.conflict }
            await refresh(session); return true
        } catch {
            self.error = (error as? VideoCompression.Failure)?.errorDescription ?? "Couldn't confirm changes. The post may have changed elsewhere; refresh before editing again."
            return false
        }
    }

    func deletePost(_ session: LiyaSession, id: UUID) async -> Bool {
        do {
            try await session.client.from("liya_posts").delete().eq("id", value: id.uuidString).execute()
            let remaining: [SocialPost] = try await session.client.from("liya_posts").select("id,owner_id,body,tags,media_paths,media_kinds,created_at,updated_at").eq("id", value: id.uuidString).execute().value
            guard remaining.isEmpty else { throw SocialError.conflict }
            await refresh(session); return true
        } catch { self.error = "Couldn't confirm deletion. Please refresh."; return false }
    }

    func toggleLike(_ session: LiyaSession, post: UUID) async {
        guard let owner = session.userID, isJoined(session) else { error = "Create your community profile first."; return }
        let desired = !likes.contains(post)
        do {
            if desired { try await session.client.from("liya_post_likes").insert(PostLike(ownerID: owner, postID: post)).execute() }
            else { try await session.client.from("liya_post_likes").delete().eq("owner_id", value: owner.uuidString).eq("post_id", value: post.uuidString).execute() }
        } catch { /* Refresh establishes the committed state. */ }
        await refresh(session)
        if !loading && error == nil && likes.contains(post) != desired { error = "Couldn't update your like." }
    }

    func setRelation(_ session: LiyaSession, target: UUID, table: String, enabled: Bool) async {
        guard let owner = session.userID, isJoined(session), table == "liya_follows" || table == "liya_blocks" else { error = "Create your community profile first."; return }
        do {
            if enabled { try await session.client.from(table).insert(SocialRelation(ownerID: owner, targetID: target)).execute() }
            else { try await session.client.from(table).delete().eq("owner_id", value: owner.uuidString).eq("target_id", value: target.uuidString).execute() }
        } catch { /* Read committed state on refresh. */ }
        await refresh(session)
        let value = table == "liya_follows" ? follows.contains(target) : blocked.contains(target)
        if !loading && error == nil && value != enabled { error = "Couldn't update this setting." }
        if table == "liya_blocks" { await refreshMessages(session) }
    }

    func comments(_ session: LiyaSession, post: UUID) async throws -> [SocialComment] {
        try await pages { offset in
            try await session.client.from("liya_post_comments").select("id,owner_id,post_id,body").eq("post_id", value: post.uuidString).order("created_at").order("id").range(from: offset, to: offset + 499).execute().value
        }
    }

    func videoComments(_ session: LiyaSession, mediaID: String) async throws -> [VideoComment] {
        try await pages { offset in
            try await session.client.from("liya_video_comments")
                .select("id,media_id,owner_id,body,created_at").eq("media_id", value: mediaID)
                .order("created_at").order("id").range(from: offset, to: offset + 499).execute().value
        }
    }

    func sendVideoComment(_ session: LiyaSession, id: UUID, mediaID: String, body: String) async -> Bool {
        guard let owner = session.userID, isJoined(session) else { return false }
        let value = VideoCommentInsert(id: id, mediaID: mediaID, ownerID: owner, body: body)
        do { try await session.client.from("liya_video_comments").insert(value).execute() } catch { }
        do {
            let rows: [VideoComment] = try await session.client.from("liya_video_comments")
                .select("id,media_id,owner_id,body,created_at").eq("id", value: id.uuidString).execute().value
            guard session.userID == owner, rows.contains(where: { $0.id == id && $0.mediaID == mediaID && $0.ownerID == owner && $0.body == body }) else { return false }
            await refreshModeration(session)
            guard session.userID == owner else { return false }
            syncGeneration = UUID()
            return true
        } catch { return false }
    }

    func deleteVideoComment(_ session: LiyaSession, id: UUID) async -> Bool {
        guard let owner = session.userID else { return false }
        do {
            try await session.client.from("liya_video_comments").delete().eq("id", value: id.uuidString).eq("owner_id", value: owner.uuidString).execute()
            let rows: [VideoComment] = try await session.client.from("liya_video_comments")
                .select("id,media_id,owner_id,body,created_at").eq("id", value: id.uuidString).execute().value
            guard session.userID == owner, rows.isEmpty else { return false }
            syncGeneration = UUID()
            return true
        } catch { return false }
    }

    func reportVideoComment(_ session: LiyaSession, id: UUID, mediaID: String, commentID: UUID?, presetKey: String?, body: String, reason: String) async -> Bool {
        guard let owner = session.userID else { return false }
        let value = VideoCommentReport(id: id, reporterID: owner, mediaID: mediaID, commentID: commentID, presetKey: presetKey, bodySnapshot: body, reason: reason)
        do { try await session.client.from("liya_video_comment_reports").insert(value).execute() } catch { }
        do {
            let rows: [VideoCommentReport] = try await session.client.from("liya_video_comment_reports")
                .select("id,reporter_id,media_id,comment_id,preset_key,body_snapshot,reason").eq("id", value: id.uuidString).execute().value
            return session.userID == owner && rows.first == value
        } catch { return false }
    }

    func sendComment(_ session: LiyaSession, id: UUID, post: UUID, body: String) async -> Bool {
        guard let owner = session.userID, isJoined(session) else { error = "Create your community profile first."; return false }
        let item = SocialComment(id: id, ownerID: owner, postID: post, body: body)
        do { try await session.client.from("liya_post_comments").insert(item).execute() } catch { }
        do {
            let rows: [SocialComment] = try await session.client.from("liya_post_comments").select("id,owner_id,post_id,body").eq("id", value: id.uuidString).execute().value
            guard rows.first == item && session.userID == owner else { return false }
            await refreshModeration(session)
            guard session.userID == owner else { return false }
            return true
        } catch { self.error = "Couldn't confirm the comment. Your text is still here."; return false }
    }

    func deleteComment(_ session: LiyaSession, id: UUID) async -> Bool {
        do {
            try await session.client.from("liya_post_comments").delete().eq("id", value: id.uuidString).execute()
            let rows: [SocialComment] = try await session.client.from("liya_post_comments").select("id,owner_id,post_id,body").eq("id", value: id.uuidString).execute().value
            return rows.isEmpty
        } catch { self.error = "Couldn't confirm deletion."; return false }
    }

    func report(_ session: LiyaSession, id: UUID, target: UUID, post: UUID?, reason: String) async -> Bool {
        guard let owner = session.userID else { return false }
        let item = SocialReport(id: id, reporterID: owner, targetUser: target, postID: post, reason: reason)
        do { try await session.client.from("liya_social_reports").insert(item).execute() } catch { }
        do {
            let rows: [SocialReport] = try await session.client.from("liya_social_reports").select("id,reporter_id,target_user,post_id,reason").eq("id", value: id.uuidString).execute().value
            return rows.first == item && session.userID == owner
        } catch { self.error = "Couldn't confirm your report. Please try again."; return false }
    }

    func reportComment(_ session: LiyaSession, id: UUID, comment: SocialComment, reason: String) async -> Bool {
        guard let owner = session.userID, owner != comment.ownerID else { return false }
        let item = PostCommentReport(id: id, reporterID: owner, commentID: comment.id, postID: comment.postID,
                                     targetUser: comment.ownerID, bodySnapshot: comment.body, reason: reason)
        do { try await session.client.from("liya_post_comment_reports").insert(item).execute() } catch { }
        do {
            let rows: [PostCommentReport] = try await session.client.from("liya_post_comment_reports")
                .select("id,reporter_id,comment_id,post_id,target_user,body_snapshot,reason").eq("id", value: id.uuidString).execute().value
            return rows.first == item && session.userID == owner
        } catch { self.error = "Couldn't confirm your report. Please try again."; return false }
    }

    func reportMessage(_ session: LiyaSession, id: UUID, message: SocialMessage, reason: String) async -> Bool {
        guard let owner = session.userID, message.recipientID == owner, message.senderID != owner else { return false }
        let item = MessageReport(id: id, reporterID: owner, messageID: message.id, targetUser: message.senderID,
                                 bodySnapshot: message.body, mediaPaths: message.mediaPaths, mediaKinds: message.mediaKinds, reason: reason)
        do { try await session.client.from("liya_message_reports").insert(item).execute() } catch { }
        do {
            let rows: [MessageReport] = try await session.client.from("liya_message_reports")
                .select("id,reporter_id,message_id,target_user,body_snapshot,media_paths,media_kinds,reason").eq("id", value: id.uuidString).execute().value
            return rows.first == item && session.userID == owner
        } catch { self.error = "Couldn't confirm your report. Please try again."; return false }
    }

    func refreshMessages(_ session: LiyaSession) async {
        guard let owner = session.userID else { return }
        if messagesLoading { refreshMessagesAgain = true; return }
        let generation = accountGeneration
        messagesLoading = true; messageLoadError = nil
        defer {
            if accountGeneration == generation {
                messagesLoading = false
                if refreshMessagesAgain { refreshMessagesAgain = false; Task { await refreshMessages(session) } }
            }
        }
        do {
            let rows: [SocialMessage] = try await pages { offset in
                try await session.client.from("liya_messages").select("id,sender_id,recipient_id,body,media_paths,media_kinds,created_at").order("created_at").order("id").range(from: offset, to: offset + 499).execute().value
            }
            guard session.userID == owner, accountGeneration == generation else { return }
            messages = rows; messagesReady = true
        } catch {
            if session.userID == owner && accountGeneration == generation {
                messageLoadError = "Couldn't load your messages. Please try again."
            }
        }
    }

    func isMutualFollow(_ session: LiyaSession, target: UUID) async throws -> Bool {
        guard let owner = session.userID, owner != target else { throw SocialError.conflict }
        let generation = accountGeneration
        let outgoing: [SocialRelation] = try await session.client.from("liya_follows").select("owner_id,target_id")
            .eq("owner_id", value: owner.uuidString).eq("target_id", value: target.uuidString).execute().value
        let incoming: [SocialRelation] = try await session.client.from("liya_follows").select("owner_id,target_id")
            .eq("owner_id", value: target.uuidString).eq("target_id", value: owner.uuidString).execute().value
        guard session.userID == owner, generation == accountGeneration else { throw SocialError.conflict }
        return !outgoing.isEmpty && !incoming.isEmpty
    }

    func sendMessage(_ session: LiyaSession, id: UUID, target: UUID, body: String, attachments: [DraftAttachment]) async -> Bool {
        guard let owner = session.userID, isJoined(session) else { messageError = "Create your community profile first."; return false }
        messageError = nil
        let generation = accountGeneration
        do {
            let old: [SocialMessage] = try await session.client.from("liya_messages").select("id,sender_id,recipient_id,body,media_paths,media_kinds,created_at").eq("id", value: id.uuidString).execute().value
            if let message = old.first {
                guard session.userID == owner, accountGeneration == generation, message.senderID == owner && message.recipientID == target && message.body == body && message.mediaPaths.count == attachments.count else { throw SocialError.conflict }
                await refreshMessages(session); return session.userID == owner && accountGeneration == generation
            }
            guard session.userID == owner, accountGeneration == generation else { return false }
            guard try await isMutualFollow(session, target: target) else { throw SocialError.mutualRequired }
            let (paths, kinds) = try await upload(session, owner: owner, id: id, attachments: attachments)
            guard session.userID == owner, accountGeneration == generation else { return false }
            let input = SocialMessageInput(id: id, senderID: owner, recipientID: target, body: body, mediaPaths: paths, mediaKinds: kinds)
            do { try await session.client.from("liya_messages").insert(input).execute() } catch { }
            let saved: [SocialMessage] = try await session.client.from("liya_messages").select("id,sender_id,recipient_id,body,media_paths,media_kinds,created_at").eq("id", value: id.uuidString).execute().value
            guard let message = saved.first, message.senderID == owner, message.recipientID == target, message.body == body, message.mediaPaths == paths, session.userID == owner, accountGeneration == generation else { throw SocialError.conflict }
            await refreshMessages(session); return session.userID == owner && accountGeneration == generation
        } catch {
            if session.userID == owner && accountGeneration == generation {
                messageError = (error as? SocialError) == .mutualRequired ? "Follow each other before sending a message." : ((error as? VideoCompression.Failure)?.errorDescription ?? "Couldn't confirm the message. Your draft is still here; please try again.")
            }
            return false
        }
    }

    func deleteMessage(_ session: LiyaSession, message: SocialMessage) async -> Bool {
        guard message.senderID == session.userID else { return false }
        do {
            try await session.client.from("liya_messages").delete().eq("id", value: message.id.uuidString).execute()
            let rows: [SocialMessage] = try await session.client.from("liya_messages").select("id,sender_id,recipient_id,body,media_paths,media_kinds,created_at").eq("id", value: message.id.uuidString).execute().value
            guard rows.isEmpty else { throw SocialError.conflict }
            await refreshMessages(session); return true
        } catch { messageError = "Couldn't confirm deletion. Please refresh."; return false }
    }

    func watchMessages(_ session: LiyaSession) {
        guard let owner = session.userID else { return }
        messageTask?.cancel(); realtimeConnected = false
        let generation = UUID(); watchID = generation
        let client = session.client
        let channel = client.channel("liya-sync-\(owner.uuidString)-\(generation.uuidString)")
        let userInserts = channel.postgresChange(InsertAction.self, schema: "public", table: "liya_user_revisions", filter: .eq("owner_id", value: owner.uuidString.lowercased()))
        let userUpdates = channel.postgresChange(UpdateAction.self, schema: "public", table: "liya_user_revisions", filter: .eq("owner_id", value: owner.uuidString.lowercased()))
        let feedUpdates = channel.postgresChange(UpdateAction.self, schema: "public", table: "liya_feed_revision")
        let statuses = channel.statusChange
        messageTask = Task { [weak self, weak session] in
            let userInsertTask = Task { [weak self, weak session] in
                for await _ in userInserts {
                    guard !Task.isCancelled, let self, let session, self.watchID == generation else { break }
                    await self.syncSocial(session)
                }
            }
            let userUpdateTask = Task { [weak self, weak session] in
                for await _ in userUpdates {
                    guard !Task.isCancelled, let self, let session, self.watchID == generation else { break }
                    await self.syncSocial(session)
                }
            }
            let feedTask = Task { [weak self, weak session] in
                for await _ in feedUpdates {
                    guard !Task.isCancelled, let self, let session, self.watchID == generation else { break }
                    await self.refresh(session)
                    self.syncGeneration = UUID()
                }
            }
            let statusTask = Task { [weak self, weak session] in
                for await status in statuses {
                    guard !Task.isCancelled, let self, let session, self.watchID == generation else { break }
                    if case .subscribed = status {
                        self.realtimeConnected = true
                        await self.syncSocial(session)
                    } else {
                        self.realtimeConnected = false
                    }
                }
            }
            defer { userInsertTask.cancel(); userUpdateTask.cancel(); feedTask.cancel(); statusTask.cancel() }
            await withTaskCancellationHandler {
                do {
                    try await channel.subscribeWithError()
                    await userUpdateTask.value
                } catch {
                    if !Task.isCancelled, self?.watchID == generation { self?.realtimeConnected = false }
                }
            } onCancel: {
                userInsertTask.cancel(); userUpdateTask.cancel(); feedTask.cancel(); statusTask.cancel()
            }
            if self?.watchID == generation { self?.realtimeConnected = false }
            await client.removeChannel(channel)
        }
    }

    private func syncSocial(_ session: LiyaSession) async {
        await refresh(session)
        await refreshMessages(session)
        await refreshNotifications(session)
        syncGeneration = UUID()
    }

    func refreshNotifications(_ session: LiyaSession) async {
        guard let owner = session.userID else { return }
        if notificationsLoading { refreshNotificationsAgain = true; return }
        notificationsLoading = true; notificationsError = nil; notifications = []
        defer {
            notificationsLoading = false
            if refreshNotificationsAgain { refreshNotificationsAgain = false; Task { await refreshNotifications(session) } }
        }
        do {
            let rows: [SocialNotification] = try await pages { offset in
                try await session.client.from("liya_social_notifications").select("id,owner_id,actor_id,kind,post_id,is_read,created_at").eq("owner_id", value: owner.uuidString).order("created_at", ascending: false).order("id", ascending: false).range(from: offset, to: offset + 499).execute().value
            }
            if session.userID == owner { notifications = rows }
        } catch { if session.userID == owner { notificationsError = "Couldn't load activity. Please try again." } }
    }

    func markRead(_ session: LiyaSession, id: Int64) async {
        struct Read: Encodable { let is_read: Bool }
        do {
            try await session.client.from("liya_social_notifications").update(Read(is_read: true)).eq("id", value: String(id)).execute()
            await refreshNotifications(session)
        } catch { notificationsError = "Couldn't update activity." }
    }

    func mediaURL(_ session: LiyaSession, path: String) async throws -> URL {
        try await session.client.storage.from("liya-user-media").createSignedURL(path: path, expiresIn: 300)
    }
}
private enum SocialError: Error { case conflict, mutualRequired }
