import SwiftUI

struct WatchlistView: View {
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var tmdb = TMDBService.shared
    @State private var watchlistShows: [WatchlistShowWithDetails] = []
    @State private var watchlistMovies: [WatchlistMovieWithDetails] = []
    @State private var isLoading = false
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var errorMessage: String?
    
    var filteredShows: [WatchlistShowWithDetails] {
        if searchText.isEmpty {
            return watchlistShows
        }
        return watchlistShows.filter { $0.showTitle.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredMovies: [WatchlistMovieWithDetails] {
        if searchText.isEmpty {
            return watchlistMovies
        }
        return watchlistMovies.filter { $0.movieTitle.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Picker("", selection: $selectedTab) {
                        Text("All").tag(0)
                        Text("Shows").tag(1)
                        Text("Movies").tag(2)
                    }
                    .pickerStyle(.segmented)

                    WatchlistSearchBar(text: $searchText)
                }
                .padding()
                .safeAreaPadding(.top, 10)
                
                if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        
                        Text("Error loading watchlist")
                            .font(.headline)
                        
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        Button(action: loadWatchlist) {
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
                    allList
                } else if selectedTab == 1 {
                    showsList
                } else {
                    moviesList
                }
            }
            .navigationTitle("Watchlist")
            .onAppear {
                loadWatchlist()
            }
        }
    }
    
    private var allList: some View {
        Group {
            if filteredShows.isEmpty && filteredMovies.isEmpty {
                VStack {
                    Text("No items in your watchlist")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    if !filteredShows.isEmpty {
                        Section("Shows") {
                            ForEach(filteredShows, id: \.id) { show in
                                watchlistShowRow(show)
                            }
                        }
                    }
                    if !filteredMovies.isEmpty {
                        Section("Movies") {
                            ForEach(filteredMovies, id: \.id) { movie in
                                watchlistMovieRow(movie)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var showsList: some View {
        Group {
            if filteredShows.isEmpty {
                VStack {
                    Text("No shows in your watchlist")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(filteredShows, id: \.id) { show in
                        watchlistShowRow(show)
                    }
                }
            }
        }
    }
    
    private var moviesList: some View {
        Group {
            if filteredMovies.isEmpty {
                VStack {
                    Text("No movies in your watchlist")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(filteredMovies, id: \.id) { movie in
                        watchlistMovieRow(movie)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func watchlistShowRow(_ show: WatchlistShowWithDetails) -> some View {
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
                
                HStack(spacing: 8) {
                    Label(show.priority, systemImage: priorityIcon(show.priority))
                        .font(.caption)
                        .foregroundColor(priorityColor(show.priority))
                    
                    if let notes = show.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) {
                removeShow(show)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private func watchlistMovieRow(_ movie: WatchlistMovieWithDetails) -> some View {
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
                
                HStack(spacing: 8) {
                    Label(movie.priority, systemImage: priorityIcon(movie.priority))
                        .font(.caption)
                        .foregroundColor(priorityColor(movie.priority))
                    
                    if let notes = movie.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) {
                removeMovie(movie)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func loadWatchlist() {
        guard let userId = supabase.currentUser?.id else {
            errorMessage = "User not logged in"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let shows = try await supabase.fetchWatchlistShows(userId: userId)
                var showsWithDetails: [WatchlistShowWithDetails] = []
                
                for show in shows {
                    var title = "Show #\(show.showId)"
                    var posterUrl: String? = nil
                    do {
                        let tvShow = try await tmdb.getTVShow(id: show.showId)
                        title = tvShow.name
                        posterUrl = tvShow.imageUrl
                    } catch {
                        print("Could not fetch show details: \(error)")
                    }
                    showsWithDetails.append(WatchlistShowWithDetails(
                        id: show.id,
                        userId: show.userId,
                        showId: show.showId,
                        priority: show.priority,
                        notes: show.notes,
                        addedAt: show.addedAt,
                        showTitle: title,
                        posterUrl: posterUrl
                    ))
                }
                
                let movies = try await supabase.fetchWatchlistMovies(userId: userId)
                var moviesWithDetails: [WatchlistMovieWithDetails] = []
                
                for movie in movies {
                    var title = "Movie #\(movie.movieId)"
                    var posterUrl: String? = nil
                    do {
                        let movieDetail = try await tmdb.getMovie(id: movie.movieId)
                        title = movieDetail.title
                        posterUrl = movieDetail.imageUrl
                    } catch {
                        print("Could not fetch movie details: \(error)")
                    }
                    moviesWithDetails.append(WatchlistMovieWithDetails(
                        id: movie.id,
                        userId: movie.userId,
                        movieId: movie.movieId,
                        priority: movie.priority,
                        notes: movie.notes,
                        addedAt: movie.addedAt,
                        movieTitle: title,
                        posterUrl: posterUrl
                    ))
                }
                
                DispatchQueue.main.async {
                    self.watchlistShows = showsWithDetails
                    self.watchlistMovies = moviesWithDetails
                    self.isLoading = false
                }
            } catch {
                print("Error loading watchlist: \(error)")
                DispatchQueue.main.async {
                    self.watchlistShows = []
                    self.watchlistMovies = []
                    self.isLoading = false
                }
            }
        }
    }
    
    private func removeShow(_ show: WatchlistShowWithDetails) {
        Task {
            do {
                try await supabase.removeFromWatchlistShow(id: show.id)
                DispatchQueue.main.async {
                    watchlistShows.removeAll { $0.id == show.id }
                }
            } catch {
                print("Error removing show: \(error)")
            }
        }
    }
    
    private func removeMovie(_ movie: WatchlistMovieWithDetails) {
        Task {
            do {
                try await supabase.removeFromWatchlistMovie(id: movie.id)
                DispatchQueue.main.async {
                    watchlistMovies.removeAll { $0.id == movie.id }
                }
            } catch {
                print("Error removing movie: \(error)")
            }
        }
    }
    
    private func priorityIcon(_ priority: String) -> String {
        switch priority {
        case "high":
            return "exclamationmark.circle.fill"
        case "medium":
            return "circle.fill"
        default:
            return "minus.circle.fill"
        }
    }
    
    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .gray
        }
    }
}

struct WatchlistSearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search watchlist", text: $text)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(20)
    }
}

struct WatchlistShowWithDetails {
    let id: Int
    let userId: String
    let showId: Int
    let priority: String
    let notes: String?
    let addedAt: String
    let showTitle: String
    let posterUrl: String?
}

struct WatchlistMovieWithDetails {
    let id: Int
    let userId: String
    let movieId: Int
    let priority: String
    let notes: String?
    let addedAt: String
    let movieTitle: String
    let posterUrl: String?
}

#Preview {
    WatchlistView()
}
