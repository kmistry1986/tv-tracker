import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var tmdb = TMDBService.shared
    @State private var isDocumentPickerPresented = false
    @State private var parsedEntries: [NetflixCSVParser.ParsedEntry] = []
    @State private var selectedEntries = Set<Int>()
    @State private var isImporting = false
    @State private var importProgress = 0
    @State private var totalItems = 0
    @State private var error: String?
    @State private var successMessage: String?
    @State private var failedItems: [String] = []
    @State private var showTestData = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if parsedEntries.isEmpty {
                    importEmptyState
                } else {
                    importPreview
                }
            }
            .navigationTitle("Import CSV")
        }
        .fileImporter(
            isPresented: $isDocumentPickerPresented,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
            onCompletion: handleFileSelection
        )
        .alert("Error", isPresented: .constant(error != nil), presenting: error) { _ in
            Button("OK") { error = nil }
        } message: { errorMsg in
            Text(errorMsg)
        }
        .alert("Success", isPresented: .constant(successMessage != nil), presenting: successMessage) { _ in
            Button("OK") { 
                successMessage = nil
                resetImport()
            }
        } message: { msg in
            Text(msg)
        }
    }
    
    @ViewBuilder
    private var importEmptyState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("Import Your Netflix History")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Easily add all your watched shows and movies")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            
            VStack(spacing: 12) {
                Button(action: { isDocumentPickerPresented = true }) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Choose Netflix CSV File")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                #if DEBUG
                Button(action: loadTestData) {
                    HStack {
                        Image(systemName: "testtube.2")
                        Text("Load Test Data (Dev Only)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                #endif
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get your Netflix CSV:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("1")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.blue)
                                .cornerRadius(12)
                            
                            Text("Visit viewingactivity.netflix.com")
                                .font(.caption)
                        }
                        
                        HStack(spacing: 8) {
                            Text("2")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.blue)
                                .cornerRadius(12)
                            
                            Text("Click \"Download Your Personal Information\"")
                                .font(.caption)
                        }
                        
                        HStack(spacing: 8) {
                            Text("3")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.blue)
                                .cornerRadius(12)
                            
                            Text("Save the CSV to your device")
                                .font(.caption)
                        }
                        
                        HStack(spacing: 8) {
                            Text("4")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.blue)
                                .cornerRadius(12)
                            
                            Text("Import it here!")
                                .font(.caption)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var importPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Parsed Entries: \(parsedEntries.count)")
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: resetImport) {
                    Text("Reset")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            List {
                ForEach(Array(parsedEntries.enumerated()), id: \.offset) { index, entry in
                    ImportEntryRow(entry: entry, isSelected: selectedEntries.contains(index))
                        .onTapGesture {
                            if selectedEntries.contains(index) {
                                selectedEntries.remove(index)
                            } else {
                                selectedEntries.insert(index)
                            }
                        }
                }
            }
            .frame(maxHeight: 300)
            
            if isImporting {
                VStack(spacing: 8) {
                    ProgressView(value: Double(importProgress), total: Double(totalItems))
                    HStack {
                        Text("\(importProgress) / \(totalItems) imported")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        if importProgress > 0 {
                            Text("(\(Int(Double(importProgress) / Double(totalItems) * 100))%)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
            } else {
                Button(action: startImport) {
                    Text("Import Selected (\(selectedEntries.count))")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedEntries.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(selectedEntries.isEmpty)
                .padding()
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                error = "Unable to access file. Please try again."
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                parsedEntries = try NetflixCSVParser.shared.parseCSV(content: content)
                selectedEntries = Set(0..<parsedEntries.count)
                error = nil
                
                if parsedEntries.isEmpty {
                    error = "No valid entries found in CSV. Make sure it's in Netflix format."
                }
            } catch {
                self.error = "Failed to parse CSV: \(error.localizedDescription)"
            }
            
        case .failure(let error):
            self.error = "Failed to read file: \(error.localizedDescription)"
        }
    }
    
    private func loadTestData() {
        let testCSV = """
        Title,Date Watched
        Dynasty: Season 4: Equal Justice for the Rich,8/4/26
        Dynasty: Season 4: Your Sick and Self-Serving Vendetta,8/4/26
        Hit & Run: Part & Parcel,8/4/26
        Dynasty: Season 4: The Birthday Party,8/4/26
        Dynasty: Season 4: A Little Father-Daughter Chat,8/4/26
        Ozark: Season 4: A Hard Way to Go,4/25/26
        Ozark: Season 4: Mud,4/24/26
        Ozark: Season 4: Trouble the Water,4/24/26
        Ozark: Season 4: Pound of Flesh and Still Kickin,4/24/26
        Peaky Blinders: Season 6: Lock and Key,8/15/23
        Peaky Blinders: Season 6: The Road to Hell,8/15/23
        Stranger Things: Stranger Things 3: Chapter Eight: The Battle of Starcourt,10/14/20
        Stranger Things: Stranger Things 2: Chapter Nine: The Gate,10/13/20
        The Crown: Season 4: War,12/7/20
        The Crown: Season 4: Avalanche,12/7/20
        Dexter: Season 8: Remember the Monsters,9/11/24
        Breaking Bad: Season 1: Pilot,2024-01-15
        The Office: Season 2: The Dundies,10/16/20
        House of Cards: Season 1: Chapter 1,8/25/20
        """
        
        do {
            parsedEntries = try NetflixCSVParser.shared.parseCSV(content: testCSV)
            selectedEntries = Set(0..<parsedEntries.count)
            error = nil
        } catch {
            self.error = "Failed to parse test data: \(error.localizedDescription)"
        }
    }
    
    private func startImport() {
        guard !selectedEntries.isEmpty else { return }

        isImporting = true
        importProgress = 0
        totalItems = selectedEntries.count
        error = nil

        Task {
            var successCount = 0
            var failedItems: [String] = []

            for (index, entryIndex) in selectedEntries.sorted().enumerated() {
                let entry = parsedEntries[entryIndex]

                do {
                    if entry.isShow {
                        var searchResults = try await tmdb.searchTV(query: entry.showName)

                        if searchResults.isEmpty, let firstWord = entry.showName.split(separator: " ").first {
                            searchResults = try await tmdb.searchTV(query: String(firstWord))
                        }

                        if searchResults.isEmpty {
                            searchResults = try await fuzzySearchTV(
                                showName: entry.showName,
                                episodeTitle: extractEpisodeTitle(from: entry.title)
                            )
                        }

                        // If multiple results, use episode name to find the right show
                        var selectedResult = searchResults.first
                        if searchResults.count > 1, let episodeTitle = extractEpisodeTitle(from: entry.title) {
                            selectedResult = await findShowByEpisodeName(
                                shows: searchResults,
                                episodeTitle: episodeTitle,
                                seasonNumber: entry.seasonNumber
                            ) ?? searchResults.first
                        }

                        if let firstResult = selectedResult ?? searchResults.first {
                            guard let userId = supabase.currentUser?.id else {
                                failedItems.append(entry.title)
                                importProgress = index + 1
                                continue
                            }
                            try await supabase.insertUserShow(
                                userId: userId,
                                showId: firstResult.id,
                                watchedDate: entry.date
                            )

                            // Insert show into tv_shows table first
                            let showDetail = try await tmdb.getTVShow(id: firstResult.id)
                            let tvShow = TVShow(
                                id: showDetail.id,
                                tmdbId: showDetail.id,
                                title: showDetail.name,
                                overview: showDetail.overview,
                                posterUrl: showDetail.imageUrl,
                                firstAirDate: showDetail.firstAirDate,
                                numberOfSeasons: showDetail.numberOfSeasons,
                                numberOfEpisodes: showDetail.numberOfEpisodes,
                                platforms: nil
                            )
                            do {
                                try await supabase.insertShow(show: tvShow)
                            } catch {
                                print("⚠️ Could not insert show: \(error)")
                            }

                            // Add all episodes for this show with watched=false
                            do {
                                for season in 1...showDetail.numberOfSeasons {
                                    let seasonDetail = try await tmdb.getTVSeason(showId: firstResult.id, seasonNumber: season)
                                    for episodeDetail in seasonDetail.episodes {
                                        var isWatched = false
                                        if let season = entry.seasonNumber, let episodeNum = entry.episodeNumber {
                                            isWatched = (season == episodeDetail.seasonNumber && episodeNum == episodeDetail.episodeNumber)
                                            if isWatched {
                                                print("✅ Matched by season/episode: S\(season)E\(episodeNum)")
                                            }
                                        } else if let episodeTitle = extractEpisodeTitle(from: entry.title) {
                                            let tmdbName = episodeDetail.name.lowercased()
                                            let netflixTitle = episodeTitle.lowercased()
                                            isWatched = tmdbName.contains(netflixTitle) || netflixTitle.contains(tmdbName)
                                            print("📺 Checking S\(episodeDetail.seasonNumber)E\(episodeDetail.episodeNumber): '\(episodeDetail.name)' vs '\(episodeTitle)' — match: \(isWatched)")
                                        }

                                        let tmdbEpisode = Episode(
                                            id: nil,
                                            showId: firstResult.id,
                                            tmdbId: episodeDetail.id,
                                            seasonNumber: episodeDetail.seasonNumber,
                                            episodeNumber: episodeDetail.episodeNumber,
                                            name: episodeDetail.name,
                                            overview: episodeDetail.overview ?? "",
                                            airDate: episodeDetail.airDate,
                                            userId: userId,
                                            watched: isWatched,
                                            watchedAt: isWatched ? entry.date : nil,
                                            showTitle: showDetail.name
                                        )

                                        do {
                                            try await supabase.insertEpisode(episode: tmdbEpisode)
                                        } catch {
                                            print("⚠️ Could not insert episode: \(error)")
                                        }
                                    }
                                }
                            } catch {
                                print("Could not fetch show episodes: \(error)")
                            }

                            print("✅ Imported: \(entry.showName)")
                            successCount += 1
                        } else {
                            print("❌ Could not find: \(entry.showName)")
                            failedItems.append(entry.title)
                        }
                    } else {
                        var searchResults = try await tmdb.searchMovie(query: entry.showName)

                        if searchResults.isEmpty, let firstWord = entry.showName.split(separator: " ").first {
                            searchResults = try await tmdb.searchMovie(query: String(firstWord))
                        }

                        if searchResults.isEmpty {
                            searchResults = try await fuzzySearchMovie(movieName: entry.showName)
                        }

                        if let firstResult = searchResults.first {
                            let movie = Movie(
                                id: firstResult.id,
                                tmdbId: firstResult.id,
                                title: firstResult.title,
                                overview: firstResult.overview ?? "",
                                posterUrl: firstResult.imageUrl,
                                releaseDate: firstResult.releaseDate,
                                runtime: nil,
                                platforms: nil
                            )
                            try await supabase.insertMovie(movie: movie)
                            print("✅ Imported: \(entry.showName)")
                            successCount += 1
                        } else {
                            print("❌ Could not find: \(entry.showName)")
                            failedItems.append(entry.title)
                        }
                    }
                } catch {
                    print("Error importing \(entry.title): \(error)")
                    failedItems.append(entry.title)
                }

                DispatchQueue.main.async {
                    importProgress = index + 1
                }
            }

            DispatchQueue.main.async {
                isImporting = false
                self.failedItems = failedItems

                if failedItems.isEmpty {
                    successMessage = "✅ Successfully imported \(successCount) items!"
                } else {
                    var message = "✅ Imported \(successCount) items\n⚠️ Failed to match \(failedItems.count) items:\n\n"
                    message += failedItems.prefix(5).joined(separator: "\n")
                    if failedItems.count > 5 {
                        message += "\n...and \(failedItems.count - 5) more"
                    }
                    successMessage = message
                }
            }
        }
    }

    private func fuzzySearchTV(showName: String, episodeTitle: String?) async throws -> [TVSearchResult] {
        var results: [TVSearchResult] = []

        if let episodeTitle = episodeTitle, !episodeTitle.isEmpty {
            let combined = "\(showName) \(episodeTitle)"
            results = try await tmdb.searchTV(query: combined)
            if !results.isEmpty {
                return results
            }
        }

        let cleaned = showName
            .lowercased()
            .replacingOccurrences(of: #"[&-:,!?]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if !cleaned.isEmpty && cleaned != showName.lowercased() {
            results = try await tmdb.searchTV(query: cleaned)
            if !results.isEmpty {
                return results
            }
        }

        let noNumbers = cleaned
            .replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if !noNumbers.isEmpty && noNumbers != cleaned {
            results = try await tmdb.searchTV(query: noNumbers)
        }

        return results
    }

    private func fuzzySearchMovie(movieName: String) async throws -> [MovieSearchResult] {
        var results: [MovieSearchResult] = []

        let cleaned = movieName
            .lowercased()
            .replacingOccurrences(of: #"[&-:,!?]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if !cleaned.isEmpty && cleaned != movieName.lowercased() {
            results = try await tmdb.searchMovie(query: cleaned)
            if !results.isEmpty {
                return results
            }
        }

        let noNumbers = cleaned
            .replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if !noNumbers.isEmpty && noNumbers != cleaned {
            results = try await tmdb.searchMovie(query: noNumbers)
        }

        return results
    }

private func findShowByEpisodeName(shows: [TVSearchResult], episodeTitle: String, seasonNumber: Int?) async -> TVSearchResult? {
        for show in shows {
            do {
                let showDetail = try await tmdb.getTVShow(id: show.id)
                
                // Try the specific season from Netflix, or up to season 5
                let seasons = seasonNumber.map { [$0] } ?? (1...min(showDetail.numberOfSeasons, 5)).map { $0 }
                
                for season in seasons {
                    if season > showDetail.numberOfSeasons { continue }
                    let seasonDetail = try await tmdb.getTVSeason(showId: show.id, seasonNumber: season)
                    
                    for episode in seasonDetail.episodes {
                        let tmdbName = episode.name.lowercased()
                        let netflixName = episodeTitle.lowercased()
                        
                        if tmdbName.contains(netflixName) || netflixName.contains(tmdbName) {
                            print("✅ Episode '\(episodeTitle)' matched in \(show.name)")
                            return show
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

        private func extractEpisodeTitle(from fullTitle: String) -> String? {
        let parts = fullTitle.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        if parts.count >= 3 {
            return String(parts[2]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    private func resetImport() {
        parsedEntries = []
        selectedEntries = []
        importProgress = 0
        totalItems = 0
        error = nil
    }
}


#Preview {
    ImportView()
}
