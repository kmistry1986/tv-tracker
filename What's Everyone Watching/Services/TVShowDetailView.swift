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
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding()
            } else if let show = show {
                VStack(alignment: .leading, spacing: 20) {
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
        .navigationTitle("Show Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadShowDetails()
            loadUserPlatforms()
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

                Label(show.displayStatus, systemImage: "tv")
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
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    // TODO: Add to library
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Add to")
                                .font(.caption2)
                                .fontWeight(.semibold)
                            Text("Library")
                                .font(.caption2)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                if isInLibrary {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                        .offset(x: 6, y: -6)
                }
            }

            ZStack(alignment: .topTrailing) {
                Button(action: {
                    // TODO: Add to watchlist
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Add to")
                                .font(.caption2)
                                .fontWeight(.semibold)
                            Text("Watchlist")
                                .font(.caption2)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                if isInWatchlist {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                        .offset(x: 6, y: -6)
                }
            }

            ZStack(alignment: .topTrailing) {
                Button(action: {
                    // TODO: Rate show
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Rate")
                                .font(.caption2)
                                .fontWeight(.semibold)
                            Text("Show")
                                .font(.caption2)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
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
