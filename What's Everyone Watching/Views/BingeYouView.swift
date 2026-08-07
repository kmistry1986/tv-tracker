//  BingeYouView.swift
//  The 3a You tab, laid out as designed: profile row, three-up stat grid,
//  three-cell section switch (Watching / Saved / Finished), title rows with
//  real episode progress, and the Services block at the bottom.
//
//  Progress comes from fetchUserEpisodes(userId:) — watched episode rows are
//  grouped by show_id, so "46 of 62" and the bar are real, not decorative.
//  Movies still need a fetchMovieById on SupabaseService to be listed here.

import SwiftUI
import Combine

struct BingeLibraryItem: Identifiable {
    let id: Int
    let show: TVShow
    let rating: Int?
    let watchedDate: String?
    let isWatchlist: Bool
    var watchedEpisodes: Int = 0
    var lastSeason: Int? = nil
    var lastEpisode: Int? = nil

    var totalEpisodes: Int { show.numberOfEpisodes }

    var isFinished: Bool {
        if totalEpisodes > 0 && watchedEpisodes >= totalEpisodes { return true }
        return rating != nil && watchedEpisodes == 0
    }

    var isWatching: Bool { watchedEpisodes > 0 && !isFinished }

    var progress: Double {
        guard totalEpisodes > 0 else { return 0 }
        return min(1, Double(watchedEpisodes) / Double(totalEpisodes))
    }

    /// "S5 E1 · 46 of 62" when we know where they are, else a title meta line.
    var subtitle: String {
        var parts: [String] = []
        if let s = lastSeason, let e = lastEpisode { parts.append("S\(s) E\(e)") }
        if totalEpisodes > 0 && watchedEpisodes > 0 {
            parts.append("\(watchedEpisodes) of \(totalEpisodes)")
        }
        if parts.isEmpty {
            if let d = show.firstAirDate, d.count >= 4 { parts.append(String(d.prefix(4))) }
            if totalEpisodes > 0 { parts.append("\(totalEpisodes) eps") }
            if let rating { parts.append("Rated \(rating)") }
        }
        return parts.isEmpty ? "Series" : parts.joined(separator: " · ")
    }
}

@MainActor
final class BingeYouEngine: ObservableObject {
    @Published var library: [BingeLibraryItem] = []
    @Published var watchlist: [BingeLibraryItem] = []
    @Published var friendCount = 0
    @Published var joined: String?
    @Published var isLoading = false

    private let supabase = SupabaseService.shared

    var watching: [BingeLibraryItem] { library.filter { $0.isWatching } }
    var finished: [BingeLibraryItem] { library.filter { $0.isFinished } }

    func load() async {
        guard let userId = supabase.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        // Watched episodes, grouped by show — the source of progress.
        let episodes = (try? await supabase.fetchUserEpisodes(userId: userId)) ?? []
        var counts: [Int: Int] = [:]
        var latest: [Int: (Int, Int)] = [:]
        for ep in episodes where ep.watched {
            counts[ep.showId, default: 0] += 1
            let here = (ep.seasonNumber, ep.episodeNumber)
            if let seen = latest[ep.showId] {
                if here > seen { latest[ep.showId] = here }
            } else {
                latest[ep.showId] = here
            }
        }

        let shows = (try? await supabase.fetchUserShows(userId: userId)) ?? []
        var built: [BingeLibraryItem] = []
        for row in shows {
            guard let show = try? await supabase.fetchShowById(id: row.showId) else { continue }
            built.append(BingeLibraryItem(id: row.id, show: show, rating: row.rating,
                                          watchedDate: row.watchedDate, isWatchlist: false,
                                          watchedEpisodes: counts[row.showId] ?? 0,
                                          lastSeason: latest[row.showId]?.0,
                                          lastEpisode: latest[row.showId]?.1))
        }
        library = built.sorted { $0.progress > $1.progress }

        let list = (try? await supabase.fetchWatchlistShows(userId: userId)) ?? []
        var wl: [BingeLibraryItem] = []
        for row in list {
            guard let show = try? await supabase.fetchShowById(id: row.showId) else { continue }
            wl.append(BingeLibraryItem(id: row.id, show: show, rating: nil,
                                       watchedDate: row.addedAt, isWatchlist: true))
        }
        watchlist = wl

        friendCount = ((try? await supabase.fetchFriends(userId: userId)) ?? []).count

        if let profile = try? await supabase.getUserProfile(userId: userId) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: profile.createdAt)
                ?? ISO8601DateFormatter().date(from: profile.createdAt) {
                let f = DateFormatter(); f.dateFormat = "MMM"
                joined = f.string(from: d)
            }
        }
    }
}

struct BingeYouView: View {
    @EnvironmentObject private var supabase: SupabaseService
    @StateObject private var engine = BingeYouEngine()
    @Binding var tab: BingeTab
    @State private var section = 0
    @State private var showSettings = false
    @State private var showImport = false
    @State private var ratingTarget: BingeLibraryItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            BingeRule(strong: true)

            statSwitch
            BingeRule(strong: true)

            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { BingeTabBar(selection: $tab) }
        .sheet(isPresented: $showSettings) { BingeSettingsView() }
        .sheet(isPresented: $showImport) { ImportManagementView() }
        .sheet(item: $ratingTarget) { item in
            BingeRatingSheet(title: item.show.title,
                             posterUrl: item.show.posterUrl,
                             itemId: item.show.id,
                             isMovie: false,
                             existingRating: item.rating) { _, _ in
                Task { await engine.load() }
            }
        }
        .task { await engine.load() }
    }

    // MARK: Profile row

    private var header: some View {
        HStack(spacing: 12) {
            Text(initials)
                .bingeHeadline(14)
                .frame(width: 44, height: 44)
                .background(BingeTheme.ink).foregroundStyle(BingeTheme.ground)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName).bingeHeadline(18)
                Text(profileMeta).bingeBody(12)
                    .foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 14) {
                Button { showImport = true } label: {
                    Text("Import").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { showSettings = true } label: {
                    Text("Edit").bingeLabel(11).foregroundStyle(BingeTheme.accent)
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.top, 10).padding(.bottom, 14)
    }

    private var profileMeta: String {
        var parts: [String] = []
        parts.append(engine.friendCount == 1 ? "1 friend" : "\(engine.friendCount) friends")
        if let joined = engine.joined { parts.append("joined \(joined)") }
        return parts.joined(separator: " · ")
    }

    // MARK: The stat row IS the switch — one row, not two

    private var statSwitch: some View {
        HStack(spacing: 0) {
            statCell("\(engine.watching.count)", "You started", index: 0)
            BingeVRule()
            statCell("\(engine.watchlist.count)", "Saved", index: 1)
            BingeVRule()
            statCell("\(engine.finished.count)", "Finished", index: 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statCell(_ value: String, _ label: String, index: Int) -> some View {
        let on = section == index
        return Button { section = index } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).bingeDisplay(28)
                    .foregroundStyle(on ? BingeTheme.accentTint : BingeTheme.ink)
                Text(label).bingeLabel(10)
                    .foregroundStyle(on ? BingeTheme.ground : BingeTheme.inkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, index == 0 ? BingeTheme.gutter : 16)
            .padding(.trailing, 10)
            .padding(.vertical, 14)
            .background(on ? BingeTheme.ink : BingeTheme.ground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: List

    private var items: [BingeLibraryItem] {
        switch section {
        case 1: return engine.watchlist
        case 2: return engine.finished
        default: return engine.watching.isEmpty ? engine.library : engine.watching
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if engine.isLoading && items.isEmpty {
                    ProgressView().tint(BingeTheme.accent).padding(.vertical, 40)
                } else if items.isEmpty {
                    BingeArgumentBlock(kicker: emptyKicker,
                                       headline: emptyHeadline,
                                       message: emptyMessage)
                } else {
                    ForEach(items) { item in
                        ZStack(alignment: .trailing) {
                            NavigationLink {
                                BingeShowDetailView(tmdbId: item.show.tmdbId,
                                                    dbShowId: item.show.id,
                                                    title: item.show.title)
                            } label: {
                                row(item)
                            }
                            .buttonStyle(.plain)
                            trailingAction(item)
                                .padding(.trailing, BingeTheme.gutter)
                        }
                        BingeRule()
                    }
                }
            }
        }
    }

    private func row(_ item: BingeLibraryItem) -> some View {
        HStack(spacing: 14) {
            BingePoster(urlString: item.show.posterUrl, width: 56, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.show.title).bingeHeadline(16).lineLimit(1)
                Text(item.subtitle).bingeBody(12).foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
                if item.totalEpisodes > 0 && item.watchedEpisodes > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(BingeTheme.hairline)
                            Rectangle().fill(BingeTheme.ink)
                                .frame(width: max(2, geo.size.width * item.progress))
                        }
                    }
                    .frame(height: 3)
                }
            }
            Spacer(minLength: 84)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
    }

    /// "Rate it" is the only trailing label that acts on its own — it opens the
    /// rating sheet instead of pushing the detail view.
    @ViewBuilder
    private func trailingAction(_ item: BingeLibraryItem) -> some View {
        if !item.isWatchlist && !item.isWatching && item.rating == nil {
            Button { ratingTarget = item } label: {
                Text("Rate it").bingeLabel(11).foregroundStyle(BingeTheme.accent)
                    .padding(.vertical, 12).padding(.leading, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if !item.isWatchlist && item.rating != nil {
            Button { ratingTarget = item } label: {
                Text("\(item.rating ?? 0)/5").bingeLabel(11)
                    .foregroundStyle(BingeTheme.inkMuted)
                    .padding(.vertical, 12).padding(.leading, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(item.isWatchlist ? "Start" : "Resume")
                .bingeLabel(11).foregroundStyle(BingeTheme.accent)
                .padding(.vertical, 12)
        }
    }

    private var emptyKicker: String {
        section == 1 ? "Room for more" : (section == 2 ? "Nothing finished" : "Nothing started")
    }
    private var emptyHeadline: String {
        switch section {
        case 1: return "SAVE SOMETHING\nFOR LATER."
        case 2: return "NOTHING\nFINISHED YET."
        default: return "YOUR LIBRARY\nIS EMPTY."
        }
    }
    private var emptyMessage: String {
        switch section {
        case 1: return "Anything you save from Tonight or a friend's feed lands here."
        case 2: return "Finish a show and it moves here — finished titles are what Tonight learns from."
        default: return "Import your Netflix history or rate a show to start. Tonight gets sharper with every title you log."
        }
    }

    private var displayName: String {
        if let n = supabase.currentUser?.name, !n.isEmpty { return n }
        guard let email = supabase.currentUser?.email else { return "You" }
        return email.split(separator: "@").first.map { String($0).replacingOccurrences(of: ".", with: " ").capitalized } ?? "You"
    }

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let s = parts.map { String($0.prefix(1)).uppercased() }.joined()
        return s.isEmpty ? "?" : s
    }
}
