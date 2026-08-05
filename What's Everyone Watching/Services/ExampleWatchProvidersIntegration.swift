import SwiftUI

/// Example of how to use WatchProviders in a TV Show or Movie detail view
struct ExampleDetailView: View {
    let showId: Int
    let mediaType: String  // "tv" or "movie"
    
    @StateObject private var tmdb = TMDBService.shared
    @State private var watchProviders: WatchProvidersResult?
    @State private var isLoadingProviders = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Your existing detail content here...
                Text("Show/Movie Details")
                    .font(.title)
                
                // Add watch providers section
                if let providers = watchProviders {
                    WatchProvidersView(providers: providers)
                } else if isLoadingProviders {
                    ProgressView("Loading streaming options...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    // No providers available
                    Text("Streaming availability not available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
        }
        .onAppear {
            loadWatchProviders()
        }
    }
    
    private func loadWatchProviders() {
        isLoadingProviders = true
        Task {
            do {
                if mediaType == "tv" {
                    watchProviders = try await tmdb.getTVWatchProviders(tvId: showId)
                } else {
                    watchProviders = try await tmdb.getMovieWatchProviders(movieId: showId)
                }
            } catch {
                print("Error loading watch providers: \(error)")
            }
            isLoadingProviders = false
        }
    }
}

// MARK: - Example with Compact View (for list items)

struct ExampleShowListItem: View {
    let show: SearchResult
    @State private var watchProviders: WatchProvidersResult?
    
    var body: some View {
        HStack {
            // Poster
            AsyncImage(url: URL(string: show.imageUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray
            }
            .frame(width: 60, height: 90)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(show.displayTitle)
                    .font(.headline)
                
                // Compact watch providers
                if let providers = watchProviders, !providers.streamingProviders.isEmpty {
                    WatchProvidersCompactView(providers: providers, maxLogos: 3)
                }
            }
            
            Spacer()
        }
        .task {
            await loadProviders()
        }
    }
    
    private func loadProviders() async {
        guard let id = show.id else { return }
        
        do {
            if show.mediaType == "tv" {
                watchProviders = try await TMDBService.shared.getTVWatchProviders(tvId: id)
            } else if show.mediaType == "movie" {
                watchProviders = try await TMDBService.shared.getMovieWatchProviders(movieId: id)
            }
        } catch {
            print("Error loading providers: \(error)")
        }
    }
}

// MARK: - Preview

#Preview("Detail View") {
    ExampleDetailView(showId: 1396, mediaType: "tv")  // Breaking Bad
}

#Preview("List Item") {
    ExampleShowListItem(show: SearchResult(
        id: 1396,
        mediaType: "tv",
        name: "Breaking Bad",
        title: nil,
        posterPath: "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
        overview: "A high school chemistry teacher..."
    ))
}
