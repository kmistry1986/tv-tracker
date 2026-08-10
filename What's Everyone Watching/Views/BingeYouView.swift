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
    /// Set once movies can be listed here; false for series.
    var isMovie: Bool = false
    var runtimeMinutes: Int? = nil

    var totalEpisodes: Int { show.numberOfEpisodes }

    /// The one service you'd actually open. `platforms` holds every provider
    /// TMDB knows about including buy/rent, which isn't what "where is this"
    /// means — subscription first, and only fall back to a paid option if a
    /// title is nowhere else.
    var platform: String? {
        guard let all = show.platforms, !all.isEmpty else { return nil }
        let pick = all.first { $0.type == "streaming" }
            ?? all.first { $0.type == "free" }
            ?? all.first
        guard let name = pick?.name else { return nil }
        return BingeLibraryItem.shortPlatform(name)
    }

    /// Provider names are marketing names, not labels — "Amazon Prime Video"
    /// eats a meta line on its own.
    static func shortPlatform(_ name: String) -> String {
        if name.contains("Amazon Prime") { return "Prime" }
        if name.contains("Apple TV")     { return "Apple TV+" }
        if name.contains("HBO") || name == "Max" { return "Max" }
        if name.contains("Disney")       { return "Disney+" }
        if name.contains("Paramount")    { return "Paramount+" }
        if name.contains("Peacock")      { return "Peacock" }
        if name.contains("Netflix")      { return "Netflix" }
        return name
    }

    var isFinished: Bool {
        if totalEpisodes > 0 && watchedEpisodes >= totalEpisodes { return true }
        return rating != nil && watchedEpisodes == 0
    }

    var isWatching: Bool { watchedEpisodes > 0 && !isFinished }

    var progress: Double {
        guard totalEpisodes > 0 else { return 0 }
        return min(1, Double(watchedEpisodes) / Double(totalEpisodes))
    }

    /// A single comparable "how much is this" — minutes for a film, episodes
    /// scaled to roughly the same order for a series, so Longest / Shortest
    /// can rank a mixed list without pretending the units are the same.
    var lengthUnits: Int {
        if isMovie { return runtimeMinutes ?? 0 }
        return totalEpisodes * 42
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
        if let platform { parts.append(platform) }
        return parts.isEmpty ? "Series" : parts.joined(separator: " · ")
    }

    /// Finished rows state a fact about the title, not progress — there is none
    /// left. Kind first, so a series and a film are told apart at a glance
    /// rather than inferred from the unit.
    /// Movies read plain "Film" until SupabaseService gains a fetchMovieById
    /// that can supply a real runtime.
    /// Finished rows state facts about the title, not progress — there is none
    /// left. Split across two lines: what it is and where it lives, then how
    /// much of it there is. Kind first, so a series and a film are told apart
    /// at a glance rather than inferred from the unit.
    var kindLine: String {
        var parts = [isMovie ? "Film" : "Series"]
        // Omitted rather than stubbed when unknown — the line just ends short.
        if let platform { parts.append(platform) }
        return parts.joined(separator: " · ")
    }

    var lengthLine: String? {
        if isMovie {
            guard let mins = runtimeMinutes, mins > 0 else { return nil }
            let h = mins / 60, m = mins % 60
            if h == 0 { return "\(m)m" }
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        guard totalEpisodes > 0 else { return nil }
        return "\(totalEpisodes) episode\(totalEpisodes == 1 ? "" : "s")"
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

    func delete(item: BingeLibraryItem) async {
        do {
            if item.isWatchlist {
                try await supabase.removeFromWatchlistShow(id: item.id)
            } else {
                try await supabase.removeUserShow(id: item.id)
            }
            library.removeAll { $0.id == item.id }
        } catch {
            print("Failed to delete item: \(error)")
        }
    }

    func load() async {
        guard let userId = supabase.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        // Watched episodes, grouped by show — the source of progress.
        let episodes = (try? await supabase.fetchUserEpisodes(userId: userId)) ?? []
        print("📺 Loaded \(episodes.count) episodes")
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
        print("📺 Loaded \(shows.count) user shows")
        var built: [BingeLibraryItem] = []
        var seenShowIds = Set<Int>()

        // Fetch all shows concurrently
        await withTaskGroup(of: (row: UserShow, show: TVShow)?.self) { group in
            for row in shows {
                group.addTask {
                    guard let show = try? await self.supabase.fetchShowById(id: row.showId) else { return nil }
                    return (row, show)
                }
            }
            for await result in group {
                guard let (row, show) = result else { continue }
                seenShowIds.insert(row.showId)
                built.append(BingeLibraryItem(id: row.id, show: show, rating: row.rating,
                                              watchedDate: row.watchedDate, isWatchlist: false,
                                              watchedEpisodes: counts[row.showId] ?? 0,
                                              lastSeason: latest[row.showId]?.0,
                                              lastEpisode: latest[row.showId]?.1))
            }
        }

        // Add shows with watched episodes that aren't in user_shows yet
        await withTaskGroup(of: (showId: Int, show: TVShow)?.self) { group in
            for (showId, _) in counts {
                guard !seenShowIds.contains(showId) else { continue }
                group.addTask {
                    guard let show = try? await self.supabase.fetchShowById(id: showId) else { return nil }
                    return (showId, show)
                }
            }
            for await result in group {
                guard let (showId, show) = result else { continue }
                built.append(BingeLibraryItem(id: showId, show: show, rating: nil,
                                              watchedDate: nil, isWatchlist: false,
                                              watchedEpisodes: counts[showId] ?? 0,
                                              lastSeason: latest[showId]?.0,
                                              lastEpisode: latest[showId]?.1))
            }
        }

        library = built.sorted { $0.progress > $1.progress }
        print("📺 Library has \(library.count) items")

        let list = (try? await supabase.fetchWatchlistShows(userId: userId)) ?? []
        print("📺 Watchlist has \(list.count) items")
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

/// A wrapping row of chips. The platform set is short and variable, so it
/// needs to wrap rather than scroll — a chip you can't see is a chip nobody taps.
struct BingeFlowGrid<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 7, alignment: .leading)],
                  alignment: .leading, spacing: 7) {
            content
        }
    }
}

/// A leading swipe that reveals one action. The library list is a LazyVStack,
/// not a List, so `.swipeActions` isn't available — this is the same gesture
/// hand-built, and it stays out of the row's layout entirely so nothing about
/// the row's height or width changes.
struct BingeSwipeRow<Content: View>: View {
    let shareText: String
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var committed: CGFloat = 0

    private let width: CGFloat = 76

    var body: some View {
        ZStack(alignment: .leading) {
            ShareLink(item: shareText) {
                VStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                    Text("Share").bingeLabel(9)
                }
                .foregroundStyle(BingeTheme.ground)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(BingeTheme.ink)
                .contentShape(Rectangle())
            }
            .simultaneousGesture(TapGesture().onEnded { close() })
            .opacity(offset > 1 ? 1 : 0)

            content
                .background(BingeTheme.ground)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(width * 1.2, max(0, committed + value.translation.width))
                        }
                        .onEnded { value in
                            let open = value.translation.width > width * 0.4 || offset > width * 0.7
                            withAnimation(.snappy(duration: 0.22)) {
                                offset = open ? width : 0
                                committed = offset
                            }
                        }
                )
        }
        .clipped()
    }

    private func close() {
        withAnimation(.snappy(duration: 0.22)) { offset = 0; committed = 0 }
    }
}

struct BingeYouView: View {
    @EnvironmentObject private var supabase: SupabaseService
    @EnvironmentObject private var notificationManager: NotificationManager
    @ObservedObject var engine: BingeYouEngine
    @Binding var tab: BingeTab
    @State private var section = 0
    @State private var showSettings = false
    @State private var showImport = false
    @State private var ratingTarget: BingeLibraryItem?
    @State private var showFilters = false
    /// 0 all · 1 shows · 2 films — a property of the title, so it holds across sections.
    @State private var kindFilter = 0
    /// 0 all · 1 rated · 2 unrated — only applied on Finished.
    @State private var rateFilter = 0
    /// nil = every service. Chips are built from the library, never a fixed list.
    @State private var platformFilter: String? = nil
    /// Index into `sortOptions`, which changes with the section.
    @State private var sortMode = 0

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                BingeRule(strong: true)

                statSwitch
                BingeRule(strong: true)
                filterSummaryLine

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
            .sheet(isPresented: $showFilters) { filterSheet }
            // Sort options differ per section, so an index doesn't survive the
            // switch; filters are properties of the title and do.
            .onChange(of: section) { sortMode = 0 }
            .sheet(item: $ratingTarget) { item in
                BingeRatingSheet(title: item.show.title,
                                 posterUrl: item.show.posterUrl,
                                 itemId: item.show.id,
                                 isMovie: item.isMovie,
                                 existingRating: item.rating) { _, _ in
                    Task { await engine.load() }
                }
            }
            .task { await engine.load() }
            .onChange(of: tab) { _, newTab in
                if newTab == .you { Task { await engine.load() } }
            }

            if let message = notificationManager.message {
                VStack {
                    HStack {
                        Text(message).bingeHeadline(14)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.vertical, 12).padding(.horizontal, BingeTheme.gutter)
                    .background(BingeTheme.ink)
                    .foregroundStyle(BingeTheme.ground)
                    .cornerRadius(8)
                    .padding(BingeTheme.gutter)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .gesture(
                        DragGesture()
                            .onEnded { gesture in
                                if gesture.translation.height < -50 {
                                    withAnimation {
                                        notificationManager.dismiss()
                                    }
                                }
                            }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
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
            BingeVRule(onDark: section == 2)

            // Trailing controls live inside the switch — the page already has one
            // filter row and doesn't get a second strip.
            Button { showFilters = true } label: {
                VStack(spacing: 3) {
                    Text("Filter").bingeLabel(9)
                        .foregroundStyle(activeFilterCount > 0 ? BingeTheme.accent : BingeTheme.inkMuted)
                    if activeFilterCount > 0 {
                        Text("· \(activeFilterCount) ·").bingeLabel(9)
                            .foregroundStyle(BingeTheme.accent)
                    }
                }
                .frame(width: 58)
                .frame(maxHeight: .infinity)
                .background(BingeTheme.ground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activeFilterCount > 0 ? "Filter, \(activeFilterCount) active" : "Filter")

            if section == 2 && !engine.finished.isEmpty {
                BingeVRule()
                ShareLink(item: finishedShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(BingeTheme.ink)
                        .frame(width: 46)
                        .frame(maxHeight: .infinity)
                        .background(BingeTheme.ground)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share what you've finished")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A plain-text list for the iOS share sheet — reads as something a person
    /// would actually paste into a message.
    private var finishedShareText: String {
        let lines = engine.finished.prefix(40).map { item -> String in
            if let r = item.rating, r > 0 {
                return "\(item.show.title) — \(String(repeating: "★", count: r))"
            }
            return item.show.title
        }
        return (["What I've finished", ""] + lines).joined(separator: "\n")
    }

    /// What one title reads like when it lands in a message — the same voice as
    /// the whole-list share, one line long.
    private func shareText(for item: BingeLibraryItem) -> String {
        var line = item.show.title
        if let r = item.rating, r > 0 {
            line += " — \(String(repeating: "★", count: r))"
        }
        if let platform = item.platform { line += " (\(platform))" }
        return line
    }

    /// Every facet is offered on every section — a control that appears and
    /// disappears as you switch tabs is harder to trust than one that's simply
    /// there. Rating still only has anything to match on Finished.
    private var ratingFilterApplies: Bool { true }

    private var activeFilterCount: Int {
        (kindFilter == 0 ? 0 : 1)
        + (ratingFilterApplies && rateFilter != 0 ? 1 : 0)
        + (platformFilter == nil ? 0 : 1)
    }

    private func clearFilters() {
        kindFilter = 0; rateFilter = 0; platformFilter = nil
    }

    private var filterSummary: String {
        var parts: [String] = []
        if kindFilter == 1 { parts.append("Shows") }
        if kindFilter == 2 { parts.append("Films") }
        if ratingFilterApplies && rateFilter == 1 { parts.append("Rated") }
        if ratingFilterApplies && rateFilter == 2 { parts.append("Unrated") }
        if let platformFilter { parts.append(platformFilter) }
        return parts.joined(separator: " · ")
    }

    /// Built from what's actually in this section, so a chip can never return
    /// an empty list. Ordered by how much of the library sits on each service.
    private var libraryPlatforms: [String] {
        var counts: [String: Int] = [:]
        for item in sectionItems {
            if let name = item.platform {
                let current: Int = counts[name] ?? 0
                counts[name] = current + 1
            }
        }
        let names: [String] = Array(counts.keys)
        return names.sorted { a, b in
            let ca: Int = counts[a] ?? 0
            let cb: Int = counts[b] ?? 0
            if ca == cb { return a < b }
            return ca > cb
        }
    }

    // MARK: Sort

    /// The one control that genuinely differs per section — "Highest rated"
    /// means nothing on Saved, "Furthest along" means nothing on Finished.
    private var sortOptions: [String] {
        switch section {
        case 1:  return ["Recently added", "Shortest first", "Title A–Z"]
        case 2:  return ["Recently finished", "Highest rated", "Longest", "Title A–Z"]
        default: return ["Furthest along", "Recently watched", "Title A–Z"]
        }
    }

    private var sortLabel: String { sortOptions[min(sortMode, sortOptions.count - 1)] }

    private func applySort(_ list: [BingeLibraryItem]) -> [BingeLibraryItem] {
        switch sortLabel {
        case "Title A–Z":
            return list.sorted { $0.show.title.localizedStandardCompare($1.show.title) == .orderedAscending }
        case "Highest rated":
            return list.sorted {
                ($0.rating ?? 0) == ($1.rating ?? 0)
                ? $0.show.title.localizedStandardCompare($1.show.title) == .orderedAscending
                : ($0.rating ?? 0) > ($1.rating ?? 0)
            }
        case "Longest":       return list.sorted { $0.lengthUnits > $1.lengthUnits }
        case "Shortest first":return list.sorted { $0.lengthUnits < $1.lengthUnits }
        case "Furthest along":return list.sorted { $0.progress > $1.progress }
        default:
            // Recently finished / watched / added — all newest first.
            return list.sorted { ($0.watchedDate ?? "") > ($1.watchedDate ?? "") }
        }
    }

    // MARK: Sort & filter sheet

    private var filterSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sort & filter").bingeDisplay(28)
                Spacer()
                if activeFilterCount > 0 {
                    Button { clearFilters() } label: {
                        Text("Clear all").bingeLabel(10).foregroundStyle(BingeTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 26)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    // Sort sits above the rule and never counts toward the badge —
                    // it doesn't show you less, it reorders what you have.
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Sort by").bingeLabel(9)
                            .foregroundStyle(BingeTheme.inkMuted)
                            .padding(.bottom, 10)
                        ForEach(Array(sortOptions.enumerated()), id: \.offset) { index, label in
                            Button { sortMode = index } label: {
                                HStack {
                                    Text(label).bingeBody(15)
                                        .foregroundStyle(sortMode == index ? BingeTheme.ink : BingeTheme.inkMuted)
                                    Spacer()
                                    if sortMode == index {
                                        Rectangle().fill(BingeTheme.accent).frame(width: 9, height: 9)
                                    }
                                }
                                .padding(.vertical, 11)
                                .overlay(alignment: .top) { BingeRule() }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        BingeRule()
                    }

                    BingeRule(strong: true)

                    facet("Kind", options: ["All", "Shows", "Films"], selection: $kindFilter)

                    facet("Rating", options: ["All", "Rated", "Unrated"], selection: $rateFilter)

                    VStack(alignment: .leading, spacing: 11) {
                        Text("Platform").bingeLabel(9).foregroundStyle(BingeTheme.inkMuted)
                        if libraryPlatforms.isEmpty {
                            Text("No platforms known for these titles yet")
                                .bingeBody(13).foregroundStyle(BingeTheme.inkFaint)
                        } else {
                            BingeFlowGrid {
                                ForEach(libraryPlatforms, id: \.self) { name in
                                    let on = platformFilter == name
                                    Button { platformFilter = on ? nil : name } label: {
                                        Text(name).bingeLabel(10)
                                            .foregroundStyle(on ? BingeTheme.ground : BingeTheme.inkMuted)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(on ? BingeTheme.ink : BingeTheme.ground)
                                            .overlay(Rectangle().stroke(on ? BingeTheme.ink : BingeTheme.hairline, lineWidth: 1))
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, BingeTheme.gutter)
                .padding(.bottom, 24)
            }

            Button { showFilters = false } label: {
                Text(items.count == 1 ? "Show 1 title" : "Show \(items.count) titles")
                    .bingeLabel(11)
                    .foregroundStyle(BingeTheme.ground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(BingeTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .presentationDetents([.large])
    }

    /// A labelled row of hard-edged cells — the segmented control this system
    /// already uses, not a picker.
    private func facet(_ title: String, options: [String], selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).bingeLabel(9).foregroundStyle(BingeTheme.inkMuted)
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                    let on = selection.wrappedValue == index
                    Button { selection.wrappedValue = index } label: {
                        Text(label).bingeLabel(10)
                            .foregroundStyle(on ? BingeTheme.ground : BingeTheme.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(on ? BingeTheme.ink : BingeTheme.ground)
                            .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// One thin line stating the filter in words, only when something is on.
    @ViewBuilder
    private var filterSummaryLine: some View {
        if activeFilterCount > 0 {
            HStack(spacing: 10) {
                Text(filterSummary).bingeLabel(10)
                    .foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    clearFilters()
                } label: {
                    Text("Clear").bingeLabel(10).foregroundStyle(BingeTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.vertical, 11)
            .background(BingeTheme.ground)
            BingeRule()
        }
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

    /// The section's contents before any filtering — what the platform chips
    /// are built from, so a chip always returns something.
    private var sectionItems: [BingeLibraryItem] {
        switch section {
        case 1: return engine.watchlist
        case 2: return engine.finished
        default: return engine.watching.isEmpty ? engine.library : engine.watching
        }
    }

    private var items: [BingeLibraryItem] {
        let filtered = sectionItems.filter { item in
            if kindFilter == 1 && item.isMovie { return false }
            if kindFilter == 2 && !item.isMovie { return false }
            if ratingFilterApplies {
                let rated = (item.rating ?? 0) > 0
                if rateFilter == 1 && !rated { return false }
                if rateFilter == 2 && rated { return false }
            }
            if let platformFilter, item.platform != platformFilter { return false }
            return true
        }
        return applySort(filtered)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if engine.isLoading && items.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        skeletonRow
                        BingeRule()
                    }
                } else if items.isEmpty {
                    BingeArgumentBlock(kicker: emptyKicker,
                                       headline: emptyHeadline,
                                       message: emptyMessage)
                } else {
                    ForEach(items) { item in
                        BingeSwipeRow(shareText: shareText(for: item)) {
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
                        }
                        .contextMenu {
                            // The swipe is invisible until found; long-press is the
                            // discoverable path to the same action.
                            ShareLink(item: shareText(for: item)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                Task { await engine.delete(item: item) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        BingeRule()
                    }
                }
            }
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(BingeTheme.hairline)
                .frame(width: 56, height: 80)
                .cornerRadius(4)
            VStack(alignment: .leading, spacing: 8) {
                Rectangle()
                    .fill(BingeTheme.hairline)
                    .frame(height: 16)
                    .frame(maxWidth: 140)
                Rectangle()
                    .fill(BingeTheme.hairline)
                    .frame(height: 12)
                    .frame(maxWidth: 100)
            }
            Spacer(minLength: 84)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
    }

    private func row(_ item: BingeLibraryItem) -> some View {
        HStack(spacing: 14) {
            BingePoster(urlString: item.show.posterUrl, width: 56, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.show.title).bingeHeadline(16).lineLimit(1)

                // Finished: facts about the title. Everything else: where you are.
                if item.isFinished {
                    Text(item.kindLine)
                        .bingeBody(12).foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
                    if let lengthLine = item.lengthLine {
                        Text(lengthLine)
                            .bingeBody(12).foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
                    }
                } else {
                    Text(item.subtitle)
                        .bingeBody(12).foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
                }

                if item.isFinished {
                    // The verdict, always on the same line whether set or not — so
                    // rating something doesn't reflow the list.
                    Button { ratingTarget = item } label: {
                        Group {
                            if let rating = item.rating, rating > 0 {
                                HStack(spacing: 3) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: star <= rating ? "star.fill" : "star")
                                            .font(.system(size: 13))
                                            .foregroundStyle(star <= rating ? BingeTheme.ink : BingeTheme.inkFaint)
                                    }
                                    Spacer(minLength: 0)
                                }
                            } else {
                                HStack {
                                    Text("Rate it").bingeLabel(10).foregroundStyle(BingeTheme.accent)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(height: 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((item.rating ?? 0) > 0
                                        ? "Rated \(item.rating ?? 0) out of 5. Change rating"
                                        : "Rate this")
                } else if item.totalEpisodes > 0 && item.watchedEpisodes > 0 {
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
            Spacer(minLength: 24)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
    }

    /// Finished rows carry their own rating control inside the row, so nothing
    /// trails them. Watchlist and in-progress rows keep their verb.
    @ViewBuilder
    private func trailingAction(_ item: BingeLibraryItem) -> some View {
        if item.isWatchlist {
            Text("Start")
                .bingeLabel(11).foregroundStyle(BingeTheme.accent)
                .padding(.vertical, 12)
        } else if item.isWatching {
            Text("Resume")
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
