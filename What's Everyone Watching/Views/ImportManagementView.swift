import SwiftUI
import UniformTypeIdentifiers

struct ImportManagementView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Netflix").tag(0)
                    Text("Prime Video").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 10)

                if selectedTab == 0 {
                    NetflixImportView()
                } else {
                    PrimeVideoImportView()
                }
            }
            .navigationTitle("Import")
        }
    }
}

struct NetflixImportView: View {
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
    @State private var failedImports: [FailedImport] = []
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            if parsedEntries.isEmpty && !showHistory {
                importEmptyState
            } else if showHistory {
                failedImportHistory
            } else {
                importPreview
            }
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
        .onAppear {
            loadFailedImports()
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

                if !failedImports.isEmpty {
                    Button(action: { showHistory = true }) {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                            Text("View Failed Imports (\(failedImports.count))")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                    }
                }

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

    @ViewBuilder
    private var failedImportHistory: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Failed Imports (\(failedImports.count))")
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { showHistory = false }) {
                    Text("Back")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)

            if failedImports.isEmpty {
                VStack {
                    Text("No failed imports")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(failedImports.sorted { $0.timestamp > $1.timestamp }, id: \.id) { failedImport in
                        NavigationLink(destination: SearchView(initialSearchQuery: failedImport.title)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(failedImport.title)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)

                                HStack(spacing: 8) {
                                    Text(formatDate(failedImport.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    Spacer()

                                    Text("Netflix")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(4)

                                    Image(systemName: "magnifyingglass")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
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
        Ozark: Season 4: A Hard Way to Go,4/25/26
        Breaking Bad: Season 1: Pilot,2024-01-15
        Hit & Run: Part & Parcel,8/4/26
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
            var newFailedImports: [FailedImport] = []
            let now = Date()

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
                                newFailedImports.append(FailedImport(title: entry.title, timestamp: now))
                                importProgress = index + 1
                                continue
                            }

                            // Check if this show is already in user's library to avoid duplicates
                            let existingShows = (try? await supabase.fetchUserShows(userId: userId)) ?? []
                            if !existingShows.contains(where: { $0.showId == firstResult.id }) {
                                try await supabase.insertUserShow(
                                    userId: userId,
                                    showId: firstResult.id,
                                    watchedDate: entry.date
                                )
                            }

                            let showDetail = try await tmdb.getTVShow(id: firstResult.id)
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
                            } catch {
                                print("⚠️ Could not insert show: \(error)")
                            }

                            do {
                                var seasonTasks: [Task<SeasonDetail, Error>] = []
                                for season in 1...showDetail.numberOfSeasons {
                                    let task = Task {
                                        return try await self.tmdb.getTVSeason(showId: firstResult.id, seasonNumber: season)
                                    }
                                    seasonTasks.append(task)
                                }

                                for seasonTask in seasonTasks {
                                    let seasonDetail = try await seasonTask.value
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
                                            id: episodeDetail.id,
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
                                            if isWatched {
                                                print("✅ Inserted watched episode S\(episodeDetail.seasonNumber)E\(episodeDetail.episodeNumber): \(episodeDetail.name)")
                                            }
                                        } catch {
                                            print("⚠️ Could not insert episode S\(episodeDetail.seasonNumber)E\(episodeDetail.episodeNumber): \(error)")
                                        }
                                    }
                                }
                            } catch {
                                print("Could not fetch show episodes: \(error)")
                            }

                            successCount += 1
                        } else {
                            newFailedImports.append(FailedImport(title: entry.title, timestamp: now))
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
                            guard let userId = supabase.currentUser?.id else {
                                newFailedImports.append(FailedImport(title: entry.title, timestamp: now))
                                importProgress = index + 1
                                continue
                            }

                            let movie = Movie(
                                id: firstResult.id,
                                tmdbId: firstResult.id,
                                title: firstResult.title,
                                overview: firstResult.overview ?? "",
                                posterUrl: firstResult.imageUrl,
                                releaseDate: firstResult.releaseDate
                            )
                            try await supabase.insertMovie(movie: movie)

                            // Check if this movie is already in user's library to avoid duplicates
                            let existingMovies = (try? await supabase.fetchUserMovies(userId: userId)) ?? []
                            if !existingMovies.contains(where: { $0.movieId == firstResult.id }) {
                                try await supabase.insertUserMovie(userId: userId, movieId: firstResult.id, watchedDate: entry.date)
                            }
                            successCount += 1
                        } else {
                            newFailedImports.append(FailedImport(title: entry.title, timestamp: now))
                        }
                    }
                } catch {
                    newFailedImports.append(FailedImport(title: entry.title, timestamp: now))
                }

                DispatchQueue.main.async {
                    importProgress = index + 1
                }
            }

            DispatchQueue.main.async {
                isImporting = false
                failedImports.append(contentsOf: newFailedImports)
                saveFailedImports()

                if newFailedImports.isEmpty {
                    successMessage = "✅ Successfully imported \(successCount) items!"
                } else {
                    successMessage = "✅ Imported \(successCount) items\n⚠️ Failed to match \(newFailedImports.count) items"
                }
            }
        }
    }

    private func resetImport() {
        parsedEntries = []
        selectedEntries = []
        importProgress = 0
        totalItems = 0
        error = nil
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

    private func extractEpisodeTitle(from title: String) -> String? {
        let parts = title.split(separator: ":")
        if parts.count >= 2 {
            // Return the last part (works for both "Show: Episode" and "Show: Season X: Episode")
            return String(parts.last ?? "").trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func saveFailedImports() {
        if let encoded = try? JSONEncoder().encode(failedImports) {
            UserDefaults.standard.set(encoded, forKey: "failedImports")
        }
    }

    private func loadFailedImports() {
        if let data = UserDefaults.standard.data(forKey: "failedImports"),
           let decoded = try? JSONDecoder().decode([FailedImport].self, from: data) {
            failedImports = decoded
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct FailedImport: Codable, Identifiable {
    let id = UUID()
    let title: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case title, timestamp
    }
}

struct ImportEntryRow: View {
    let entry: NetflixCSVParser.ParsedEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(entry.date)
                        .font(.caption)
                        .foregroundColor(.gray)

                    if entry.isShow {
                        Text("TV Show")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct PrimeVideoImportView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Coming Soon")
                .font(.title2)
                .fontWeight(.bold)

            Text("Prime Video import support will be available soon")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    ImportManagementView()
}
