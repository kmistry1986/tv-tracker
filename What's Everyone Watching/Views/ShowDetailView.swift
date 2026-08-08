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
    @State private var showCompleteShowConfirmation = false
    @State private var showCompleteSeasonModal = false
    @State private var isInLibrary = false
    @State private var showRatingPrompt = false
    @State private var shouldOpenRatingAfterComplete = false
    @State private var showRatingModal = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
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

                if isInLibrary {
                    HStack(spacing: 12) {
                        Button(action: { showCompleteShowConfirmation = true }) {
                            Text("Complete Show")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }

                        Button(action: { showCompleteSeasonModal = true }) {
                            Text("Complete Seasons")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.purple)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

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
            .navigationTitle(showTitle)
            .onAppear {
                loadShowDetails()
            }
            .alert("Complete Show?", isPresented: $showCompleteShowConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Complete") {
                    Task {
                        await completeEntireShow()
                    }
                }
                Button("Complete and Rate", role: .destructive) {
                    shouldOpenRatingAfterComplete = true
                    Task {
                        await completeEntireShow()
                    }
                }
            } message: {
                Text("Mark all episodes in this show as watched?")
            }
            .fullScreenCover(isPresented: $showCompleteSeasonModal) {
                CompleteSeasonModal(
                    showId: showId,
                    showTitle: showTitle,
                    watchedEpisodes: watchedEpisodes,
                    episodesBySeason: episodesBySeason
                ) { watchedSeasons, unwatchedSeasons in
                    Task {
                        await saveSeasonChanges(watchedSeasons: watchedSeasons, unwatchedSeasons: unwatchedSeasons)
                        showCompleteSeasonModal = false
                    }
                }
            }
            .alert("Rate This Show?", isPresented: $showRatingPrompt) {
                Button("Rate Now") {
                    // Rating is already shown in the header, just dismiss
                    showRatingPrompt = false
                }
                Button("Not Now", role: .cancel) { }
            } message: {
                Text("You've finished watching. Would you like to rate this show?")
            }
            .sheet(isPresented: $showRatingModal) {
                RatingView(title: showTitle, mediaType: "tv", itemId: showId, isMovie: false)
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
                watchedEpisodes = Set(episodes.filter { $0.watched }.compactMap { $0.id })

                // Load rating from user_shows and check if in library
                let userShows = try await supabase.fetchUserShows(userId: userId)
                let userShow = userShows.first { $0.showId == showId }
                let inLibrary = userShow != nil

                DispatchQueue.main.async {
                    self.rating = userShow?.rating
                    self.isInLibrary = inLibrary
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
                try await supabase.updateRating(userId: userId, itemId: showId, rating: newRating, isMovie: false)
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

    private func completeEntireShow() async {
        do {
            // Mark all episodes as watched
            for seasonNum in seasons {
                if let episodes = episodesBySeason[seasonNum] {
                    for episode in episodes {
                        try await supabase.updateEpisodeWatched(episodeId: episode.id, watched: true)
                        DispatchQueue.main.async {
                            watchedEpisodes.insert(episode.id)
                        }
                    }
                }
            }
            loadShowDetails()

            // Check if user has rated - if not, prompt them or force rating modal
            DispatchQueue.main.async {
                if shouldOpenRatingAfterComplete {
                    showRatingModal = true
                    shouldOpenRatingAfterComplete = false
                } else if rating == nil {
                    showRatingPrompt = true
                }
            }
        } catch {
            print("Error completing show: \(error)")
        }
    }

    private func saveWatchedEpisodes(_ episodeIds: [Int]) async {
        do {
            for episodeId in episodeIds {
                try await supabase.updateEpisodeWatched(episodeId: episodeId, watched: true)
                DispatchQueue.main.async {
                    watchedEpisodes.insert(episodeId)
                }
            }
            loadShowDetails()
        } catch {
            print("Error saving watched episodes: \(error)")
        }
    }

    private func saveSeasonChanges(watchedSeasons: [Int], unwatchedSeasons: [Int]) async {
        do {
            // Mark newly checked seasons as watched
            for seasonNum in watchedSeasons {
                if let episodes = episodesBySeason[seasonNum] {
                    for episode in episodes {
                        try await supabase.updateEpisodeWatched(episodeId: episode.id, watched: true)
                        DispatchQueue.main.async {
                            watchedEpisodes.insert(episode.id)
                        }
                    }
                }
            }

            // Mark newly unchecked seasons as unwatched
            for seasonNum in unwatchedSeasons {
                if let episodes = episodesBySeason[seasonNum] {
                    for episode in episodes {
                        try await supabase.updateEpisodeWatched(episodeId: episode.id, watched: false)
                        DispatchQueue.main.async {
                            watchedEpisodes.remove(episode.id)
                        }
                    }
                }
            }

            loadShowDetails()

            // Check if user has rated - if not and they've completed seasons, prompt them
            DispatchQueue.main.async {
                if rating == nil && !watchedSeasons.isEmpty {
                    showRatingPrompt = true
                }
            }
        } catch {
            print("Error saving season changes: \(error)")
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
