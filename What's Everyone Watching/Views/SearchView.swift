import SwiftUI

struct SearchView: View {
    @StateObject private var tmdb = TMDBService.shared
    @StateObject private var supabase = SupabaseService.shared
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var isLoading = false
    @State private var selectedResult: SearchResult?

    var initialSearchQuery: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, onSearch: performSearch)
                
                if isLoading {
                    VStack {
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if results.isEmpty {
                    VStack {
                        Text("Search for movies or TV shows")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                } else {
                    List(results) { result in
                        SearchResultRow(result: result)
                            .onTapGesture {
                                selectedResult = result
                            }
                    }
                }
            }
            .navigationTitle("Search")
            .sheet(item: $selectedResult) { result in
                SearchDetailView(result: result)
            }
            .onAppear {
                if let query = initialSearchQuery, searchText.isEmpty {
                    searchText = query
                    performSearch()
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        
        isLoading = true
        Task {
            do {
                results = try await tmdb.searchMulti(query: searchText)
            } catch {
                results = []
            }
            isLoading = false
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    var onSearch: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search", text: $text)
                .onSubmit(onSearch)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
        .padding()
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    
    var body: some View {
        HStack(spacing: 12) {
            if let imageUrl = result.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 50, height: 75)
                .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayTitle)
                    .fontWeight(.semibold)
                
                if let overview = result.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                
                Text(result.mediaType.uppercased())
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SearchDetailView: View {
    let result: SearchResult
    @StateObject private var tmdb = TMDBService.shared
    @StateObject private var supabase = SupabaseService.shared
    @State private var isAddingToLibrary = false
    @State private var isAddingToWatchlist = false
    @State private var showWatchlistOptions = false
    @State private var selectedPriority = "medium"
    @State private var watchlistNotes = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Text("Details")
                        .font(.headline)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                ScrollView {
                    VStack(spacing: 20) {
                        if let imageUrl = result.imageUrl, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                Color.gray
                            }
                            .frame(height: 300)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.displayTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(result.mediaType.uppercased())
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            if let overview = result.overview {
                                Text(overview)
                                    .font(.body)
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        
                        VStack(spacing: 12) {
                            Button(action: addToLibrary) {
                                if isAddingToLibrary {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Add to Library")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .disabled(isAddingToLibrary || isAddingToWatchlist)
                            
                            Button(action: { showWatchlistOptions.toggle() }) {
                                if isAddingToWatchlist {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Add to Watchlist")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .disabled(isAddingToLibrary || isAddingToWatchlist)
                        }
                        .padding()
                    }
                }
            }
            .sheet(isPresented: $showWatchlistOptions) {
                WatchlistOptionsSheet(
                    result: result,
                    selectedPriority: $selectedPriority,
                    notes: $watchlistNotes,
                    isAdding: $isAddingToWatchlist,
                    onAdd: addToWatchlist,
                    onDismiss: { showWatchlistOptions = false }
                )
            }
        }
    }
    
    private func addToLibrary() {
        isAddingToLibrary = true
        Task {
            defer { isAddingToLibrary = false }

            if result.mediaType == "tv" {
                guard let id = result.id, let userId = supabase.currentUser?.id else { return }
                do {
                    try await supabase.insertUserShow(
                        userId: userId,
                        showId: id,
                        watchedDate: ISO8601DateFormatter().string(from: Date())
                    )

                    // Fetch show details and insert into tv_shows first
                    let showDetail = try await tmdb.getTVShow(id: id)
                    print("📺 Fetching \(showDetail.numberOfSeasons) seasons for \(showDetail.name)")

                    // Insert show into tv_shows table
                    print("📺 Attempting to insert show with id=\(showDetail.id)")
                    let tvShow = TVShow(
                        id: showDetail.id,
                        tmdbId: showDetail.id,
                        title: showDetail.name,
                        overview: showDetail.overview,
                        posterUrl: showDetail.imageUrl,
                        firstAirDate: showDetail.firstAirDate,
                        numberOfSeasons: showDetail.numberOfSeasons,
                        numberOfEpisodes: showDetail.numberOfEpisodes
                    )
                    do {
                        try await supabase.insertShow(show: tvShow)
                        print("✅ Show inserted into tv_shows")
                    } catch {
                        print("⚠️ Could not insert show: \(error)")
                    }

                    for season in 1...showDetail.numberOfSeasons {
                        let seasonDetail = try await tmdb.getTVSeason(showId: id, seasonNumber: season)
                        print("📺 Season \(season): \(seasonDetail.episodes.count) episodes")
                        for episodeDetail in seasonDetail.episodes {
                            let episode = Episode(
                                id: episodeDetail.id,
                                showId: id,
                                tmdbId: episodeDetail.id,
                                seasonNumber: episodeDetail.seasonNumber,
                                episodeNumber: episodeDetail.episodeNumber,
                                name: episodeDetail.name,
                                overview: episodeDetail.overview ?? "",
                                airDate: episodeDetail.airDate,
                                userId: userId,
                                watched: false,
                                watchedAt: nil,
                                showTitle: showDetail.name
                            )
                            print("📺 Inserting episode \(episodeDetail.seasonNumber)x\(episodeDetail.episodeNumber): \(episodeDetail.name)")
                            try await supabase.insertEpisode(episode: episode)
                        }
                    }
                    print("✅ All episodes inserted")

                    dismiss()
                } catch {
                    print("Error adding show: \(error)")
                }
            } else if result.mediaType == "movie" {
                guard let id = result.id else { return }
                do {
                    let detail = try await tmdb.getMovie(id: id)
                    let movie = Movie(
                        id: detail.id,
                        tmdbId: detail.id,
                        title: detail.title,
                        overview: detail.overview,
                        posterUrl: detail.imageUrl,
                        releaseDate: detail.releaseDate
                    )
                    try await supabase.insertMovie(movie: movie)
                    dismiss()
                } catch {
                    print("Error adding movie: \(error)")
                }
            }
        }
    }
    
    private func addToWatchlist() {
        isAddingToWatchlist = true
        Task {
            guard let userId = supabase.currentUser?.id else {
                isAddingToWatchlist = false
                return
            }
            
            do {
                if result.mediaType == "tv" {
                    guard let showId = result.id else {
                        isAddingToWatchlist = false
                        return
                    }
                    try await supabase.addToWatchlistShow(
                        userId: userId,
                        showId: showId,
                        priority: selectedPriority,
                        notes: watchlistNotes.isEmpty ? nil : watchlistNotes
                    )
                } else if result.mediaType == "movie" {
                    guard let movieId = result.id else {
                        isAddingToWatchlist = false
                        return
                    }
                    try await supabase.addToWatchlistMovie(
                        userId: userId,
                        movieId: movieId,
                        priority: selectedPriority,
                        notes: watchlistNotes.isEmpty ? nil : watchlistNotes
                    )
                }
                isAddingToWatchlist = false
                showWatchlistOptions = false
                dismiss()
            } catch {
                print("Error adding to watchlist: \(error)")
                isAddingToWatchlist = false
            }
        }
    }
}

struct WatchlistOptionsSheet: View {
    let result: SearchResult
    @Binding var selectedPriority: String
    @Binding var notes: String
    @Binding var isAdding: Bool
    var onAdd: () -> Void
    var onDismiss: () -> Void
    @FocusState private var isNotesFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Text("Add to Watchlist")
                        .font(.headline)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Priority")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Picker("Priority", selection: $selectedPriority) {
                            Text("High").tag("high")
                            Text("Medium").tag("medium")
                            Text("Low").tag("low")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        TextEditor(text: $notes)
                            .frame(height: 80)
                            .border(Color.gray.opacity(0.3))
                            .cornerRadius(4)
                            .focused($isNotesFocused)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 12) {
                        Button(action: {
                            isNotesFocused = false
                            onAdd()
                        }) {
                            if isAdding {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Add to Watchlist")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .disabled(isAdding)
                        
                        Button(action: onDismiss) {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
            }
        }
    }
}

#Preview {
    SearchView()
}
