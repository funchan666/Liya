import Foundation
import Combine
import Supabase

@MainActor
final class LiyaSession: ObservableObject {
    @Published private(set) var isSigningIn = false
    @Published private(set) var isDeletingAccount = false
    @Published var deletionError: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var userID: UUID?
    @Published private(set) var photos: [LiyaMedia] = []
    @Published private(set) var videos: [LiyaMedia] = []
    @Published private(set) var catalogError: String?
    @Published private(set) var catalogLoading = false
    @Published private(set) var catalogGeneration = UUID()
    @Published private(set) var imageGeneration = UUID()
    @Published private(set) var coinBalance: Int64?
    @Published private(set) var walletError: String?
    @Published private(set) var walletLive = false
    @Published var welcomeGift: WelcomeGift?
    @Published private(set) var moodEntries: [CloudMood] = []
    @Published private(set) var moodError: String?
    @Published private(set) var moodLoading = false
    @Published private(set) var profile: CloudProfile?
    @Published private(set) var profileAvatarURL: URL?
    @Published private(set) var profileError: String?
    @Published private(set) var profileLoading = false
    @Published private(set) var likedMediaIDs: Set<String> = []
    @Published private(set) var likesLoading = false
    @Published private(set) var likesReady = false
    @Published private(set) var likesError: String?
    @Published private(set) var treeEntries: [TreeEntry] = []
    @Published private(set) var treeLoading = false
    @Published private(set) var treeError: String?
    private var walletTask: Task<Void, Never>?
    private var walletGeneration = UUID()
    private var walletWatchGeneration = UUID()
    private var profileGeneration = UUID()
    private var moodGeneration = UUID()
    private static let projectURL = URL(string: "https://hymfjhuglaqoftrcxfjx.supabase.co")!
    private static let publishableKey = "sb_publishable_taByCR_N24fMyWxw4aFUqw_eZMldttB"

    let client: SupabaseClient = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 900
        return SupabaseClient(
            supabaseURL: LiyaSession.projectURL,
            supabaseKey: LiyaSession.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
    }()

    func signIn() async -> Bool {
        guard !isSigningIn else { return false }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            // Never replace an existing anonymous account merely because refresh failed.
            let session: Session
            if client.auth.currentSession != nil {
                session = try await client.auth.session
            } else {
                guard !UserDefaults.standard.bool(forKey: "liya.hasSupabaseAccount") else {
                    throw SessionError.savedSessionUnavailable
                }
                session = try await client.auth.signInAnonymously()
            }
            UserDefaults.standard.set(true, forKey: "liya.hasSupabaseAccount")
            let response: BootstrapResponse = try await client.functions.invoke(
                "liya-bootstrap", options: FunctionInvokeOptions(body: [String: String]())
            )
            guard response.code == 0, response.data.isEmpty else {
                throw SessionError.invalidBootstrap
            }
            userID = session.user.id
            Task { await refreshCatalog() }
            Task { await refreshWallet() }
            Task { await refreshProfile() }
            Task { await refreshLikes() }
            startWalletUpdates(for: session.user.id)
            return true
        } catch SessionError.savedSessionUnavailable {
            errorMessage = "Your saved anonymous account is unavailable. Account recovery is not connected yet."
            return false
        } catch {
            errorMessage = "Couldn't connect to Liya. Check your connection and try again."
            return false
        }
    }

    func refreshCatalog() async {
        guard userID != nil, !catalogLoading else { return }
        catalogLoading = true
        catalogError = nil
        photos = []; videos = []; catalogGeneration = UUID(); imageGeneration = UUID()
        defer { catalogLoading = false }
        do {
            var rows: [LiyaMedia] = []
            var offset = 0
            while true {
                let page: [LiyaMedia] = try await client.from("liya_example_media")
                    .select("id,kind,sort_order,object_key")
                    .order("sort_order").order("id").range(from: offset, to: offset + 499).execute().value
                rows.append(contentsOf: page)
                if page.count < 500 { break }
                offset += 500
            }
            photos = rows.filter { $0.kind == "photo" }
            videos = rows.filter { $0.kind == "video" }
            catalogGeneration = UUID(); imageGeneration = UUID()
        } catch {
            catalogError = "Couldn't load the content. Please try again."
        }
    }

    func mediaURL(kind: String, index: Int) async throws -> URL {
        let media = kind == "photo" ? photos : videos
        guard media.indices.contains(index) else { throw SessionError.mediaUnavailable }
        return try await client.storage.from("liya-example-media")
            .createSignedURL(path: media[index].objectKey, expiresIn: 3600)
    }

    func resumeAccount() async {
        guard let owner = userID, !isDeletingAccount else { return }
        imageGeneration = UUID()
        startWalletUpdates(for: owner)
        await refreshProfile()
        await refreshWallet()
    }

    func deleteAccount() async -> Bool {
        guard let owner = userID, !isDeletingAccount else { return false }
        isDeletingAccount = true; deletionError = nil
        defer { isDeletingAccount = false }
        let key = "liya.deleteRequest.\(owner.uuidString.lowercased())"
        let requestID: UUID
        if let saved = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: saved) { requestID = id }
        else { requestID = UUID(); UserDefaults.standard.set(requestID.uuidString, forKey: key) }
        do {
            let token = try await client.auth.session.accessToken
            var request = URLRequest(url: Self.projectURL.appendingPathComponent("functions").appendingPathComponent("v1").appendingPathComponent("liya-delete-account"))
            request.httpMethod = "POST"; request.timeoutInterval = 90
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["request_id": requestID.uuidString])
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 120
            let connection = URLSession(configuration: config, delegate: DeleteRedirectGuard(), delegateQueue: nil)
            defer { connection.invalidateAndCancel() }
            let (data, reply) = try await connection.data(for: request)
            let result = try JSONDecoder().decode(DeletionResponse.self, from: data)
            guard let http = reply as? HTTPURLResponse, (200..<300).contains(http.statusCode), result.code == 0, result.data.status == "deleted" else { throw SessionError.deletionUnconfirmed }
            walletTask?.cancel(); walletTask = nil; walletGeneration = UUID(); walletWatchGeneration = UUID()
            userID = nil; coinBalance = nil; walletLive = false; welcomeGift = nil
            profile = nil; profileAvatarURL = nil; moodEntries = []; treeEntries = []; likedMediaIDs = []
            photos = []; videos = []; catalogGeneration = UUID(); imageGeneration = UUID()
            try? await client.auth.signOut(scope: .local)
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: "liya.hasSupabaseAccount")
            return true
        } catch {
            deletionError = "Deletion could not be confirmed. Keep this account on this device and retry; some cloud files may already have been removed."
            return false
        }
    }

    func refreshWallet() async {
        guard let owner = userID else { return }
        let generation = UUID()
        walletGeneration = generation
        do {
            let rows: [WalletState] = try await client.rpc("liya_claim_welcome").execute().value
            guard generation == walletGeneration, owner == userID else { return }
            guard let row = rows.first else { throw SessionError.walletUnavailable }
            coinBalance = row.balance
            walletError = nil
            if row.welcomePending && welcomeGift == nil { welcomeGift = WelcomeGift(coins: 600) }
        } catch {
            guard generation == walletGeneration, owner == userID else { return }
            coinBalance = nil
            walletError = "Couldn't load your coin balance. Please try again."
        }
    }

    func acknowledgeWelcome() async -> Bool {
        do {
            try await client.rpc("liya_acknowledge_welcome").execute()
            walletGeneration = UUID()
            welcomeGift = nil
            return true
        } catch {
            walletError = "Couldn't save this confirmation. Please try again."
            return false
        }
    }

    func refreshMoods() async {
        guard let owner = userID, !moodLoading else { return }
        let generation = UUID(); moodGeneration = generation
        moodLoading = true; moodError = nil; moodEntries = []
        defer { moodLoading = false }
        do {
            var rows: [CloudMood] = []
            var offset = 0
            while true {
                let page: [CloudMood] = try await client.from("liya_moods")
                    .select("owner_id,day,state,mood,note")
                    .eq("owner_id", value: owner.uuidString).eq("state", value: "saved")
                    .order("day", ascending: false).range(from: offset, to: offset + 499).execute().value
                rows.append(contentsOf: page)
                if page.count < 500 { break }
                offset += 500
            }
            guard userID == owner, moodGeneration == generation else { return }
            moodEntries = rows
        } catch {
            if userID == owner && moodGeneration == generation { moodError = "Couldn't load your journal. Please try again." }
        }
    }

    func saveMood(_ mood: String, note: String, date: Date) async -> Bool {
        guard let owner = userID else { moodError = "Connect your account to save."; return false }
        moodGeneration = UUID()
        let row = CloudMood(ownerID: owner, day: CloudMood.dayKey(date), state: "saved", mood: mood, note: note)
        do {
            let saved: [CloudMood] = try await client.from("liya_moods")
                .upsert(row, onConflict: "owner_id,day,state").execute().value
            guard userID == owner, let confirmed = saved.first,
                  confirmed.day == row.day, confirmed.mood == mood, confirmed.note == note else {
                throw SessionError.moodUnavailable
            }
            moodEntries.removeAll { $0.day == row.day }
            moodEntries.append(confirmed)
            moodEntries.sort { $0.day > $1.day }
            moodError = nil
            return true
        } catch {
            moodError = "Couldn't save your journal entry. Your draft is still on this device."
            return false
        }
    }

    func refreshProfile() async {
        guard let owner = userID, !profileLoading else { return }
        let generation = UUID(); profileGeneration = generation
        profileLoading = true
        profileError = nil
        defer { profileLoading = false }
        do {
            let value: CloudProfile = try await client.from("liya_profiles")
                .select("id,display_name,signature,tags,avatar_path")
                .eq("id", value: owner.uuidString).single().execute().value
            let url: URL?
            if let path = value.avatarPath {
                url = try await client.storage.from("liya-user-media").createSignedURL(path: path, expiresIn: 3600)
            } else { url = nil }
            guard userID == owner, profileGeneration == generation else { return }
            profile = value; profileAvatarURL = url
        } catch {
            if userID == owner && profileGeneration == generation { profileError = "Couldn't load your profile. Please try again." }
        }
    }

    func saveProfile(name: String, signature: String, tags: [String], avatar: DraftAttachment?) async -> Bool {
        guard let owner = userID, let current = profile else {
            profileError = "Load your account profile before saving."; return false
        }
        profileGeneration = UUID()
        do {
            var path = current.avatarPath
            if let avatar {
                let ext = DraftFiles.url(avatar).pathExtension.lowercased()
                let safeExtension = ext.isEmpty ? "jpg" : ext
                let newPath = "\(owner.uuidString.lowercased())/avatars/\(UUID().uuidString.lowercased()).\(safeExtension)"
                try await client.storage.from("liya-user-media").upload(newPath, fileURL: DraftFiles.url(avatar))
                path = newPath
            }
            let update = ProfileUpdate(displayName: name, signature: signature, tags: tags, avatarPath: path)
            let saved: CloudProfile = try await client.from("liya_profiles").update(update)
                .eq("id", value: owner.uuidString).select("id,display_name,signature,tags,avatar_path").single().execute().value
            guard userID == owner else { return false }
            profile = saved
            profileAvatarURL = nil
            profileError = nil
            if let path = saved.avatarPath {
                profileAvatarURL = try? await client.storage.from("liya-user-media").createSignedURL(path: path, expiresIn: 3600)
            }
            return true
        } catch {
            profileError = "Couldn't save your profile. Your selected photo remains on this device."
            return false
        }
    }

    func submitReport(id: UUID, index: Int, targetType: String, reason: String) async -> Bool {
        guard let owner = userID else { return false }
        let media = targetType == "video" ? videos : photos
        guard media.indices.contains(index) else { return false }
        let report = ContentReport(id: id, reporterID: owner, mediaID: media[index].id, targetType: targetType, reason: reason)
        do { try await client.from("liya_content_reports").insert(report).execute() }
        catch { /* The insert may have succeeded before the connection failed; read it back. */ }
        do {
            let rows: [ContentReport] = try await client.from("liya_content_reports")
                .select("id,reporter_id,media_id,target_type,reason").eq("id", value: id.uuidString).execute().value
            return userID == owner && rows.first == report
        } catch { return false }
    }

    func refreshLikes() async {
        guard let owner = userID, !likesLoading else { return }
        likesLoading = true; likesReady = false; likesError = nil; likedMediaIDs = []
        defer { likesLoading = false }
        do {
            var rows: [MediaLike] = []
            var offset = 0
            while true {
                let page: [MediaLike] = try await client.from("liya_media_likes")
                    .select("owner_id,media_id").eq("owner_id", value: owner.uuidString)
                    .order("media_id").range(from: offset, to: offset + 499).execute().value
                rows.append(contentsOf: page)
                if page.count < 500 { break }
                offset += 500
            }
            guard userID == owner else { return }
            likedMediaIDs = Set(rows.map(\.mediaID)); likesReady = true
        } catch {
            if userID == owner { likesError = "Couldn't load your likes. Please try again." }
        }
    }

    func toggleLike(kind: String, index: Int) async {
        guard let owner = userID, likesReady, !likesLoading else { return }
        let media = kind == "photo" ? photos : videos
        guard media.indices.contains(index) else { return }
        let id = media[index].id
        let shouldLike = !likedMediaIDs.contains(id)
        likesLoading = true; likesError = nil
        do {
            if shouldLike {
                try await client.from("liya_media_likes").insert(MediaLike(ownerID: owner, mediaID: id)).execute()
            } else {
                try await client.from("liya_media_likes").delete().eq("owner_id", value: owner.uuidString).eq("media_id", value: id).execute()
            }
        } catch { /* Read back below to resolve an uncertain request. */ }
        likesLoading = false
        await refreshLikes()
        if likesReady && likedMediaIDs.contains(id) != shouldLike {
            likesError = "Couldn't update this like. Please try again."
        }
    }

    func isLiked(kind: String, index: Int) -> Bool {
        let media = kind == "photo" ? photos : videos
        return media.indices.contains(index) && likedMediaIDs.contains(media[index].id)
    }

    func refreshTreeEntries() async {
        guard let owner = userID, !treeLoading else { return }
        treeLoading = true; treeError = nil; treeEntries = []
        defer { treeLoading = false }
        do {
            var rows: [TreeEntry] = []
            var offset = 0
            while true {
                let page: [TreeEntry] = try await client.from("liya_tree_entries")
                    .select("id,owner_id,mood,body").eq("owner_id", value: owner.uuidString)
                    .order("created_at", ascending: false).order("id").range(from: offset, to: offset + 499).execute().value
                rows.append(contentsOf: page)
                if page.count < 500 { break }
                offset += 500
            }
            guard owner == userID else { return }
            treeEntries = rows
        } catch { if owner == userID { treeError = "Couldn't load your private thoughts. Please try again." } }
    }

    func saveTreeEntry(id: UUID, mood: String, body: String) async -> Bool {
        guard let owner = userID else { return false }
        let row = TreeEntry(id: id, ownerID: owner, mood: mood, body: body)
        do { try await client.from("liya_tree_entries").insert(row).execute() }
        catch { /* A prior attempt may already have reached the server. */ }
        do {
            let rows: [TreeEntry] = try await client.from("liya_tree_entries")
                .select("id,owner_id,mood,body").eq("id", value: id.uuidString).execute().value
            guard owner == userID, rows.first == row else { throw SessionError.treeUnavailable }
            await refreshTreeEntries()
            return true
        } catch { treeError = "Couldn't confirm saving. Your words remain on this device."; return false }
    }

    func deleteTreeEntry(_ id: UUID) async {
        guard let owner = userID else { return }
        do {
            try await client.from("liya_tree_entries").delete().eq("id", value: id.uuidString)
                .eq("owner_id", value: owner.uuidString).execute()
            await refreshTreeEntries()
            if treeError == nil && treeEntries.contains(where: { $0.id == id }) { treeError = "Couldn't delete this thought." }
        } catch { treeError = "Couldn't delete this thought. Please try again." }
    }

    private func startWalletUpdates(for owner: UUID) {
        walletTask?.cancel()
        walletLive = false
        let watchGeneration = UUID()
        walletWatchGeneration = watchGeneration
        let client = client
        let channel = client.channel("liya-wallet-\(owner.uuidString.lowercased())-\(watchGeneration.uuidString.lowercased())")
        let changes = channel.postgresChange(
            AnyAction.self, schema: "public", table: "liya_wallets",
            filter: .eq("owner_id", value: owner.uuidString.lowercased())
        )
        walletTask = Task { [weak self] in
            do {
                try await channel.subscribeWithError()
                guard !Task.isCancelled else { await client.removeChannel(channel); return }
                if self?.walletWatchGeneration == watchGeneration { self?.walletLive = true }
                await self?.refreshWallet()
                for await _ in changes {
                    if Task.isCancelled { break }
                    await self?.refreshWallet()
                }
            } catch {
                if self?.walletWatchGeneration == watchGeneration {
                    self?.walletLive = false
                    await self?.refreshWallet()
                }
            }
            if self?.walletWatchGeneration == watchGeneration { self?.walletLive = false }
            await client.removeChannel(channel)
        }
    }
}

struct LiyaMedia: Decodable, Identifiable {
    let id: String
    let kind: String
    let sortOrder: Int
    let objectKey: String
    enum CodingKeys: String, CodingKey {
        case id, kind
        case sortOrder = "sort_order", objectKey = "object_key"
    }
}

struct WelcomeGift: Identifiable {
    let id = UUID()
    let coins: Int
}

struct CloudMood: Codable, Identifiable, Equatable {
    let ownerID: UUID
    let day: String
    let state: String
    let mood: String
    let note: String
    var id: String { day }
    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case day, state, mood, note
    }
    static func dayKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

struct CloudProfile: Decodable {
    let id: UUID
    let displayName: String
    let signature: String
    let tags: [String]
    let avatarPath: String?
    enum CodingKeys: String, CodingKey {
        case id, signature, tags
        case displayName = "display_name", avatarPath = "avatar_path"
    }
}

private struct ProfileUpdate: Encodable {
    let displayName: String
    let signature: String
    let tags: [String]
    let avatarPath: String?
    enum CodingKeys: String, CodingKey {
        case signature, tags
        case displayName = "display_name", avatarPath = "avatar_path"
    }
}

private struct ContentReport: Codable, Equatable {
    let id: UUID
    let reporterID: UUID
    let mediaID: String
    let targetType: String
    let reason: String
    enum CodingKeys: String, CodingKey {
        case id, reason
        case reporterID = "reporter_id", mediaID = "media_id", targetType = "target_type"
    }
}

private struct MediaLike: Codable {
    let ownerID: UUID
    let mediaID: String
    enum CodingKeys: String, CodingKey { case ownerID = "owner_id", mediaID = "media_id" }
}

struct TreeEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let ownerID: UUID
    let mood: String
    let body: String
    enum CodingKeys: String, CodingKey { case id, mood, body; case ownerID = "owner_id" }
}

private struct WalletState: Decodable {
    let balance: Int64
    let welcomePending: Bool
    enum CodingKeys: String, CodingKey { case balance; case welcomePending = "welcome_pending" }
}

private enum SessionError: Error { case invalidBootstrap, savedSessionUnavailable, mediaUnavailable, walletUnavailable, moodUnavailable, treeUnavailable, deletionUnconfirmed }

private struct DeletionResponse: Decodable {
    struct Result: Decodable { let status: String }
    let code: Int
    let data: Result
}

private final class DeleteRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct BootstrapResponse: Decodable {
    let code: Int
    let message: String
    let data: EmptyObject
}

private struct EmptyObject: Decodable {
    let isEmpty: Bool
    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }
    init(from decoder: Decoder) throws {
        isEmpty = try decoder.container(keyedBy: Key.self).allKeys.isEmpty
    }
}
