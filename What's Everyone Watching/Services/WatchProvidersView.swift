import SwiftUI

struct WatchProvidersView: View {
    let providers: WatchProvidersResult
    var userPlatforms: Set<String> = []

    private func isUserSubscribedTo(provider: WatchProvider) -> Bool {
        let providerName = provider.providerName.lowercased()
            .replacingOccurrences(of: " with ads", with: "")
            .replacingOccurrences(of: " (basic)", with: "")
            .trimmingCharacters(in: .whitespaces)

        for platform in userPlatforms {
            let platformLower = platform.lowercased()
                .replacingOccurrences(of: " with ads", with: "")
                .replacingOccurrences(of: " (basic)", with: "")
                .trimmingCharacters(in: .whitespaces)

            // Exact match first
            if providerName == platformLower {
                return true
            }

            // Partial matches - only if both contain the keyword
            if platformLower.contains("amazon") && providerName.contains("amazon") {
                return true
            }

            if (platformLower.contains("hbo") || platformLower.contains("max")) &&
               (providerName.contains("hbo") || providerName.contains("max")) {
                return true
            }

            if platformLower.contains("apple") && providerName.contains("apple") {
                return true
            }

            if platformLower.contains("disney") && providerName.contains("disney") {
                return true
            }

            if platformLower.contains("paramount") && providerName.contains("paramount") {
                return true
            }
        }

        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where to Watch")
                .font(.headline)
            
            // Streaming Services (Subscription)
            if !providers.streamingProviders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stream")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    providerLogos(providers: providers.streamingProviders)
                }
            }
            
            // Buy Options
            if let buyProviders = providers.buy, !buyProviders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Buy")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    providerLogos(providers: buyProviders)
                }
            }
            
            // Rent Options
            if let rentProviders = providers.rent, !rentProviders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rent")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    providerLogos(providers: rentProviders)
                }
            }
            
            // Link to full details
            if let link = providers.link, let url = URL(string: link) {
                Link(destination: url) {
                    HStack {
                        Text("See more options")
                            .font(.caption)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
            
            Text("Provided by JustWatch")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func providerLogos(providers: [WatchProvider]) -> some View {
        let deduplicatedProviders = deduplicateProviders(providers)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(deduplicatedProviders.sorted(by: { $0.displayPriority < $1.displayPriority })) { provider in
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            AsyncImage(url: URL(string: provider.logoUrl)) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                Color.gray
                            }
                            .frame(width: 50, height: 50)
                            .cornerRadius(8)

                            // Subscription status badge
                            if !userPlatforms.isEmpty {
                                Image(systemName: isUserSubscribedTo(provider: provider) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(isUserSubscribedTo(provider: provider) ? .green : .red)
                                    .background(Circle().fill(Color(.systemBackground)).frame(width: 20, height: 20))
                                    .offset(x: 4, y: -4)
                            }
                        }

                        Text(provider.providerName)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 60, maxWidth: 70)
                    }
                }
            }
        }
    }

    private func deduplicateProviders(_ providers: [WatchProvider]) -> [WatchProvider] {
        var seen = Set<String>()
        var deduped: [WatchProvider] = []

        for provider in providers {
            let key = provider.providerName.lowercased()
                .replacingOccurrences(of: " with ads", with: "")
                .replacingOccurrences(of: " (basic)", with: "")
                .trimmingCharacters(in: .whitespaces)

            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(provider)
            }
        }

        return deduped
    }
}

// MARK: - Compact Version (for smaller spaces)

struct WatchProvidersCompactView: View {
    let providers: WatchProvidersResult
    let maxLogos: Int
    
    init(providers: WatchProvidersResult, maxLogos: Int = 4) {
        self.providers = providers
        self.maxLogos = maxLogos
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available on")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(providers.streamingProviders.prefix(maxLogos).sorted(by: { $0.displayPriority < $1.displayPriority })) { provider in
                    AsyncImage(url: URL(string: provider.logoUrl)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Color.gray
                    }
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                }
                
                if providers.streamingProviders.count > maxLogos {
                    Text("+\(providers.streamingProviders.count - maxLogos)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Full version
        WatchProvidersView(providers: WatchProvidersResult(
            link: "https://www.themoviedb.org",
            flatrate: [
                WatchProvider(
                    providerId: 8,
                    providerName: "Netflix",
                    logoPath: "/t2yyOv40HZeVlLjYsCsPHnWLk4W.jpg",
                    displayPriority: 0
                ),
                WatchProvider(
                    providerId: 337,
                    providerName: "Disney Plus",
                    logoPath: "/7rwgEs15tFwyR9NPQ5vpzxTj19Q.jpg",
                    displayPriority: 1
                )
            ],
            buy: [
                WatchProvider(
                    providerId: 2,
                    providerName: "Apple TV",
                    logoPath: "/peURlLlr8jggOwK53fJ5wdQl05y.jpg",
                    displayPriority: 2
                )
            ],
            rent: [
                WatchProvider(
                    providerId: 3,
                    providerName: "Google Play Movies",
                    logoPath: "/tbEdFQDwx5LEVr8WpSeXQSIirVq.jpg",
                    displayPriority: 3
                )
            ],
            free: nil
        ))
        
        // Compact version
        WatchProvidersCompactView(providers: WatchProvidersResult(
            link: nil,
            flatrate: [
                WatchProvider(
                    providerId: 8,
                    providerName: "Netflix",
                    logoPath: "/t2yyOv40HZeVlLjYsCsPHnWLk4W.jpg",
                    displayPriority: 0
                )
            ],
            buy: nil,
            rent: nil,
            free: nil
        ))
    }
    .padding()
}

// MARK: - Async Loading Badge (Use in ForEach loops)

struct WatchProvidersBadge: View {
    let showId: Int?
    let mediaType: String
    let region: String
    
    @StateObject private var tmdb = TMDBService.shared
    @State private var providers: WatchProvidersResult?
    
    init(showId: Int?, mediaType: String, region: String = "US") {
        self.showId = showId
        self.mediaType = mediaType
        self.region = region
    }
    
    var body: some View {
        Group {
            if let providers = providers, !providers.streamingProviders.isEmpty {
                HStack(spacing: 4) {
                    ForEach(providers.streamingProviders.prefix(3).sorted(by: { $0.displayPriority < $1.displayPriority })) { provider in
                        AsyncImage(url: URL(string: provider.logoUrl)) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Color.gray
                        }
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
                    }
                    
                    if providers.streamingProviders.count > 3 {
                        Text("+\(providers.streamingProviders.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .task {
            await loadProviders()
        }
    }
    
    private func loadProviders() async {
        guard let id = showId else { return }
        
        do {
            if mediaType == "tv" {
                providers = try await tmdb.getTVWatchProviders(tvId: id, region: region)
            } else if mediaType == "movie" {
                providers = try await tmdb.getMovieWatchProviders(movieId: id, region: region)
            }
        } catch {
            // Silently fail - providers are optional
        }
    }
}
