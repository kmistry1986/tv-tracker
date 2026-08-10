//  BingeTonightView.swift
//  The one genuinely new screen. Wired to your SupabaseService + TMDBService.
//
//  Reads: fetchFriends, getFriendRatings, fetchUserShows, fetchShow(tmdbId:),
//         addToWatchlistShow, TMDBService.getTrendingTV, getTVWatchProviders.
//
//  ONE GAP: `UserShow.showId` is your DB row id, but `SupabaseService.fetchShow`
//  looks up by `tmdb_id`. Add this to SupabaseService and the engine resolves
//  real titles instead of falling back to trending:
//
//      func fetchShowById(id: Int) async throws -> TVShow {
//          try await client.from("tv_shows").select().eq("id", value: id)
//              .single().execute().value
//      }
//
//  Until then TonightEngine.resolveShow() returns nil and Tonight shows the
//  trending fallback, which still works.

import SwiftUI
import Combine

// TMDB has no similar/recommendations endpoint in TMDBService yet — added here.
extension TMDBService {
    func getSimilarTV(tvId: Int) async throws -> [SearchResult] {
        var components = URLComponents(string: "\(baseURL)/tv/\(tvId)/recommendations")!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return try JSONDecoder().decode(MultiSearchResponse.self, from: data).results
    }
}

// MARK: - Recommendation

struct TonightPick {
    let show: TVShow
    let friendsFinished: [User]
    let averageFriendRating: Double?
    let service: String?
    let isFallback: Bool        // true = no social signal
    var isMovie: Bool = false   // true for movies, false for shows
    /// The user's own show this was derived from, when there's no social signal.
    var seedTitle: String? = nil
}

enum BingeGraphStage {
    case cold, seeded, social
    static func from(friendCount: Int) -> BingeGraphStage {
        switch friendCount {
        case 0:     return .cold
        case 1...4: return .seeded
        default:    return .social
        }
    }
}

@MainActor
final class TonightEngine: ObservableObject {
    @Published var picks: [TonightPick] = []
    @Published var currentIndex = 0
    @Published var friends: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var watchlist: [Int] = []
    @Published var visibleIndex = 0
    /// Shows already dismissed this session, so "Show me another" advances.
    private var skipped: Set<Int> = []

    private let supabase = SupabaseService.shared

    var stage: BingeGraphStage { .from(friendCount: friends.count) }

    var pick: TonightPick? { currentIndex < picks.count ? picks[currentIndex] : nil }
    var visiblePick: TonightPick? { visibleIndex < picks.count ? picks[visibleIndex] : nil }

    var isOnWatchlist: Bool {
        guard let pick = visiblePick else { return false }
        return watchlist.contains(pick.show.id)
    }

    // The sentence in the red band. Upgrades as the graph grows.
    var sourceCopy: (kicker: String, statement: String) {
        guard let pick else { return ("Finding something", "Reading what your friends finished.") }

        if pick.isFallback {
            if let seed = pick.seedTitle {
                return ("Where this came from",
                        "You rated \(seed) highly. This is what it leads to — no friends needed yet.")
            }
            return ("Where this came from",
                    "Nobody you follow has watched anything yet, so this is simply what's popular right now. It gets specific the moment you add one person.")
        }
        if pick.friendsFinished.isEmpty {
            return ("Where this came from",
                    "None of your friends have logged this — it matches what you've rated highly.")
        }
        let names = pick.friendsFinished.prefix(2).map {
            $0.name.split(separator: " ").first.map(String.init) ?? $0.name
        }
        let others = pick.friendsFinished.count - names.count

        switch stage {
        case .cold:
            return ("Where this came from",
                    "Based on what you've finished. Add friends and this gets specific.")
        case .seeded:
            let who = names.joined(separator: " and ")
            return ("Why you, why tonight",
                    "\(who) finished it\(others > 0 ? ", plus \(others) more" : "") — and didn't stop early.")
        case .social:
            return ("Why you, why tonight",
                    "\(pick.friendsFinished.count) of your \(friends.count) friends finished it. Not one stopped early.")
        }
    }

    var stats: [BingeStat] {
        guard let pick else { return [] }
        let rating = pick.averageFriendRating.map { String(format: "%.1f", $0) } ?? "—"
        return [
            BingeStat(value: rating,
                      label: pick.isFallback ? "No friend data" : "Friend rating",
                      spoken: pick.averageFriendRating == nil ? "No rating yet" : nil),
            BingeStat(value: "\(pick.friendsFinished.count)", label: "Friends done"),
            BingeStat(value: pick.service == nil ? "—" : "✓",
                      label: pick.service ?? "Not on your plan",
                      accent: pick.service != nil,
                      spoken: pick.service == nil ? "Not available" : "Yes")
        ]
    }

    // MARK: Load

    func load() async {
        guard let userId = supabase.currentUser?.id else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            print("🌙 Tonight: Starting load for user \(userId)")
            
            // Load friends (with graceful failure for empty users)
            friends = (try? await supabase.fetchFriends(userId: userId)) ?? []
            print("🌙 Tonight: Loaded \(friends.count) friends")

            // Load watchlist
            let watchlistItems = (try? await supabase.fetchWatchlistShows(userId: userId)) ?? []
            watchlist = watchlistItems.map(\.showId)

            // What the user has already watched — never recommend these.
            let mine = (try? await supabase.fetchUserShows(userId: userId)) ?? []
            let seen = Set(mine.map(\.showId))

            // Tally friends' well-rated shows.
            var tally: [Int: (count: Int, ratings: [Int], who: [User])] = [:]
            for friend in friends {
                let rated = (try? await supabase.getFriendRatings(friendId: friend.id)) ?? []
                for row in rated where !seen.contains(row.showId) && !skipped.contains(row.showId) {
                    guard (row.rating ?? 0) >= 4 else { continue }
                    var entry = tally[row.showId] ?? (0, [], [])
                    entry.count += 1
                    if let r = row.rating { entry.ratings.append(r) }
                    entry.who.append(friend)
                    tally[row.showId] = entry
                }
            }

            // Best candidate: most friends, then highest average.
            let ranked = tally.sorted {
                if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
                return average($0.value.ratings) > average($1.value.ratings)
            }

            for (showId, entry) in ranked {
                guard picks.count < 15 else { break }
                if let show = try? await resolveShow(id: showId) {
                    picks.append(TonightPick(show: show,
                                             friendsFinished: entry.who,
                                             averageFriendRating: average(entry.ratings),
                                             service: try? await service(for: show),
                                             isFallback: false))
                }
            }

            try await loadFromOwnTaste(mine: mine, excluding: seen)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipCurrent() async {
        if let id = pick?.show.id { skipped.insert(id) }
        currentIndex = (currentIndex + 1) % max(1, picks.count)
    }

    func saveCurrent() async {
        guard let userId = supabase.currentUser?.id, let show = visiblePick?.show else { return }
        if isOnWatchlist {
            do {
                try await supabase.removeShowFromWatchlist(userId: userId, showId: show.id)
                watchlist.removeAll { $0 == show.id }
            } catch {
                print("Failed to remove from watchlist: \(error)")
            }
        } else {
            try? await supabase.addToWatchlistShow(userId: userId, showId: show.id, priority: "high")
            if !watchlist.contains(show.id) {
                watchlist.append(show.id)
            }
        }
    }

    // MARK: Helpers

    private func average(_ xs: [Int]) -> Double {
        xs.isEmpty ? 0 : Double(xs.reduce(0, +)) / Double(xs.count)
    }

    /// Needs `fetchShowById` on SupabaseService — see the note at the top.
    private func resolveShow(id: Int) async throws -> TVShow? {
        return try await supabase.fetchShowById(id: id)
    }

    private func service(for show: TVShow) async throws -> String? {
        guard let result = try? await TMDBService.shared.getTVWatchProviders(tvId: show.tmdbId)
        else { return nil }
        return result.streamingProviders.first?.providerName
    }

    /// No social signal. Recommend from the user's OWN highest-rated show —
    /// a real signal — and fall back to trending only if they've rated nothing.
    private func loadFromOwnTaste(mine: [UserShow], excluding seen: Set<Int>) async throws {
        print("🌙 Tonight: loadFromOwnTaste starting with \(mine.count) shows")
        let best = mine
            .filter { ($0.rating ?? 0) >= 4 }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }

        for row in best {
            guard picks.count < 15 else { break }
            guard let seed = try? await resolveShow(id: row.showId) else { continue }
            guard let recs = try? await TMDBService.shared.getSimilarTV(tvId: seed.tmdbId),
                  let first = recs.first(where: { r in
                      guard let id = r.id else { return false }
                      return !seen.contains(id) && !picks.contains(where: { $0.show.id == id })
                  })
            else { continue }

            let show = makeShow(from: first)
            picks.append(TonightPick(show: show,
                                     friendsFinished: [], averageFriendRating: nil,
                                     service: try? await service(for: show),
                                     isFallback: true, seedTitle: seed.title))
        }

        print("🌙 Tonight: Fetching trending...")
        let trending = try await TMDBService.shared.getTrendingTV()
        print("🌙 Tonight: Got \(trending.count) trending TV shows")
        let trendingMovies = try await TMDBService.shared.getTrendingMovies()
        print("🌙 Tonight: Got \(trendingMovies.count) trending movies")

        var tvIndex = 0, movieIndex = 0
        while picks.count < 15 {
            let hasTV = tvIndex < trending.count
            let hasMovie = movieIndex < trendingMovies.count

            if !hasTV && !hasMovie { break }

            if hasTV && picks.count < 15 {
                let result = trending[tvIndex]
                tvIndex += 1
                guard let id = result.id, !seen.contains(id) && !picks.contains(where: { $0.show.id == id }) else { continue }
                let show = makeShow(from: result)
                picks.append(TonightPick(show: show, friendsFinished: [],
                                         averageFriendRating: nil,
                                         service: try? await service(for: show),
                                         isFallback: true))
            }

            if hasMovie && picks.count < 15 {
                let result = trendingMovies[movieIndex]
                movieIndex += 1
                guard let id = result.id, !seen.contains(id) && !picks.contains(where: { $0.show.id == id }) else { continue }

                // Fetch movie details to get runtime and validate release date
                guard let movie = try? await TMDBService.shared.getMovie(id: id) else { continue }
                guard let releaseDate = movie.releaseDate else { continue }

                // Skip movies that are too recent (likely in theatres)
                if let date = ISO8601DateFormatter().date(from: releaseDate) {
                    let daysOld = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
                    if daysOld < 90 { continue }
                }

                let show = makeShow(from: result, runtime: movie.runtime)
                var pick = TonightPick(show: show, friendsFinished: [],
                                       averageFriendRating: nil,
                                       service: try? await service(for: show),
                                       isFallback: true)
                pick.isMovie = true
                picks.append(pick)
            }
        }
    }

    private func makeShow(from r: SearchResult, runtime: Int? = nil) -> TVShow {
        TVShow(id: r.id ?? 0,
               tmdbId: r.id ?? 0,
               title: r.displayTitle.isEmpty ? "Untitled" : r.displayTitle,
               overview: r.overview ?? "",
               posterUrl: r.imageUrl,
               firstAirDate: nil,
               numberOfSeasons: 0,
               numberOfEpisodes: 0,
               platforms: nil,
               runtime: runtime)
    }
}

// MARK: - View

struct BingeTonightView: View {
    @StateObject private var engine = TonightEngine()
    @Binding var tab: BingeTab
    @State private var middleHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            if engine.isLoading && engine.pick == nil {
                loading
            } else if let pick = engine.pick {
                content(pick)
                    .id(engine.currentIndex)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ink.ignoresSafeArea())
        .foregroundStyle(BingeTheme.ground)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { BingeTabBar(selection: $tab, onDark: true) }
        .task { await engine.load() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            BingeMark(height: 15, onDark: true)
            Text(weekday).bingeLabel(13).foregroundStyle(BingeTheme.accentTint)
            Spacer()
            Text(engine.friends.isEmpty ? "0 friends yet" : "\(engine.friends.count) friends")
                .bingeLabel(13).foregroundStyle(BingeTheme.onDarkMuted)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.top, 7).padding(.bottom, 9)
    }

    private var loading: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(BingeTheme.accentTint)
            Text("Reading what your friends finished")
                .bingeLabel(11).foregroundStyle(BingeTheme.onDarkMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 0) {
            BingeArgumentBlock(
                kicker: engine.errorMessage == nil ? "Nothing to go on yet" : "Something broke",
                headline: engine.errorMessage == nil ? "ADD ONE PERSON\nAND THIS WORKS." : "COULDN'T LOAD\nTONIGHT.",
                message: engine.errorMessage ?? "Tonight reads what the people you follow actually finished. Right now there's nobody to read.",
                onDark: true)
            Spacer()
            BingePrimaryButton(title: engine.errorMessage == nil ? "Find your people" : "Try again",
                               onDark: true) {
                if engine.errorMessage == nil { tab = .friends }
                else { Task { await engine.load() } }
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 14)
        }
    }

    private func content(_ pick: TonightPick) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(engine.picks.indices, id: \.self) { index in
                            GeometryReader { geo in
                                NavigationLink {
                                    let pick = engine.picks[index]
                                    if pick.isMovie {
                                        BingeMovieDetailView(tmdbId: pick.show.tmdbId,
                                                             dbMovieId: pick.show.id,
                                                             title: pick.show.title)
                                    } else {
                                        BingeShowDetailView(tmdbId: pick.show.tmdbId,
                                                            dbShowId: pick.show.id,
                                                            title: pick.show.title)
                                    }
                                } label: {
                                    Color.clear
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(
                                            BingePoster(urlString: engine.picks[index].show.posterUrl, width: nil, height: nil, cropAnchor: .top)
                                        )
                                        .overlay(
                                            LinearGradient(colors: [BingeTheme.ink.opacity(0.94), BingeTheme.ink.opacity(0)],
                                                           startPoint: .bottom, endPoint: .top)
                                        )
                                        .overlay(alignment: .bottomLeading) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(engine.picks[index].show.title.isEmpty ? "Untitled" : engine.picks[index].show.title.uppercased())
                                                    .bingeDisplay(39)
                                                    .foregroundStyle(BingeTheme.ground)
                                                    .lineLimit(3)
                                                    .minimumScaleFactor(0.55)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Text(metaLine(engine.picks[index])).bingeLabel(10).foregroundStyle(BingeTheme.inkFaint)
                                            }
                                            .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 15)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .clipped()
                                }
                                .buttonStyle(.plain)
                                .onGeometryChange(for: Bool.self) { geometry in
                                    let frame = geometry.frame(in: .global)
                                    let isVisible = frame.minX >= 0 && frame.maxX <= UIScreen.main.bounds.width
                                    return isVisible
                                } action: { isVisible in
                                    if isVisible {
                                        engine.visibleIndex = index
                                    }
                                }
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                        }
                        if !engine.picks.isEmpty {
                            GeometryReader { geo in
                                NavigationLink {
                                    let pick = engine.picks[0]
                                    if pick.isMovie {
                                        BingeMovieDetailView(tmdbId: pick.show.tmdbId,
                                                             dbMovieId: pick.show.id,
                                                             title: pick.show.title)
                                    } else {
                                        BingeShowDetailView(tmdbId: pick.show.tmdbId,
                                                            dbShowId: pick.show.id,
                                                            title: pick.show.title)
                                    }
                                } label: {
                                    Color.clear
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(
                                            BingePoster(urlString: engine.picks[0].show.posterUrl, width: nil, height: nil, cropAnchor: .top)
                                        )
                                        .overlay(
                                            LinearGradient(colors: [BingeTheme.ink.opacity(0.94), BingeTheme.ink.opacity(0)],
                                                           startPoint: .bottom, endPoint: .top)
                                        )
                                        .overlay(alignment: .bottomLeading) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(engine.picks[0].show.title.isEmpty ? "Untitled" : engine.picks[0].show.title.uppercased())
                                                    .bingeDisplay(39)
                                                    .foregroundStyle(BingeTheme.ground)
                                                    .lineLimit(3)
                                                    .minimumScaleFactor(0.55)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Text(metaLine(engine.picks[0])).bingeLabel(10).foregroundStyle(BingeTheme.inkFaint)
                                            }
                                            .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 15)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                }
                                .buttonStyle(.plain)
                                .clipped()
                                .onGeometryChange(for: Bool.self) { geometry in
                                    let frame = geometry.frame(in: .global)
                                    let isVisible = frame.minX >= 0 && frame.maxX <= UIScreen.main.bounds.width
                                    return isVisible
                                } action: { isVisible in
                                    if isVisible {
                                        engine.visibleIndex = 0
                                    }
                                }
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(engine.picks.count)
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
                .onChange(of: engine.currentIndex) { oldValue, newValue in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .frame(minHeight: 150, maxHeight: .infinity)
            .layoutPriority(0)

            ScrollView {
                VStack(spacing: 0) {
                    BingeSourceBand(kicker: engine.sourceCopy.kicker,
                                    statement: engine.sourceCopy.statement)

                    BingeRule(onDark: true)

                    if engine.friends.count < 3 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("This gets better fast").bingeLabel(9).foregroundStyle(BingeTheme.onDarkMuted)
                            Text("Add three people you actually know and Tonight starts naming names.")
                                .bingeBody(12).foregroundStyle(BingeTheme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { tab = .friends } label: {
                                Text("Find your people →").bingeLabel(10)
                                    .foregroundStyle(BingeTheme.accentTint)
                                    .padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
                        BingeRule(onDark: true)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { middleHeight = $0 }
            }
            .frame(maxHeight: middleHeight == 0 ? nil : middleHeight)
            .scrollBounceBehavior(.basedOnSize)
            .layoutPriority(1)

            VStack(spacing: 9) {
                if let visiblePick = engine.visiblePick {
                    NavigationLink {
                        BingeShowDetailView(tmdbId: visiblePick.show.tmdbId,
                                            dbShowId: visiblePick.show.id,
                                            title: visiblePick.show.title)
                    } label: {
                        HStack {
                            Text("Open \(visiblePick.show.title)").bingeHeadline(11).textCase(.uppercase)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            Text("→").bingeHeadline(11)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap)
                        .background(BingeTheme.ground)
                        .foregroundStyle(BingeTheme.ink)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 9) {
                        BingeOutlineButton(title: "Not tonight", onDark: true, labelSize: 10) {
                            Task { await engine.skipCurrent() }
                        }
                        if engine.isOnWatchlist {
                            BingeOutlineButton(title: "On Watchlist", onDark: true, labelSize: 10) {
                                Task { await engine.saveCurrent() }
                            }
                        } else {
                            BingeOutlineButton(title: "Save it", onDark: true, labelSize: 10) {
                                Task { await engine.saveCurrent() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.vertical, 12)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
    }

    private func metaLine(_ pick: TonightPick) -> String {
        var parts: [String] = []

        if let airDate = pick.show.firstAirDate, airDate.count >= 4 {
            let year = String(airDate.prefix(4))
            parts.append(year)
        }

        parts.append(pick.isMovie ? "Movie" : "Series")

        if pick.isMovie {
            if let runtime = pick.show.runtime, runtime > 0 {
                let hours = runtime / 60
                let minutes = runtime % 60
                if hours > 0 && minutes > 0 {
                    parts.append("\(hours)h \(minutes)m")
                } else if hours > 0 {
                    parts.append("\(hours)h")
                } else {
                    parts.append("\(minutes)m")
                }
            }
        } else {
            if pick.show.numberOfEpisodes > 0 {
                parts.append("\(pick.show.numberOfEpisodes) episode\(pick.show.numberOfEpisodes == 1 ? "" : "s")")
            }
        }

        if let s = pick.service, !s.isEmpty {
            parts.append(s)
        }

        return parts.joined(separator: " · ")
    }

    private var weekday: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return "\(f.string(from: Date())) night"
    }
}
