import Foundation
import Combine

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
 @Published var passwordRecovery = false
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
 private let defaults = UserDefaults.standard
 var isGuest: Bool { false }
 private var ownerKey: String { "liya.local.identity" }
 private func storageKey(_ name: String) -> String { "liya.local.\(userID?.uuidString ?? "none").\(name)" }
 private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
  defaults.data(forKey: storageKey(name)).flatMap { try? JSONDecoder().decode(type, from: $0) }
 }
 private func write<T: Encodable>(_ value: T, _ name: String) -> Bool {
  guard let data = try? JSONEncoder().encode(value) else { return false }
  defaults.set(data, forKey: storageKey(name)); return true
 }
 func clearAuthFeedback() { errorMessage = nil; authNotice = nil }
 func appleAuthorizationFailed() { errorMessage = "Apple sign-in is currently unavailable." }
 func emailSignIn(email: String, password: String) async -> Bool {
  guard !isSigningIn else { return false }
  let text = email.trimmingCharacters(in: .whitespacesAndNewlines)
  let pieces = text.split(separator: "@", omittingEmptySubsequences: false)
  guard pieces.count == 2, !pieces[0].isEmpty, pieces[1].contains("."), !pieces[1].hasPrefix("."), !pieces[1].hasSuffix("."), !text.contains(where: { $0.isWhitespace }), !password.isEmpty else {
   errorMessage = "Enter a valid email address and password."; return false
  }
  isSigningIn = true; defer { isSigningIn = false }
  let id = defaults.string(forKey: ownerKey).flatMap(UUID.init(uuidString:)) ?? UUID()
  defaults.set(id.uuidString, forKey: ownerKey); defaults.set(true, forKey: "liya.local.signedIn")
  userID = id; clearAuthFeedback(); welcomeNotice = nil
  await loadLocalData(); return true
 }
 func emailSignUp(email: String, password: String) async -> Bool { errorMessage = "Account registration is unavailable."; return false }
 func appleSignIn(token: String, nonce: String) async -> Bool { errorMessage = "Apple sign-in is currently unavailable."; return false }
 func sendPasswordReset(email: String) async { errorMessage = "Password reset is currently unavailable." }
 func handleAuthURL(_ url: URL) async -> Bool { false }
 func updatePassword(_ password: String) async -> Bool { false }
 func cancelPasswordRecovery() async -> Bool { passwordRecovery = false; return true }
 func restoreSavedAccount() async -> Bool {
  guard defaults.bool(forKey: "liya.local.signedIn"), let value = defaults.string(forKey: ownerKey), let id = UUID(uuidString: value) else { return false }
  userID = id; await loadLocalData(); return true
 }
 private func loadLocalData() async { await refreshCatalog(); await refreshProfile(); await refreshMoods(); await refreshLikes(); await refreshTreeEntries(); await refreshWallet() }
 func refreshCatalog() async {
  func bundled(_ kind: String, count: Int, ext: String) -> [LiyaMedia] {
   (1...count).compactMap { number in
    let suffix = String(format: "%03d", number); let filename = "example_\(kind)_\(suffix)"
    guard Bundle.main.url(forResource: filename, withExtension: ext, subdirectory: "Examples") != nil else { return nil }
    return LiyaMedia(id: "example-\(kind)-\(suffix)", kind: kind, sortOrder: number - 1, objectKey: "\(filename).\(ext)")
   }
  }
  photos = bundled("photo", count: 40, ext: "jpg"); videos = bundled("video", count: 10, ext: "mp4")
  catalogError = photos.count == 40 && videos.count == 10 ? nil : "Some content is unavailable."
  catalogGeneration = UUID(); imageGeneration = UUID()
 }
 func mediaURL(kind: String, index: Int) async throws -> URL {
  let media = kind == "photo" ? photos : videos
  guard media.indices.contains(index) else { throw LocalError.unavailable }
  let name = media[index].objectKey as NSString
  guard let url = Bundle.main.url(forResource: name.deletingPathExtension, withExtension: name.pathExtension, subdirectory: "Examples") else { throw LocalError.unavailable }
  return url
 }
 func resumeAccount() async { guard userID != nil else { return }; await loadLocalData() }
 func restoreForIncomingCall() async -> Bool { false }
 func signOut() async -> Bool {
  guard userID != nil else { return false }; isSigningOut = true; defer { isSigningOut = false }
  defaults.set(false, forKey: "liya.local.signedIn"); userID = nil; profile = nil; profileAvatarURL = nil; moodEntries = []; treeEntries = []; likedMediaIDs = []; coinBalance = nil
  welcomeNotice = "You are signed out."; return true
 }
 func deleteAccount() async -> Bool { deletionError = "Online account deletion is unavailable. Your previous account has not been deleted."; return false }
 func refreshWallet() async { coinBalance = nil; walletError = nil; welcomeGift = nil }
 func configurePurchaseWallet(sandbox: Bool, owner: UUID) async -> Bool { false }
 func acknowledgeWelcome() async -> Bool { welcomeGift = nil; return true }
 func refreshMoods() async { moodEntries = read([CloudMood].self, "moods") ?? []; moodError = nil }
 func saveMood(_ mood: String, note: String, date: Date) async -> Bool {
  guard let owner = userID else { return false }
  let item = CloudMood(ownerID: owner, day: CloudMood.dayKey(date), state: "saved", mood: mood, note: note)
  var items = moodEntries.filter { $0.day != item.day }; items.append(item); items.sort { $0.day > $1.day }
  guard write(items, "moods") else { moodError = "Couldn't save your entry."; return false }
  moodEntries = items; moodError = nil; return true
 }
 func refreshProfile() async {
  guard let owner = userID else { return }
  profile = read(CloudProfile.self, "profile") ?? CloudProfile(id: owner, displayName: "", signature: "", tags: [], avatarPath: nil)
  if let path = profile?.avatarPath { profileAvatarURL = URL(fileURLWithPath: path) } else { profileAvatarURL = nil }
  profileError = nil
 }
 func saveProfile(name: String, signature: String, tags: [String], avatar: DraftAttachment?) async -> Bool {
  guard let owner = userID else { return false }
  let path = avatar.map { DraftFiles.url($0).path } ?? profile?.avatarPath
  let value = CloudProfile(id: owner, displayName: name, signature: signature, tags: tags, avatarPath: path)
  guard write(value, "profile") else { profileError = "Couldn't save your profile."; return false }
  profile = value; profileAvatarURL = path.map { URL(fileURLWithPath: $0) }; profileError = nil; return true
 }
 func submitReport(id: UUID, index: Int, targetType: String, reason: String) async -> Bool { false }
 func refreshLikes() async { likedMediaIDs = Set(read([String].self, "likes") ?? []); likesReady = true; likesError = nil }
 func toggleLike(kind: String, index: Int) async {
  let items = kind == "photo" ? photos : videos; guard items.indices.contains(index) else { return }
  var next = likedMediaIDs; let id = items[index].id
  if next.contains(id) { next.remove(id) } else { next.insert(id) }
  if write(Array(next), "likes") { likedMediaIDs = next } else { likesError = "Couldn't save your like." }
 }
 func isLiked(kind: String, index: Int) -> Bool { let items = kind == "photo" ? photos : videos; return items.indices.contains(index) && likedMediaIDs.contains(items[index].id) }
 func refreshTreeEntries() async { treeEntries = read([TreeEntry].self, "tree") ?? []; treeError = nil }
 func saveTreeEntry(id: UUID, mood: String, body: String) async -> Bool {
  guard let owner = userID else { return false }; var next = treeEntries.filter { $0.id != id }; next.insert(TreeEntry(id: id, ownerID: owner, mood: mood, body: body), at: 0)
  guard write(next, "tree") else { treeError = "Couldn't save your thought."; return false }; treeEntries = next; return true
 }
 func deleteTreeEntry(_ id: UUID) async { let next = treeEntries.filter { $0.id != id }; if write(next, "tree") { treeEntries = next } else { treeError = "Couldn't remove your thought." } }
 private enum LocalError: Error { case unavailable }
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

struct CloudProfile: Codable {
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


struct TreeEntry: Codable, Identifiable, Equatable {
 let id: UUID; let ownerID: UUID; let mood: String; let body: String
 enum CodingKeys: String, CodingKey { case id, mood, body; case ownerID = "owner_id" }
}
