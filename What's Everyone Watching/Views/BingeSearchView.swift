//  BingeSearchView.swift
//  The fourth tab. Search is a destination, not a field bolted onto another screen.
//
//  Reads: TMDBService.searchTV / searchMovie / getTVWatchProviders / getMovieWatchProviders,
//         SupabaseService.searchUsers, fetchFriends, getFriendRatings, fetchUserShows,
//         fetchWatchlistShows, fetchWatchlistMovies, addToWatchlistShow, addToWatchlistMovie,
//         sendFriendRequest.
//
//  NOTE: in this codebase `show_id` / `movie_id` ARE the TMDB ids — addToWatchlistShow
//  passes showId straight to TMDBService.getTVShow(id:). So nothing here needs to
//  translate between id spaces.

import SwiftUI
import Combine

// MARK: - Row model

struct BingeSearchResult: Identifiable {
    let tmdbId: Int
    let title: String
    let posterUrl: String?
    let year: String?
    let isMovie: Bool
    var id: String { "\(isMovie ? "m" : "t")\(tmdbId)" }
}

// MARK: - Engine

@MainActor
final class BingeSearchEngine: ObservableObject {
    @Published var query = ""
    @Published var scope = 0                       // 0 All · 1 Shows · 2 Movies · 3 People
    @Published var results: [BingeSearchResult] = []
    @Published var people: [UserProfile] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    /// tmdb id -> how many friends finished it
    @Published private(set) var friendsFinished: [Int: Int] = [:]
    @Published private(set) var platforms: [String: String] = [:]   // row id -> provider
    @Published private(set) var saved: Set<String> = []
    @Published private(set) var requested: Set<String> = []
    @Published var ratingTarget: BingeSearchResult?

    private var watchlistShows: Set<Int> = []
    private var watchlistMovies: Set<Int> = []
    /// movie tmdb id -> watchlist_movies row id (that table only deletes by row id)
    private var watchlistMovieRows: [Int: Int] = [:]
    private var libraryShows: Set<Int> = []
    private var libraryMovies: Set<Int> = []
    private var finishedShows: Set<Int> = []
    private let supabase = SupabaseService.shared
    private var searchTask: Task<Void, Never>?

    // MARK: Context

    /// Everything the rows need to describe themselves. Loaded once when the tab opens.
    func primeContext() async {
        guard let userId = supabase.currentUser?.id else { return }

        if let mine = try? await supabase.fetchUserShows(userId: userId) {
            libraryShows = Set(mine.map(\.showId))
            finishedShows = Set(mine.filter { ($0.rating ?? 0) > 0 }.map(\.showId))
        }
        if let myMovies = try? await supabase.fetchUserMovies(userId: userId) {
            libraryMovies = Set(myMovies.map(\.movieId))
        }
        if let wl = try? await supabase.fetchWatchlistShows(userId: userId) {
            watchlistShows = Set(wl.map(\.showId))
        }
        if let wlm = try? await supabase.fetchWatchlistMovies(userId: userId) {
            watchlistMovies = Set(wlm.map(\.movieId))
            watchlistMovieRows = Dictionary(wlm.map { ($0.movieId, $0.id) }, uniquingKeysWith: { a, _ in a })
        }

        guard let friends = try? await supabase.fetchFriends(userId: userId) else { return }
        var counts: [Int: Int] = [:]
        for friend in friends {
            let rated = (try? await supabase.getFriendRatings(friendId: friend.id)) ?? []
            for row in rated where (row.rating ?? 0) >= 4 {
                counts[row.showId, default: 0] += 1
            }
        }
        friendsFinished = counts
    }

    func friendLine(for result: BingeSearchResult) -> (text: String, accent: Bool) {
        guard !result.isMovie, let n = friendsFinished[result.tmdbId], n > 0 else {
            return ("Nobody you follow yet", false)
        }
        return (n == 1 ? "1 friend finished" : "\(n) friends finished", true)
    }

    // MARK: Search

    func queryChanged() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []; people = []; isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)     // debounce
            guard !Task.isCancelled else { return }
            await self?.run(text)
        }
    }

    private func run(_ text: String) async {
        defer { isSearching = false }
        errorMessage = nil

        if scope == 3 {
            results = []
            people = (try? await supabase.searchUsers(query: text)) ?? []
            return
        }
        // "All" mixes people in above the titles, capped so they never bury results.
        if scope == 0 {
            people = Array(((try? await supabase.searchUsers(query: text)) ?? []).prefix(3))
        } else {
            people = []
        }

        var rows: [BingeSearchResult] = []
        if scope == 0 || scope == 1 {
            let tv = (try? await TMDBService.shared.searchTV(query: text)) ?? []
            rows += tv.map {
                BingeSearchResult(tmdbId: $0.id, title: $0.name, posterUrl: $0.imageUrl,
                                  year: year($0.firstAirDate), isMovie: false)
            }
        }
        if scope == 0 || scope == 2 {
            let movies = (try? await TMDBService.shared.searchMovie(query: text)) ?? []
            rows += movies.map {
                BingeSearchResult(tmdbId: $0.id, title: $0.title, posterUrl: $0.imageUrl,
                                  year: year($0.releaseDate), isMovie: true)
            }
        }
        // Titles your people have finished rise to the top.
        results = rows.sorted { (friendsFinished[$0.tmdbId] ?? 0) > (friendsFinished[$1.tmdbId] ?? 0) }
    }

    /// Platform is fetched per row as it scrolls into view, then cached.
    func loadPlatform(for result: BingeSearchResult) async {
        guard platforms[result.id] == nil else { return }
        let provider: WatchProvidersResult?
        if result.isMovie {
            provider = try? await TMDBService.shared.getMovieWatchProviders(movieId: result.tmdbId)
        } else {
            provider = try? await TMDBService.shared.getTVWatchProviders(tvId: result.tmdbId)
        }

        // Find first provider that isn't an Amazon Channel variant
        let filtered = provider?.streamingProviders.first { p in
            !p.providerName.lowercased().contains("amazon channel")
        }

        if let name = filtered?.providerName {
            platforms[result.id] = name
        } else {
            platforms[result.id] = ""
        }
    }

    func metaLine(for result: BingeSearchResult) -> String {
        var parts: [String] = [result.isMovie ? "Movie" : "Series"]
        if let y = result.year { parts.append(y) }
        if let p = platforms[result.id], !p.isEmpty { parts.append(p) }
        return parts.joined(separator: " | ")
    }

    // MARK: Actions
    // Watchlist and Watched are mutually exclusive: entering one leaves the other.
    // Tapping the section you're already in removes you from it.

    func toggleWatchlist(_ result: BingeSearchResult) async {
        guard let userId = supabase.currentUser?.id else { return }
        do {
            if isOnWatchlist(result) {
                try await removeFromWatchlist(result, userId: userId)
            } else {
                if isInLibrary(result) { try await removeFromLibrary(result, userId: userId) }
                if result.isMovie {
                    try await supabase.addToWatchlistMovie(userId: userId, movieId: result.tmdbId, priority: "high")
                    watchlistMovies.insert(result.tmdbId)
                    if let wlm = try? await supabase.fetchWatchlistMovies(userId: userId) {
                        watchlistMovieRows = Dictionary(wlm.map { ($0.movieId, $0.id) }, uniquingKeysWith: { a, _ in a })
                    }
                } else {
                    try await supabase.addToWatchlistShow(userId: userId, showId: result.tmdbId, priority: "high")
                    watchlistShows.insert(result.tmdbId)
                }
            }
            objectWillChange.send()
        } catch {
            errorMessage = "Couldn't update your watchlist."
        }
    }

    func toggleWatched(_ result: BingeSearchResult) async {
        guard let userId = supabase.currentUser?.id else { return }
        do {
            if isInLibrary(result) {
                try await removeFromLibrary(result, userId: userId)
            } else {
                if isOnWatchlist(result) { try await removeFromWatchlist(result, userId: userId) }

                // Fetch and insert show/movie data first
                if result.isMovie {
                    if let tmdbMovie = try? await TMDBService.shared.getMovie(id: result.tmdbId) {
                        let movie = Movie(id: result.tmdbId, tmdbId: result.tmdbId, title: tmdbMovie.title,
                                        overview: tmdbMovie.overview, posterUrl: tmdbMovie.imageUrl,
                                        releaseDate: tmdbMovie.releaseDate)
                        try? await supabase.insertMovie(movie: movie)
                    }
                } else {
                    if let tmdbShow = try? await TMDBService.shared.getTVShow(id: result.tmdbId) {
                        let show = TVShow(id: result.tmdbId, tmdbId: result.tmdbId, title: tmdbShow.name,
                                        overview: tmdbShow.overview, posterUrl: tmdbShow.imageUrl,
                                        firstAirDate: tmdbShow.firstAirDate, numberOfSeasons: tmdbShow.numberOfSeasons,
                                        numberOfEpisodes: tmdbShow.numberOfEpisodes)
                        try? await supabase.insertShow(show: show)
                    }
                }

                let today = ISO8601DateFormatter().string(from: Date())
                if result.isMovie {
                    try await supabase.insertUserMovie(userId: userId, movieId: result.tmdbId, watchedDate: today)
                    libraryMovies.insert(result.tmdbId)
                } else {
                    try await supabase.insertUserShow(userId: userId, showId: result.tmdbId, watchedDate: today)
                    libraryShows.insert(result.tmdbId)
                    finishedShows.insert(result.tmdbId)
                    ratingTarget = result
                    objectWillChange.send()

                    // Mark all episodes as watched in background
                    Task {
                        if let tmdbShow = try? await TMDBService.shared.getTVShow(id: result.tmdbId) {
                            let watchedAt = ISO8601DateFormatter().string(from: Date())
                            for season in 1...tmdbShow.numberOfSeasons {
                                if let tmdbSeason = try? await TMDBService.shared.getTVSeason(showId: result.tmdbId, seasonNumber: season) {
                                    for episode in tmdbSeason.episodes {
                                        let ep = Episode(id: episode.id, showId: result.tmdbId, tmdbId: episode.id,
                                                       seasonNumber: season, episodeNumber: episode.episodeNumber,
                                                       name: episode.name, overview: episode.overview ?? "",
                                                       airDate: episode.airDate, userId: userId,
                                                       watched: true, watchedAt: watchedAt, showTitle: result.title)
                                        try? await supabase.insertEpisode(episode: ep)
                                    }
                                }
                            }
                        }
                    }
                    return
                }
            }
            objectWillChange.send()
        } catch {
            errorMessage = "Couldn't update what you've watched."
        }
    }

    private func removeFromWatchlist(_ result: BingeSearchResult, userId: String) async throws {
        if result.isMovie {
            if let rowId = watchlistMovieRows[result.tmdbId] {
                try await supabase.removeFromWatchlistMovie(id: rowId)
            }
            watchlistMovies.remove(result.tmdbId)
            watchlistMovieRows[result.tmdbId] = nil
        } else {
            try await supabase.removeShowFromWatchlist(userId: userId, showId: result.tmdbId)
            watchlistShows.remove(result.tmdbId)
        }
        saved.remove(result.id)
    }

    private func removeFromLibrary(_ result: BingeSearchResult, userId: String) async throws {
        if result.isMovie {
            try await supabase.removeMovieFromLibrary(userId: userId, movieId: result.tmdbId)
            libraryMovies.remove(result.tmdbId)
        } else {
            try await supabase.removeShowFromLibrary(userId: userId, showId: result.tmdbId)
            libraryShows.remove(result.tmdbId)
            finishedShows.remove(result.tmdbId)
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func isInLibrary(_ result: BingeSearchResult) -> Bool {
        result.isMovie ? libraryMovies.contains(result.tmdbId) : libraryShows.contains(result.tmdbId)
    }

    func isOnWatchlist(_ result: BingeSearchResult) -> Bool {
        if saved.contains(result.id) { return true }
        return result.isMovie ? watchlistMovies.contains(result.tmdbId) : watchlistShows.contains(result.tmdbId)
    }

    func addPerson(_ profile: UserProfile) async {
        guard let userId = supabase.currentUser?.id else { return }
        requested.insert(profile.userId)
        do { try await supabase.sendFriendRequest(userId: userId, friendId: profile.userId) }
        catch {
            requested.remove(profile.userId)
            errorMessage = "Couldn't send that request."
        }
    }

    private func year(_ date: String?) -> String? {
        guard let d = date, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }
}

// MARK: - View

struct BingeSearchView: View {
    @ObservedObject var engine: BingeSearchEngine
    @Binding var tab: BingeTab
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Search").bingeDisplay(34).textCase(.uppercase)
                Spacer(minLength: 12)
                if !engine.query.isEmpty {
                    Button {
                        engine.query = ""
                        engine.queryChanged()
                    } label: {
                        Text("Clear").bingeLabel(11)
                            .foregroundStyle(BingeTheme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 8).padding(.bottom, 12)
            BingeRule(strong: true)

            TextField("", text: Binding(get: { engine.query }, set: { engine.query = $0 }), prompt:
                        Text("Shows, movies, people")
                            .foregroundColor(BingeTheme.inkMuted))
                .textFieldStyle(.plain)
                .bingeHeadline(17)
                .submitLabel(.search)
                .focused($fieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, BingeTheme.gutter)
                .frame(height: 52)
                .onChange(of: engine.query) { _, _ in engine.queryChanged() }
            BingeRule()

            BingeSegmented(options: ["All", "Shows", "Movies", "People"], selection: Binding(get: { engine.scope }, set: { engine.scope = $0 }))
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 10)
                .onChange(of: engine.scope) { _, _ in engine.queryChanged() }
            BingeRule(strong: true)

            resultsBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { BingeTabBar(selection: $tab) }
        .onReceive(engine.objectWillChange) { _ in }
        .task {
            await engine.primeContext()
            fieldFocused = true
        }
        .sheet(item: $engine.ratingTarget) { result in
            BingeRatingSheet(title: result.title,
                           posterUrl: result.posterUrl,
                           itemId: result.tmdbId,
                           isMovie: result.isMovie) { _, _ in
                engine.ratingTarget = nil
            }
        }
    }

    @ViewBuilder
    private var resultsBody: some View {
        if engine.query.trimmingCharacters(in: .whitespaces).count < 2 {
            Spacer()                                  // empty ground, as asked
        } else if engine.isSearching && engine.results.isEmpty && engine.people.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(BingeTheme.accent)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if engine.results.isEmpty && engine.people.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing found").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                Text("Try fewer words, or the original title.")
                    .bingeBody(14).foregroundStyle(BingeTheme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 18)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(engine.people) { person in
                        personRow(person)
                        BingeRule()
                    }
                    ForEach(engine.results) { result in
                        resultRow(result)
                        BingeRule()
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func resultRow(_ result: BingeSearchResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink {
                if result.isMovie {
                    BingeMovieDetailView(tmdbId: result.tmdbId,
                                         dbMovieId: result.tmdbId,
                                         title: result.title)
                } else {
                    BingeShowDetailView(tmdbId: result.tmdbId,
                                    dbShowId: result.tmdbId,
                                    title: result.title)
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    BingePoster(urlString: result.posterUrl, width: 52, height: 74)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title).bingeHeadline(15)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(engine.metaLine(for: result))
                            .bingeLabel(9).foregroundStyle(BingeTheme.inkMuted)
                        let signal = engine.friendLine(for: result)
                        Text(signal.text).bingeLabel(9)
                            .foregroundStyle(signal.accent ? BingeTheme.accent : BingeTheme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actions(result)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
        .task { await engine.loadPlatform(for: result) }
    }

    /// Two mutually exclusive sections. Tap the one you're in to leave it.
    private func actions(_ result: BingeSearchResult) -> some View {
        let onList = engine.isOnWatchlist(result)
        let watched = engine.isInLibrary(result)
        return VStack(spacing: 6) {
            Button {
                Task { await engine.toggleWatchlist(result) }
            } label: {
                rowAction(title: "Watchlist", active: onList, accent: false)
            }
            .buttonStyle(.plain)

            Button {
                Task { await engine.toggleWatched(result) }
            } label: {
                rowAction(title: "Watched", active: watched, accent: true)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 104)
    }

    private func rowAction(title: String, active: Bool, accent: Bool) -> some View {
        Text(title)
            .bingeLabel(9)
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(active ? BingeTheme.ground : (accent ? BingeTheme.accent : BingeTheme.ink))
            .background(active ? (accent ? BingeTheme.accent : BingeTheme.ink) : Color.clear)
            .overlay(Rectangle().stroke(accent ? BingeTheme.accent : BingeTheme.ink, lineWidth: 1))
            .contentShape(Rectangle())
    }

    private func personRow(_ person: UserProfile) -> some View {
        HStack(spacing: 12) {
            Text(initials(person.displayName)).bingeHeadline(13)
                .frame(width: 44, height: 44)
                .background(BingeTheme.ink).foregroundStyle(BingeTheme.ground)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).bingeHeadline(15)
                if let bio = person.bio, !bio.isEmpty {
                    Text(bio).bingeBody(12).foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
                } else {
                    Text("On Binge").bingeLabel(9).foregroundStyle(BingeTheme.inkMuted)
                }
            }
            Spacer(minLength: 12)
            let sent = engine.requested.contains(person.userId)
            Button {
                Task { await engine.addPerson(person) }
            } label: {
                Text(sent ? "Requested" : "Add")
                    .bingeLabel(10)
                    .padding(.horizontal, 12)
                    .frame(minHeight: BingeTheme.minTap)
                    .foregroundStyle(sent ? BingeTheme.inkMuted : BingeTheme.accent)
                    .overlay(Rectangle().stroke(sent ? BingeTheme.hairline : BingeTheme.accent, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(sent)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2)
            .map { String($0.prefix(1)).uppercased() }.joined()
    }
}
