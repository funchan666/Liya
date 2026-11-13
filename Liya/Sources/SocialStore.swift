import Foundation
import Combine

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
 func person(_ id: UUID) -> SocialPerson? { people.first { $0.id == id } }
 func isJoined(_ session: LiyaSession) -> Bool { false }
 func moderationText(kind: String, id: UUID) -> String? { nil }
 func refreshModeration(_ session: LiyaSession) async { }
 func submittedReports(_ session: LiyaSession) async throws -> [SubmittedReport] { throw OfflineError.unavailable }
 func pendingProfile(_ session: LiyaSession) async throws -> SocialPerson? { throw OfflineError.unavailable }
 func editableProfile(_ session: LiyaSession) async throws -> SocialPerson? { throw OfflineError.unavailable }
 func clearAccount() { people = []; posts = []; follows = []; followers = []; blocked = []; likes = []; messages = []; notifications = []; error = nil; messageError = nil; messageLoadError = nil; messagesReady = false; syncGeneration = UUID() }
 func refresh(_ session: LiyaSession) async { loading = false; error = nil; syncGeneration = UUID() }
 func join(_ session: LiyaSession, name: String, signature: String, shareAvatar: Bool) async -> Bool { error = "Community features are unavailable right now."; return false }
 func publish(_ session: LiyaSession, id: UUID, body: String, tags: [String], attachments: [DraftAttachment]) async -> Bool { error = "Sharing is unavailable right now."; return false }
 func updatePost(_ session: LiyaSession, post: SocialPost, body: String, tags: [String], paths: [String], kinds: [String], additions: [DraftAttachment]) async -> Bool { error = "Sharing is unavailable right now."; return false }
 func deletePost(_ session: LiyaSession, id: UUID) async -> Bool { false }
 func toggleLike(_ session: LiyaSession, post: UUID) async { error = "Community features are unavailable right now." }
 func setRelation(_ session: LiyaSession, target: UUID, table: String, enabled: Bool) async { error = "Community features are unavailable right now." }
 func comments(_ session: LiyaSession, post: UUID) async throws -> [SocialComment] { throw OfflineError.unavailable }
 func videoComments(_ session: LiyaSession, mediaID: String) async throws -> [VideoComment] { throw OfflineError.unavailable }
 func sendVideoComment(_ session: LiyaSession, id: UUID, mediaID: String, body: String) async -> Bool { false }
 func deleteVideoComment(_ session: LiyaSession, id: UUID) async -> Bool { false }
 func reportVideoComment(_ session: LiyaSession, id: UUID, mediaID: String, commentID: UUID?, presetKey: String?, body: String, reason: String) async -> Bool { false }
 func sendComment(_ session: LiyaSession, id: UUID, post: UUID, body: String) async -> Bool { false }
 func deleteComment(_ session: LiyaSession, id: UUID) async -> Bool { false }
 func report(_ session: LiyaSession, id: UUID, target: UUID, post: UUID?, reason: String) async -> Bool { false }
 func reportComment(_ session: LiyaSession, id: UUID, comment: SocialComment, reason: String) async -> Bool { false }
 func reportMessage(_ session: LiyaSession, id: UUID, message: SocialMessage, reason: String) async -> Bool { false }
 func refreshMessages(_ session: LiyaSession) async { messagesReady = false; messageLoadError = "Messaging is unavailable right now." }
 func isMutualFollow(_ session: LiyaSession, target: UUID) async throws -> Bool { throw OfflineError.unavailable }
 func sendMessage(_ session: LiyaSession, id: UUID, target: UUID, body: String, attachments: [DraftAttachment]) async -> Bool { messageError = "Messaging is unavailable right now."; return false }
 func deleteMessage(_ session: LiyaSession, message: SocialMessage) async -> Bool { false }
 func watchMessages(_ session: LiyaSession) { }
 func refreshNotifications(_ session: LiyaSession) async { notifications = []; notificationsLoading = false }
 func markRead(_ session: LiyaSession, id: Int64) async { }
 func mediaURL(_ session: LiyaSession, path: String) async throws -> URL { throw OfflineError.unavailable }
 private enum OfflineError: Error { case unavailable }
}
