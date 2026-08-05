import Foundation
import Combine

class TMDBService: NSObject, ObservableObject {
    static let shared = TMDBService()
    
    let apiKey = "a5c6205d661a81dfc1a85361cfb631d4"
    let baseURL = "https://api.themoviedb.org/3"
    let imageBaseURL = "https://image.tmdb.org/t/p/w500"
    
    override private init() {
        super.init()
    }
    
    // MARK: - Search
    
    func searchMulti(query: String) async throws -> [SearchResult] {
        let endpoint = "\(baseURL)/search/multi"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query)
        ]
        
        let response: MultiSearchResponse = try await fetch(url: components.url!)
        return response.results
    }
    
    func searchTV(query: String) async throws -> [TVSearchResult] {
        let endpoint = "\(baseURL)/search/tv"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query)
        ]
        
        let response: TVSearchResponse = try await fetch(url: components.url!)
        return response.results
    }
    
    func searchMovie(query: String) async throws -> [MovieSearchResult] {
        let endpoint = "\(baseURL)/search/movie"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query)
        ]
        
        let response: MovieSearchResponse = try await fetch(url: components.url!)
        return response.results
    }
    
    // MARK: - Details
    
    func getTVShow(id: Int) async throws -> TVShowDetail {
        let endpoint = "\(baseURL)/tv/\(id)"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        
        return try await fetch(url: components.url!)
    }
    
    func getTVSeason(showId: Int, seasonNumber: Int) async throws -> SeasonDetail {
        let endpoint = "\(baseURL)/tv/\(showId)/season/\(seasonNumber)"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        
        return try await fetch(url: components.url!)
    }
    
    func getMovie(id: Int) async throws -> MovieDetail {
        let endpoint = "\(baseURL)/movie/\(id)"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        return try await fetch(url: components.url!)
    }

    // MARK: - Trending

    func getTrendingTV() async throws -> [SearchResult] {
        let endpoint = "\(baseURL)/trending/tv/day"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        let response: MultiSearchResponse = try await fetch(url: components.url!)
        return response.results.filter { $0.mediaType == "tv" }
    }

    func getTrendingMovies() async throws -> [SearchResult] {
        let endpoint = "\(baseURL)/trending/movie/day"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        let response: MultiSearchResponse = try await fetch(url: components.url!)
        return response.results.filter { $0.mediaType == "movie" }
    }

    // MARK: - Private
    
    private func fetch<T: Decodable>(url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "TMDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Request failed"])
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Response Models

struct MultiSearchResponse: Decodable {
    let results: [SearchResult]
}

struct SearchResult: Identifiable, Decodable {
    let id: Int?
    let mediaType: String
    let name: String?
    let title: String?
    let posterPath: String?
    let overview: String?
    
    var displayTitle: String {
        name ?? title ?? ""
    }
    
    var imageUrl: String? {
        guard let path = posterPath else { return nil }
        return "\(TMDBService.shared.imageBaseURL)\(path)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case name
        case title
        case posterPath = "poster_path"
        case overview
    }
}

struct TVSearchResponse: Decodable {
    let results: [TVSearchResult]
}

struct TVSearchResult: Identifiable, Decodable {
    let id: Int
    let name: String
    let posterPath: String?
    let overview: String?
    let firstAirDate: String?
    
    var imageUrl: String? {
        guard let path = posterPath else { return nil }
        return "\(TMDBService.shared.imageBaseURL)\(path)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case posterPath = "poster_path"
        case overview
        case firstAirDate = "first_air_date"
    }
}

struct TVShowDetail: Decodable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let firstAirDate: String?
    let numberOfSeasons: Int
    let numberOfEpisodes: Int
    let status: String?
    let genres: [TVGenre]?

    var imageUrl: String? {
        guard let path = posterPath else { return nil }
        return "\(TMDBService.shared.imageBaseURL)\(path)"
    }

    var displayStatus: String {
        status ?? "Unknown"
    }

    var displayGenres: String {
        genres?.map { $0.name }.joined(separator: ", ") ?? "Unknown"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case status
        case genres
    }
}

struct TVGenre: Decodable {
    let id: Int
    let name: String
}

struct SeasonDetail: Decodable {
    let episodes: [EpisodeDetail]
}

struct EpisodeDetail: Identifiable, Decodable {
    let id: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String
    let overview: String?
    let airDate: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case name
        case overview
        case airDate = "air_date"
    }
}

struct MovieSearchResponse: Decodable {
    let results: [MovieSearchResult]
}

struct MovieSearchResult: Identifiable, Decodable {
    let id: Int
    let title: String
    let posterPath: String?
    let overview: String?
    let releaseDate: String?
    
    var imageUrl: String? {
        guard let path = posterPath else { return nil }
        return "\(TMDBService.shared.imageBaseURL)\(path)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case posterPath = "poster_path"
        case overview
        case releaseDate = "release_date"
    }
}

struct MovieDetail: Decodable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let releaseDate: String?
    
    var imageUrl: String? {
        guard let path = posterPath else { return nil }
        return "\(TMDBService.shared.imageBaseURL)\(path)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
    }
}
