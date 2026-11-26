import Foundation
import Combine
import Supabase

@MainActor
final class LiyaSession: ObservableObject {
    @Published private(set) var isSigningIn = false
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var isSigningOut = false
    @Published var signOutError: String?
    @Published var welcomeNotice: String?
    @Published private(set) var showAppleRevocationHelp = false
    @Published var deletionError: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var authNotice: String?
    @Published private(set) var emailConfirmationID: UUID?
    @Published var passwordRecovery = false
    @Published private(set) var userID: UUID? {
        didSet {
            guard userID != oldValue else { return }
            moodGeneration = UUID()
            moodLoading = false
            moodEntries = []
            moodError = nil
            catalogRequest = nil
            catalogLoading = false
            catalogHasLoaded = false
            catalogError = nil
            photos = []; videos = []; curatedVideoCreators = [:]; curatedTreePrompts = []
            resetMediaEngagement()
            resetCuratedFollows()
        }
    }
    @Published private(set) var photos: [CatalogMediaAsset] = []
    @Published private(set) var videos: [CatalogMediaAsset] = []
    @Published private(set) var curatedVideoCreators: [String: CollectionVideoAuthor] = [:]
    @Published private(set) var curatedTreePrompts: [ReflectionPrompt] = []
    @Published private(set) var catalogError: String?
    @Published private(set) var catalogLoading = false
    private var catalogHasLoaded = false
    private var catalogRequest: UUID?
    @Published private(set) var catalogGeneration = UUID()
    @Published private(set) var imageGeneration = UUID()
    @Published private(set) var moodEntries: [JournalDayEntry] = []
    @Published private(set) var moodError: String?
    @Published private(set) var moodLoading = false
    @Published private(set) var profile: CloudProfile?
    @Published private(set) var profileAvatarURL: URL?
    @Published private(set) var profileError: String?
    @Published private(set) var profileLoading = false
    @Published private(set) var likedMediaIDs: Set<String> = []
    @Published private(set) var mediaEngagement: [String: MediaEngagement] = [:]
    @Published private(set) var mediaEngagementFailures: Set<String> = []
    private var engagementRequests: [String: UUID] = [:]
    private var threadCountsDuringRefresh: [String: Int] = [:]
    @Published private(set) var likesLoading = false
    @Published private(set) var likesReady = false
    @Published private(set) var likesError: String?
    @Published private(set) var curatedFollowsReady = false
    @Published private(set) var curatedFollowsLoading = false
    @Published private(set) var curatedFollowsError: String?
    @Published private(set) var curatedFollowPending: Set<String> = []
    @Published private var curatedFollowIDs: Set<String> = []
    private var curatedFollowRefresh: Task<Void, Never>?
    private var curatedFollowGeneration = UUID()
    @Published private(set) var treeEntries: [TreeEntry] = []
    @Published private(set) var treeLoading = false
    @Published private(set) var treeError: String?
    private var profileGeneration = UUID()
    private var moodGeneration = UUID()
    private var accountGeneration = UUID()
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
                auth: .init(emitLocalSessionAsInitialSession: true),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
    }()

    var isGuest: Bool { client.auth.currentUser?.isAnonymous ?? true }
    var hasSavedMemberSession: Bool { client.auth.currentSession?.user.isAnonymous == false }
    private var savedMember: User? {
        guard let user = client.auth.currentSession?.user, !user.isAnonymous,
              userID == nil || userID == user.id else { return nil }
        return user
    }
    private var savedEmail: String? {
        guard let user = savedMember, user.emailConfirmedAt != nil,
              let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return nil }
        return email
    }

    func matchesSavedEmail(_ email: String) -> Bool {
        guard let savedEmail else { return false }
        return savedEmail.caseInsensitiveCompare(email.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    func matchesSavedApple(_ subject: String) -> Bool {
        guard !subject.isEmpty, let user = savedMember, let identities = user.identities else { return false }
        return identities.contains { identity in
            guard identity.provider == "apple", identity.userId == user.id else { return false }
            return (identity.identityData?["sub"]?.stringValue ?? identity.id) == subject
        }
    }

    var savedAccountLabel: String? {
        guard let user = client.auth.currentSession?.user, !user.isAnonymous else { return nil }
        if let savedEmail { return savedEmail }
        if let profile, profile.id == user.id {
            let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        let language = UserDefaults.standard.string(forKey: "liya.language") ?? "en"
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return String(localized: "Saved account", bundle: bundle, locale: Locale(identifier: language))
    }
    private static let confirmationURL = URL(string: "com.liyalumora.auroramuse://auth/confirm")!
    private static let recoveryURL = URL(string: "com.liyalumora.auroramuse://auth/recovery")!

    func clearAuthFeedback() { errorMessage = nil; authNotice = nil }
    func appleAuthorizationFailed() { errorMessage = "Couldn't sign in with Apple. Please try again." }

    private func canBeginAlternateSignIn(matchingSavedIdentity: Bool = false) -> Bool {
        guard !isSigningOut, !isDeletingAccount, !passwordRecovery,
              (userID == nil && !hasSavedMemberSession) || matchingSavedIdentity else {
            errorMessage = "An existing account is still on this device. Reconnect to it before changing accounts."
            return false
        }
        return true
    }

    func emailSignIn(email: String, password: String) async -> Bool {
        guard !isSigningIn else { return false }
        clearAuthFeedback()
        guard canBeginAlternateSignIn(matchingSavedIdentity: matchesSavedEmail(email)) else { return false }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            return try await authenticate { auth in
                try await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            }
        } catch {
            errorMessage = "Couldn't sign in. Check your email and password, and make sure your email is confirmed."
            return false
        }
    }

    func emailSignUp(email: String, password: String) async -> Bool {
        guard !isSigningIn else { return false }
        clearAuthFeedback()
        guard canBeginAlternateSignIn() else { return false }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let result = try await client.auth.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, redirectTo: Self.confirmationURL)
            if result.session != nil { return await activateSignedInAccount() }
            authNotice = "Check your inbox for a confirmation link, then return to Liya."
            return false
        } catch {
            errorMessage = "Couldn't create your account. Check your details and try again."
            return false
        }
    }

    func appleSignIn(token: String, nonce: String, subject: String) async -> Bool {
        guard !isSigningIn else { return false }
        clearAuthFeedback()
        guard canBeginAlternateSignIn(matchingSavedIdentity: matchesSavedApple(subject)) else { return false }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            return try await authenticate { auth in
                try await auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
            }
        } catch {
            errorMessage = "Couldn't sign in with Apple. Please try again."
            return false
        }
    }

    private func authenticate(_ signIn: (AuthClient) async throws -> Session) async throws -> Bool {
        if let owner = savedMember?.id {
            let probe = SupabaseClient(supabaseURL: Self.projectURL, supabaseKey: Self.publishableKey,
                options: .init(auth: .init(storage: TemporaryAuthStorage(), autoRefreshToken: false,
                                          emitLocalSessionAsInitialSession: true)))
            let verified = try await signIn(probe.auth)
            guard verified.user.id == owner, !verified.user.isAnonymous else {
                try? await probe.auth.signOut(scope: .local)
                throw SessionError.savedSessionUnavailable
            }
            _ = try await client.auth.setSession(accessToken: verified.accessToken, refreshToken: verified.refreshToken)
        } else {
            _ = try await signIn(client.auth)
        }
        return await activateSignedInAccount()
    }

    func sendPasswordReset(email: String) async {
        guard !isSigningIn else { return }
        clearAuthFeedback()
        guard canBeginAlternateSignIn() else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await client.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespacesAndNewlines), redirectTo: Self.recoveryURL)
            authNotice = "If an account exists for this email, a reset link is on its way."
        } catch { errorMessage = "Couldn't send a reset link. Please try again." }
    }

    func handleAuthURL(_ url: URL) async -> Bool {
        guard url.scheme == "com.liyalumora.auroramuse", url.host == "auth",
              ["/confirm", "/recovery"].contains(url.path), !isSigningIn else { return false }
        guard canBeginAlternateSignIn() else { return false }
        isSigningIn = true; clearAuthFeedback()
        defer { isSigningIn = false }
        do {
            if url.path == "/recovery" { UserDefaults.standard.set(true, forKey: "liya.pendingPasswordRecovery") }
            _ = try await client.auth.session(from: url)
            if url.path == "/recovery" {
                passwordRecovery = true
                return false
            }
            guard await activateSignedInAccount() else { return false }
            emailConfirmationID = UUID()
            return true
        } catch {
            if url.path == "/recovery" { UserDefaults.standard.removeObject(forKey: "liya.pendingPasswordRecovery") }
            errorMessage = "This link is invalid or has expired. Please request a new one on this device."
            return false
        }
    }

    func updatePassword(_ password: String) async -> Bool {
        guard passwordRecovery, !isSigningIn else { return false }
        isSigningIn = true; clearAuthFeedback()
        defer { isSigningIn = false }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
            UserDefaults.standard.removeObject(forKey: "liya.pendingPasswordRecovery")
            passwordRecovery = false
            return await activateSignedInAccount()
        } catch {
            errorMessage = "Couldn't update your password. Please try again."
            return false
        }
    }

    func cancelPasswordRecovery() async -> Bool {
        guard passwordRecovery, !isSigningIn else { return false }
        isSigningIn = true
        defer { isSigningIn = false }
        try? await client.auth.signOut(scope: .local)
        guard client.auth.currentSession == nil else {
            errorMessage = "Couldn't close password recovery. Please try again."
            return false
        }
        UserDefaults.standard.removeObject(forKey: "liya.pendingPasswordRecovery")
        passwordRecovery = false
        clearAuthFeedback()
        return true
    }

    private func activateSignedInAccount() async -> Bool {
        let generation = accountGeneration
        do {
            let current = try await client.auth.session
            guard !current.user.isAnonymous else { throw SessionError.savedSessionUnavailable }
            UserDefaults.standard.set(true, forKey: "liya.hasSupabaseAccount")
            let response: BootstrapResponse = try await client.functions.invoke(
                "liya-bootstrap", options: FunctionInvokeOptions(body: [String: String]())
            )
            guard generation == accountGeneration, response.code == 0, response.data.isEmpty else { throw SessionError.invalidBootstrap }
            userID = current.user.id
            welcomeNotice = nil
            showAppleRevocationHelp = false
            Task { await refreshCatalog() }
            Task { await refreshProfile() }
            Task { await refreshLikes() }
            return true
        } catch {
            errorMessage = "Your account is signed in, but Liya couldn't finish connecting. Please try again."
            return false
        }
    }

    func prepareWelcome(store: LocalStore) {
        store.identifyPreviousCloudSpace(savedMember?.id)
        guard !isSigningIn else { return }
        inspectSavedCredential()
    }

    @discardableResult
    private func inspectSavedCredential() -> Session? {
        if UserDefaults.standard.bool(forKey: "liya.pendingPasswordRecovery") {
            if client.auth.currentSession != nil {
                passwordRecovery = true
                return nil
            }
            passwordRecovery = false
            UserDefaults.standard.removeObject(forKey: "liya.pendingPasswordRecovery")
        }
        guard let saved = client.auth.currentSession, !saved.user.isAnonymous else {
            if userID != nil || UserDefaults.standard.bool(forKey: "liya.hasSupabaseAccount") {
                showExpiredSession()
            }
            return nil
        }
        return saved
    }

    func restoreSavedAccount() async -> Bool {
        guard !isSigningIn, !isSigningOut, !isDeletingAccount, let saved = inspectSavedCredential() else { return false }
        if userID == saved.user.id, !saved.isExpired { return true }
        return await connectAccount()
    }

    private func showExpiredSession() {
        userID = nil
        UserDefaults.standard.removeObject(forKey: "liya.hasSupabaseAccount")
        errorMessage = "Your session has expired. Please sign in again."
    }

    private func connectAccount() async -> Bool {
        guard !isSigningIn else { return false }
        isSigningIn = true
        let generation = accountGeneration
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            guard client.auth.currentSession != nil else { throw SessionError.savedSessionUnavailable }
            let session = try await client.auth.session
            guard !session.user.isAnonymous else { throw SessionError.savedSessionUnavailable }
            guard generation == accountGeneration else { return false }
            UserDefaults.standard.set(true, forKey: "liya.hasSupabaseAccount")
            let response: BootstrapResponse = try await client.functions.invoke(
                "liya-bootstrap", options: FunctionInvokeOptions(body: [String: String]())
            )
            guard response.code == 0, response.data.isEmpty else {
                throw SessionError.invalidBootstrap
            }
            guard generation == accountGeneration else { return false }
            userID = session.user.id
            welcomeNotice = nil
            showAppleRevocationHelp = false
            Task { await refreshCatalog() }
            Task { await refreshProfile() }
            Task { await refreshLikes() }
            return true
        } catch {
            guard generation == accountGeneration else { return false }
            if hasSavedMemberSession {
                errorMessage = "Please check your connection and try again."
            } else {
                showExpiredSession()
            }
            return false
        }
    }

    func refreshCatalog() async {
        guard let owner = userID, !catalogLoading else { return }
        let request = UUID()
        catalogRequest = request
        catalogLoading = true
        catalogError = nil
        defer {
            if catalogRequest == request {
                catalogLoading = false
                catalogRequest = nil
            }
        }
        do {
            var rows: [CatalogMediaAsset] = []
            var offset = 0
            while true {
                let page: [CatalogMediaAsset] = try await client.from("liya_example_media")
                    .select("id,kind,sort_order,object_key,portrait_byline")
                    .order("sort_order").order("id").range(from: offset, to: offset + 499).execute().value
                rows.append(contentsOf: page)
                if page.count < 500 { break }
                offset += 500
            }
            let creators: [CollectionVideoAuthor] = try await client.from("liya_curated_video_creators")
                .select("video_id,photo_id,display_name,caption").order("video_id").execute().value
            let treePrompts: [ReflectionPrompt] = try await client.from("liya_curated_tree_prompts")
                .select("position,mood,body").order("position").execute().value
            guard userID == owner, catalogRequest == request else { return }
            photos = rows.filter { $0.mediaKind == "photo" }
            videos = rows.filter { $0.mediaKind == "video" }
            curatedVideoCreators = Dictionary(uniqueKeysWithValues: creators.map { ($0.videoID, $0) })
            curatedTreePrompts = treePrompts
            catalogHasLoaded = true
            catalogGeneration = UUID(); imageGeneration = UUID()
            let ids = rows.map(\.id)
            Task {
                guard userID == owner else { return }
                await refreshMediaEngagement(ids: ids)
            }
        } catch {
            if userID == owner, catalogRequest == request { catalogError = "Couldn't load the content. Please try again." }
        }
    }

    func mediaURL(kind: String, index: Int) async throws -> URL {
        let media = kind == "photo" ? photos : videos
        guard media.indices.contains(index) else { throw SessionError.mediaUnavailable }
        return try await client.storage.from("liya-example-media")
            .createSignedURL(path: media[index].storageObjectPath, expiresIn: 3600)
    }

    func resumeAccount() async {
        guard userID != nil, !isDeletingAccount, !isSigningOut else { return }
        imageGeneration = UUID()
        await refreshProfile()
    }

    func deleteAccount() async -> Bool {
        guard let owner = userID, !isDeletingAccount, !isSigningOut, !isSigningIn else { return false }
        isDeletingAccount = true; deletionError = nil
        accountGeneration = UUID()
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
            userID = nil
            profile = nil; profileAvatarURL = nil; moodEntries = []; treeEntries = []
            photos = []; videos = []; curatedVideoCreators = [:]; curatedTreePrompts = []
            catalogGeneration = UUID(); imageGeneration = UUID()
            try? await client.auth.signOut(scope: .local)
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: "liya.hasSupabaseAccount")
            welcomeNotice = "Your account has been deleted. You can start again whenever you're ready."
            showAppleRevocationHelp = true
            return true
        } catch {
            deletionError = "Deletion could not be confirmed. Please retry before signing out; some uploaded files may already have been removed."
            return false
        }
    }

    func signOutForAccountChange(store: LocalStore, social: SocialStore, calls: LiyaCalls) async -> Bool {
        guard !isSigningOut, !isSigningIn, !isDeletingAccount, !passwordRecovery else {
            signOutError = "Please wait…"
            return false
        }
        guard let owner = userID ?? client.auth.currentSession?.user.id else {
            signOutError = "Your session has expired. Please sign in again."
            return false
        }
        signOutError = nil
        isSigningOut = true
        defer { isSigningOut = false }
        accountGeneration = UUID()
        var serverConfirmed = client.auth.currentSession != nil
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            guard client.auth.currentSession == nil else {
                signOutError = "Couldn't sign out. Please check your connection and try again."
                return false
            }
            serverConfirmed = false
        }
        userID = nil
        profile = nil; profileAvatarURL = nil; moodEntries = []; treeEntries = []
        photos = []; videos = []; curatedVideoCreators = [:]; curatedTreePrompts = []
        catalogGeneration = UUID(); imageGeneration = UUID()
        likesReady = false; likesError = nil
        clearAuthFeedback()
        showAppleRevocationHelp = false
        UserDefaults.standard.removeObject(forKey: "liya.hasSupabaseAccount")
        welcomeNotice = serverConfirmed ? "You are signed out. Sign in whenever you're ready." : "Signed out on this device. The server could not confirm sign-out."
        store.archiveCloudSpace(leaving: owner)
        store.inPreview = false
        social.clearAccount()
        calls.reset()
        return true
    }

    func refreshMoods() async {
        guard let owner = userID, !moodLoading else { return }
        let generation = UUID(); moodGeneration = generation
        moodLoading = true; moodError = nil
        defer { if moodGeneration == generation { moodLoading = false } }
        do {
            var rows: [JournalDayEntry] = []
            var beforeDay: String?
            while true {
                var query = client.from("liya_moods").select("owner_id,day,state,mood,note")
                    .eq("owner_id", value: owner.uuidString).eq("state", value: "saved")
                if let beforeDay { query = query.lt("day", value: beforeDay) }
                let page: [JournalDayEntry] = try await query.order("day", ascending: false)
                    .limit(500).execute().value
                rows.append(contentsOf: page)
                guard page.count == 500, let oldest = page.last else { break }
                beforeDay = oldest.dayStamp
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
        moodLoading = false
        let row = JournalDayEntry(journalOwnerID: owner, dayStamp: JournalDayEntry.dayKey(date), entryStatus: "saved", feelingKey: mood, reflectionText: note)
        do {
            let saved: [JournalDayEntry] = try await client.from("liya_moods")
                .upsert(row, onConflict: "owner_id,day,state").execute().value
            guard userID == owner, let confirmed = saved.first,
                  confirmed.dayStamp == row.dayStamp, confirmed.feelingKey == mood, confirmed.reflectionText == note else {
                throw SessionError.moodUnavailable
            }
            moodEntries.removeAll { $0.dayStamp == row.dayStamp }
            moodEntries.append(confirmed)
            moodEntries.sort { $0.dayStamp > $1.dayStamp }
            moodError = nil
            return true
        } catch {
            guard userID == owner else { return false }
            moodError = "Couldn't save your journal entry. Your draft is still available; please try again."
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
            profileError = "Couldn't save your profile. Please try again."
            return false
        }
    }

    func submitReport(id: UUID, index: Int, targetType: String, reason: String) async -> Bool {
        guard let owner = userID else { return false }
        let media = targetType == "video" ? videos : photos
        guard media.indices.contains(index) else { return false }
        let report = ContentReport(id: id, reporterID: owner, mediaID: media[index].id, targetType: targetType, reason: reason)
        do { try await client.from("liya_content_reports").insert(report).execute() }
        catch {}
        do {
            let rows: [ContentReport] = try await client.from("liya_content_reports")
                .select("id,reporter_id,media_id,target_type,reason").eq("id", value: id.uuidString).execute().value
            return userID == owner && rows.first == report
        } catch { return false }
    }

    private func resetCuratedFollows() {
        curatedFollowGeneration = UUID()
        curatedFollowRefresh?.cancel()
        curatedFollowRefresh = nil
        curatedFollowIDs = []
        curatedFollowPending = []
        curatedFollowsReady = false
        curatedFollowsLoading = false
        curatedFollowsError = nil
    }

    func curatedCreator(for photoID: String) -> CollectionVideoAuthor? {
        curatedVideoCreators.values.filter { $0.photoID == photoID }.min { $0.videoID < $1.videoID }
    }

    func curatedDisplayName(for photoID: String) -> String {
        if let creator = curatedCreator(for: photoID) { return creator.name }
        guard let post = photos.firstIndex(where: { $0.id == photoID }),
              let portrait = CollectionPhotoRoles.portraitIndex(for: post, in: photos) else { return "Liya collection" }
        return photos[portrait].portraitByline ?? "Liya collection"
    }

    func curatedFollowing(in store: LocalStore) -> [CuratedFollowedProfile] {
        guard let owner = userID, store.hasCloudSpace(for: owner) else { return [] }
        let hidden = store.pendingCuratedUnfollows
        return photos.enumerated().compactMap { index, photo in
            guard curatedFollowIDs.contains(photo.id), !store.hiddenCollectionProfiles.contains(index),
                  !hidden.contains(photo.id) else { return nil }
            return CuratedFollowedProfile(id: photo.id, index: index, displayName: curatedDisplayName(for: photo.id))
        }
    }

    func isFollowingCurated(_ id: String, store: LocalStore) -> Bool {
        guard let owner = userID, store.hasCloudSpace(for: owner), curatedFollowIDs.contains(id),
              let index = photos.firstIndex(where: { $0.id == id }) else { return false }
        return !store.hiddenCollectionProfiles.contains(index) && !store.pendingCuratedUnfollows.contains(id)
    }

    func refreshCuratedFollows(store: LocalStore) async {
        guard let owner = userID, store.hasCloudSpace(for: owner), !isGuest else { return }
        if let task = curatedFollowRefresh { await task.value; return }
        guard curatedFollowPending.isEmpty else { return }
        let generation = curatedFollowGeneration
        curatedFollowsLoading = true
        curatedFollowsError = nil
        let task = Task {
            defer {
                if generation == curatedFollowGeneration {
                    curatedFollowsLoading = false
                    curatedFollowRefresh = nil
                }
            }
            if !catalogHasLoaded && !catalogLoading && catalogError == nil { await refreshCatalog() }
            guard catalogHasLoaded else {
                if generation == curatedFollowGeneration { curatedFollowsError = catalogError }
                return
            }
            await loadCuratedFollows(owner: owner, generation: generation, store: store)
        }
        curatedFollowRefresh = task
        await task.value
    }

    private func loadCuratedFollows(owner: UUID, generation: UUID, store: LocalStore) async {
        guard generation == curatedFollowGeneration, store.hasCloudSpace(for: owner) else { return }
        let catalog = Set(photos.map(\.id))
        let legacy = store.previousCollectionFollows.compactMap { index -> (Int, String)? in
            guard (0..<40).contains(index) else { return nil }
            let id = String(format: "example-photo-%03d", index + 1)
            return catalog.contains(id) ? (index, id) : nil
        }
        do {
            if !legacy.isEmpty {
                let rows = legacy.map { CuratedFollowWrite(owner_id: owner, media_id: $0.1, is_following: true) }
                try await client.from("liya_curated_follows")
                    .upsert(rows, onConflict: "owner_id,media_id", returning: .minimal, ignoreDuplicates: true).execute()
            }
            var ids: Set<String> = []
            var offset = 0
            while true {
                let page: [CuratedFollowKey] = try await client.from("liya_curated_follows")
                    .select("media_id").eq("owner_id", value: owner.uuidString).eq("is_following", value: true)
                    .order("media_id").range(from: offset, to: offset + 499).execute().value
                ids.formUnion(page.map(\.media_id))
                if page.count < 500 { break }
                offset += 500
            }
            guard generation == curatedFollowGeneration, store.hasCloudSpace(for: owner) else { return }
            let blocked = Set(store.hiddenCollectionProfiles.compactMap { photos.indices.contains($0) ? photos[$0].id : nil })
            let removals = ids.intersection(blocked).union(store.pendingCuratedUnfollows.intersection(catalog))
            if !removals.isEmpty {
                let rows = removals.map { CuratedFollowWrite(owner_id: owner, media_id: $0, is_following: false) }
                try await client.from("liya_curated_follows").upsert(rows, onConflict: "owner_id,media_id", returning: .minimal).execute()
            }
            guard generation == curatedFollowGeneration, store.hasCloudSpace(for: owner) else { return }
            store.finishFollowImport(Set(legacy.map { $0.0 }), owner: owner)
            store.finishBlockedUnfollows(removals, owner: owner)
            curatedFollowIDs = ids.subtracting(removals)
            curatedFollowsReady = true
        } catch {
            if generation == curatedFollowGeneration && store.hasCloudSpace(for: owner) {
                curatedFollowsError = "Couldn't refresh following. Please try again."
            }
        }
    }

    @discardableResult
    func setCuratedFollow(_ following: Bool, id: String, store: LocalStore) async -> Bool {
        guard let owner = userID, store.hasCloudSpace(for: owner), !isGuest else { return false }
        let generation = curatedFollowGeneration
        if !curatedFollowsReady || curatedFollowsLoading { await refreshCuratedFollows(store: store) }
        guard generation == curatedFollowGeneration, store.hasCloudSpace(for: owner),
              curatedFollowsReady, let index = photos.firstIndex(where: { $0.id == id }),
              !following || !store.hiddenCollectionProfiles.contains(index),
              curatedFollowPending.insert(id).inserted else { return false }
        defer {
            if generation == curatedFollowGeneration {
                curatedFollowPending.remove(id)
                if curatedFollowPending.isEmpty, !store.pendingCuratedUnfollows.isEmpty {
                    Task {
                        guard userID == owner, store.hasCloudSpace(for: owner) else { return }
                        await refreshCuratedFollows(store: store)
                    }
                }
            }
        }
        do {
            let row = CuratedFollowWrite(owner_id: owner, media_id: id, is_following: following)
            try await client.from("liya_curated_follows").upsert(row, onConflict: "owner_id,media_id", returning: .minimal).execute()
            guard generation == curatedFollowGeneration, store.hasCloudSpace(for: owner) else { return false }
            if following {
                curatedFollowIDs.insert(id)
                if !store.hiddenCollectionProfiles.contains(index) {
                    store.finishBlockedUnfollows([id], owner: owner)
                }
            } else {
                curatedFollowIDs.remove(id)
                store.finishBlockedUnfollows([id], owner: owner)
            }
            curatedFollowsError = nil
            return true
        } catch {
            if generation == curatedFollowGeneration && store.hasCloudSpace(for: owner) {
                curatedFollowsError = "Couldn't update your follow. Please try again."
            }
            return false
        }
    }

    private func resetMediaEngagement() {
        likedMediaIDs = []
        likesReady = false
        likesLoading = false
        likesError = nil
        engagementRequests = [:]
        threadCountsDuringRefresh = [:]
        mediaEngagement = [:]
        mediaEngagementFailures = []
    }

    func confirmVisibleMediaComments(_ count: Int, mediaID: String) {
        if engagementRequests[mediaID] != nil { threadCountsDuringRefresh[mediaID] = count }
        if let prior = mediaEngagement[mediaID], prior.commentCount != count {
            mediaEngagement[mediaID] = MediaEngagement(mediaID: mediaID, likeCount: prior.likeCount, commentCount: count)
        }
    }

    func refreshMediaEngagement(ids: [String]) async {
        guard let owner = userID, !ids.isEmpty else { return }
        let generation = accountGeneration
        let ids = Array(Set(ids))
        let request = UUID()
        for id in ids {
            engagementRequests[id] = request
            threadCountsDuringRefresh.removeValue(forKey: id)
        }
        defer {
            for id in ids where engagementRequests[id] == request {
                engagementRequests.removeValue(forKey: id)
                threadCountsDuringRefresh.removeValue(forKey: id)
            }
        }
        for start in stride(from: 0, to: ids.count, by: 150) {
            guard userID == owner, accountGeneration == generation else { return }
            let batch = Array(ids[start..<min(start + 150, ids.count)])
            let rows: [MediaEngagement]
            do {
                rows = try await client.rpc("liya_media_engagement", params: ["p_media_ids": batch]).execute().value
            } catch {
                if Task.isCancelled { return }
                rows = []
            }
            guard userID == owner, accountGeneration == generation else { return }
            let latest = batch.filter { engagementRequests[$0] == request }
            let received = Dictionary(uniqueKeysWithValues: rows.map { ($0.mediaID, $0) })
            let updates = received.filter { engagementRequests[$0.key] == request }.mapValues { update in
                MediaEngagement(mediaID: update.mediaID, likeCount: update.likeCount,
                                commentCount: threadCountsDuringRefresh[update.mediaID] ?? update.commentCount)
            }
            mediaEngagement.merge(updates) { _, latest in latest }
            let missing = latest.filter { received[$0] == nil }
            mediaEngagementFailures.subtract(updates.keys)
            mediaEngagementFailures.formUnion(missing)
        }
    }

    func refreshLikes() async {
        guard let owner = userID, !likesLoading else { return }
        let generation = accountGeneration
        likesLoading = true; likesError = nil
        defer { if userID == owner && accountGeneration == generation { likesLoading = false } }
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
            guard userID == owner, generation == accountGeneration else { return }
            likedMediaIDs = Set(rows.map(\.mediaID)); likesReady = true
        } catch {
            if userID == owner, generation == accountGeneration { likesError = "Couldn't load your likes. Please try again." }
        }
    }

    func toggleLike(kind: String, index: Int) async {
        let media = kind == "photo" ? photos : videos
        guard media.indices.contains(index) else { return }
        await toggleMediaLike(id: media[index].id)
    }

    func toggleMediaLike(id: String) async {
        guard let owner = userID, likesReady, !likesLoading else { return }
        let generation = accountGeneration
        let shouldLike = !likedMediaIDs.contains(id)
        likesLoading = true; likesError = nil
        defer { if userID == owner && generation == accountGeneration { likesLoading = false } }
        do {
            if shouldLike {
                try await client.from("liya_media_likes").insert(MediaLike(ownerID: owner, mediaID: id)).execute()
            } else {
                try await client.from("liya_media_likes").delete().eq("owner_id", value: owner.uuidString).eq("media_id", value: id).execute()
            }
        } catch {}
        guard userID == owner, generation == accountGeneration else { return }
        do {
            let rows: [MediaLike] = try await client.from("liya_media_likes").select("owner_id,media_id")
                .eq("owner_id", value: owner.uuidString).eq("media_id", value: id).execute().value
            guard userID == owner, generation == accountGeneration else { return }
            if rows.isEmpty { likedMediaIDs.remove(id) } else { likedMediaIDs.insert(id) }
            if likedMediaIDs.contains(id) != shouldLike { likesError = "Couldn't update this like. Please try again." }
        } catch {
            guard userID == owner, generation == accountGeneration else { return }
            likesError = "Couldn't update this like. Please try again."
        }
        await refreshMediaEngagement(ids: [id])
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
        catch {}
        do {
            let rows: [TreeEntry] = try await client.from("liya_tree_entries")
                .select("id,owner_id,mood,body").eq("id", value: id.uuidString).execute().value
            guard owner == userID, rows.first == row else { throw SessionError.treeUnavailable }
            await refreshTreeEntries()
            return true
        } catch { treeError = "Couldn't confirm saving. Your words are still here; please try again."; return false }
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


}

struct MediaEngagement: Decodable, Equatable {
    let mediaID: String
    let likeCount: Int
    let commentCount: Int
    enum CodingKeys: String, CodingKey {
        case mediaID = "media_id", likeCount = "like_count", commentCount = "comment_count"
    }
}

struct CatalogMediaAsset: Decodable, Identifiable {
    let id: String
    let mediaKind: String
    let storageObjectPath: String
    let portraitByline: String?
    enum CodingKeys: String, CodingKey {
        case id, mediaKind = "kind", storageObjectPath = "object_key", portraitByline = "portrait_byline"
    }
}

struct ReflectionPrompt: Decodable, Identifiable {
    let promptOrder: Int
    let feelingKey: String
    let writingPrompt: String
    var id: Int { promptOrder }
    enum CodingKeys: String, CodingKey {
        case promptOrder = "position", feelingKey = "mood", writingPrompt = "body"
    }
}

struct JournalDayEntry: Codable, Identifiable, Equatable {
    let journalOwnerID: UUID
    let dayStamp: String
    let entryStatus: String
    let feelingKey: String
    let reflectionText: String
    var id: String { dayStamp }

    enum CodingKeys: String, CodingKey {
        case journalOwnerID = "owner_id", dayStamp = "day", entryStatus = "state"
        case feelingKey = "mood", reflectionText = "note"
    }

    var recordedDate: Date? {
        let parts = dayStamp.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    var feelingName: String {
        switch feelingKey {
        case "mood-happy": return "Happy"
        case "mood-calm": return "Calm"
        case "mood-yellow": return "Thoughtful"
        case "mood-teal": return "Tired"
        case "mood-blue": return "Blue"
        case "mood-upset": return "Upset"
        default: return "Mood"
        }
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

private final class TemporaryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        lock.withLock { values[key] = nil }
    }
}

struct CuratedFollowedProfile: Identifiable {
    let id: String
    let index: Int
    let displayName: String
}

private struct CuratedFollowKey: Decodable {
    let media_id: String
}

private struct CuratedFollowWrite: Encodable {
    let owner_id: UUID
    let media_id: String
    let is_following: Bool
}

private enum SessionError: Error { case invalidBootstrap, savedSessionUnavailable, mediaUnavailable, moodUnavailable, treeUnavailable, deletionUnconfirmed }

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
