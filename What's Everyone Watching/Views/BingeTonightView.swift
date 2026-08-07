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
    @Published var pick: TonightPick?
    @Published var friends: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var watchlist: [Int] = []
    /// Shows already dismissed this session, so "Show me another" advances.
    private var skipped: Set<Int> = []

    private let supabase = SupabaseService.shared

    var stage: BingeGraphStage { .from(friendCount: friends.count) }

    var isOnWatchlist: Bool {
        guard let pick else { return false }
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
            friends = try await supabase.fetchFriends(userId: userId)

            // Load watchlist
            let watchlistItems = try await supabase.fetchWatchlistShows(userId: userId)
            watchlist = watchlistItems.map(\.showId)

            // What the user has already watched — never recommend these.
            let mine = try await supabase.fetchUserShows(userId: userId)
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
                if let show = try? await resolveShow(id: showId) {
                    pick = TonightPick(show: show,
                                       friendsFinished: entry.who,
                                       averageFriendRating: average(entry.ratings),
                                       service: try? await service(for: show),
                                       isFallback: false)
                    return
                }
            }

            try await loadFromOwnTaste(mine: mine, excluding: seen)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipCurrent() async {
        if let id = pick?.show.id { skipped.insert(id) }
        pick = nil
        await load()
    }

    func saveCurrent() async {
        guard let userId = supabase.currentUser?.id, let show = pick?.show else { return }
        try? await supabase.addToWatchlistShow(userId: userId, showId: show.id, priority: "high")
    }

    // MARK: Helpers

    private func average(_ xs: [Int]) -> Double {
        xs.isEmpty ? 0 : Double(xs.reduce(0, +)) / Double(xs.count)
    }

    /// Needs `fetchShowById` on SupabaseService — see the note at the top.
    private func resolveShow(id: Int) async throws -> TVShow? {
        // return try await supabase.fetchShowById(id: id)
        return nil
    }

    private func service(for show: TVShow) async throws -> String? {
        guard let result = try? await TMDBService.shared.getTVWatchProviders(tvId: show.tmdbId)
        else { return nil }
        return result.streamingProviders.first?.providerName
    }

    /// No social signal. Recommend from the user's OWN highest-rated show —
    /// a real signal — and fall back to trending only if they've rated nothing.
    private func loadFromOwnTaste(mine: [UserShow], excluding seen: Set<Int>) async throws {
        let best = mine
            .filter { ($0.rating ?? 0) >= 4 }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }

        for row in best {
            guard let seed = try? await resolveShow(id: row.showId) else { continue }
            guard let recs = try? await TMDBService.shared.getSimilarTV(tvId: seed.tmdbId),
                  let first = recs.first(where: { r in
                      guard let id = r.id else { return false }
                      return !seen.contains(id)
                  })
            else { continue }

            pick = TonightPick(show: makeShow(from: first),
                               friendsFinished: [], averageFriendRating: nil,
                               service: nil, isFallback: true, seedTitle: seed.title)
            return
        }

        let trending = try await TMDBService.shared.getTrendingTV()
        guard let first = trending.first(where: { r in
            guard let id = r.id else { return false }
            return !seen.contains(id)
        }) else { return }
        pick = TonightPick(show: makeShow(from: first), friendsFinished: [],
                           averageFriendRating: nil, service: nil, isFallback: true)
    }

    private func makeShow(from r: SearchResult) -> TVShow {
        TVShow(id: r.id ?? 0,
               tmdbId: r.id ?? 0,
               title: r.displayTitle.isEmpty ? "Untitled" : r.displayTitle,
               overview: r.overview ?? "",
               posterUrl: r.imageUrl,
               firstAirDate: nil,
               numberOfSeasons: 0,
               numberOfEpisodes: 0)
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
        HStack {
            Text(weekday).bingeLabel(11).foregroundStyle(BingeTheme.accentTint)
            Spacer()
            Text(engine.friends.isEmpty ? "0 friends yet" : "\(engine.friends.count) friends")
                .bingeLabel(11).foregroundStyle(BingeTheme.onDarkMuted)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.top, 8).padding(.bottom, 10)
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
            ZStack(alignment: .bottomLeading) {
                BingePoster(urlString: pick.show.posterUrl, width: nil, height: nil, cropAnchor: .top)
                LinearGradient(colors: [BingeTheme.ink.opacity(0.94), BingeTheme.ink.opacity(0)],
                               startPoint: .bottom, endPoint: .top)
                VStack(alignment: .leading, spacing: 8) {
                    Text(pick.show.title.uppercased())
                        .bingeDisplay(46)
                        .foregroundStyle(BingeTheme.ground)
                        .lineLimit(3)
                        .minimumScaleFactor(0.55)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metaLine(pick)).bingeLabel(12).foregroundStyle(BingeTheme.inkFaint)
                }
                .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 18)
            }
            .frame(minHeight: 150, maxHeight: .infinity).clipped()
            .layoutPriority(0)

            ScrollView {
                VStack(spacing: 0) {
                    BingeSourceBand(kicker: engine.sourceCopy.kicker,
                                    statement: engine.sourceCopy.statement)

                    BingeRule(onDark: true)

                    if engine.friends.count < 3 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("This gets better fast").bingeLabel(11).foregroundStyle(BingeTheme.onDarkMuted)
                            Text("Add three people you actually know and Tonight starts naming names.")
                                .bingeBody(14).foregroundStyle(BingeTheme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { tab = .friends } label: {
                                Text("Find your people →").bingeLabel(12)
                                    .foregroundStyle(BingeTheme.accentTint)
                                    .padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
                        BingeRule(onDark: true)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { middleHeight = $0 }
            }
            .frame(maxHeight: middleHeight == 0 ? nil : middleHeight)
            .scrollBounceBehavior(.basedOnSize)
            .layoutPriority(1)

            VStack(spacing: 10) {
                NavigationLink {
                    BingeShowDetailView(tmdbId: pick.show.tmdbId,
                                        dbShowId: pick.show.id,
                                        title: pick.show.title)
                } label: {
                    HStack {
                        Text("Open \(pick.show.title)").bingeHeadline(13).textCase(.uppercase)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Text("→").bingeHeadline(13)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap)
                    .background(BingeTheme.ground)
                    .foregroundStyle(BingeTheme.ink)
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    BingeOutlineButton(title: "Not tonight", onDark: true) {
                        Task { await engine.skipCurrent() }
                    }
                    if engine.isOnWatchlist {
                        BingeOutlineButton(title: "On Watchlist", onDark: true) {}
                    } else {
                        BingeOutlineButton(title: "Save it", onDark: true) {
                            Task { await engine.saveCurrent() }
                        }
                    }
                }
            }
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.vertical, 14)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
    }

    private func metaLine(_ pick: TonightPick) -> String {
        var parts: [String] = []
        if let d = pick.show.firstAirDate, d.count >= 4 { parts.append(String(d.prefix(4))) }
        parts.append("Series")
        if pick.show.numberOfEpisodes > 0 { parts.append("\(pick.show.numberOfEpisodes) eps") }
        if let s = pick.service { parts.append(s) }
        return parts.joined(separator: " · ")
    }

    private var weekday: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return "\(f.string(from: Date())) night"
    }
}
