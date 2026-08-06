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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("All").tag(2)
                    Text("Shows").tag(0)
                    Text("Movies").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                .padding(.top, -10)
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search library...", text: $searchText)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .padding(.horizontal)
                .padding(.bottom, 8)
                
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
                } else if selectedTab == 1 {
                    moviesList
                } else {
                    allItemsList
                }
            }
            .navigationTitle("My Library")
            .onAppear {
                loadLibrary()
            }
            .onChange(of: selectedTab) { _ in
                searchText = ""
                showAllShows = false
                showAllMovies = false
                loadLibrary()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                loadLibrary()
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

                                    VStack(alignment: .trailing, spacing: 4) {
                                        if show.watchedEpisodes == show.totalEpisodes {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.green)
                                        } else if let lastEpisode = show.lastWatchedEpisode {
                                            Text(lastEpisode)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.blue)
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
                    // Shows section
                    if !filteredShows.isEmpty {
                        Section(header: Text("Shows")) {
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

                                            HStack(spacing: 12) {
                                                if let rating = show.rating {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: "star.fill")
                                                            .foregroundColor(.orange)
                                                        Text("\(rating)")
                                                            .font(.caption)
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
                            }
                        }
                    }

                    // Movies section
                    if !filteredMovies.isEmpty {
                        Section(header: Text("Movies")) {
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
                                                        .font(.caption)
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
                 var showMap: [Int: (episodes: [Episode], title: String, posterUrl: String?, firstAirDate: String?)] = [:]

                 // Group episodes by show
                 for episode in episodes {
                     if showMap[episode.showId] == nil {
                         showMap[episode.showId] = (episodes: [], title: "Show #\(episode.showId)", posterUrl: nil, firstAirDate: nil)
                     }
                     showMap[episode.showId]?.episodes.append(episode)
                 }

                 // Fetch show details in parallel for unique shows
                 let uniqueShowIds = Array(Set(episodes.map { $0.showId }))
                 print("📚 Fetching details for \(uniqueShowIds.count) unique shows")

                 let tmdbService = self.tmdb
                 if !uniqueShowIds.isEmpty {
                     await withTaskGroup(of: (Int, String, String?, String?).self) { group in
                         for showId in uniqueShowIds {
                             group.addTask {
                                 do {
                                     let show = try await tmdbService.getTVShow(id: showId)
                                     return (showId, show.name, show.imageUrl, show.firstAirDate)
                                 } catch {
                                     print("Could not fetch show details for \(showId): \(error)")
                                     return (showId, "Show #\(showId)", nil, nil)
                                 }
                             }
                         }

                         for await (showId, name, imageUrl, firstAirDate) in group {
                             showMap[showId]?.title = name
                             showMap[showId]?.posterUrl = imageUrl
                             showMap[showId]?.firstAirDate = firstAirDate
                         }
                     }
                 }
                 print("📚 Show details fetched")

                // Convert to LibraryShowWithDetails
                for (showId, data) in showMap {
                    let episodeList = data.episodes
                    let watchedEpisodes = episodeList.filter { $0.watched }.count
                    let totalEpisodes = episodeList.count

                    // Get last watched episode
                    let lastWatched = episodeList.filter { $0.watched }.max { a, b in
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
                                        posterUrl: movieDetail.imageUrl,
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
    
    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "M/d/yyyy"
            return displayFormatter.string(from: date)
        }
        return dateStr
    }

    private func formatReleaseDate(_ dateStr: String?) -> String {
        guard let dateStr = dateStr, !dateStr.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "M/d/yyyy"
            return displayFormatter.string(from: date)
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
                    try await supabase.updateEpisodeWatched(
                        episodeId: episode.id,
                        watched: true
                    )
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

#Preview {
    LibraryView()
}
