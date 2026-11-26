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
    let author: SocialPerson?
    enum CodingKeys: String, CodingKey {
        case id, body, author
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
private struct FollowMember: Decodable {
    let member: SocialPerson
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
 @Published private(set) var checkedMemberProfileOwner: UUID?
 @Published private(set) var posts: [SocialPost] = []
 @Published private(set) var follows: [UUID] = []
 @Published private(set) var followers: [UUID] = []
 @Published private(set) var connectionsOwner: UUID?
 @Published private(set) var connectionsReady = false
 @Published private(set) var connectionsLoading = false
 @Published private(set) var connectionsError: String?
 @Published private(set) var changingFollows: Set<UUID> = []
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
 private var commentAuthors: [UUID: SocialPerson] = [:]
 private var connectionPeople: [UUID: SocialPerson] = [:]
 private var connectionAccountRevision = UUID()
 private var connectionsRequest = UUID()
 private var connectionsTask: Task<Void, Never>?
 private var refreshRequest = UUID()
 private var visibilityRevision = UUID()
 private var moderationRequest = UUID()
 private var moderationEndpointMissing = false
 private let commentColumns = "id,media_id,owner_id,body,created_at"
 func person(_ id: UUID) -> SocialPerson? { people.first { $0.id == id } ?? connectionPeople[id] ?? commentAuthors[id] }
 func isJoined(_ session: LiyaSession) -> Bool { false }
 func canFollowMembers(_ session: LiyaSession) -> Bool {
     canCommentOnMedia(session) || (session.userID == connectionsOwner && (!follows.isEmpty || !followers.isEmpty))
 }
 func canCommentOnMedia(_ session: LiyaSession) -> Bool {
     guard let owner = session.userID else { return false }
     return people.contains { $0.id == owner }
 }
 func moderationText(kind: String, id: UUID) -> String? {
     switch moderationStatuses["\(kind):\(id.uuidString.lowercased())"] {
     case "pending": return "Awaiting review · visible to you and reviewers."
     case "rejected": return "Not approved · visible to you and reviewers. Contact support if needed."
     case "hidden": return "Your community profile is hidden. Contact support if you need help."
     default: return nil
     }
 }
 func refreshModeration(_ session: LiyaSession) async {
     guard let owner = session.userID, !moderationEndpointMissing else { return }
     let request = UUID()
     moderationRequest = request
     do {
         let rows: [ModerationStatus] = try await pages { offset in
             try await session.client.rpc("liya_my_moderation_status").order("kind").order("content_id")
                 .range(from: offset, to: offset + 499).execute().value
         }
         guard session.userID == owner, moderationRequest == request else { return }
         moderationStatuses = Dictionary(rows.map { ("\($0.kind):\($0.contentID.uuidString.lowercased())", $0.status) }, uniquingKeysWith: { _, latest in latest })
         moderationAvailable = true
     } catch {
         guard session.userID == owner, moderationRequest == request, !Task.isCancelled else { return }
         moderationEndpointMissing = (error as? PostgrestError)?.code == "PGRST202"
         moderationStatuses = [:]; moderationAvailable = false
     }
 }
 func submittedReports(_ session: LiyaSession) async throws -> [SubmittedReport] {
     guard let owner = session.userID else { throw OfflineError.unavailable }
     let results: [SubmittedReport] = try await pages { offset in
         guard session.userID == owner else { throw CancellationError() }
         return try await session.client.rpc("liya_my_report_status")
             .order("created_at", ascending: false).order("kind").order("report_id")
             .range(from: offset, to: offset + 499).execute().value
     }
     guard session.userID == owner else { throw CancellationError() }
     var seen = Set<String>()
     return results.filter { seen.insert($0.id).inserted }
 }
 func pendingProfile(_ session: LiyaSession) async throws -> SocialPerson? {
     guard let owner = session.userID else { throw OfflineError.unavailable }
     if moderationEndpointMissing { return nil }
     do {
         let rows: [ProfileSubmission] = try await session.client.rpc("liya_my_profile_submission")
             .limit(1).execute().value
         guard session.userID == owner else { throw CancellationError() }
         return rows.first.map { SocialPerson(id: owner, displayName: $0.displayName, signature: $0.signature, avatarPath: $0.avatarPath) }
     } catch let error as PostgrestError where error.code == "PGRST202" {
         return nil
     }
 }

 private func publicProfile(_ session: LiyaSession, owner: UUID) async throws -> SocialPerson? {
     let rows: [SocialPerson] = try await session.client.from("liya_people")
         .select("id,display_name,signature,avatar_path").eq("id", value: owner.uuidString).limit(1).execute().value
     guard session.userID == owner else { throw CancellationError() }
     return rows.first
 }

 func editableProfile(_ session: LiyaSession) async throws -> SocialPerson? {
     guard let owner = session.userID else { throw OfflineError.unavailable }
     if let pending = try await pendingProfile(session) { return pending }
     return try await publicProfile(session, owner: owner)
 }

 func clearAccount() {
     refreshRequest = UUID(); visibilityRevision = UUID(); loading = false
     moderationRequest = UUID(); moderationEndpointMissing = false; moderationStatuses = [:]; moderationAvailable = false
     resetConnections(owner: nil)
     checkedMemberProfileOwner = nil
     commentAuthors.removeAll(); people = []; posts = []; blocked = []; likes = []
     messages = []; notifications = []; error = nil; messageError = nil; messageLoadError = nil
     messagesReady = false; syncGeneration = UUID()
 }

 private func invalidateConnectionRead() {
     connectionsRequest = UUID()
     connectionsTask?.cancel()
     connectionsTask = nil
     connectionsLoading = false
 }

 private func resetConnections(owner: UUID?) {
     invalidateConnectionRead()
     connectionAccountRevision = UUID()
     connectionsOwner = owner
     connectionsReady = false
     connectionsError = nil
     connectionPeople.removeAll()
     changingFollows.removeAll()
     follows = []
     followers = []
 }

 private func selectConnectionAccount(_ owner: UUID?) {
     guard connectionsOwner != owner else { return }
     if connectionsOwner != nil { clearAccount() }
     if let owner { resetConnections(owner: owner) }
 }

 private func connectedMembers(_ session: LiyaSession, owner: UUID, outgoing: Bool) async throws -> [SocialPerson] {
     let ownerColumn = outgoing ? "owner_id" : "target_id"
     let memberColumn = outgoing ? "target_id" : "owner_id"
     let selection = "member:liya_people!liya_follows_\(memberColumn)_fkey!inner(id,display_name,signature,avatar_path)"
     var members: [SocialPerson] = []
     while true {
         try Task.checkCancellation()
         guard session.userID == owner else { throw CancellationError() }
         var query = session.client.from("liya_follows").select(selection).eq(ownerColumn, value: owner.uuidString)
         if let cursor = members.last?.id { query = query.gt(memberColumn, value: cursor.uuidString) }
         let page: [FollowMember] = try await query.order(memberColumn).limit(500).execute().value
         members.append(contentsOf: page.map(\.member))
         if page.count < 500 { return members }
     }
 }

 func refreshConnections(_ session: LiyaSession) async {
     selectConnectionAccount(session.userID)
     guard let owner = session.userID else { return }
     if let connectionsTask { await connectionsTask.value; return }
     let request = UUID()
     connectionsRequest = request
     connectionsLoading = true
     connectionsError = nil
     let task = Task {
         defer {
             if connectionsRequest == request {
                 connectionsLoading = false
                 connectionsTask = nil
             }
         }
         do {
             async let incoming = connectedMembers(session, owner: owner, outgoing: false)
             async let outgoing = connectedMembers(session, owner: owner, outgoing: true)
             let (fans, following) = try await (incoming, outgoing)
             guard session.userID == owner, connectionsRequest == request else { return }
             let hidden = Set(blocked)
             let visibleFans = fans.filter { !hidden.contains($0.id) }
             let visibleFollowing = following.filter { !hidden.contains($0.id) }
             connectionPeople = Dictionary((visibleFans + visibleFollowing).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
             followers = visibleFans.map(\.id)
             follows = visibleFollowing.map(\.id)
             connectionsReady = true
         } catch {
             if session.userID == owner, connectionsRequest == request, !Task.isCancelled {
                 connectionsError = "Couldn't refresh your connections."
             }
         }
     }
     connectionsTask = task
     await task.value
 }

 private func pages<T>(_ fetch: (Int) async throws -> [T]) async throws -> [T] {
     var rows: [T] = []
     while true {
         try Task.checkCancellation()
         let page = try await fetch(rows.count)
         rows.append(contentsOf: page)
         if page.count < 500 { return rows }
     }
 }

 func refresh(_ session: LiyaSession) async {
     selectConnectionAccount(session.userID)
     guard let owner = session.userID else { return }
     async let connections: Void = refreshConnections(session)
     let request = UUID()
     refreshRequest = request; loading = true; error = nil
     defer { if refreshRequest == request { loading = false } }
     do {
         let profile = try await publicProfile(session, owner: owner)
         guard session.userID == owner, refreshRequest == request else { return }
         people = profile.map { [$0] } ?? []
         checkedMemberProfileOwner = owner
         let relations: [SocialRelation] = try await pages { offset in
             try await session.client.from("liya_blocks").select("owner_id,target_id").eq("owner_id", value: owner.uuidString)
                 .order("target_id").range(from: offset, to: offset + 499).execute().value
         }
         guard session.userID == owner, refreshRequest == request else { return }
         let blocks = relations.map(\.targetID)
         if Set(blocks) != Set(blocked) {
             visibilityRevision = UUID()
             blocked = blocks
             let hidden = Set(blocks)
             follows.removeAll { hidden.contains($0) }
             followers.removeAll { hidden.contains($0) }
             connectionPeople = connectionPeople.filter { !hidden.contains($0.key) }
             commentAuthors = commentAuthors.filter { !hidden.contains($0.key) }
             syncGeneration = UUID()
         }
         await refreshModeration(session)
     } catch {
         if session.userID == owner, refreshRequest == request, !Task.isCancelled {
             self.error = "Couldn't load your profile. Please try again."
         }
     }
     await connections
 }

 func join(_ session: LiyaSession, name: String, signature: String, shareAvatar: Bool) async -> Bool {
     guard let owner = session.userID else { return false }
     let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
     let path = shareAvatar ? session.profile?.avatarPath : nil
     guard !name.isEmpty, name.count <= 80, signature.count <= 500, !shareAvatar || path != nil else { return false }
     let requested = SocialPerson(id: owner, displayName: name, signature: signature, avatarPath: path)
     error = nil
     do {
         // Read back the requested values even if the write response was interrupted.
         do { try await session.client.from("liya_people").upsert(requested, onConflict: "id").execute() } catch { }
         guard let saved = try await publicProfile(session, owner: owner) else { throw OfflineError.unavailable }
         if saved != requested {
             guard try await pendingProfile(session) == requested else { throw OfflineError.unavailable }
         }
         guard session.userID == owner else { return false }
         people = [saved]
         checkedMemberProfileOwner = owner
         await refresh(session)
         return session.userID == owner
     } catch {
         if session.userID == owner { self.error = "Couldn't save your community profile. Please try again." }
         return false
     }
 }
 func publish(_ session: LiyaSession, id: UUID, body: String, tags: [String], attachments: [DraftAttachment]) async -> Bool { error = "Sharing is unavailable right now."; return false }
 func updatePost(_ session: LiyaSession, post: SocialPost, body: String, tags: [String], paths: [String], kinds: [String], additions: [DraftAttachment]) async -> Bool { error = "Sharing is unavailable right now."; return false }
 func deletePost(_ session: LiyaSession, id: UUID) async -> Bool { false }
 func toggleLike(_ session: LiyaSession, post: UUID) async { error = "Community features are unavailable right now." }
 @discardableResult
 func setRelation(_ session: LiyaSession, target: UUID, table: String, enabled: Bool) async -> Bool {
     switch table {
     case "liya_blocks": return await setCommenterBlock(session, target: target, enabled: enabled)
     case "liya_follows": return await setFollow(session, target: target, enabled: enabled)
     default: return false
     }
 }

 private func setFollow(_ session: LiyaSession, target: UUID, enabled: Bool) async -> Bool {
     guard let owner = session.userID, owner != target else { return false }
     selectConnectionAccount(owner)
     guard !enabled || canFollowMembers(session) else {
         error = "Create a community profile to follow people."
         return false
     }
     guard !blocked.contains(target), changingFollows.insert(target).inserted else { return false }
     let accountRevision = connectionAccountRevision
     defer {
         if connectionAccountRevision == accountRevision { changingFollows.remove(target) }
     }
     error = nil
     let relation = SocialRelation(ownerID: owner, targetID: target)
     do {
         if enabled {
             try await session.client.from("liya_follows").insert(relation).execute()
         } else {
             try await session.client.from("liya_follows").delete()
                 .eq("owner_id", value: owner.uuidString).eq("target_id", value: target.uuidString).execute()
         }
     } catch { /* A retry can encounter a follow that was already committed. */ }
     do {
         guard session.userID == owner, connectionAccountRevision == accountRevision else { return false }
         let row: [FollowMember] = try await session.client.from("liya_follows")
             .select("member:liya_people!liya_follows_target_id_fkey!inner(id,display_name,signature,avatar_path)")
             .eq("owner_id", value: owner.uuidString).eq("target_id", value: target.uuidString).limit(1).execute().value
         guard session.userID == owner, connectionAccountRevision == accountRevision else { return false }
         guard (row.first?.member.id == target) == enabled, !blocked.contains(target) else { throw OfflineError.unavailable }
         // A read that started before this write must not reinstate the old snapshot.
         invalidateConnectionRead()
         follows.removeAll { $0 == target }
         if let member = row.first?.member {
             connectionPeople[target] = member
             follows.append(target)
         }
         if !connectionsReady || connectionsError != nil { await refreshConnections(session) }
         return session.userID == owner && connectionAccountRevision == accountRevision
     } catch {
         if session.userID == owner, connectionAccountRevision == accountRevision {
             self.error = enabled ? "Couldn't follow this member. Please try again." : "Couldn't unfollow this member. Please try again."
         }
         return false
     }
 }
 func blockMediaCommenter(_ session: LiyaSession, ownerID: UUID) async -> Bool {
     await setCommenterBlock(session, target: ownerID, enabled: true)
 }
 private func setCommenterBlock(_ session: LiyaSession, target: UUID, enabled: Bool) async -> Bool {
     guard let owner = session.userID, owner != target else { return false }
     selectConnectionAccount(owner)
     let accountRevision = connectionAccountRevision
     error = nil
     let relation = SocialRelation(ownerID: owner, targetID: target)
     do {
         if enabled {
             try await session.client.from("liya_blocks").insert(relation).execute()
         } else {
             try await session.client.from("liya_blocks").delete().eq("owner_id", value: owner.uuidString).eq("target_id", value: target.uuidString).execute()
         }
     } catch { /* Verify the requested state below, including a duplicate block. */ }
     do {
         let rows: [SocialRelation] = try await session.client.from("liya_blocks").select("owner_id,target_id")
             .eq("owner_id", value: owner.uuidString).eq("target_id", value: target.uuidString).limit(1).execute().value
         guard session.userID == owner, connectionAccountRevision == accountRevision else { return false }
         guard (!rows.isEmpty) == enabled else { throw OfflineError.unavailable }
         visibilityRevision = UUID()
         invalidateConnectionRead()
         blocked.removeAll { $0 == target }
         if enabled {
             blocked.append(target)
             follows.removeAll { $0 == target }
             followers.removeAll { $0 == target }
             connectionPeople.removeValue(forKey: target)
             commentAuthors.removeValue(forKey: target)
         }
         syncGeneration = UUID()
         await refresh(session)
         guard session.userID == owner else { return false }
         await session.refreshMediaEngagement(ids: (session.photos + session.videos).map(\.id))
         return session.userID == owner
     } catch {
         if session.userID == owner, connectionAccountRevision == accountRevision {
             self.error = enabled ? "Couldn't block this member. Please try again." : "Couldn't unblock this member. Please try again."
         }
         return false
     }
 }
 func comments(_ session: LiyaSession, post: UUID) async throws -> [SocialComment] { throw OfflineError.unavailable }
 func videoComments(_ session: LiyaSession, mediaID: String) async throws -> [VideoComment] {
     guard let owner = session.userID else { throw OfflineError.unavailable }
     let revision = visibilityRevision
     let columns = commentColumns + ",author:liya_people!liya_video_comments_owner_id_fkey(id,display_name,signature,avatar_path)"
     var rows: [VideoComment] = []
     // A stable cursor keeps concurrent deletes on an earlier page from skipping replies.
     while true {
         try Task.checkCancellation()
         guard session.userID == owner, visibilityRevision == revision else { throw CancellationError() }
         var query = session.client.from("liya_video_comments").select(columns).eq("media_id", value: mediaID)
         if let cursor = rows.last?.id { query = query.gt("id", value: cursor.uuidString) }
         let page: [VideoComment] = try await query.order("id").limit(500).execute().value
         rows.append(contentsOf: page)
         if page.count < 500 { break }
     }
     guard session.userID == owner, visibilityRevision == revision else { throw CancellationError() }
     for row in rows {
         if let author = row.author, author.id == row.ownerID { commentAuthors[author.id] = author }
     }
     return rows.sorted {
         if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
         return $0.createdAt < $1.createdAt
     }
 }
 private func mediaComment(_ session: LiyaSession, id: UUID, mediaID: String) async throws -> VideoComment? {
     let rows: [VideoComment] = try await session.client.from("liya_video_comments")
         .select(commentColumns).eq("id", value: id.uuidString).eq("media_id", value: mediaID).limit(1).execute().value
     return rows.first
 }
 func sendVideoComment(_ session: LiyaSession, id: UUID, mediaID: String, body: String) async -> Bool {
     let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
     guard !text.isEmpty, text.count <= 2000, let owner = session.userID, canCommentOnMedia(session) else { return false }
     let value = VideoCommentInsert(id: id, mediaID: mediaID, ownerID: owner, body: text)
     do { try await session.client.from("liya_video_comments").insert(value).execute() } catch { }
     do {
         guard let saved = try await mediaComment(session, id: id, mediaID: mediaID),
               session.userID == owner, saved.ownerID == owner, saved.body == text else { return false }
         syncGeneration = UUID()
         await session.refreshMediaEngagement(ids: [mediaID])
         if session.userID == owner { await refreshModeration(session) }
         return session.userID == owner
     } catch { return false }
 }
 func deleteVideoComment(_ session: LiyaSession, id: UUID, mediaID: String) async -> Bool {
     guard let owner = session.userID else { return false }
     do {
         try await session.client.from("liya_video_comments").delete().eq("id", value: id.uuidString)
             .eq("owner_id", value: owner.uuidString).eq("media_id", value: mediaID).execute()
     } catch { }
     do {
         guard try await mediaComment(session, id: id, mediaID: mediaID) == nil, session.userID == owner else { return false }
         syncGeneration = UUID()
         await session.refreshMediaEngagement(ids: [mediaID])
         return session.userID == owner
     } catch { return false }
 }
 func reportVideoComment(_ session: LiyaSession, id: UUID, mediaID: String, commentID: UUID?, presetKey: String?, body: String, reason: String) async -> Bool {
     guard let owner = session.userID else { return false }
     let report = VideoCommentReport(id: id, reporterID: owner, mediaID: mediaID, commentID: commentID,
                                    presetKey: presetKey, bodySnapshot: body, reason: reason)
     do { try await session.client.from("liya_video_comment_reports").insert(report).execute() } catch { }
     do {
         let rows: [VideoCommentReport] = try await session.client.from("liya_video_comment_reports")
             .select("id,reporter_id,media_id,comment_id,preset_key,body_snapshot,reason")
             .eq("id", value: id.uuidString).eq("reporter_id", value: owner.uuidString).limit(1).execute().value
         return session.userID == owner && rows.first == report
     } catch { return false }
 }
 func sendComment(_ session: LiyaSession, id: UUID, post: UUID, body: String) async -> Bool { false }
 func deleteComment(_ session: LiyaSession, id: UUID) async -> Bool { false }
 func report(_ session: LiyaSession, id: UUID, target: UUID, post: UUID?, reason: String) async -> Bool {
     guard let owner = session.userID, session.hasSavedMemberSession, owner != target else { return false }
     let report = SocialReport(id: id, reporterID: owner, targetUser: target, postID: post, reason: reason)
     let table = "liya_social_reports"
     let columns = "id,reporter_id,target_user,post_id,reason"
     do {
         let saved: SocialReport = try await session.client.from(table)
             .insert(report).select(columns).single().execute().value
         return session.userID == owner && saved == report
     } catch {
         // An interrupted response or a retry can follow an already committed insert.
         guard session.userID == owner, !Task.isCancelled else { return false }
         let saved: [SocialReport]? = try? await session.client.from(table).select(columns)
             .eq("id", value: id.uuidString).eq("reporter_id", value: owner.uuidString)
             .limit(1).execute().value
         return session.userID == owner && saved?.first == report
     }
 }
 func reportComment(_ session: LiyaSession, id: UUID, comment: SocialComment, reason: String) async -> Bool { false }
 func reportMessage(_ session: LiyaSession, id: UUID, message: SocialMessage, reason: String) async -> Bool { false }
 func refreshMessages(_ session: LiyaSession) async { messagesReady = false; messageLoadError = "Messaging is unavailable right now." }
 func isMutualFollow(_ session: LiyaSession, target: UUID) async throws -> Bool { throw OfflineError.unavailable }
 func sendMessage(_ session: LiyaSession, id: UUID, target: UUID, body: String, attachments: [DraftAttachment]) async -> Bool { messageError = "Messaging is unavailable right now."; return false }
 func deleteMessage(_ session: LiyaSession, message: SocialMessage) async -> Bool { false }
 func watchMessages(_ session: LiyaSession) { }
 func refreshNotifications(_ session: LiyaSession) async { notifications = []; notificationsLoading = false }
 func markRead(_ session: LiyaSession, id: Int64) async { }
 func mediaURL(_ session: LiyaSession, path: String) async throws -> URL {
     guard let owner = session.userID else { throw OfflineError.unavailable }
     let url = try await session.client.storage.from("liya-user-media").createSignedURL(path: path, expiresIn: 300)
     guard owner == session.userID else { throw CancellationError() }
     return url
 }
 private enum OfflineError: Error { case unavailable }
}
