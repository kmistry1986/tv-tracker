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
    @State private var selectedShow: SearchResult?
    @State private var selectedMovie: SearchResult?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            VStack(spacing: 12) {
                                Text("Trending Now")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if !trendingShows.isEmpty {
                                    VStack(spacing: 8) {
                                        Text("TV Shows")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(trendingShows.prefix(10), id: \.id) { show in
                                                    Button(action: { selectedShow = show }) {
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
                                                                .foregroundColor(.primary)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                if !trendingMovies.isEmpty {
                                    VStack(spacing: 8) {
                                        Text("Movies")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(trendingMovies.prefix(10), id: \.id) { movie in
                                                    Button(action: { selectedMovie = movie }) {
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
                                                                .foregroundColor(.primary)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            quickActionsSection

                            statsSection
                        }
                        .padding()
                        .padding(.top, 10)
                    }
                }
            }
            .navigationTitle("TV Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadTrendingContent()
                loadStats()
            }
            .sheet(item: $selectedShow) { show in
                SearchDetailView(result: show)
            }
            .sheet(item: $selectedMovie) { movie in
                SearchDetailView(result: movie)
            }
        }
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
                async let shows = tmdb.getTrendingTV()
                async let movies = tmdb.getTrendingMovies()

                let (showResults, movieResults) = await (shows, movies)

                DispatchQueue.main.async {
                    self.trendingShows = showResults
                    self.trendingMovies = movieResults
                    self.isLoading = false
                }
            } catch {
                print("Error loading trending content: \(error)")
                self.isLoading = false
            }
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
