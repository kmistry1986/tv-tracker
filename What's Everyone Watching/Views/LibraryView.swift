import SwiftUI

struct LibraryView: View {
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var tmdb = TMDBService.shared
    @State private var libraryShows: [LibraryShowWithDetails] = []
    @State private var libraryMovies: [LibraryMovieWithDetails] = []
    @State private var isLoading = false
    @State private var selectedTab = 2
    @State private var errorMessage: String?
    @State private var lastRefreshTime = Date()
    @State private var searchText = ""
    @State private var showAllShows = false
    @State private var showAllMovies = false
    @State private var showCompleteShowModal = false
    @State private var showCompleteSeasonModal = false
    @State private var showRatingModal = false
    @State private var showRemoveConfirmation = false
    @State private var selectedShowIdForModal: Int?
    @State private var selectedShowTitleForModal: String = ""
    @State private var selectedShowForRating: (showId: Int, title: String, isMovie: Bool)?
    @State private var itemToRemove: (id: Int, title: String, isMovie: Bool)?
    @Environment(\.scenePhase) var scenePhase
    var importTrigger: Binding<Bool>? = nil
    
    var filteredShows: [LibraryShowWithDetails] {
        if searchText.isEmpty {
            return showAllShows ? libraryShows : Array(libraryShows.prefix(10))
        }
        return libraryShows.filter { $0.showTitle.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredMovies: [LibraryMovieWithDetails] {
        if searchText.isEmpty {
            return showAllMovies ? libraryMovies : Array(libraryMovies.prefix(10))
        }
        return libraryMovies.filter { $0.movieTitle.localizedCaseInsensitiveContains(searchText) }
    }

    enum CombinedItem: Hashable {
        case show(LibraryShowWithDetails)
        case movie(LibraryMovieWithDetails)

        var watchedDate: String {
            switch self {
            case .show(let show):
                return show.watchedDate
            case .movie(let movie):
                return movie.watchedDate
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .show(let show):
                hasher.combine("show")
                hasher.combine(show.id)
            case .movie(let movie):
                hasher.combine("movie")
                hasher.combine(movie.id)
            }
        }

        static func == (lhs: CombinedItem, rhs: CombinedItem) -> Bool {
            switch (lhs, rhs) {
            case (.show(let show1), .show(let show2)):
                return show1.id == show2.id
            case (.movie(let movie1), .movie(let movie2)):
                return movie1.id == movie2.id
            default:
                return false
            }
        }
    }

    var filteredAllItems: [CombinedItem] {
        var combined: [CombinedItem] = []
        combined.append(contentsOf: filteredShows.map { .show($0) })
        combined.append(contentsOf: filteredMovies.map { .movie($0) })

        // Sort by watched date descending
        combined.sort { item1, item2 in
            let dateFormatter = ISO8601DateFormatter()
            let date1 = dateFormatter.date(from: item1.watchedDate) ?? Date.distantPast
            let date2 = dateFormatter.date(from: item2.watchedDate) ?? Date.distantPast
            return date1 > date2
        }

        return combined
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .lastTextBaseline) {
                Text("LIBRARY").displayTitle(34)
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 14)
            
            Rule(strong: true)
            
            // Segmented control
            RuledSegmented(options: [
                "All (\(libraryShows.count + libraryMovies.count))",
                "Shows (\(libraryShows.count))",
                "Movies (\(libraryMovies.count))"
            ], selection: Binding(
                get: { selectedTab },
                set: { selectedTab = $0 == 0 ? 2 : ($0 == 1 ? 0 : 1) }
            ))
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            
            Rule(strong: true)

            // Search bar
            HStack(spacing: Theme.Space.sm) {
                TextField("Search library", text: $searchText)
                    .font(Theme.body(15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Text("×").font(Theme.heavy(24)).foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Space.md)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            
            Rule(strong: true)

                if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)

                        Text("Error loading library")
                            .font(.headline)

                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)

                        Button(action: loadLibrary) {
                            Text("Try Again")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    .padding()
                    Spacer()
                } else if isLoading {
                    VStack {
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if selectedTab == 0 {
                    showsList
                        .refreshable {
                            await loadLibraryAsync()
                        }
                } else if selectedTab == 1 {
                    moviesList
                        .refreshable {
                            await loadLibraryAsync()
                        }
                } else {
                    allItemsList
                        .refreshable {
                            await loadLibraryAsync()
                        }
                }
            }
            .background(Theme.ground)
            .foregroundStyle(Theme.ink)
            .onAppear {
                loadLibrary()
            }
            .onChange(of: selectedTab) {
                searchText = ""
                showAllShows = false
                showAllMovies = false
                loadLibrary()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                loadLibrary()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    loadLibrary()
                }
            }
            .task(id: importTrigger?.wrappedValue) {
                if importTrigger?.wrappedValue == false {
                    loadLibrary()
                }
            }
            .sheet(isPresented: $showCompleteShowModal) {
                if let showId = selectedShowIdForModal {
                    MarkWatchedModal(showId: showId, showTitle: selectedShowTitleForModal) { selectedEpisodeIds in
                        saveWatchedEpisodesForShow(selectedEpisodeIds)
                    }
                }
            }
            .sheet(isPresented: $showCompleteSeasonModal) {
                if let showId = selectedShowIdForModal {
                    CompleteSeasonModal(showId: showId, showTitle: selectedShowTitleForModal) { watchedSeasons, unwatchedSeasons in
                        saveWatchedSeasonsForShow(watchedSeasons: watchedSeasons, unwatchedSeasons: unwatchedSeasons)
                    }
                }
            }
            .sheet(isPresented: $showRatingModal) {
                if let (itemId, title, isMovie) = selectedShowForRating {
                    RatingView(title: title, mediaType: isMovie ? "movie" : "tv", itemId: itemId, isMovie: isMovie)
                }
            }
            .alert("Remove from Library?", isPresented: $showRemoveConfirmation) {
                Button("Remove", role: .destructive) {
                    if let (id, _, isMovie) = itemToRemove {
                        Task {
                            await removeItemFromLibrary(id: id, isMovie: isMovie)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if let (_, title, _) = itemToRemove {
                    Text("No episodes watched for \"\(title)\". Remove from library?")
                }
            }
    }
    
    private var showsList: some View {
        Group {
            if filteredShows.isEmpty && !searchText.isEmpty {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding()
                    Text("No shows found")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.top, 50)
            } else if libraryShows.isEmpty {
                VStack {
                    Text("No shows watched yet")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    List {
                        ForEach(filteredShows, id: \.id) { show in
                            NavigationLink(destination: ShowDetailView(showId: show.showId, showTitle: show.showTitle)) {
                                HStack(spacing: 12) {
                                    if let imageUrl = show.posterUrl, let url = URL(string: imageUrl) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Color.gray
                                        }
                                        .frame(width: 50, height: 75)
                                        .cornerRadius(4)
                                    } else {
                                        Color.gray
                                            .frame(width: 50, height: 75)
                                            .cornerRadius(4)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(show.showTitle)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)

                                        if let rating = show.rating {
                                            Text("\(String(repeating: "★", count: rating))\(String(repeating: "☆", count: 10 - rating)) \(rating)/10")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        } else {
                                            Button(action: {
                                                selectedShowForRating = (showId: show.showId, title: show.showTitle, isMovie: false)
                                                showRatingModal = true
                                            }) {
                                                Text("Not yet rated")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                        }

                                        if let releaseDate = show.firstAirDate, !releaseDate.isEmpty {
                                            Text("Released: \(formatReleaseDate(releaseDate))")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }

                                        if let review = show.review, !review.isEmpty {
                                            Text(review)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .lineLimit(2)
                                        }
                                    }

                                    VStack(alignment: .trailing, spacing: 6) {
                                        if show.watchedEpisodes < show.totalEpisodes {
                                            if let lastEpisode = show.lastWatchedEpisode {
                                                Text(lastEpisode)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.blue)
                                            }
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.green)
                                        }

                                        Text("\(show.watchedEpisodes)/\(show.totalEpisodes) episodes")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeShow(id: show.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    markShowAsWatched(showId: show.showId)
                                } label: {
                                    Label("Watched", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
                        }
                        
                        // "See All" button
                        if !showAllShows && libraryShows.count > 10 && searchText.isEmpty {
                            Button(action: { showAllShows = true }) {
                                HStack {
                                    Spacer()
                                    Text("See All (\(libraryShows.count) shows)")
                                        .foregroundColor(.blue)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var moviesList: some View {
        Group {
            if filteredMovies.isEmpty && !searchText.isEmpty {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding()
                    Text("No movies found")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.top, 50)
            } else if libraryMovies.isEmpty {
                VStack {
                    Text("No movies watched yet")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(filteredMovies, id: \.id) { movie in
                        HStack(spacing: 12) {
                            if let imageUrl = movie.posterUrl, let url = URL(string: imageUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 50, height: 75)
                                .cornerRadius(4)
                            } else {
                                Color.gray
                                    .frame(width: 50, height: 75)
                                    .cornerRadius(4)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.movieTitle)
                                    .fontWeight(.semibold)

                                HStack(spacing: 12) {
                                    if let rating = movie.rating {
                                        HStack(spacing: 2) {
                                            Image(systemName: "star.fill")
                                                .foregroundColor(.orange)
                                            Text("\(rating)")
                                        }
                                        .font(.caption)
                                    }

                                    Text(formatDate(movie.watchedDate))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                if let review = movie.review, !review.isEmpty {
                                    Text(review)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeMovie(id: movie.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    
                    // "See All" button
                    if !showAllMovies && libraryMovies.count > 10 && searchText.isEmpty {
                        Button(action: { showAllMovies = true }) {
                            HStack {
                                Spacer()
                                Text("See All (\(libraryMovies.count) movies)")
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private var allItemsList: some View {
        Group {
            if (filteredShows.isEmpty && filteredMovies.isEmpty) && !searchText.isEmpty {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding()
                    Text("No items found")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.top, 50)
            } else if libraryShows.isEmpty && libraryMovies.isEmpty {
                VStack {
                    Text("No items watched yet")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(filteredAllItems, id: \.self) { item in
                        switch item {
                        case .show(let show):
                            NavigationLink(destination: ShowDetailView(showId: show.showId, showTitle: show.showTitle)) {
                                HStack(spacing: 12) {
                                    if let imageUrl = show.posterUrl, let url = URL(string: imageUrl) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Color.gray
                                        }
                                        .frame(width: 50, height: 75)
                                        .cornerRadius(4)
                                    } else {
                                        Color.gray
                                            .frame(width: 50, height: 75)
                                            .cornerRadius(4)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(show.showTitle)
                                            .fontWeight(.semibold)

                                        HStack(spacing: 12) {
                                            if let rating = show.rating {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "star.fill")
                                                        .foregroundColor(.orange)
                                                    Text("\(rating)")
                                                        .font(.caption)
                                                }
                                            } else {
                                                Button(action: {
                                                    selectedShowForRating = (showId: show.showId, title: show.showTitle, isMovie: false)
                                                    showRatingModal = true
                                                }) {
                                                    Text("Not rated")
                                                        .font(.caption)
                                                        .foregroundColor(.blue)
                                                }
                                            }

                                            Text("\(show.watchedEpisodes)/\(show.totalEpisodes)")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }

                                        if let releaseDate = show.firstAirDate, !releaseDate.isEmpty {
                                            Text("Released: \(formatReleaseDate(releaseDate))")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }

                        case .movie(let movie):
                            HStack(spacing: 12) {
                                if let imageUrl = movie.posterUrl, let url = URL(string: imageUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Color.gray
                                    }
                                    .frame(width: 50, height: 75)
                                    .cornerRadius(4)
                                } else {
                                    Color.gray
                                        .frame(width: 50, height: 75)
                                        .cornerRadius(4)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(movie.movieTitle)
                                        .fontWeight(.semibold)

                                    HStack(spacing: 12) {
                                        if let rating = movie.rating {
                                            HStack(spacing: 2) {
                                                Image(systemName: "star.fill")
                                                    .foregroundColor(.orange)
                                                Text("\(rating)")
                                                    .font(.caption)
                                            }
                                        } else {
                                            Button(action: {
                                                selectedShowForRating = (showId: movie.movieId, title: movie.movieTitle, isMovie: true)
                                                showRatingModal = true
                                            }) {
                                                Text("Not rated")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                        }

                                        if let releaseDate = movie.releaseDate, !releaseDate.isEmpty {
                                            Text("Released: \(formatReleaseDate(releaseDate))")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func loadLibrary() {
        guard let userId = supabase.currentUser?.id else {
            errorMessage = "User not logged in"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
             do {
                 print("📚 Fetching episodes for userId: \(userId)")
                 let episodes = try await supabase.fetchUserEpisodes(userId: userId)
                 print("📚 Loaded \(episodes.count) user episodes")

                 // Also fetch ratings from user_shows
                 let userShows = try await supabase.fetchUserShows(userId: userId)
                 var ratingMap: [Int: Int?] = [:]
                 for userShow in userShows {
                     ratingMap[userShow.showId] = userShow.rating
                 }
                 for episode in episodes.prefix(5) {
                     print("  - S\(episode.seasonNumber)E\(episode.episodeNumber): \(episode.name) (showId: \(episode.showId), userId: \(episode.userId ?? "nil"))")
                 }

                 var showsWithDetails: [LibraryShowWithDetails] = []
                 var showMap: [Int: (episodes: [Episode], title: String, posterUrl: String?, firstAirDate: String?, totalEpisodes: Int)] = [:]

                 // Group episodes by show
                 for episode in episodes {
                     if showMap[episode.showId] == nil {
                         showMap[episode.showId] = (episodes: [], title: "Show #\(episode.showId)", posterUrl: nil, firstAirDate: nil, totalEpisodes: 0)
                     }
                     showMap[episode.showId]?.episodes.append(episode)
                 }

                 // Fetch show details in parallel for unique shows
                 let uniqueShowIds = Array(Set(episodes.map { $0.showId }))
                 print("📚 Fetching details for \(uniqueShowIds.count) unique shows")

                 let tmdbService = self.tmdb
                 if !uniqueShowIds.isEmpty {
                     await withTaskGroup(of: (Int, String, String?, String?, Int).self) { group in
                         for showId in uniqueShowIds {
                             group.addTask {
                                 do {
                                     let show = try await tmdbService.getTVShow(id: showId)
                                     let posterUrl = show.posterPath.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                                     return (showId, show.name, posterUrl, show.firstAirDate, show.numberOfEpisodes)
                                 } catch {
                                     print("Could not fetch show details for \(showId): \(error)")
                                     return (showId, "Show #\(showId)", nil, nil, 0)
                                 }
                             }
                         }

                         for await (showId, name, imageUrl, firstAirDate, totalEpisodes) in group {
                             showMap[showId]?.title = name
                             showMap[showId]?.posterUrl = imageUrl
                             showMap[showId]?.firstAirDate = firstAirDate
                             showMap[showId]?.totalEpisodes = totalEpisodes
                         }
                     }
                 }
                 print("📚 Show details fetched")

                // Convert to LibraryShowWithDetails
                for (showId, data) in showMap {
                    let episodeList = data.episodes
                    let watchedEpisodes = episodeList.filter { $0.watched }.count
                    let totalEpisodes = data.totalEpisodes

                    // Get last watched episode (already filtered for watched above)
                    let lastWatched = episodeList.max { a, b in
                        let aDate = ISO8601DateFormatter().date(from: a.watchedAt ?? "") ?? Date.distantPast
                        let bDate = ISO8601DateFormatter().date(from: b.watchedAt ?? "") ?? Date.distantPast
                        return aDate < bDate
                    }
                    let lastWatchedEpisode = lastWatched.map { "S\($0.seasonNumber)E\($0.episodeNumber)" }

                    // Most recent watched date
                    let mostRecentDate = episodeList.compactMap { $0.watchedAt }.max() ?? ISO8601DateFormatter().string(from: Date())

                    let showDetail = LibraryShowWithDetails(
                        id: episodeList.first?.id ?? 0,
                        showId: showId,
                        watchedDate: mostRecentDate,
                        rating: ratingMap[showId] ?? nil,
                        review: nil,
                        showTitle: data.title,
                        posterUrl: data.posterUrl,
                        totalEpisodes: totalEpisodes,
                        watchedEpisodes: watchedEpisodes,
                        lastWatchedEpisode: lastWatchedEpisode,
                        firstAirDate: data.firstAirDate
                    )
                    showsWithDetails.append(showDetail)
                }

                print("📚 Sorting \(showsWithDetails.count) shows")
                showsWithDetails.sort {
                    let dateFormatter = ISO8601DateFormatter()
                    let date1 = dateFormatter.date(from: $0.watchedDate) ?? Date.distantPast
                    let date2 = dateFormatter.date(from: $1.watchedDate) ?? Date.distantPast
                    return date1 > date2
                }
                print("📚 Shows sorted")

                print("📚 Fetching movies...")
                let movies = try await supabase.fetchUserMovies(userId: userId)
                print("📚 Loaded \(movies.count) user movies")

                var moviesWithDetails: [LibraryMovieWithDetails] = []
                let tmdbService2 = self.tmdb
                if !movies.isEmpty {
                    await withTaskGroup(of: LibraryMovieWithDetails.self) { group in
                        for movie in movies {
                            group.addTask {
                                do {
                                    let movieDetail = try await tmdbService2.getMovie(id: movie.movieId)
                                    return LibraryMovieWithDetails(
                                        id: movie.id,
                                        movieId: movie.movieId,
                                        watchedDate: movie.watchedDate,
                                        rating: movie.rating,
                                        review: movie.review,
                                        movieTitle: movieDetail.title,
                                        posterUrl: movieDetail.posterPath.flatMap { "https://image.tmdb.org/t/p/w500\($0)" },
                                        releaseDate: movieDetail.releaseDate
                                    )
                                } catch {
                                    print("Could not fetch movie details for \(movie.movieId): \(error)")
                                    return LibraryMovieWithDetails(
                                        id: movie.id,
                                        movieId: movie.movieId,
                                        watchedDate: movie.watchedDate,
                                        rating: movie.rating,
                                        review: movie.review,
                                        movieTitle: "Movie #\(movie.movieId)",
                                        posterUrl: nil,
                                        releaseDate: nil
                                    )
                                }
                            }
                        }

                        for await movieDetail in group {
                            moviesWithDetails.append(movieDetail)
                        }
                    }
                }
                print("📚 Movie details fetched")

                var movieMap: [String: LibraryMovieWithDetails] = [:]
                for movie in moviesWithDetails {
                    if let existing = movieMap[movie.movieTitle] {
                        if movie.watchedDate > existing.watchedDate {
                            movieMap[movie.movieTitle] = movie
                        }
                    } else {
                        movieMap[movie.movieTitle] = movie
                    }
                }

                print("📚 Sorting \(moviesWithDetails.count) movies")
                moviesWithDetails = Array(movieMap.values).sorted {
                    let dateFormatter = ISO8601DateFormatter()
                    let date1 = dateFormatter.date(from: $0.watchedDate) ?? Date.distantPast
                    let date2 = dateFormatter.date(from: $1.watchedDate) ?? Date.distantPast
                    return date1 > date2
                }
                print("📚 Movies sorted")

                print("📚 Updating UI with \(showsWithDetails.count) shows and \(moviesWithDetails.count) movies")
                DispatchQueue.main.async {
                    self.libraryShows = showsWithDetails
                    self.libraryMovies = moviesWithDetails
                    self.isLoading = false
                    print("📚 UI updated, loading complete")
                }
            } catch {
                print("Error loading library: \(error)")
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load library: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadLibraryAsync() async {
        guard let userId = supabase.currentUser?.id else {
            errorMessage = "User not logged in"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            print("📚 Fetching episodes for userId: \(userId)")
            let episodes = try await supabase.fetchUserEpisodes(userId: userId)
            print("📚 Loaded \(episodes.count) user episodes")

            DispatchQueue.main.async {
                isLoading = false
            }

            let userShows = try await supabase.fetchUserShows(userId: userId)
            var ratingMap: [Int: Int?] = [:]
            for userShow in userShows {
                ratingMap[userShow.showId] = userShow.rating
            }
            for episode in episodes.prefix(5) {
                print("  - S\(episode.seasonNumber)E\(episode.episodeNumber): \(episode.name) (showId: \(episode.showId), userId: \(episode.userId ?? "nil"))")
            }

            var showsWithDetails: [LibraryShowWithDetails] = []
            var showMap: [Int: (episodes: [Episode], title: String, posterUrl: String?, firstAirDate: String?)] = [:]

            for episode in episodes {
                if showMap[episode.showId] == nil {
                    showMap[episode.showId] = (episodes: [], title: episode.showTitle ?? "Unknown", posterUrl: nil, firstAirDate: nil)
                }
                showMap[episode.showId]?.episodes.append(episode)
            }

            let tmdbService2 = self.tmdb
            if !showMap.isEmpty {
                await withTaskGroup(of: LibraryShowWithDetails.self) { group in
                    for (showId, data) in showMap {
                        group.addTask {
                            do {
                                let showDetail = try await tmdbService2.getTVShow(id: showId)
                                let episodeList = data.episodes
                                let totalEpisodes = showDetail.numberOfEpisodes
                                let watchedEpisodes = episodeList.filter { $0.watched }.count
                                let lastWatched = episodeList.filter { $0.watched }.sorted { ($0.watchedAt ?? "") > ($1.watchedAt ?? "") }.first
                                let lastWatchedEpisode = lastWatched.map { "S\($0.seasonNumber)E\($0.episodeNumber)" }
                                let mostRecentDate = episodeList.compactMap { $0.watchedAt }.max() ?? ISO8601DateFormatter().string(from: Date())

                                return LibraryShowWithDetails(
                                    id: episodeList.first?.id ?? 0,
                                    showId: showId,
                                    watchedDate: mostRecentDate,
                                    rating: ratingMap[showId] ?? nil,
                                    review: nil,
                                    showTitle: showDetail.name,
                                    posterUrl: showDetail.posterPath.flatMap { "https://image.tmdb.org/t/p/w500\($0)" },
                                    totalEpisodes: totalEpisodes,
                                    watchedEpisodes: watchedEpisodes,
                                    lastWatchedEpisode: lastWatchedEpisode,
                                    firstAirDate: showDetail.firstAirDate
                                )
                            } catch {
                                print("Error loading show \(showId): \(error)")
                                return LibraryShowWithDetails(
                                    id: 0,
                                    showId: showId,
                                    watchedDate: data.episodes.first?.watchedAt ?? ISO8601DateFormatter().string(from: Date()),
                                    rating: ratingMap[showId] ?? nil,
                                    review: nil,
                                    showTitle: data.title,
                                    posterUrl: data.posterUrl,
                                    totalEpisodes: data.episodes.count,
                                    watchedEpisodes: data.episodes.filter { $0.watched }.count,
                                    lastWatchedEpisode: nil,
                                    firstAirDate: data.firstAirDate
                                )
                            }
                        }
                    }

                    for await showDetail in group {
                        showsWithDetails.append(showDetail)
                    }
                }
            }
            print("📚 Sorting \(showsWithDetails.count) shows")
            showsWithDetails.sort {
                let dateFormatter = ISO8601DateFormatter()
                let date1 = dateFormatter.date(from: $0.watchedDate) ?? Date.distantPast
                let date2 = dateFormatter.date(from: $1.watchedDate) ?? Date.distantPast
                return date1 > date2
            }
            print("📚 Shows sorted")

            print("📚 Fetching movies...")
            let movies = try await supabase.fetchUserMovies(userId: userId)
            print("📚 Loaded \(movies.count) user movies")

            var moviesWithDetails: [LibraryMovieWithDetails] = []
            if !movies.isEmpty {
                await withTaskGroup(of: LibraryMovieWithDetails.self) { group in
                    for movie in movies {
                        group.addTask {
                            do {
                                let movieDetail = try await tmdbService2.getMovie(id: movie.movieId)
                                return LibraryMovieWithDetails(
                                    id: movie.id,
                                    movieId: movie.movieId,
                                    watchedDate: movie.watchedDate,
                                    rating: movie.rating,
                                    review: movie.review,
                                    movieTitle: movieDetail.title,
                                    posterUrl: movieDetail.posterPath.flatMap { "https://image.tmdb.org/t/p/w500\($0)" },
                                    releaseDate: movieDetail.releaseDate
                                )
                            } catch {
                                print("Error loading movie \(movie.movieId): \(error)")
                                return LibraryMovieWithDetails(
                                    id: movie.id,
                                    movieId: movie.movieId,
                                    watchedDate: movie.watchedDate,
                                    rating: movie.rating,
                                    review: movie.review,
                                    movieTitle: "Unknown",
                                    posterUrl: nil,
                                    releaseDate: nil
                                )
                            }
                        }
                    }

                    for await movieDetail in group {
                        moviesWithDetails.append(movieDetail)
                    }
                }
            }
            print("📚 Movie details fetched")

            var movieMap: [String: LibraryMovieWithDetails] = [:]
            for movie in moviesWithDetails {
                if let existing = movieMap[movie.movieTitle] {
                    if movie.watchedDate > existing.watchedDate {
                        movieMap[movie.movieTitle] = movie
                    }
                } else {
                    movieMap[movie.movieTitle] = movie
                }
            }

            print("📚 Sorting \(moviesWithDetails.count) movies")
            moviesWithDetails = Array(movieMap.values).sorted {
                let dateFormatter = ISO8601DateFormatter()
                let date1 = dateFormatter.date(from: $0.watchedDate) ?? Date.distantPast
                let date2 = dateFormatter.date(from: $1.watchedDate) ?? Date.distantPast
                return date1 > date2
            }
            print("📚 Movies sorted")

            print("📚 Updating UI with \(showsWithDetails.count) shows and \(moviesWithDetails.count) movies")
            self.libraryShows = showsWithDetails
            self.libraryMovies = moviesWithDetails
            self.isLoading = false
            print("📚 UI updated, loading complete")

            // Check for shows/movies with no episodes/activity
            DispatchQueue.main.async {
                self.checkForEmptyItems()
            }
        } catch {
            let nsError = error as NSError
            // Ignore network cancellation errors (-999) which happen during pull-to-refresh
            if nsError.code == -999 {
                print("ℹ️ Network request cancelled (pull-to-refresh)")
            } else {
                print("Error loading library: \(error)")
                self.errorMessage = "Failed to load library: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy"
            return displayFormatter.string(from: date)
        }
        // Fallback: extract year if it's in YYYY-MM-DD format
        if dateStr.count >= 4 {
            return String(dateStr.prefix(4))
        }
        return dateStr
    }

    private func formatReleaseDate(_ dateStr: String?) -> String {
        guard let dateStr = dateStr, !dateStr.isEmpty else { return "" }

        // Extract year from YYYY-MM-DD or return if already YYYY
        if dateStr.count >= 4 {
            return String(dateStr.prefix(4))
        }

        return dateStr
    }

    private func markShowAsWatched(showId: Int) {
        Task {
            do {
                guard let userId = supabase.currentUser?.id else { return }

                // Get all episodes for this show
                let episodes = try await supabase.fetchUserEpisodes(userId: userId)
                let showEpisodes = episodes.filter { $0.showId == showId && !$0.watched }

                // Mark all unwatched episodes as watched
                for episode in showEpisodes {
                    if let episodeId = episode.id {
                        try await supabase.updateEpisodeWatched(
                            episodeId: episodeId,
                            watched: true
                        )
                    }
                }

                // Reload library
                loadLibrary()
            } catch {
                print("Error marking show as watched: \(error)")
                errorMessage = "Failed to mark show as watched"
            }
        }
    }

    private func removeShow(id: Int) {
        Task {
            do {
                guard let userId = supabase.currentUser?.id else { return }

                // Find the show to get its showId
                if let show = libraryShows.first(where: { $0.id == id }) {
                    // Delete all episodes for this show
                    try await supabase.deleteEpisodesByShowId(showId: show.showId, userId: userId)
                }

                try await supabase.removeUserShow(id: id)
                libraryShows.removeAll { $0.id == id }
            } catch {
                print("Error removing show: \(error)")
                errorMessage = "Failed to remove show"
            }
        }
    }

    private func removeMovie(id: Int) {
        Task {
            do {
                try await supabase.removeUserMovie(id: id)
                libraryMovies.removeAll { $0.id == id }
            } catch {
                print("Error removing movie: \(error)")
                errorMessage = "Failed to remove movie"
            }
        }
    }

    private func saveWatchedEpisodesForShow(_ episodeIds: [Int]) {
        loadLibrary()
        showCompleteShowModal = false
    }

    private func saveWatchedSeasonsForShow(watchedSeasons: [Int], unwatchedSeasons: [Int]) {
        loadLibrary()
        showCompleteSeasonModal = false
    }

}

struct LibraryShowWithDetails {
    let id: Int
    let showId: Int
    let watchedDate: String
    let rating: Int?
    let review: String?
    let showTitle: String
    let posterUrl: String?
    let totalEpisodes: Int
    let watchedEpisodes: Int
    let lastWatchedEpisode: String? // Format: "S1E5"
    let firstAirDate: String? // Release date of first episode
}

struct LibraryMovieWithDetails {
    let id: Int
    let movieId: Int
    let watchedDate: String
    let rating: Int?
    let review: String?
    let movieTitle: String
    let posterUrl: String?
    let releaseDate: String?
}

extension LibraryView {
    private func removeItemFromLibrary(id: Int, isMovie: Bool) async {
        guard let userId = supabase.currentUser?.id else { return }

        do {
            if isMovie {
                try await supabase.removeMovieFromLibrary(userId: userId, movieId: id)
            } else {
                try await supabase.removeShowFromLibrary(userId: userId, showId: id)
            }
            loadLibrary()
        } catch {
            print("Error removing item from library: \(error)")
        }
    }

    func checkForEmptyItems() {
        if let emptyShow = libraryShows.first(where: { $0.watchedEpisodes == 0 }) {
            itemToRemove = (id: emptyShow.showId, title: emptyShow.showTitle, isMovie: false)
            showRemoveConfirmation = true
        } else if let emptyMovie = libraryMovies.first(where: { $0.rating == nil && $0.releaseDate != nil }) {
            itemToRemove = (id: emptyMovie.movieId, title: emptyMovie.movieTitle, isMovie: true)
            showRemoveConfirmation = true
        }
    }
}

#Preview {
    LibraryView()
}
