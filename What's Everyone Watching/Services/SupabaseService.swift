import Foundation
import Combine
import SwiftUI

class SupabaseService: NSObject, ObservableObject {
    static let shared = SupabaseService()
    
    let supabaseURL = "https://iacsrhqxjxexbocrlmuq.supabase.co"
    let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlhY3NyaHF4anhleGJvY3JsbXVxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4NzYzNjAsImV4cCI6MjEwMTQ1MjM2MH0.77R1TaHpsxGeArDUSx4dpglozLwiiSik3obTOCEl5V0"
    
    @Published var currentUser: User?
    @Published var isLoggedIn = false
    @Published var profileSetupNeeded = false

    private let userDefaultsKey = "savedUser"
    private let tokenDefaultsKey = "authToken"
    private let profileSetupKey = "profileSetupNeeded"
    private var authToken: String = ""
    
    override private init() {
        super.init()
        restoreSession()
    }
    
    // MARK: - Session Persistence
    
    private func restoreSession() {
        if let userData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let user = try? JSONDecoder().decode(User.self, from: userData) {
            print("Restored user from session: id='\(user.id)', email='\(user.email)'")
            if let token = UserDefaults.standard.string(forKey: tokenDefaultsKey) {
                self.authToken = token
                print("Restored auth token")
            }
            let needsSetup = UserDefaults.standard.bool(forKey: profileSetupKey)
            DispatchQueue.main.async {
                self.currentUser = user
                self.isLoggedIn = true
                self.profileSetupNeeded = needsSetup
            }
        }
    }
    
    private func saveSession(user: User, token: String) {
        print("Saving user to session: id='\(user.id)', email='\(user.email)'")
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
        UserDefaults.standard.set(token, forKey: tokenDefaultsKey)
        self.authToken = token
    }

    private func setProfileSetupNeeded(_ needed: Bool) {
        DispatchQueue.main.async {
            self.profileSetupNeeded = needed
        }
        UserDefaults.standard.set(needed, forKey: profileSetupKey)
    }
    
    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
        self.authToken = ""
    }
    
    // MARK: - Authentication
    
    func signUp(email: String, password: String, name: String) async throws -> User {
        let endpoint = "\(supabaseURL)/auth/v1/signup"
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        struct SignUpBody: Encodable {
            let email: String
            let password: String
        }
        
        let body = SignUpBody(email: email, password: password)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sign up failed"])
        }
        
        print("SignUp Response: \(String(data: data, encoding: .utf8) ?? "no data")")
        
        struct SignUpResponse: Decodable {
            let id: String
        }
        
        let signupResponse = try JSONDecoder().decode(SignUpResponse.self, from: data)
        let userId = signupResponse.id
        print("SignUp userId: \(userId)")
        
        let user = User(id: userId, email: email, name: name, avatarUrl: nil)

        self.authToken = ""
        try await insertUser(user: user)

        DispatchQueue.main.async {
            self.currentUser = user
            self.isLoggedIn = true
            self.profileSetupNeeded = true
            self.saveSession(user: user, token: "")
            self.setProfileSetupNeeded(true)
        }

        return user
    }
    
    func signIn(email: String, password: String) async throws -> User {
        let endpoint = "\(supabaseURL)/auth/v1/token?grant_type=password"
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        struct SignInBody: Encodable {
            let email: String
            let password: String
        }
        
        let body = SignInBody(email: email, password: password)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sign in failed"])
        }
        
        print("SignIn Response: \(String(data: data, encoding: .utf8) ?? "no data")")
        
        struct TokenResponse: Decodable {
            let user: UserResponse?
            let access_token: String?
        }
        
        struct UserResponse: Decodable {
            let id: String
            let email: String
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let userId = tokenResponse.user?.id ?? UUID().uuidString
        let userEmail = tokenResponse.user?.email ?? email
        let token = tokenResponse.access_token ?? ""
        print("SignIn userId: \(userId), email: \(userEmail), token: \(token.prefix(20))...")
        
        let user = User(id: userId, email: userEmail, name: "", avatarUrl: nil)
        
        self.authToken = token
        try await insertUser(user: user)
        
        DispatchQueue.main.async {
            self.currentUser = user
            self.isLoggedIn = true
            self.saveSession(user: user, token: token)
        }
        
        return user
    }
    
    func signOut() {
        DispatchQueue.main.async {
            self.currentUser = nil
            self.isLoggedIn = false
            self.clearSession()
        }
    }
    
    // MARK: - Database Operations
    
    func insertUser(user: User) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/users"
        try await insert(endpoint: endpoint, body: user)
    }
    
    func fetchUser(userId: String) async throws -> User {
        let endpoint = "\(supabaseURL)/rest/v1/users?id=eq.\(userId)"
        return try await fetchSingle(endpoint: endpoint)
    }
    
    func fetchShow(tmdbId: Int) async throws -> TVShow {
        let endpoint = "\(supabaseURL)/rest/v1/tv_shows?tmdb_id=eq.\(tmdbId)"
        return try await fetchSingle(endpoint: endpoint)
    }

    func insertShow(show: TVShow) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/tv_shows"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(show)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 201 {
            return
        } else if statusCode == 409 {
            return
        } else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Show insert failed with status \(statusCode): \(responseBody)"])
        }
    }
    
    func fetchEpisodes(showId: Int, userId: String) async throws -> [Episode] {
        let endpoint = "\(supabaseURL)/rest/v1/episodes?show_id=eq.\(showId)&user_id=eq.\(userId)"
        return try await fetch(endpoint: endpoint)
    }

    func insertEpisode(episode: Episode) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/episodes"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(episode)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseBody = String(data: data, encoding: .utf8) ?? ""

        print("📝 Episode insert: status=\(statusCode), episode=S\(episode.seasonNumber)E\(episode.episodeNumber), userId=\(episode.userId ?? "nil")")
        if !responseBody.isEmpty {
            print("   Response: \(responseBody)")
        }

        if statusCode == 201 {
            return
        } else if statusCode == 409 {
            print("⚠️ Duplicate episode - skipping")
            return
        } else if statusCode == 401 {
            print("⚠️ Episode insert blocked by RLS policy - skipping")
            return
        } else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Episode insert failed with status \(statusCode): \(responseBody)"])
        }
    }

    func updateEpisodeWatched(episodeId: Int, watched: Bool) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/episodes?id=eq.\(episodeId)"
        let watchedAt = watched ? ISO8601DateFormatter().string(from: Date()) : nil

        struct UpdateBody: Encodable {
            let watched: Bool
            let watched_at: String?
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let body = UpdateBody(watched: watched, watched_at: watchedAt)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Update failed"])
        }
    }

    func fetchUserEpisodes(userId: String) async throws -> [Episode] {
        let endpoint = "\(supabaseURL)/rest/v1/episodes?user_id=eq.\(userId)&order=watched_at.desc"
        return try await fetch(endpoint: endpoint)
    }
    
    func fetchUserShows(userId: String) async throws -> [UserShow] {
        let endpoint = "\(supabaseURL)/rest/v1/user_shows?user_id=eq.\(userId)&order=watched_date.desc"
        return try await fetch(endpoint: endpoint)
    }
    
    func insertUserEpisode(userEpisode: UserEpisode) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_episodes"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(userEpisode)

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 201 {
            return
        } else if statusCode == 409 {
            print("⚠️ Episode not found in database - skipping user_episodes insert (episodes table may have RLS blocking inserts)")
            return
        } else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "User episode insert failed with status \(statusCode)"])
        }
    }
    
    func insertUserShow(userId: String, showId: Int, watchedDate: String) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_shows"

        struct UserShowInsert: Encodable {
            let user_id: String
            let show_id: Int
            let watched_date: String
            let created_at: String
        }

        let body = UserShowInsert(
            user_id: userId,
            show_id: showId,
            watched_date: watchedDate,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        try await insert(endpoint: endpoint, body: body)
    }

    func removeUserShow(id: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_shows?id=eq.\(id)"
        try await delete(endpoint: endpoint)
    }

    func deleteEpisodesByShowId(showId: Int, userId: String) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/episodes?show_id=eq.\(showId)&user_id=eq.\(userId)"
        try await delete(endpoint: endpoint)
    }

    func updateShowRating(showId: Int, userId: String, rating: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_shows?show_id=eq.\(showId)&user_id=eq.\(userId)"

        struct UpdateBody: Encodable {
            let rating: Int
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let body = UpdateBody(rating: rating)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Rating update failed"])
        }
    }

    func removeUserMovie(id: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_movies?id=eq.\(id)"
        try await delete(endpoint: endpoint)
    }
    
    func insertMovie(movie: Movie) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/movies"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(movie)

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 201 {
            return
        } else if statusCode == 409 {
            return
        } else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Movie insert failed with status \(statusCode)"])
        }
    }

    func fetchUserMovies(userId: String) async throws -> [UserMovie] {
        let endpoint = "\(supabaseURL)/rest/v1/user_movies?user_id=eq.\(userId)"
        return try await fetch(endpoint: endpoint)
    }
    
    func fetchActivityFeed(userId: String) async throws -> [ActivityFeedItem] {
        let endpoint = "\(supabaseURL)/rest/v1/activity?user_id=eq.\(userId)&order=created_at.desc"
        return try await fetch(endpoint: endpoint)
    }
    
    // MARK: - Watchlist Operations
    
    func fetchWatchlistShows(userId: String) async throws -> [WatchlistShow] {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_shows?user_id=eq.\(userId)&order=priority.asc,added_at.desc"
        return try await fetch(endpoint: endpoint)
    }
    
    func fetchWatchlistMovies(userId: String) async throws -> [WatchlistMovie] {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_movies?user_id=eq.\(userId)&order=priority.asc,added_at.desc"
        return try await fetch(endpoint: endpoint)
    }
    
    func addToWatchlistShow(userId: String, showId: Int, priority: String = "medium", notes: String? = nil) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_shows"
        print("Adding to watchlist with userId: '\(userId)'")
        
        struct WatchlistShowInsert: Encodable {
            let user_id: String
            let show_id: Int
            let priority: String
            let notes: String?
            let added_at: String
        }
        
        let body = WatchlistShowInsert(
            user_id: userId,
            show_id: showId,
            priority: priority,
            notes: notes,
            added_at: ISO8601DateFormatter().string(from: Date())
        )
        try await insert(endpoint: endpoint, body: body)
    }
    
    func addToWatchlistMovie(userId: String, movieId: Int, priority: String = "medium", notes: String? = nil) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_movies"
        print("Adding to watchlist with userId: '\(userId)'")
        
        struct WatchlistMovieInsert: Encodable {
            let user_id: String
            let movie_id: Int
            let priority: String
            let notes: String?
            let added_at: String
        }
        
        let body = WatchlistMovieInsert(
            user_id: userId,
            movie_id: movieId,
            priority: priority,
            notes: notes,
            added_at: ISO8601DateFormatter().string(from: Date())
        )
        try await insert(endpoint: endpoint, body: body)
    }
    
    func removeFromWatchlistShow(id: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_shows?id=eq.\(id)"
        try await delete(endpoint: endpoint)
    }
    
    func removeFromWatchlistMovie(id: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_movies?id=eq.\(id)"
        try await delete(endpoint: endpoint)
    }

    // MARK: - Friends

    func sendFriendRequest(userId: String, friendId: String) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/friendships"

        struct FriendshipInsert: Encodable {
            let user_id: String
            let friend_id: String
            let status: String
            let created_at: String
        }

        let body = FriendshipInsert(
            user_id: userId,
            friend_id: friendId,
            status: "pending",
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        try await insert(endpoint: endpoint, body: body)
    }

    func acceptFriendRequest(requestId: Int, userId: String, friendId: String) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/friendships?id=eq.\(requestId)"

        struct FriendshipUpdate: Encodable {
            let status: String
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let body = FriendshipUpdate(status: "accepted")
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Accept failed"])
        }

        // Create reverse friendship
        try await sendFriendRequest(userId: friendId, friendId: userId)
    }

    func rejectFriendRequest(requestId: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/friendships?id=eq.\(requestId)"
        try await delete(endpoint: endpoint)
    }

    func removeFriend(userId: String, friendId: String) async throws {
        let endpoint1 = "\(supabaseURL)/rest/v1/friendships?user_id=eq.\(userId)&friend_id=eq.\(friendId)"
        let endpoint2 = "\(supabaseURL)/rest/v1/friendships?user_id=eq.\(friendId)&friend_id=eq.\(userId)"
        try await delete(endpoint: endpoint1)
        try await delete(endpoint: endpoint2)
    }

    func fetchFriends(userId: String) async throws -> [User] {
        let endpoint = "\(supabaseURL)/rest/v1/friendships?user_id=eq.\(userId)&status=eq.accepted&select=friend_id"
        let friendships: [Friendship] = try await fetch(endpoint: endpoint)
        var friends: [User] = []

        for friendship in friendships {
            if let friend = try? await fetchUser(userId: friendship.friendId) {
                friends.append(friend)
            }
        }
        return friends
    }

    func fetchFriendRequests(userId: String) async throws -> [Friendship] {
        let endpoint = "\(supabaseURL)/rest/v1/friendships?friend_id=eq.\(userId)&status=eq.pending"
        return try await fetch(endpoint: endpoint)
    }

    func searchUsers(query: String) async throws -> [UserProfile] {
        let endpoint = "\(supabaseURL)/rest/v1/user_profiles?display_name=ilike.%\(query)%&is_public=eq.true"
        return try await fetch(endpoint: endpoint)
    }

    func getFriendRatings(friendId: String) async throws -> [UserShow] {
        let endpoint = "\(supabaseURL)/rest/v1/user_shows?user_id=eq.\(friendId)"
        return try await fetch(endpoint: endpoint)
    }

    func getUserProfile(userId: String) async throws -> UserProfile {
        let endpoint = "\(supabaseURL)/rest/v1/user_profiles?user_id=eq.\(userId)"
        return try await fetchSingle(endpoint: endpoint)
    }

    func createUserProfile(userId: String, displayName: String) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_profiles"

        struct UserProfileInsert: Encodable {
            let user_id: String
            let display_name: String
            let is_public: Bool
            let created_at: String
        }

        let body = UserProfileInsert(
            user_id: userId,
            display_name: displayName,
            is_public: true,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        try await insert(endpoint: endpoint, body: body)
    }

    func completeProfileSetup(userId: String, displayName: String, bio: String? = nil) async throws {
        try await createUserProfile(userId: userId, displayName: displayName)
        if let bio = bio {
            try await updateUserProfile(userId: userId, displayName: displayName, bio: bio, isPublic: true)
        }
        setProfileSetupNeeded(false)
    }

    func updateUserProfile(userId: String, displayName: String? = nil, bio: String? = nil, isPublic: Bool? = nil) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_profiles?user_id=eq.\(userId)"

        struct UserProfileUpdate: Encodable {
            let display_name: String?
            let bio: String?
            let is_public: Bool?

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let displayName = display_name {
                    try container.encode(displayName, forKey: .display_name)
                }
                if let bio = bio {
                    try container.encode(bio, forKey: .bio)
                }
                if let isPublic = is_public {
                    try container.encode(isPublic, forKey: .is_public)
                }
            }

            enum CodingKeys: String, CodingKey {
                case display_name
                case bio
                case is_public
            }
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let body = UserProfileUpdate(display_name: displayName, bio: bio, is_public: isPublic)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Update failed"])
        }
    }

    // MARK: - Private Helpers
    
    private func fetch<T: Decodable>(endpoint: String) async throws -> [T] {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Request failed"])
        }
        
        return try JSONDecoder().decode([T].self, from: data)
    }
    
    private func fetchSingle<T: Decodable>(endpoint: String) async throws -> T {
        let results: [T] = try await fetch(endpoint: endpoint)
        guard let first = results.first else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not found"])
        }
        return first
    }
    
    private func insert<T: Encodable>(endpoint: String, body: T) async throws {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        print("Insert request to: \(endpoint)")
        print("Status code: \(statusCode)")
        if let responseBody = String(data: data, encoding: .utf8) {
            print("Response: \(responseBody)")
        }

        guard statusCode == 201 else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Insert failed with status \(statusCode)"])
        }
    }
    
    private func delete(endpoint: String) async throws {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "DELETE"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Delete failed"])
        }
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else {
            try container.encodeNil()
        }
    }
}
