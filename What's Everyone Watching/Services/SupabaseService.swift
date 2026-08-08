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
    private let refreshTokenDefaultsKey = "refreshToken"
    private let profileSetupKey = "profileSetupNeeded"
    var authToken: String = ""
    private var refreshToken: String = ""
    
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
            if let refToken = UserDefaults.standard.string(forKey: refreshTokenDefaultsKey) {
                self.refreshToken = refToken
                print("Restored refresh token")
            }
            let needsSetup = UserDefaults.standard.bool(forKey: profileSetupKey)
            DispatchQueue.main.async {
                self.currentUser = user
                self.isLoggedIn = true
                self.profileSetupNeeded = needsSetup
            }
        }
    }
    
    func saveSession(user: User, token: String, refreshToken: String = "") {
        print("Saving user to session: id='\(user.id)', email='\(user.email)'")
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
        UserDefaults.standard.set(token, forKey: tokenDefaultsKey)
        UserDefaults.standard.set(refreshToken, forKey: refreshTokenDefaultsKey)
        self.authToken = token
        self.refreshToken = refreshToken
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
        UserDefaults.standard.removeObject(forKey: refreshTokenDefaultsKey)
        self.authToken = ""
        self.refreshToken = ""
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
            let refresh_token: String?
        }
        
        struct UserResponse: Decodable {
            let id: String
            let email: String
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let userId = tokenResponse.user?.id ?? UUID().uuidString
        let userEmail = tokenResponse.user?.email ?? email
        let token = tokenResponse.access_token ?? ""
        let refToken = tokenResponse.refresh_token ?? ""
        print("SignIn userId: \(userId), email: \(userEmail), token: \(token.prefix(20))...")
        
        let user = User(id: userId, email: userEmail, name: "", avatarUrl: nil)
        
        self.authToken = token
        try await insertUser(user: user)
        
        DispatchQueue.main.async {
            self.currentUser = user
            self.isLoggedIn = true
            self.saveSession(user: user, token: token, refreshToken: refToken)
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
    
    // MARK: - Token Refresh
    
    private func refreshAccessToken() async throws {
        guard !refreshToken.isEmpty else {
            print("⚠️ No refresh token available, skipping refresh")
            return
        }

        let endpoint = "\(supabaseURL)/auth/v1/token?grant_type=refresh_token"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        struct RefreshBody: Encodable {
            let refresh_token: String
        }

        let body = RefreshBody(refresh_token: refreshToken)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            print("❌ Token refresh failed")
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Token refresh failed"])
        }

        struct TokenResponse: Decodable {
            let access_token: String?
            let refresh_token: String?
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newToken = tokenResponse.access_token ?? ""
        let newRefreshToken = tokenResponse.refresh_token ?? refreshToken
        
        print("✅ Token refreshed successfully")
        
        self.authToken = newToken
        self.refreshToken = newRefreshToken
        
        // Update saved session
        if let user = currentUser {
            saveSession(user: user, token: newToken, refreshToken: newRefreshToken)
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
    
    func fetchShowById(id: Int) async throws -> TVShow {
        let endpoint = "\(supabaseURL)/rest/v1/tv_shows?id=eq.\(id)"
        print("🔍 Fetching show with id: \(id)")
        do {
            let result: TVShow = try await fetchSingle(endpoint: endpoint)
            print("✅ Show fetch succeeded: \(result.title)")
            return result
        } catch {
            print("❌ Show fetch failed for id \(id): \(error.localizedDescription)")
            throw error
        }
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
            // Episode already exists - update it to mark as watched
            if episode.watched {
                print("⚠️ Duplicate episode - updating watched status")
                try await updateEpisodeWatchedById(episodeId: episode.id, watched: true, watchedAt: episode.watchedAt)
            } else {
                print("⚠️ Duplicate episode - skipping")
            }
            return
        } else if statusCode == 401 {
            print("⚠️ Episode insert blocked by RLS policy - skipping")
            return
        } else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Episode insert failed with status \(statusCode): \(responseBody)"])
        }
    }

    private func updateEpisodeWatchedById(episodeId: Int, watched: Bool, watchedAt: String?) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/episodes?id=eq.\(episodeId)"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        struct UpdateBody: Encodable {
            let watched: Bool
            let watched_at: String?
        }

        let body = UpdateBody(watched: watched, watched_at: watchedAt)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 204 || statusCode == 200 {
            return
        }

        let responseStr = String(data: data, encoding: .utf8) ?? ""
        print("⚠️ updateEpisodeWatchedById failed: status=\(statusCode), response=\(responseStr)")
    }

    private func updateEpisodeWatched(episodeId: Int, watched: Bool, watchedAt: String?, userId: String?) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/episodes?id=eq.\(episodeId)&user_id=eq.\(userId ?? "")"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        struct UpdatePayload: Encodable {
            let watched: Bool
            let watched_at: String?
        }

        let payload = UpdatePayload(watched: watched, watched_at: watchedAt)
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 200 {
            print("✅ Updated episode watched status for id=\(episodeId)")
        } else {
            print("⚠️ Failed to update episode \(episodeId): status=\(statusCode)")
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

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 204 || statusCode == 200 {
            return
        }

        let responseStr = String(data: data, encoding: .utf8) ?? ""
        print("⚠️ updateEpisodeWatched failed: status=\(statusCode), response=\(responseStr)")
    }

    func moveWatchlistToLibrary(userId: String, showId: Int) async throws {
        let userShows = (try? await fetchUserShows(userId: userId)) ?? []
        guard !userShows.contains(where: { $0.showId == showId }) else { return }
        let today = ISO8601DateFormatter().string(from: Date())
        try await insertUserShow(userId: userId, showId: showId, watchedDate: today)
    }

    func removeFromLibraryIfNoWatchedEpisodes(userId: String, showId: Int) async throws {
        let watchedEpisodes = (try? await fetchUserEpisodes(userId: userId)) ?? []
        let episodesForShow = watchedEpisodes.filter { $0.showId == showId }

        if episodesForShow.isEmpty {
            if let userShow = try? await fetchUserShows(userId: userId),
               let item = userShow.first(where: { $0.showId == showId }) {
                try await removeUserShow(id: item.id)
            }
        }
    }

    func fetchUserEpisodes(userId: String) async throws -> [Episode] {
        let endpoint = "\(supabaseURL)/rest/v1/episodes?user_id=eq.\(userId)&watched=eq.true&order=watched_at.desc"
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
    
    func insertUserShow(userId: String, showId: Int, watchedDate: String, rating: Int? = nil) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_shows"

        struct UserShowInsert: Encodable {
            let user_id: String
            let show_id: Int
            let watched_date: String
            let rating: Int?
            let created_at: String
        }

        let body = UserShowInsert(
            user_id: userId,
            show_id: showId,
            watched_date: watchedDate,
            rating: rating,
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

    func updateRating(userId: String, itemId: Int, rating: Int, review: String? = nil, isMovie: Bool) async throws {
        let table = isMovie ? "user_movies" : "user_shows"
        let idColumn = isMovie ? "movie_id" : "show_id"
        let endpoint = "\(supabaseURL)/rest/v1/\(table)?\(idColumn)=eq.\(itemId)&user_id=eq.\(userId)"

        struct UpdateBody: Encodable {
            let rating: Int
            let review: String?
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let body = UpdateBody(rating: rating, review: review)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Rating update failed"])
        }
    }

    func insertUserMovie(userId: String, movieId: Int, watchedDate: String, rating: Int? = nil) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/user_movies"

        struct UserMovieInsert: Encodable {
            let user_id: String
            let movie_id: Int
            let watched_date: String
            let rating: Int?
            let created_at: String
        }

        let body = UserMovieInsert(
            user_id: userId,
            movie_id: movieId,
            watched_date: watchedDate,
            rating: rating,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        try await insert(endpoint: endpoint, body: body)
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

    func fetchMovieById(id: Int) async throws -> Movie {
        let endpoint = "\(supabaseURL)/rest/v1/movies?id=eq.\(id)"
        return try await fetchSingle(endpoint: endpoint)
    }

    func fetchActivityFeed(userId: String) async throws -> [ActivityFeedItem] {
        let endpoint = "\(supabaseURL)/rest/v1/activity?user_id=eq.\(userId)&order=created_at.desc"
        return try await fetch(endpoint: endpoint)
    }
    
    // MARK: - Watchlist Operations
    
    func fetchWatchlistShows(userId: String) async throws -> [WatchlistShow] {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_shows?user_id=eq.\(userId)&order=priority.asc,added_at.desc"
        print("📋 Fetching watchlist for user: \(userId)")
        do {
            let result: [WatchlistShow] = try await fetch(endpoint: endpoint)
            print("✅ Watchlist fetch succeeded: \(result.count) items")
            return result
        } catch {
            print("❌ Watchlist fetch failed: \(error.localizedDescription)")
            throw error
        }
    }

    func isShowInWatchlist(userId: String, showId: Int) async throws -> Bool {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_shows?user_id=eq.\(userId)&show_id=eq.\(showId)"
        let results: [WatchlistShow] = try await fetch(endpoint: endpoint)
        return !results.isEmpty
    }

    func isShowInLibrary(userId: String, showId: Int) async throws -> Bool {
        let endpoint = "\(supabaseURL)/rest/v1/user_shows?user_id=eq.\(userId)&show_id=eq.\(showId)"
        let results: [UserShow] = try await fetch(endpoint: endpoint)
        return !results.isEmpty
    }

    func fetchWatchlistMovies(userId: String) async throws -> [WatchlistMovie] {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_movies?user_id=eq.\(userId)&order=priority.asc,added_at.desc"
        return try await fetch(endpoint: endpoint)
    }

    func isMovieInWatchlist(userId: String, movieId: Int) async throws -> Bool {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_movies?user_id=eq.\(userId)&movie_id=eq.\(movieId)"
        let results: [WatchlistMovie] = try await fetch(endpoint: endpoint)
        return !results.isEmpty
    }

    func isMovieInLibrary(userId: String, movieId: Int) async throws -> Bool {
        let endpoint = "\(supabaseURL)/rest/v1/user_movies?user_id=eq.\(userId)&movie_id=eq.\(movieId)"
        let results: [UserMovie] = try await fetch(endpoint: endpoint)
        return !results.isEmpty
    }
    
    func addToWatchlistShow(userId: String, showId: Int, priority: String = "medium", notes: String? = nil) async throws {
        // Check if already in watchlist to prevent duplicates
        let existing = try? await isShowInWatchlist(userId: userId, showId: showId)
        if existing == true {
            print("Show already in watchlist, skipping duplicate insert")
            return
        }

        // Fetch show from TMDB and insert into tv_shows table
        if let tmdbShow = try? await TMDBService.shared.getTVShow(id: showId) {
            let show = TVShow(id: showId, tmdbId: showId, title: tmdbShow.name,
                            overview: tmdbShow.overview, posterUrl: tmdbShow.imageUrl,
                            firstAirDate: tmdbShow.firstAirDate, numberOfSeasons: tmdbShow.numberOfSeasons,
                            numberOfEpisodes: tmdbShow.numberOfEpisodes)
            try? await insertShow(show: show)
        }

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
        // Check if already in watchlist to prevent duplicates
        let existing = try? await isMovieInWatchlist(userId: userId, movieId: movieId)
        if existing == true {
            print("Movie already in watchlist, skipping duplicate insert")
            return
        }

        // Fetch movie from TMDB and insert into movies table
        if let tmdbMovie = try? await TMDBService.shared.getMovie(id: movieId) {
            let movie = Movie(id: movieId, tmdbId: movieId, title: tmdbMovie.title,
                            overview: tmdbMovie.overview, posterUrl: tmdbMovie.imageUrl,
                            releaseDate: tmdbMovie.releaseDate)
            try? await insertMovie(movie: movie)
        }

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

    func removeShowFromWatchlist(userId: String, showId: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_shows?user_id=eq.\(userId)&show_id=eq.\(showId)"
        try await delete(endpoint: endpoint)
    }

    func restoreToWatchlist(userId: String, showId: Int) async throws {
        // Fetch show from TMDB and ensure it's in tv_shows table
        if let tmdbShow = try? await TMDBService.shared.getTVShow(id: showId) {
            let show = TVShow(id: showId, tmdbId: showId, title: tmdbShow.name,
                            overview: tmdbShow.overview, posterUrl: tmdbShow.imageUrl,
                            firstAirDate: tmdbShow.firstAirDate, numberOfSeasons: tmdbShow.numberOfSeasons,
                            numberOfEpisodes: tmdbShow.numberOfEpisodes)
            try? await insertShow(show: show)
        }

        // Delete any existing entry, then insert fresh one to ensure it's in watchlist
        try? await removeShowFromWatchlist(userId: userId, showId: showId)

        let endpoint = "\(supabaseURL)/rest/v1/watchlist_shows"
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
            priority: "medium",
            notes: nil,
            added_at: ISO8601DateFormatter().string(from: Date())
        )
        try await insert(endpoint: endpoint, body: body)
    }

    func removeFromWatchlistMovie(id: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_movies?id=eq.\(id)"
        try await delete(endpoint: endpoint)
    }

    func removeMovieFromWatchlist(userId: String, movieId: Int) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/watchlist_movies?user_id=eq.\(userId)&movie_id=eq.\(movieId)"
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

    // MARK: - Streaming Platforms
    
    func saveUserPlatforms(userId: String, platformIds: [Int]) async throws {
        // First, delete existing platforms for this user
        try await deleteUserPlatforms(userId: userId)

        // Now insert the new platforms
        if !platformIds.isEmpty {
            let endpoint = "\(supabaseURL)/rest/v1/user_streaming_platforms"

            struct PlatformInsert: Encodable {
                let user_id: String
                let platform_id: Int
            }

            for platformId in platformIds {
                let body = PlatformInsert(user_id: userId, platform_id: platformId)
                try await insert(endpoint: endpoint, body: body)
            }
        }
    }

    private func deleteUserPlatforms(userId: String) async throws {
        let deleteEndpoint = "\(supabaseURL)/rest/v1/user_streaming_platforms?user_id=eq.\(userId)"

        do {
            try await performDelete(endpoint: deleteEndpoint)
        } catch let error as NSError where error.code == 401 {
            // Token expired, try to refresh
            print("🔄 Token expired on delete, attempting refresh...")
            do {
                try await refreshAccessToken()
                // Retry with new token
                try await performDelete(endpoint: deleteEndpoint)
            } catch {
                // If refresh fails, user needs to log in again
                print("❌ Token refresh failed, user session expired")
                signOut()
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Session expired. Please log in again."])
            }
        }
    }

    private func performDelete(endpoint: String) async throws {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "DELETE"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? -1

        guard statusCode == 200 || statusCode == 204 else {
            throw NSError(domain: "API", code: statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Delete request failed with status \(statusCode)"
            ])
        }
    }
    
    func getUserPlatforms(userId: String) async throws -> [Int] {
        let endpoint = "\(supabaseURL)/rest/v1/user_streaming_platforms?user_id=eq.\(userId)&select=platform_id"

        struct PlatformResult: Decodable {
            let platform_id: Int
        }

        do {
            let results: [PlatformResult] = try await fetch(endpoint: endpoint)
            return results.map { $0.platform_id }
        } catch {
            // If no auth token or refresh token, just return empty (new user case)
            if refreshToken.isEmpty {
                print("⚠️ No platforms saved yet (new user)")
                return []
            }
            throw error
        }
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
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 204 || statusCode == 200 {
            return
        }

        if statusCode == 0 {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Update failed"])
        }

        throw NSError(domain: "API", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Update failed with status \(statusCode)"])
    }

    // MARK: - Private Helpers
    
    private func fetch<T: Decodable>(endpoint: String) async throws -> [T] {
        // Try the request with current token
        do {
            return try await performFetch(endpoint: endpoint)
        } catch let error as NSError where error.code == 401 {
            // Token expired, try to refresh
            print("🔄 Token expired, attempting refresh...")
            try await refreshAccessToken()
            
            // Retry with new token
            return try await performFetch(endpoint: endpoint)
        }
    }
    
    private func performFetch<T: Decodable>(endpoint: String) async throws -> [T] {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? -1
        
        guard statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ API Error:")
            print("   Endpoint: \(endpoint)")
            print("   Status Code: \(statusCode)")
            print("   Response: \(responseBody)")
            throw NSError(domain: "API", code: statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Request failed with status \(statusCode)",
                NSLocalizedFailureReasonErrorKey: responseBody
            ])
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

        if statusCode == 201 || statusCode == 409 {
            return
        } else {
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

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 204 || statusCode == 200 else {
            let responseStr = String(data: data, encoding: .utf8) ?? ""
            print("⚠️ Delete failed: status=\(statusCode), response=\(responseStr)")
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

// MARK: - Streaming Platforms

struct StreamingPlatformRow: Decodable {
    let id: Int
    let display_name: String
    let tmdb_provider_names: [String]
}

extension SupabaseService {
    func getStreamingPlatforms() async throws -> [StreamingPlatformRow] {
        let endpoint = "\(supabaseURL)/rest/v1/streaming_platforms?select=id,display_name,tmdb_provider_names"
        let results: [StreamingPlatformRow] = try await fetch(endpoint: endpoint)
        return results
    }

    func cleanupOrphanedWatchlist() async throws {
        guard let userId = currentUser?.id else { return }

        // Get all watchlist shows
        let watchlistShows = (try? await fetchWatchlistShows(userId: userId)) ?? []
        let watchlistMovies = (try? await fetchWatchlistMovies(userId: userId)) ?? []

        // Remove shows that don't exist in tv_shows table
        for show in watchlistShows {
            if (try? await fetchShowById(id: show.showId)) == nil {
                try? await removeShowFromWatchlist(userId: userId, showId: show.showId)
                print("🧹 Removed orphaned watchlist show: \(show.showId)")
            }
        }

        // Remove movies that don't exist in movies table
        for movie in watchlistMovies {
            if (try? await fetchMovieById(id: movie.movieId)) == nil {
                try? await removeFromWatchlistMovie(id: movie.id)
                print("🧹 Removed orphaned watchlist movie: \(movie.movieId)")
            }
        }
    }

    func removeDuplicatesFromWatchlist() async throws {
        guard let userId = currentUser?.id else { return }

        // Get shows in both watchlist and user_shows
        let watchlistShows = (try? await fetchWatchlistShows(userId: userId)) ?? []
        let userShows = (try? await fetchUserShows(userId: userId)) ?? []
        let libraryShowIds = Set(userShows.map { $0.showId })

        // Remove from watchlist if also in library
        for show in watchlistShows {
            if libraryShowIds.contains(show.showId) {
                try? await removeShowFromWatchlist(userId: userId, showId: show.showId)
                print("🧹 Removed duplicate show from watchlist: \(show.showId)")
            }
        }
    }

    func mergeMaxIntoHBOMax() async throws {
        guard let userId = currentUser?.id else { return }

        // Find the Max and HBO Max platform IDs
        let platforms = try await getStreamingPlatforms()
        guard let maxPlatform = platforms.first(where: { $0.display_name == "Max" }),
              let hboMaxPlatform = platforms.first(where: { $0.display_name == "HBO Max" }) else {
            print("Max or HBO Max platform not found")
            return
        }

        // Update user_streaming_preferences to replace Max with HBO Max
        let endpoint = "\(supabaseURL)/rest/v1/user_streaming_preferences?user_id=eq.\(userId)&streaming_platform_id=eq.\(maxPlatform.id)"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        struct UpdateBody: Encodable {
            let streaming_platform_id: Int
        }

        let body = UpdateBody(streaming_platform_id: hboMaxPlatform.id)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 200 || statusCode == 204 {
            print("✅ Successfully merged Max into HBO Max")
        } else {
            let responseStr = String(data: data, encoding: .utf8) ?? ""
            print("⚠️ Failed to merge Max into HBO Max: status=\(statusCode), response=\(responseStr)")
        }
    }
}

// MARK: - Data Management

extension SupabaseService {
    func clearUserData() async throws {
        guard let userId = currentUser?.id else { return }

        let deleteEpisodesEndpoint = "\(supabaseURL)/rest/v1/episodes?user_id=eq.\(userId)"
        try await deleteRequest(endpoint: deleteEpisodesEndpoint)

        let deleteShowsEndpoint = "\(supabaseURL)/rest/v1/user_shows?user_id=eq.\(userId)"
        try await deleteRequest(endpoint: deleteShowsEndpoint)

        let deleteMoviesEndpoint = "\(supabaseURL)/rest/v1/user_movies?user_id=eq.\(userId)"
        try await deleteRequest(endpoint: deleteMoviesEndpoint)
    }

    func removeShowFromLibrary(userId: String, showId: Int) async throws {
        // Delete all episodes for this show
        try await deleteEpisodesByShowId(showId: showId, userId: userId)

        // Delete the show from user_shows
        let endpoint = "\(supabaseURL)/rest/v1/user_shows?user_id=eq.\(userId)&show_id=eq.\(showId)"
        try await deleteRequest(endpoint: endpoint)
    }

    func removeMovieFromLibrary(userId: String, movieId: Int) async throws {
        // Delete the movie from user_movies
        let endpoint = "\(supabaseURL)/rest/v1/user_movies?user_id=eq.\(userId)&movie_id=eq.\(movieId)"
        try await deleteRequest(endpoint: endpoint)
    }

    private func deleteRequest(endpoint: String) async throws {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "DELETE"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue(authToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "DeleteError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to delete data"])
        }
    }

    // MARK: - Reconciliation

    func reconcileWatchlistWithTables() async {
        print("Starting watchlist reconciliation...")
        var showsReconciled = 0
        var moviesReconciled = 0
        var showsFailed = 0
        var moviesFailed = 0

        // Reconcile shows
        do {
            let watchlistShows = try await fetchWatchlistShows(userId: currentUser?.id ?? "")
            for watchlistShow in watchlistShows {
                if (try? await fetchShowById(id: watchlistShow.showId)) != nil {
                    print("Show \(watchlistShow.showId) already exists in tv_shows")
                    continue
                }
                do {
                    let tmdbShow = try await TMDBService.shared.getTVShow(id: watchlistShow.showId)
                    let show = TVShow(id: watchlistShow.showId, tmdbId: watchlistShow.showId,
                                    title: tmdbShow.name, overview: tmdbShow.overview,
                                    posterUrl: tmdbShow.imageUrl, firstAirDate: tmdbShow.firstAirDate,
                                    numberOfSeasons: tmdbShow.numberOfSeasons,
                                    numberOfEpisodes: tmdbShow.numberOfEpisodes)
                    try await insertShow(show: show)
                    print("✅ Inserted show \(watchlistShow.showId): \(tmdbShow.name)")
                    showsReconciled += 1
                } catch {
                    print("❌ Failed to reconcile show \(watchlistShow.showId): \(error.localizedDescription)")
                    showsFailed += 1
                }
            }
        } catch {
            print("Error fetching watchlist shows: \(error)")
        }

        // Reconcile movies
        do {
            let watchlistMovies = try await fetchWatchlistMovies(userId: currentUser?.id ?? "")
            for watchlistMovie in watchlistMovies {
                if (try? await fetchMovieById(id: watchlistMovie.movieId)) != nil {
                    print("Movie \(watchlistMovie.movieId) already exists in movies")
                    continue
                }
                do {
                    let tmdbMovie = try await TMDBService.shared.getMovie(id: watchlistMovie.movieId)
                    let movie = Movie(id: watchlistMovie.movieId, tmdbId: watchlistMovie.movieId,
                                    title: tmdbMovie.title, overview: tmdbMovie.overview,
                                    posterUrl: tmdbMovie.imageUrl, releaseDate: tmdbMovie.releaseDate)
                    try await insertMovie(movie: movie)
                    print("✅ Inserted movie \(watchlistMovie.movieId): \(tmdbMovie.title)")
                    moviesReconciled += 1
                } catch {
                    print("❌ Failed to reconcile movie \(watchlistMovie.movieId): \(error.localizedDescription)")
                    moviesFailed += 1
                }
            }
        } catch {
            print("Error fetching watchlist movies: \(error)")
        }

        print("Reconciliation complete: \(showsReconciled) shows and \(moviesReconciled) movies added. Failed: \(showsFailed) shows, \(moviesFailed) movies")
    }
}
