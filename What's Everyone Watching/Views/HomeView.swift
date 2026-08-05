import SwiftUI

struct HomeView: View {
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var tmdb = TMDBService.shared
    @State private var trendingShows: [SearchResult] = []
    @State private var trendingMovies: [SearchResult] = []
    @State private var libraryCount = 0
    @State private var watchlistCount = 0
    @State private var ratedCount = 0
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerSection
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            quickActionsSection
                            
                            if !trendingShows.isEmpty {
                                trendingShowsSection
                            }
                            
                            if !trendingMovies.isEmpty {
                                trendingMoviesSection
                            }
                            
                            statsSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("TV Tracker")
            .onAppear {
                loadTrendingContent()
                loadStats()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back!")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Text(supabase.currentUser?.name ?? "User")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
            }
            .padding()
        }
        .background(Color(.systemGray6))
    }
    
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            NavigationLink(destination: SearchView()) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Search Shows & Movies")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Find new content to watch")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            NavigationLink(destination: WatchlistView()) {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("View Watchlist")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("See what you want to watch")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.green)
                .cornerRadius(12)
            }
        }
    }
    
    private var trendingShowsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Trending TV Shows")
                    .font(.headline)
                
                Spacer()
                
                NavigationLink(destination: SearchView()) {
                    Text("See All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
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
                                        .frame(width: 100)
                                }
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
                
                NavigationLink(destination: SearchView()) {
                    Text("See All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
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
                                        .frame(width: 100)
                                }
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
                StatCard(icon: "books.vertical.fill", title: "Library", value: String(libraryCount), color: .blue)
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
                
                libraryCount = userShows.count + userMovies.count
                watchlistCount = watchlistShows.count + watchlistMovies.count
                ratedCount = (userShows.filter { $0.rating != nil }.count) + (userMovies.filter { $0.rating != nil }.count)
            } catch {
                print("Error loading stats: \(error)")
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

#Preview {
    HomeView()
        .environmentObject(SupabaseService.shared)
}
