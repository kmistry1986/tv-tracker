import Foundation

struct StreamingPlatform {
    let id: Int
    let displayName: String
    let tmdbProviderNames: [String]
}

class StreamingPlatformMapper {
    static var platforms: [StreamingPlatform] = []
    static var isLoaded = false

    // Fallback hardcoded platforms (used if Supabase fetch fails)
    static let fallbackPlatforms: [StreamingPlatform] = [
        StreamingPlatform(
            id: 8,
            displayName: "Netflix",
            tmdbProviderNames: ["Netflix"]
        ),
        StreamingPlatform(
            id: 337,
            displayName: "Disney+",
            tmdbProviderNames: ["Disney Plus"]
        ),
        StreamingPlatform(
            id: 384,
            displayName: "HBO Max",
            tmdbProviderNames: ["HBO Max"]
        ),
        StreamingPlatform(
            id: 15,
            displayName: "Hulu",
            tmdbProviderNames: ["Hulu"]
        ),
        StreamingPlatform(
            id: 9,
            displayName: "Amazon Prime",
            tmdbProviderNames: ["Amazon Prime Video", "Amazon Prime Vide...", "Amazon Prime Video with Ads", "Amazon Video On Demand", "Amazon Prime Video Amazon Channel"]
        ),
        StreamingPlatform(
            id: 350,
            displayName: "Apple TV+",
            tmdbProviderNames: ["Apple TV", "Apple TV Plus", "Apple TV Amazon Channel", "Apple TV Channels"]
        ),
        StreamingPlatform(
            id: 531,
            displayName: "Paramount+",
            tmdbProviderNames: ["Paramount Plus", "Paramount+"]
        ),
        StreamingPlatform(
            id: 1899,
            displayName: "Max",
            tmdbProviderNames: ["Max"]
        ),
        StreamingPlatform(
            id: 372,
            displayName: "Peacock",
            tmdbProviderNames: ["Peacock"]
        ),
        StreamingPlatform(
            id: 2,
            displayName: "Apple iTunes",
            tmdbProviderNames: ["Apple iTunes"]
        ),
        StreamingPlatform(
            id: 3,
            displayName: "Google Play",
            tmdbProviderNames: ["Google Play Movies", "Google Play"]
        ),
        StreamingPlatform(
            id: 29,
            displayName: "Vudu",
            tmdbProviderNames: ["Vudu"]
        ),
        StreamingPlatform(
            id: 192,
            displayName: "YouTube",
            tmdbProviderNames: ["YouTube", "YouTube Movies"]
        ),
        StreamingPlatform(
            id: 105,
            displayName: "Crunchyroll",
            tmdbProviderNames: ["Crunchyroll"]
        ),
        StreamingPlatform(
            id: 188,
            displayName: "BritBox",
            tmdbProviderNames: ["BritBox"]
        ),
        StreamingPlatform(
            id: 37,
            displayName: "Showtime",
            tmdbProviderNames: ["Showtime"]
        ),
        StreamingPlatform(
            id: 45,
            displayName: "Starz",
            tmdbProviderNames: ["Starz"]
        ),
        StreamingPlatform(
            id: 505,
            displayName: "FuboTV",
            tmdbProviderNames: ["FuboTV"]
        ),
        StreamingPlatform(
            id: 456,
            displayName: "Sling TV",
            tmdbProviderNames: ["Sling TV"]
        ),
        StreamingPlatform(
            id: 386,
            displayName: "YouTube TV",
            tmdbProviderNames: ["YouTube TV"]
        ),
        StreamingPlatform(
            id: 257,
            displayName: "Tubi",
            tmdbProviderNames: ["Tubi"]
        ),
        StreamingPlatform(
            id: 189,
            displayName: "Pluto TV",
            tmdbProviderNames: ["Pluto TV"]
        ),
        StreamingPlatform(
            id: 25,
            displayName: "Fandango",
            tmdbProviderNames: ["Fandango At Home", "FandangoNow"]
        )
    ]

    static func loadPlatforms() async {
        do {
            let supabase = SupabaseService.shared
            let rows = try await supabase.getStreamingPlatforms()
            platforms = rows.map { StreamingPlatform(id: $0.id, displayName: $0.display_name, tmdbProviderNames: $0.tmdb_provider_names) }
            isLoaded = true
            print("✅ Loaded \(platforms.count) streaming platforms from Supabase")
        } catch {
            print("⚠️ Failed to load platforms from Supabase, using fallback: \(error)")
            platforms = fallbackPlatforms
            isLoaded = true
        }
    }

    static func ensureLoaded() async {
        if !isLoaded {
            await loadPlatforms()
        }
    }

    static func getDisplayName(for platformId: Int) -> String? {
        platforms.first(where: { $0.id == platformId })?.displayName
    }

    static func getPlatformId(for displayName: String) -> Int? {
        platforms.first(where: { $0.displayName == displayName })?.id
    }

    static func isUserSubscribedTo(providerName: String, userDisplayNames: [String]) -> Bool {
        let providerNameLower = providerName.lowercased()
            .replacingOccurrences(of: " with ads", with: "")
            .replacingOccurrences(of: " (basic)", with: "")
            .trimmingCharacters(in: .whitespaces)

        for userDisplayName in userDisplayNames {
            if let platform = platforms.first(where: { $0.displayName == userDisplayName }) {
                for tmdbName in platform.tmdbProviderNames {
                    let tmdbNameLower = tmdbName.lowercased()
                        .replacingOccurrences(of: " with ads", with: "")
                        .replacingOccurrences(of: " (basic)", with: "")
                        .trimmingCharacters(in: .whitespaces)

                    if providerNameLower == tmdbNameLower || providerNameLower.contains(tmdbNameLower) {
                        return true
                    }
                }
            }
        }

        return false
    }

    static func deduplicateProviders(_ providerNames: [String]) -> [String] {
        var seen = Set<String>()
        var deduped: [String] = []

        for providerName in providerNames {
            let key = providerName.lowercased()
                .replacingOccurrences(of: " with ads", with: "")
                .replacingOccurrences(of: " (basic)", with: "")
                .trimmingCharacters(in: .whitespaces)

            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(providerName)
            }
        }

        return deduped
    }
}
