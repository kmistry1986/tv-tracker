import SwiftUI

struct TVShowDetailView: View {
    let showId: Int

    @StateObject private var tmdb = TMDBService.shared
    @StateObject private var supabase = SupabaseService.shared
    @State private var show: TVShowDetail?
    @State private var watchProviders: WatchProvidersResult?
    @State private var userPlatforms: Set<String> = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var isInLibrary = false
    @State private var isInWatchlist = false
    @State private var hasRating = false
    @State private var showMarkWatchedModal = false
    @State private var showRatingModal = false
    @State private var showWatchlistModal = false

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding()
            } else if let show = show {
                VStack(alignment: .leading, spacing: 20) {
                    // Title header
                    Text("Show Details")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal)
                        .padding(.top, 10)

                    // Header with poster and basic info
                    headerSection(show: show)
                    
                    // Watch Providers
                    if let providers = watchProviders {
                        WatchProvidersView(providers: providers, userPlatforms: userPlatforms)
                            .padding(.horizontal)
                    }
                    
                    // Overview
                    overviewSection(show: show)
                    
                    // Show Details
                    detailsSection(show: show)
                    
                    // Action Buttons
                    actionButtonsSection(show: show)
                }
                .padding(.bottom)
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Error Loading Show")
                        .font(.headline)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadShowDetails()
            loadUserPlatforms()
        }
        .sheet(isPresented: $showMarkWatchedModal) {
            MarkWatchedModal(showId: showId, showTitle: show?.name ?? "Show") { selectedEpisodeIds in
                saveWatchedEpisodes(selectedEpisodeIds)
            }
        }
        .sheet(isPresented: $showRatingModal) {
            RatingView(title: show?.name ?? "Show", mediaType: "tv", itemId: showId, isMovie: false)
        }
        .sheet(isPresented: $showWatchlistModal) {
            WatchlistPriorityModal(showTitle: show?.name ?? "Show", isMovie: false) { priority, notes in
                addToWatchlistWithDetails(priority: priority, notes: notes)
            }
        }
    }
    
    // MARK: - Header Section
    
    private func headerSection(show: TVShowDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Poster
            if let imageUrl = show.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 120, height: 180)
                .cornerRadius(12)
                .shadow(radius: 5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(show.name)
                    .font(.title2)
                    .fontWeight(.bold)

                if let firstAirDate = show.firstAirDate {
                    Label(firstAirDate.prefix(4), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Label(show.displayType, systemImage: "tv")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("\(show.numberOfSeasons) Season\(show.numberOfSeasons == 1 ? "" : "s")", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("\(show.numberOfEpisodes) Episode\(show.numberOfEpisodes == 1 ? "" : "s")", systemImage: "film")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !show.displayGenres.isEmpty && show.displayGenres != "Unknown" {
                    Text(show.displayGenres)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding()
    }
    
    // MARK: - Overview Section
    
    private func overviewSection(show: TVShowDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            
            Text(show.overview)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Details Section
    
    private func detailsSection(show: TVShowDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            VStack(spacing: 8) {
                DetailRow(label: "Status", value: show.displayStatus)
                DetailRow(label: "First Aired", value: show.firstAirDate ?? "Unknown")
                DetailRow(label: "Seasons", value: "\(show.numberOfSeasons)")
                DetailRow(label: "Total Episodes", value: "\(show.numberOfEpisodes)")
                if !show.displayGenres.isEmpty && show.displayGenres != "Unknown" {
                    DetailRow(label: "Genres", value: show.displayGenres)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Action Buttons
    
    private func actionButtonsSection(show: TVShowDetail) -> some View {
        HStack(spacing: 12) {
            if isInLibrary {
                NavigationLink(destination: ShowDetailView(showId: showId, showTitle: show.name)) {
                    VStack(spacing: 2) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 12))
                        Text("View in")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text("Library")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                Button(action: addToLibrary) {
                    VStack(spacing: 2) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 12))
                        Text("Add to")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text("Library")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }

            if isInWatchlist {
                NavigationLink(destination: WatchlistView()) {
                    VStack(spacing: 2) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                        Text("View in")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text("Watchlist")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                Button(action: addToWatchlist) {
                    VStack(spacing: 2) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                        Text("Add to")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text("Watchlist")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }

            ZStack(alignment: .topTrailing) {
                Button(action: rateShow) {
                    VStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                        Text("Rate")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text("Show")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                if hasRating {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                        .offset(x: 6, y: -6)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Loading

    private func loadShowDetails() async {
        isLoading = true
        error = nil

        do {
            // Load show details and watch providers concurrently
            async let showData = tmdb.getTVShow(id: showId)
            async let providersData = tmdb.getTVWatchProviders(tvId: showId)

            self.show = try await showData
            self.watchProviders = try await providersData

            // Check if show is in library and watchlist
            guard let userId = supabase.currentUser?.id else { return }
            let inLibrary = try await supabase.isShowInLibrary(userId: userId, showId: showId)
            let inWatchlist = try await supabase.isShowInWatchlist(userId: userId, showId: showId)

            DispatchQueue.main.async {
                self.isInLibrary = inLibrary
                self.isInWatchlist = inWatchlist
            }
        } catch {
            self.error = error.localizedDescription
            print("Error loading show details: \(error)")
        }

        isLoading = false
    }

    private func loadUserPlatforms() {
        guard let userId = supabase.currentUser?.id else { return }

        Task {
            do {
                let platformIds = try await supabase.getUserPlatforms(userId: userId)
                let platformNames = platformIds.compactMap { StreamingPlatformMapper.getDisplayName(for: $0) }
                DispatchQueue.main.async {
                    self.userPlatforms = Set(platformNames)
                }
            } catch {
                print("Error loading user platforms: \(error)")
            }
        }
    }

    private func addToLibrary() {
        showMarkWatchedModal = true
    }

    private func addToWatchlist() {
        showWatchlistModal = true
    }

    private func addToWatchlistWithDetails(priority: String, notes: String?) {
        guard let userId = supabase.currentUser?.id else { return }

        Task {
            do {
                try await supabase.addToWatchlistShow(userId: userId, showId: showId, priority: priority, notes: notes)
                DispatchQueue.main.async {
                    self.isInWatchlist = true
                }
            } catch {
                print("Error adding to watchlist: \(error)")
            }
        }
    }

    private func rateShow() {
        showRatingModal = true
    }

    private func saveWatchedEpisodes(_ episodeIds: [Int]) {
        guard let userId = supabase.currentUser?.id else {
            print("Error: User not logged in")
            return
        }
        Task {
            do {
                // ALWAYS ensure the show exists in tv_shows table first (required for foreign key)
                if let show = show {
                    let tvShow = TVShow(
                        id: show.id,
                        tmdbId: show.id,
                        title: show.name,
                        overview: show.overview,
                        posterUrl: show.posterPath.flatMap { "https://image.tmdb.org/t/p/w500\($0)" },
                        firstAirDate: show.firstAirDate,
                        numberOfSeasons: show.numberOfSeasons,
                        numberOfEpisodes: show.numberOfEpisodes,
                        platforms: nil
                    )
                    try await supabase.insertShow(show: tvShow)
                    print("✅ Show inserted to tv_shows table")
                }

                // Check if already in library to avoid duplicate user_shows entry
                let alreadyInLibrary = try await supabase.isShowInLibrary(userId: userId, showId: showId)
                if !alreadyInLibrary {
                    print("Adding show to library: showId=\(showId)")
                    try await supabase.insertUserShow(userId: userId, showId: showId, watchedDate: ISO8601DateFormatter().string(from: Date()))
                    DispatchQueue.main.async {
                        self.isInLibrary = true
                        print("✅ Show added to library")
                    }
                } else {
                    print("Show already in library")
                }

                // If marking entire show as watched (empty array), fetch all episodes and mark them
                if episodeIds.isEmpty && show != nil {
                    print("Marking entire show as watched: \(show!.numberOfSeasons) seasons")
                    let now = ISO8601DateFormatter().string(from: Date())
                    for seasonNum in 1...show!.numberOfSeasons {
                        let seasonDetail = try await tmdb.getTVSeason(showId: showId, seasonNumber: seasonNum)
                        for episode in seasonDetail.episodes {
                            let episodeRecord = Episode(
                                id: nil,
                                showId: showId,
                                tmdbId: episode.id,
                                seasonNumber: episode.seasonNumber,
                                episodeNumber: episode.episodeNumber,
                                name: episode.name,
                                overview: episode.overview ?? "",
                                airDate: episode.airDate,
                                userId: userId,
                                watched: true,
                                watchedAt: now,
                                showTitle: show?.name
                            )
                            try await supabase.insertEpisode(episode: episodeRecord)
                        }
                    }
                    print("✅ All episodes marked as watched")
                } else {
                    // Mark selected episodes as watched
                    for episodeId in episodeIds {
                        print("Marking episode \(episodeId) as watched")
                    }
                }
            } catch {
                print("❌ Error saving watched episodes: \(error)")
                DispatchQueue.main.async {
                    self.isInLibrary = false
                }
            }
        }
    }
}

// MARK: - Detail Row Component

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TVShowDetailView(showId: 1396) // Breaking Bad
    }
}
