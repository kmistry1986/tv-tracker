import Foundation

struct TVShow: Identifiable, Codable {
    let id: Int
    let tmdbId: Int
    let title: String
    let overview: String
    let posterUrl: String?
    let firstAirDate: String?
    let numberOfSeasons: Int
    let numberOfEpisodes: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case tmdbId = "tmdb_id"
        case title
        case overview
        case posterUrl = "poster_url"
        case firstAirDate = "first_air_date"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
    }
}

struct Episode: Identifiable, Codable {
    let id: Int? // Database surrogate key (read-only, auto-generated)
    let showId: Int
    let tmdbId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String
    let overview: String
    let airDate: String?
    let userId: String?
    let watched: Bool
    let watchedAt: String?
    let showTitle: String?

    enum CodingKeys: String, CodingKey {
        case id = "id_surrogate"
        case showId = "show_id"
        case tmdbId = "tmdb_id"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case name
        case overview
        case airDate = "air_date"
        case userId = "user_id"
        case watched
        case watchedAt = "watched_at"
        case showTitle = "show_title"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Don't send id_surrogate on INSERT — Supabase auto-generates it
        try container.encode(showId, forKey: .showId)
        try container.encode(tmdbId, forKey: .tmdbId)
        try container.encode(seasonNumber, forKey: .seasonNumber)
        try container.encode(episodeNumber, forKey: .episodeNumber)
        try container.encode(name, forKey: .name)
        try container.encode(overview, forKey: .overview)
        try container.encode(airDate, forKey: .airDate)
        try container.encode(userId, forKey: .userId)
        try container.encode(watched, forKey: .watched)
        try container.encode(watchedAt, forKey: .watchedAt)
        try container.encode(showTitle, forKey: .showTitle)
    }
}

struct Movie: Identifiable, Codable {
    let id: Int
    let tmdbId: Int
    let title: String
    let overview: String
    let posterUrl: String?
    let releaseDate: String?
    let runtime: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case tmdbId = "tmdb_id"
        case title
        case overview
        case posterUrl = "poster_url"
        case releaseDate = "release_date"
        case runtime
    }
}

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let name: String
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case avatarUrl = "avatar_url"
    }
}

struct UserEpisode: Identifiable, Codable {
    let id: Int
    let userId: String
    let episodeId: Int
    let watchedDate: String
    let rating: Int?
    let review: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case episodeId = "episode_id"
        case watchedDate = "watched_date"
        case rating
        case review
        case createdAt = "created_at"
    }
}

struct UserShow: Identifiable, Codable {
    let id: Int
    let userId: String
    let showId: Int
    let watchedDate: String
    let rating: Int?
    let review: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case showId = "show_id"
        case watchedDate = "watched_date"
        case rating
        case review
        case createdAt = "created_at"
    }
}

struct UserMovie: Identifiable, Codable {
    let id: Int
    let userId: String
    let movieId: Int
    let watchedDate: String
    let rating: Int?
    let review: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case movieId = "movie_id"
        case watchedDate = "watched_date"
        case rating
        case review
        case createdAt = "created_at"
    }
}

struct ActivityFeedItem: Identifiable, Codable {
    let id: Int
    let userId: String
    let friendId: String?
    let actionType: String
    let episodeId: Int?
    let movieId: Int?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case friendId = "friend_id"
        case actionType = "action_type"
        case episodeId = "episode_id"
        case movieId = "movie_id"
        case createdAt = "created_at"
    }
}

struct WatchlistShow: Identifiable, Codable {
    let id: Int
    let userId: String
    let showId: Int
    let priority: String
    let notes: String?
    let addedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case showId = "show_id"
        case priority
        case notes
        case addedAt = "added_at"
    }
}

struct WatchlistMovie: Identifiable, Codable {
    let id: Int
    let userId: String
    let movieId: Int
    let priority: String
    let notes: String?
    let addedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case movieId = "movie_id"
        case priority
        case notes
        case addedAt = "added_at"
    }
}

struct Friendship: Identifiable, Codable {
    let id: Int
    let userId: String
    let friendId: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case friendId = "friend_id"
        case status
        case createdAt = "created_at"
    }
}

struct UserProfile: Identifiable, Codable {
    let id: Int
    let userId: String
    let displayName: String
    let bio: String?
    let avatarUrl: String?
    let isPublic: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case isPublic = "is_public"
        case createdAt = "created_at"
    }
}
