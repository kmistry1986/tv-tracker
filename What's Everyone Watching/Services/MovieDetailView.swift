import SwiftUI

struct MovieDetailView: View {
    let movieId: Int

    @StateObject private var tmdb = TMDBService.shared
    @StateObject private var supabase = SupabaseService.shared
    @State private var movie: MovieDetail?
    @State private var watchProviders: WatchProvidersResult?
    @State private var userPlatforms: Set<String> = []
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding()
            } else if let movie = movie {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with poster and basic info
                    headerSection(movie: movie)
                    
                    // Watch Providers
                    if let providers = watchProviders {
                        WatchProvidersView(providers: providers, userPlatforms: userPlatforms)
                            .padding(.horizontal)
                    }
                    
                    // Overview
                    overviewSection(movie: movie)
                    
                    // Movie Details
                    detailsSection(movie: movie)
                    
                    // Action Buttons
                    actionButtonsSection(movie: movie)
                }
                .padding(.bottom)
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Error Loading Movie")
                        .font(.headline)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle("Movie Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMovieDetails()
            loadUserPlatforms()
        }
    }
    
    // MARK: - Header Section
    
    private func headerSection(movie: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                // Poster
                VStack(spacing: 8) {
                    if let imageUrl = movie.imageUrl, let url = URL(string: imageUrl) {
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
                }

                // Basic Info
                VStack(alignment: .leading, spacing: 8) {
                    Text(movie.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let releaseDate = movie.releaseDate {
                        Label(releaseDate.prefix(4), systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Label("Movie", systemImage: "film")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding()
    }
    
    // MARK: - Overview Section
    
    private func overviewSection(movie: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            
            Text(movie.overview)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Details Section
    
    private func detailsSection(movie: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            VStack(spacing: 8) {
                if let releaseDate = movie.releaseDate {
                    DetailRow(label: "Release Date", value: releaseDate)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Action Buttons
    
    private func actionButtonsSection(movie: MovieDetail) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                // TODO: Add to library
            }) {
                Label("Add to Library", systemImage: "books.vertical.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Button(action: {
                // TODO: Add to watchlist
            }) {
                Label("Add to Watchlist", systemImage: "bookmark.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Button(action: {
                // TODO: Rate movie
            }) {
                Label("Rate This Movie", systemImage: "star.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Loading

    private func loadMovieDetails() async {
        isLoading = true
        error = nil

        do {
            // Load movie details and watch providers concurrently
            async let movieData = tmdb.getMovie(id: movieId)
            async let providersData = tmdb.getMovieWatchProviders(movieId: movieId)

            self.movie = try await movieData
            self.watchProviders = try await providersData
        } catch {
            self.error = error.localizedDescription
            print("Error loading movie details: \(error)")
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
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MovieDetailView(movieId: 550) // Fight Club
    }
}
