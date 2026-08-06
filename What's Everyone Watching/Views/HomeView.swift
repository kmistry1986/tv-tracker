import SwiftUI

struct HomeView: View {
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var tmdb = TMDBService.shared
    @State private var trendingShows: [SearchResult] = []
    @State private var trendingMovies: [SearchResult] = []
    @State private var partiallyWatchedShows: [LibraryShowWithDetails] = []
    @State private var libraryShowCount = 0
    @State private var libraryMovieCount = 0
    @State private var watchlistShowCount = 0
    @State private var watchlistMovieCount = 0
    @State private var ratedCount = 0
    @State private var totalLibraryCount = 0
    @State private var isLoading = false
    @State private var showSearchOverlay = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .lastTextBaseline) {
                Text("HOME").displayTitle(34)
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 14)
            
            Rule(strong: true)
            
            ScrollView {
                VStack(spacing: 0) {
                    // Stats section
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your Stats").label(11).foregroundStyle(Theme.inkMuted)
                        
                        StatRow(stats: [
                            .init(value: "\(libraryShowCount + libraryMovieCount)", label: "Library"),
                            .init(value: "\(watchlistShowCount + watchlistMovieCount)", label: "Watchlist"),
                            .init(value: "\(ratedCount)", label: "Rated", accent: true)
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, Theme.Space.lg)
                    
                    Rule(strong: true)
                    
                    // Continue Watching
                    if !partiallyWatchedShows.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Continue Watching").label(11).foregroundStyle(Theme.inkMuted)
                                .padding(.horizontal, Theme.gutter)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(partiallyWatchedShows.prefix(10), id: \.id) { show in
                                        NavigationLink(destination: ShowDetailView(showId: show.showId, showTitle: show.showTitle)) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                if let imageUrl = show.posterUrl, let url = URL(string: imageUrl) {
                                                    Poster(url: url, width: 100, height: 150)
                                                } else {
                                                    Poster(url: nil, width: 100, height: 150)
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(show.showTitle)
                                                        .headline(13)
                                                        .lineLimit(2)
                                                        .frame(width: 100, alignment: .leading)
                                                    
                                                    if let lastEpisode = show.lastWatchedEpisode {
                                                        Text(lastEpisode)
                                                            .label(9)
                                                            .foregroundStyle(Theme.accent)
                                                    }
                                                    
                                                    Text("\(show.watchedEpisodes)/\(show.totalEpisodes)")
                                                        .bodyCopy(10)
                                                        .foregroundStyle(Theme.inkMuted)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, Theme.gutter)
                            }
                        }
                        .padding(.vertical, Theme.Space.lg)
                        
                        Rule(strong: true)
                    }
                    
                    // Trending Shows
                    if !trendingShows.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Trending TV Shows").label(11).foregroundStyle(Theme.inkMuted)
                                .padding(.horizontal, Theme.gutter)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(trendingShows.prefix(10), id: \.id) { show in
                                        if let showId = show.id {
                                            NavigationLink(destination: TVShowDetailView(showId: showId)) {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    if let imageUrl = show.imageUrl, let url = URL(string: imageUrl) {
                                                        Poster(url: url, width: 100, height: 150)
                                                    } else {
                                                        Poster(url: nil, width: 100, height: 150)
                                                    }
                                                    
                                                    Text(show.displayTitle)
                                                        .bodyCopy(11)
                                                        .lineLimit(2)
                                                        .frame(width: 100, alignment: .leading)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.gutter)
                            }
                        }
                        .padding(.vertical, Theme.Space.lg)
                        
                        Rule(strong: true)
                    }
                    
                    // Trending Movies
                    if !trendingMovies.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Trending Movies").label(11).foregroundStyle(Theme.inkMuted)
                                .padding(.horizontal, Theme.gutter)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(trendingMovies.prefix(10), id: \.id) { movie in
                                        if let movieId = movie.id {
                                            NavigationLink(destination: MovieDetailView(movieId: movieId)) {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    if let imageUrl = movie.imageUrl, let url = URL(string: imageUrl) {
                                                        Poster(url: url, width: 100, height: 150)
                                                    } else {
                                                        Poster(url: nil, width: 100, height: 150)
                                                    }
                                                    
                                                    Text(movie.displayTitle)
                                                        .bodyCopy(11)
                                                        .lineLimit(2)
                                                        .frame(width: 100, alignment: .leading)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.gutter)
                            }
                        }
                        .padding(.vertical, Theme.Space.lg)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.ground)
        .foregroundStyle(Theme.ink)
        .onAppear {
            loadTrendingContent()
            loadStats()
            loadPartiallyWatched()
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
                // Library Card
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("Library")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }

                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shows")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text(String(libraryShowCount))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Movies")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text(String(libraryMovieCount))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Watchlist Card
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        Text("Watchlist")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }

                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shows")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text(String(watchlistShowCount))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Movies")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text(String(watchlistMovieCount))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Ratings Card
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Ratings")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }

                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rated")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text(String(ratedCount))
                                .font(.callout)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Complete")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                            Text(totalLibraryCount > 0 ? "\(Int(Double(ratedCount) / Double(totalLibraryCount) * 100))%" : "0%")
                                .font(.callout)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
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

                libraryShowCount = userShows.count
                libraryMovieCount = userMovies.count
                watchlistShowCount = watchlistShows.count
                watchlistMovieCount = watchlistMovies.count
                totalLibraryCount = userShows.count + userMovies.count
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

#Preview("Stats Cards") {
    VStack(spacing: 12) {
        Text("Your Stats")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 12) {
            // Library Card
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    Text("Library")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }

                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shows")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("8")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Movies")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("5")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Watchlist Card
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text("Watchlist")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }

                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shows")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("12")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Movies")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("6")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Ratings Card
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text("Ratings")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }

                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rated")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("4")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Complete")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                        Text("23%")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}
