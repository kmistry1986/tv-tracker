import SwiftUI

struct HomeView: View {
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var tmdb = TMDBService.shared
    @State private var trendingShows: [SearchResult] = []
    @State private var trendingMovies: [SearchResult] = []
    @State private var partiallyWatchedShows: [LibraryShowWithDetails] = []
    @State private var libraryCount = 0
    @State private var watchlistCount = 0
    @State private var ratedCount = 0
    @State private var isLoading = false
    @State private var showSearchOverlay = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search section that expands
                    VStack(spacing: 0) {
                        // Search bar (hidden when search is active)
                        if !showSearchOverlay {
                            searchButtonSection
                                .padding(.horizontal)
                                .padding(.top, 10)
                        }

                        // Search results expand below the bar
                        if showSearchOverlay {
                            searchResultsSection
                        }
                    }
                    .background(Color(.systemBackground))
                    .zIndex(1)
                    
                    // Main content (hidden when searching)
                    if !showSearchOverlay {
                        ScrollView {
                            VStack(spacing: 24) {
                                if !partiallyWatchedShows.isEmpty {
                                    continueWatchingSection
                                }

                                if !trendingShows.isEmpty {
                                    trendingShowsSection
                                }

                                if !trendingMovies.isEmpty {
                                    trendingMoviesSection
                                }

                                statsSection
                            }
                            .padding(.horizontal)
                            .padding(.top, 24)
                        }
                    }
                }
            }
            .navigationTitle("TV Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadTrendingContent()
                loadStats()
                loadPartiallyWatched()
            }
        }
    }
    
    private var searchButtonSection: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showSearchOverlay = true
            }
        }) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                Text("Search for shows and movies...")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var searchResultsSection: some View {
        ExpandedSearchView(isPresented: $showSearchOverlay)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }

    private var continueWatchingSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Continue where you left off")
                    .font(.headline)

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(partiallyWatchedShows, id: \.id) { show in
                        NavigationLink(destination: ShowDetailView(showId: show.showId, showTitle: show.showTitle)) {
                            VStack(spacing: 8) {
                                if let imageUrl = show.posterUrl, let url = URL(string: imageUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Color.gray
                                    }
                                    .frame(width: 100, height: 150)
                                    .cornerRadius(8)
                                } else {
                                    Color.gray
                                        .frame(width: 100, height: 150)
                                        .cornerRadius(8)
                                }

                                VStack(spacing: 4) {
                                    Text(show.showTitle)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    if let lastEpisode = show.lastWatchedEpisode {
                                        Text(lastEpisode)
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }

                                    Text("\(show.watchedEpisodes)/\(show.totalEpisodes)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                .frame(width: 100)
                            }
                            .frame(width: 100)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    private var trendingShowsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Trending TV Shows")
                    .font(.headline)

                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(trendingShows.prefix(10), id: \.id) { show in
                        if let showId = show.id {
                            NavigationLink(destination: TVShowDetailView(showId: showId)) {
                                VStack(spacing: 8) {
                                    if let imageUrl = show.imageUrl, let url = URL(string: imageUrl) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Color.gray
                                        }
                                        .frame(width: 100, height: 150)
                                        .cornerRadius(8)
                                    } else {
                                        Color.gray
                                            .frame(width: 100, height: 150)
                                            .cornerRadius(8)
                                    }

                                    Text(show.displayTitle)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 100, height: 36, alignment: .center)
                                }
                                .frame(width: 100)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }
    
    private var trendingMoviesSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Trending Movies")
                    .font(.headline)

                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(trendingMovies.prefix(10), id: \.id) { movie in
                        if let movieId = movie.id {
                            NavigationLink(destination: MovieDetailView(movieId: movieId)) {
                                VStack(spacing: 8) {
                                    if let imageUrl = movie.imageUrl, let url = URL(string: imageUrl) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Color.gray
                                        }
                                        .frame(width: 100, height: 150)
                                        .cornerRadius(8)
                                    } else {
                                        Color.gray
                                            .frame(width: 100, height: 150)
                                            .cornerRadius(8)
                                    }

                                    Text(movie.displayTitle)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 100, height: 36, alignment: .center)
                                }
                                .frame(width: 100)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }
    
    private var statsSection: some View {
        VStack(spacing: 12) {
            Text("Your Stats")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                StatCard(icon: "tv.fill", title: "Shows", value: String(libraryCount), color: .blue)
                StatCard(icon: "bookmark.fill", title: "Watchlist", value: String(watchlistCount), color: .green)
                StatCard(icon: "star.fill", title: "Rated", value: String(ratedCount), color: .orange)
            }
        }
    }
    
    private func loadTrendingContent() {
        isLoading = true
        Task {
            do {
                // Load trending TV shows and movies concurrently
                async let shows = tmdb.getTrendingTV(timeWindow: .week)
                async let movies = tmdb.getTrendingMovies(timeWindow: .week)
                
                self.trendingShows = try await shows
                self.trendingMovies = try await movies
            } catch {
                print("Error loading trending content: \(error)")
            }
            isLoading = false
        }
    }
    
    private func loadStats() {
        guard let userId = supabase.currentUser?.id else { return }

        Task {
            do {
                let userShows = try await supabase.fetchUserShows(userId: userId)
                let userMovies = try await supabase.fetchUserMovies(userId: userId)
                let watchlistShows = try await supabase.fetchWatchlistShows(userId: userId)
                let watchlistMovies = try await supabase.fetchWatchlistMovies(userId: userId)

                print("📊 Stats - Shows: \(userShows.count), Movies: \(userMovies.count)")
                print("📊 Shows IDs: \(userShows.map { $0.showId })")
                print("📊 Movie IDs: \(userMovies.map { $0.movieId })")

                libraryCount = userShows.count + userMovies.count
                watchlistCount = watchlistShows.count + watchlistMovies.count
                ratedCount = (userShows.filter { $0.rating != nil }.count) + (userMovies.filter { $0.rating != nil }.count)
            } catch {
                print("Error loading stats: \(error)")
            }
        }
    }

    private func loadPartiallyWatched() {
        guard let userId = supabase.currentUser?.id else { return }

        Task {
            do {
                let episodes = try await supabase.fetchUserEpisodes(userId: userId)
                let userShows = try await supabase.fetchUserShows(userId: userId)

                var showMap: [Int: (episodes: [Episode], title: String, posterUrl: String?, firstAirDate: String?)] = [:]

                for episode in episodes {
                    if showMap[episode.showId] == nil {
                        showMap[episode.showId] = (episodes: [], title: episode.showTitle ?? "Unknown", posterUrl: nil, firstAirDate: nil)
                    }
                    showMap[episode.showId]?.episodes.append(episode)
                }

                var partialShows: [LibraryShowWithDetails] = []

                for (showId, data) in showMap {
                    if let showDetail = try? await tmdb.getTVShow(id: showId) {
                        let episodeList = data.episodes
                        let totalEpisodes = showDetail.numberOfEpisodes
                        let watchedEpisodes = episodeList.filter { $0.watched }.count

                        // Only include if partially watched (not complete)
                        if watchedEpisodes > 0 && watchedEpisodes < totalEpisodes {
                            // Get all episodes from TMDB to find next unwatched
                            var allEpisodes: [EpisodeDetail] = []
                            for season in 1...showDetail.numberOfSeasons {
                                do {
                                    let seasonDetail = try await tmdb.getTVSeason(showId: showId, seasonNumber: season)
                                    allEpisodes.append(contentsOf: seasonDetail.episodes)
                                } catch {
                                    print("Could not fetch season \(season) for show \(showId)")
                                }
                            }

                            let watchedEpisodeIds = Set(episodeList.map { $0.id })
                            let nextUnwatched = allEpisodes.sorted { a, b in
                                if a.seasonNumber == b.seasonNumber {
                                    return a.episodeNumber < b.episodeNumber
                                }
                                return a.seasonNumber < b.seasonNumber
                            }.first { !watchedEpisodeIds.contains($0.id) }

                            let lastWatched = episodeList.sorted { ($0.watchedAt ?? "") > ($1.watchedAt ?? "") }.first
                            let displayLabel: String? = if let next = nextUnwatched {
                                "S\(next.seasonNumber)E\(next.episodeNumber)"
                            } else if let last = lastWatched {
                                "S\(last.seasonNumber)E\(last.episodeNumber)"
                            } else {
                                nil
                            }
                            let mostRecentDate = episodeList.compactMap { $0.watchedAt }.max() ?? ISO8601DateFormatter().string(from: Date())

                            partialShows.append(LibraryShowWithDetails(
                                id: episodeList.first?.id ?? 0,
                                showId: showId,
                                watchedDate: mostRecentDate,
                                rating: userShows.first(where: { $0.showId == showId })?.rating,
                                review: userShows.first(where: { $0.showId == showId })?.review,
                                showTitle: showDetail.name,
                                posterUrl: showDetail.posterPath.flatMap { "https://image.tmdb.org/t/p/w500\($0)" },
                                totalEpisodes: totalEpisodes,
                                watchedEpisodes: watchedEpisodes,
                                lastWatchedEpisode: displayLabel,
                                firstAirDate: showDetail.firstAirDate
                            ))
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.partiallyWatchedShows = partialShows.sorted { ($0.watchedDate) > ($1.watchedDate) }
                }
            } catch {
                print("Error loading partially watched shows: \(error)")
            }
        }
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Expanded Search View

struct ExpandedSearchView: View {
    @Binding var isPresented: Bool
    @StateObject private var tmdb = TMDBService.shared
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Active search bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search for shows and movies...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .focused($isSearchFieldFocused)
                        .autocorrectionDisabled()
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Button("Cancel") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPresented = false
                        searchText = ""
                        searchResults = []
                    }
                }
                .foregroundColor(.blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            
            Divider()
            
            // Search Results
            if isSearching {
                VStack {
                    ProgressView()
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if searchResults.isEmpty && !searchText.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding()
                    Text("No results found")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Try searching with different keywords")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if searchResults.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "film")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding()
                    Text("Search for shows and movies")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Type above to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(searchResults, id: \.id) { result in
                            if result.id != nil {
                                NavigationLink(destination: destinationView(for: result)) {
                                    HomeSearchResultRow(result: result)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            // Delay to allow animation to complete first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: searchText) {
            if !searchText.isEmpty {
                performSearch()
            } else {
                searchResults = []
            }
        }
    }
    
    @ViewBuilder
    private func destinationView(for result: SearchResult) -> some View {
        if result.mediaType == "tv", let showId = result.id {
            TVShowDetailView(showId: showId)
        } else if result.mediaType == "movie", let movieId = result.id {
            MovieDetailView(movieId: movieId)
        } else {
            EmptyView()
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        Task {
            do {
                let results = try await tmdb.searchMulti(query: searchText)
                DispatchQueue.main.async {
                    self.searchResults = results.filter { $0.mediaType == "tv" || $0.mediaType == "movie" }
                    self.isSearching = false
                }
            } catch {
                print("Search error: \(error)")
                DispatchQueue.main.async {
                    self.isSearching = false
                }
            }
        }
    }
}

// MARK: - Search Result Row

struct HomeSearchResultRow: View {
    let result: SearchResult
    
    var body: some View {
        HStack(spacing: 12) {
            // Poster
            if let imageUrl = result.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 60, height: 90)
                .cornerRadius(8)
            } else {
                Color.gray
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Image(systemName: result.mediaType == "tv" ? "tv" : "film")
                        .font(.caption)
                    Text(result.mediaType == "tv" ? "TV Show" : "Movie")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                if let overview = result.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    HomeView()
        .environmentObject(SupabaseService.shared)
}
