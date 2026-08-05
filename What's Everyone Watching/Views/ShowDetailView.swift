import SwiftUI

struct ShowDetailView: View {
    let showId: Int
    let showTitle: String
    @StateObject private var tmdb = TMDBService.shared
    @StateObject private var supabase = SupabaseService.shared
    @State private var showDetails: TVShowDetail?
    @State private var seasons: [Int] = []
    @State private var selectedSeason = 1
    @State private var episodesBySeason: [Int: [EpisodeDetail]] = [:]
    @State private var watchedEpisodes: Set<Int> = []
    @State private var rating: Int? = nil
    @State private var isLoading = false
    @State private var isUpdatingRating = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(showTitle)
                            .font(.headline)

                        if let rating = rating {
                            HStack(spacing: 8) {
                                Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 10 - rating))
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("\(rating)/10")
                                    .font(.caption)
                                    .foregroundColor(.orange)

                                HStack(spacing: 2) {
                                    Button(action: { updateRating(max(1, rating - 1)) }) {
                                        Image(systemName: "minus.circle")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                    Button(action: { updateRating(min(10, rating + 1)) }) {
                                        Image(systemName: "plus.circle")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                if isLoading {
                    VStack {
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if seasons.isEmpty {
                    VStack {
                        Text("No episodes found")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        // Show info and description
                        if let showDetails = showDetails {
                            VStack(alignment: .leading, spacing: 12) {
                                // Status and genres
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Status")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                        Text(showDetails.displayStatus)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Genres")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                        Text(showDetails.displayGenres)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }

                                    Spacer()
                                }

                                // Description
                                if !showDetails.overview.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("About")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                        Text(showDetails.overview)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(nil)
                                    }
                                }
                            }
                            .padding()

                            Divider()
                        }

                        // Season selector
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(seasons, id: \.self) { season in
                                    Button(action: { selectedSeason = season }) {
                                        Text("Season \(season)")
                                            .font(.caption)
                                            .fontWeight(selectedSeason == season ? .bold : .regular)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(selectedSeason == season ? Color.blue : Color.gray.opacity(0.2))
                                            .foregroundColor(selectedSeason == season ? .white : .primary)
                                            .cornerRadius(6)
                                    }
                                }
                            }
                            .padding()
                        }

                        Divider()

                        // Episodes list
                        if let episodes = episodesBySeason[selectedSeason], !episodes.isEmpty {
                            List {
                                ForEach(episodes, id: \.id) { episode in
                                    EpisodeRow(
                                        episode: episode,
                                        isWatched: watchedEpisodes.contains(episode.id),
                                        onToggleWatched: {
                                            toggleEpisodeWatched(episodeId: episode.id, showId: showId)
                                        }
                                    )
                                }
                            }
                        } else {
                            VStack {
                                Text("No episodes for this season")
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Episodes")
            .onAppear {
                loadShowDetails()
            }
        }
    }

    private func loadShowDetails() {
        isLoading = true
        Task {
            do {
                guard let userId = supabase.currentUser?.id else {
                    DispatchQueue.main.async {
                        isLoading = false
                    }
                    return
                }

                let details = try await tmdb.getTVShow(id: showId)
                showDetails = details

                // Generate season numbers
                seasons = Array(1...details.numberOfSeasons)

                // Fetch all seasons' episodes
                for season in seasons {
                    let seasonDetail = try await tmdb.getTVSeason(showId: showId, seasonNumber: season)
                    episodesBySeason[season] = seasonDetail.episodes
                }

                // Load watched episodes from database
                let episodes = try await supabase.fetchEpisodes(showId: showId, userId: userId)
                watchedEpisodes = Set(episodes.filter { $0.watched }.map { $0.id })

                // Load rating from user_shows
                let userShows = try await supabase.fetchUserShows(userId: userId)
                let userShow = userShows.first { $0.showId == showId }

                DispatchQueue.main.async {
                    self.rating = userShow?.rating
                    isLoading = false
                }
            } catch {
                print("Error loading show details: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }

    private func toggleEpisodeWatched(episodeId: Int, showId: Int) {
        if watchedEpisodes.contains(episodeId) {
            watchedEpisodes.remove(episodeId)
        } else {
            watchedEpisodes.insert(episodeId)
        }

        Task {
            do {
                let isWatched = watchedEpisodes.contains(episodeId)
                try await supabase.updateEpisodeWatched(episodeId: episodeId, watched: isWatched)
            } catch {
                print("Error updating episode: \(error)")
                if watchedEpisodes.contains(episodeId) {
                    watchedEpisodes.remove(episodeId)
                } else {
                    watchedEpisodes.insert(episodeId)
                }
            }
        }
    }

    private func updateRating(_ newRating: Int) {
        isUpdatingRating = true
        Task {
            do {
                guard let userId = supabase.currentUser?.id else { return }
                try await supabase.updateShowRating(showId: showId, userId: userId, rating: newRating)
            } catch {
                print("Error updating rating: \(error)")
                // Revert rating on error
                DispatchQueue.main.async {
                    self.rating = rating
                }
            }
            DispatchQueue.main.async {
                isUpdatingRating = false
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: EpisodeDetail
    let isWatched: Bool
    var onToggleWatched: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleWatched) {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isWatched ? .green : .gray)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("E\(episode.episodeNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)

                    Text(episode.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }

                if let airDate = episode.airDate {
                    Text(airDate)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ShowDetailView(showId: 1399, showTitle: "Breaking Bad")
}
