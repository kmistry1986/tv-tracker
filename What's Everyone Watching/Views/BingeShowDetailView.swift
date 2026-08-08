//  BingeShowDetailView.swift
//  Unified show detail view: what it is, how far you are, and every episode you can
//  tick off — plus "finish the show" and "finish whole seasons" in one place.
//
//  Used from all Binge screens (Tonight, You, Search, Friends, Home, Library).
//  Same data paths as the original (TMDB for details/episodes, Supabase for watched
//  state), restyled to the system and with the 1–5 rating sheet attached.
//
//  `tmdbId` drives TMDB and the episodes table.
//  `dbShowId` is the tv_shows row id — the one user_shows.show_id points at,
//  so ratings PATCH the right row. Pass it when the caller knows it.

import SwiftUI

struct BingeShowDetailView: View {
    let tmdbId: Int
    var dbShowId: Int? = nil
    let title: String

    @StateObject private var tmdb = TMDBService.shared
    @StateObject private var supabase = SupabaseService.shared

    @State private var details: TVShowDetail?
    @State private var seasons: [Int] = []
    @State private var selectedSeason = 1
    @State private var episodesBySeason: [Int: [EpisodeDetail]] = [:]
    @State private var watched: Set<Int> = []
    @State private var rating: Int?
    @State private var review: String?
    @State private var isInLibrary = false
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var showAbout = false
    @State private var showSeasonSheet = false
    @State private var showRatingSheet = false
    @State private var confirmFinishShow = false
    @State private var hasLoaded = false
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var youEngine: BingeYouEngine

    @Environment(\.dismiss) private var dismiss

    private var allEpisodes: [EpisodeDetail] { episodesBySeason.values.flatMap { $0 } }
    private var totalCount: Int { max(allEpisodes.count, details?.numberOfEpisodes ?? 0) }
    private var watchedCount: Int { watched.count }
    private var fraction: Double {
        totalCount == 0 ? 0 : min(1, Double(watchedCount) / Double(totalCount))
    }
    private var seasonEpisodes: [EpisodeDetail] { episodesBySeason[selectedSeason] ?? [] }
    private var showTitleForWrite: String? { details?.name ?? title }
    private var seasonDone: Bool {
        !seasonEpisodes.isEmpty && seasonEpisodes.allSatisfy { watched.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            BingeRule(strong: true)

            if isLoading {
                Spacer()
                ProgressView().tint(BingeTheme.accent).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        subject
                        BingeRule(strong: true)
                        progressBlock
                        BingeRule(strong: true)
                        actions
                        BingeRule(strong: true)
                        if let overview = details?.overview, !overview.isEmpty {
                            about(overview)
                            BingeRule(strong: true)
                        }

                        Section {
                            seasonHeader
                            BingeRule(strong: true)
                            if seasonEpisodes.isEmpty {
                                Text("No episodes listed for this season.")
                                    .bingeBody(13).foregroundStyle(BingeTheme.inkMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 20)
                            } else {
                                ForEach(seasonEpisodes) { ep in
                                    episodeRow(ep)
                                    BingeRule()
                                }
                            }
                        } header: {
                            seasonStrip
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if !hasLoaded {
                await load()
                hasLoaded = true
            }
        }
        .confirmationDialog("Mark every episode as watched?",
                            isPresented: $confirmFinishShow, titleVisibility: .visible) {
            Button("Finish the show") { Task { await finishShow(thenRate: false) } }
            Button("Finish and rate it") { Task { await finishShow(thenRate: true) } }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showSeasonSheet) {
            BingeSeasonSheet(seasons: seasons,
                             episodesBySeason: episodesBySeason,
                             watched: watched) { on, off in
                Task { await applySeasons(on: on, off: off) }
            }
        }
        .sheet(isPresented: $showRatingSheet) {
            BingeRatingSheet(title: details?.name ?? title,
                             posterUrl: details?.imageUrl,
                             itemId: dbShowId ?? tmdbId,
                             isMovie: false,
                             existingRating: rating,
                             existingReview: review) { newRating, newReview in
                rating = newRating
                review = newReview
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("←").bingeHeadline(18)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(details?.name ?? title).bingeLabel(11)
                .foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
            Spacer(minLength: 8)
            Button { showRatingSheet = true } label: {
                Text(rating == nil ? "Rate it" : "\(rating ?? 0)/5")
                    .bingeLabel(11)
                    .foregroundStyle(rating == nil ? BingeTheme.accent : BingeTheme.inkMuted)
                    .padding(.vertical, 12).padding(.leading, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8).padding(.trailing, BingeTheme.gutter)
        .padding(.top, 4)
    }

    private var subject: some View {
        HStack(alignment: .top, spacing: 14) {
            BingePoster(urlString: details?.imageUrl, width: 74, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text((details?.name ?? title).uppercased())
                    .bingeDisplay(26)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metaLine).bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let d = details {
            if let air = d.firstAirDate, air.count >= 4 { parts.append(String(air.prefix(4))) }
            parts.append(d.displayStatus)
            if d.numberOfSeasons > 0 {
                parts.append("\(d.numberOfSeasons) season\(d.numberOfSeasons == 1 ? "" : "s")")
            }
            if d.displayGenres != "Unknown" { parts.append(d.displayGenres) }
        }
        return parts.joined(separator: " · ")
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(watchedCount) of \(totalCount) episodes")
                    .bingeHeadline(16)
                Spacer()
                Text(totalCount == 0 ? "—" : "\(Int(fraction * 100))%")
                    .bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
            }
            BingeProgress(fraction: fraction)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { confirmFinishShow = true } label: {
                HStack {
                    Text(isWorking ? "Working…" : "Finish show")
                        .bingeLabel(12)
                    Spacer(minLength: 8)
                    Text("✓").bingeLabel(12)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap, alignment: .leading)
                .background(BingeTheme.accent)
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            Button { showSeasonSheet = true } label: {
                Text("Pick seasons").bingeLabel(12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap, alignment: .leading)
                    .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
    }

    private func about(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
            Text(overview).bingeBody(13)
                .foregroundStyle(BingeTheme.ink.opacity(0.78))
                .lineLimit(showAbout ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            Button { showAbout.toggle() } label: {
                Text(showAbout ? "Less" : "More").bingeLabel(11)
                    .foregroundStyle(BingeTheme.accent)
                    .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
    }

    // MARK: Seasons and episodes

    private var seasonStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(seasons, id: \.self) { s in
                        Button { selectedSeason = s } label: {
                            Text("S\(s)").bingeLabel(11)
                                .frame(minWidth: 54, minHeight: 44)
                                .foregroundStyle(selectedSeason == s ? BingeTheme.ground : BingeTheme.inkMuted)
                                .background(selectedSeason == s ? BingeTheme.ink : BingeTheme.ground)
                                .overlay(alignment: .trailing) { BingeVRule() }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Mark a season without leaving the one you're on.
                        .contextMenu {
                            Button(seasonComplete(s) ? "Unmark season \(s)" : "Mark season \(s) watched") {
                                Task { await setSeason(s, watched: !seasonComplete(s)) }
                            }
                        }
                    }
                }
            }
            if !seasonEpisodes.isEmpty {
                Button { Task { await setSeason(selectedSeason, watched: !seasonDone) } } label: {
                    Text(seasonDone ? "Unmark\nS\(selectedSeason)" : "Mark S\(selectedSeason)\nWatched")
                        .bingeLabel(10)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .foregroundStyle(seasonDone ? BingeTheme.inkMuted : .white)
                        .background(seasonDone ? BingeTheme.ground : BingeTheme.accent)
                        .overlay(alignment: .leading) { BingeVRule() }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
        .background(BingeTheme.ground)
    }

    private func seasonComplete(_ s: Int) -> Bool {
        let eps = episodesBySeason[s] ?? []
        return !eps.isEmpty && eps.allSatisfy { watched.contains($0.id) }
    }

    private var seasonHeader: some View {
        let done = seasonEpisodes.filter { watched.contains($0.id) }.count
        return HStack(alignment: .firstTextBaseline) {
            Text("Season \(selectedSeason) · \(seasonEpisodes.count) episodes")
                .bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
            Spacer(minLength: 12)
            if !seasonEpisodes.isEmpty {
                Text("\(done) watched")
                    .bingeLabel(11)
                    .foregroundStyle(done == seasonEpisodes.count ? BingeTheme.accent : BingeTheme.inkFaint)
            }
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.top, 14).padding(.bottom, 10)
    }

    private func episodeRow(_ ep: EpisodeDetail) -> some View {
        let on = watched.contains(ep.id)
        return Button { Task { await toggle(ep) } } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Rectangle()
                        .fill(on ? BingeTheme.ink : Color.clear)
                        .overlay(Rectangle().stroke(on ? BingeTheme.ink : BingeTheme.hairline, lineWidth: 2))
                        .frame(width: 22, height: 22)
                    if on {
                        Text("✓").bingeLabel(11).foregroundStyle(BingeTheme.ground)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("E\(ep.episodeNumber)").bingeLabel(10)
                            .foregroundStyle(BingeTheme.inkMuted)
                        Text(ep.name).bingeHeadline(15).lineLimit(1)
                    }
                    if let overview = ep.overview, !overview.isEmpty {
                        Text(overview).bingeBody(12)
                            .foregroundStyle(BingeTheme.inkMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let air = ep.airDate, !air.isEmpty {
                        Text(air).bingeLabel(10).foregroundStyle(BingeTheme.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
            .frame(minHeight: BingeTheme.minTap)
            .background(on ? BingeTheme.surface : BingeTheme.ground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Episode \(ep.episodeNumber), \(ep.name)")
        .accessibilityValue(on ? "Watched" : "Not watched")
    }

    // MARK: Data

    private func load() async {
        guard let userId = supabase.currentUser?.id else { isLoading = false; return }
        do {
            let d = try await tmdb.getTVShow(id: tmdbId)
            details = d

            // Ensure show exists in database for episode tracking
            let show = TVShow(id: tmdbId, tmdbId: tmdbId, title: d.name,
                            overview: d.overview, posterUrl: d.imageUrl,
                            firstAirDate: d.firstAirDate, numberOfSeasons: d.numberOfSeasons,
                            numberOfEpisodes: d.numberOfEpisodes)
            try? await supabase.insertShow(show: show)

            let list = d.numberOfSeasons > 0 ? Array(1...d.numberOfSeasons) : []
            seasons = list
            if !list.contains(selectedSeason) { selectedSeason = list.first ?? 1 }
            for s in list {
                if let season = try? await tmdb.getTVSeason(showId: tmdbId, seasonNumber: s) {
                    episodesBySeason[s] = season.episodes
                }
            }
            let rows = (try? await supabase.fetchEpisodes(showId: tmdbId, userId: userId)) ?? []
            watched = Set(rows.filter { $0.watched }.map { $0.id })

            let userShows = (try? await supabase.fetchUserShows(userId: userId)) ?? []
            let mine = userShows.first { $0.showId == (dbShowId ?? tmdbId) }
            rating = mine?.rating
            review = mine?.review
            isInLibrary = mine != nil
        } catch {
            print("BingeShowDetailView load failed: \(error)")
        }
        isLoading = false
    }

    private func toggle(_ ep: EpisodeDetail) async {
        let turningOn = !watched.contains(ep.id)
        let wasEmpty = watched.isEmpty
        let wasComplete = fraction == 1.0

        if turningOn { watched.insert(ep.id) } else { watched.remove(ep.id) }
        let isNowComplete = watchedCount == totalCount && totalCount > 0

        do {
            guard let userId = supabase.currentUser?.id else { return }

            // Update UI immediately, then run backend calls concurrently
            if isNowComplete && !wasComplete {
                showRatingSheet = true
            }

            // Run episode insert/update and state transitions concurrently
            async let episodeOp = updateEpisode(ep: ep, turningOn: turningOn, userId: userId)
            async let stateOp = updateLibraryState(turningOn: turningOn, wasEmpty: wasEmpty, userId: userId)

            _ = try await (episodeOp, stateOp)

            // Update isInLibrary based on final watched state and update engine
            if turningOn && wasEmpty {
                notificationManager.show("Moved to Started")
                youEngine.library.removeAll { $0.show.id == (dbShowId ?? tmdbId) }
            } else if !turningOn && watched.isEmpty {
                isInLibrary = false
                notificationManager.show("Moved to Saved")
                youEngine.library.removeAll { $0.show.id == (dbShowId ?? tmdbId) }
            }
        } catch {
            if turningOn { watched.remove(ep.id) } else { watched.insert(ep.id) }
        }
    }

    private func updateEpisode(ep: EpisodeDetail, turningOn: Bool, userId: String) async throws {
        if turningOn {
            let episode = Episode(id: ep.id, showId: tmdbId, tmdbId: ep.id,
                                seasonNumber: ep.seasonNumber, episodeNumber: ep.episodeNumber,
                                name: ep.name, overview: ep.overview ?? "",
                                airDate: ep.airDate, userId: userId,
                                watched: true, watchedAt: ISO8601DateFormatter().string(from: Date()),
                                showTitle: details?.name)
            try? await supabase.insertEpisode(episode: episode)
        } else {
            try await supabase.updateEpisodeWatched(episodeId: ep.id, watched: false)
        }
    }

    private func updateLibraryState(turningOn: Bool, wasEmpty: Bool, userId: String) async throws {
        if turningOn && wasEmpty {
            async let move = supabase.moveWatchlistToLibrary(userId: userId, showId: dbShowId ?? tmdbId)
            async let remove = supabase.removeShowFromWatchlist(userId: userId, showId: dbShowId ?? tmdbId)
            _ = try await (move, remove)
        } else if !turningOn && watched.isEmpty {
            try await supabase.removeFromLibraryIfNoWatchedEpisodes(userId: userId, showId: dbShowId ?? tmdbId)
            // Add back to watchlist — force insert regardless of current state
            do {
                try await supabase.restoreToWatchlist(userId: userId, showId: dbShowId ?? tmdbId)
            } catch {
                print("Failed to restore show to watchlist: \(error)")
            }
        }
    }

    private func setSeason(_ season: Int, watched on: Bool) async {
        isWorking = true
        guard let userId = supabase.currentUser?.id else { isWorking = false; return }

        let episodes = episodesBySeason[season] ?? []
        let wasEmpty = watched.isEmpty

        // Update UI first
        for ep in episodes {
            if on { watched.insert(ep.id) } else { watched.remove(ep.id) }
        }

        // Then run all insertions/updates concurrently
        await withTaskGroup(of: Void.self) { group in
            for ep in episodes {
                group.addTask {
                    if on {
                        let episode = Episode(id: ep.id, showId: tmdbId, tmdbId: ep.id,
                                            seasonNumber: season, episodeNumber: ep.episodeNumber,
                                            name: ep.name, overview: ep.overview ?? "",
                                            airDate: ep.airDate, userId: userId,
                                            watched: true, watchedAt: ISO8601DateFormatter().string(from: Date()),
                                            showTitle: details?.name)
                        try? await supabase.insertEpisode(episode: episode)
                    } else {
                        try? await supabase.updateEpisodeWatched(episodeId: ep.id, watched: false)
                    }
                }
            }
        }

        // Marking a season is how a show ENTERS your library — same transition
        // toggle() does for a single episode.
        await syncLibraryMembership(wasEmpty: wasEmpty, userId: userId)

        isWorking = false
    }

    /// One place that decides whether this show belongs in Started or Saved,
    /// based on whether anything is ticked. Safe to call after any bulk change.
    private func syncLibraryMembership(wasEmpty: Bool, userId: String) async {
        let hasWatched = !watched.isEmpty

        if hasWatched && wasEmpty {
            // Optimistically update library before database operations complete
            if let details = details {
                let show = TVShow(id: dbShowId ?? tmdbId, tmdbId: tmdbId, title: details.name,
                                overview: details.overview, posterUrl: details.imageUrl,
                                firstAirDate: details.firstAirDate, numberOfSeasons: details.numberOfSeasons,
                                numberOfEpisodes: details.numberOfEpisodes)
                let item = BingeLibraryItem(id: dbShowId ?? tmdbId, show: show, rating: rating,
                                          watchedDate: ISO8601DateFormatter().string(from: Date()),
                                          isWatchlist: false, watchedEpisodes: watchedCount,
                                          lastSeason: nil, lastEpisode: nil)
                youEngine.library.removeAll { $0.show.id == (dbShowId ?? tmdbId) }
                youEngine.library.append(item)
            }

            async let move = supabase.moveWatchlistToLibrary(userId: userId, showId: dbShowId ?? tmdbId)
            async let remove = supabase.removeShowFromWatchlist(userId: userId, showId: dbShowId ?? tmdbId)
            _ = try? await (move, remove)
            isInLibrary = true
            notificationManager.show("Moved to Started")
        } else if !hasWatched && !wasEmpty {
            // Optimistically remove from library before database operations complete
            youEngine.library.removeAll { $0.show.id == (dbShowId ?? tmdbId) }

            try? await supabase.removeFromLibraryIfNoWatchedEpisodes(userId: userId, showId: dbShowId ?? tmdbId)
            try? await supabase.restoreToWatchlist(userId: userId, showId: dbShowId ?? tmdbId)
            isInLibrary = false
            notificationManager.show("Moved to Saved")
        }
    }

    private func finishShow(thenRate: Bool) async {
        guard let userId = supabase.currentUser?.id else { return }
        isWorking = true

        let wasEmpty = watched.isEmpty

        // Mark all episodes as watched optimistically
        for s in seasons {
            for ep in episodesBySeason[s] ?? [] {
                watched.insert(ep.id)
            }
        }

        // If moving from watchlist to library, update state immediately
        if wasEmpty && !isInLibrary {
            isInLibrary = true
        }

        // Run all backend operations concurrently
        async let seasonOps = setAllSeasons(watched: true)
        async let libraryOp = updateLibraryStateForFinish(wasEmpty: wasEmpty, userId: userId)

        _ = await (seasonOps, libraryOp)

        isWorking = false
        if thenRate || rating == nil { showRatingSheet = true }
    }

    private func setAllSeasons(watched on: Bool) async {
        guard let userId = supabase.currentUser?.id else { return }
        let showTitle = details?.name
        let episodeData = seasons.map { ($0, episodesBySeason[$0] ?? []) }

        await withTaskGroup(of: Void.self) { group in
            for (season, episodes) in episodeData {
                group.addTask {
                    for ep in episodes {
                        let episode = Episode(id: ep.id, showId: tmdbId, tmdbId: ep.id,
                                            seasonNumber: season, episodeNumber: ep.episodeNumber,
                                            name: ep.name, overview: ep.overview ?? "",
                                            airDate: ep.airDate, userId: userId,
                                            watched: on, watchedAt: on ? ISO8601DateFormatter().string(from: Date()) : nil,
                                            showTitle: showTitle)
                        try? await supabase.insertEpisode(episode: episode)
                    }
                }
            }
        }
    }

    private func updateLibraryStateForFinish(wasEmpty: Bool, userId: String) async {
        if wasEmpty && !isInLibrary {
            async let move = supabase.moveWatchlistToLibrary(userId: userId, showId: dbShowId ?? tmdbId)
            async let remove = supabase.removeShowFromWatchlist(userId: userId, showId: dbShowId ?? tmdbId)
            _ = try? await (move, remove)
        }
    }

    private func applySeasons(on: [Int], off: [Int]) async {
        showSeasonSheet = false
        guard let userId = supabase.currentUser?.id else { return }

        let wasEmpty = watched.isEmpty
        isWorking = true

        for s in on { await writeSeason(s, watched: true, userId: userId) }
        for s in off { await writeSeason(s, watched: false, userId: userId) }

        let rows = (try? await supabase.fetchEpisodes(showId: tmdbId, userId: userId)) ?? []
        watched = Set(rows.filter { $0.watched }.map { $0.id })

        // One transition for the whole batch — not one per season.
        await syncLibraryMembership(wasEmpty: wasEmpty, userId: userId)
        isWorking = false

        if rating == nil && !on.isEmpty && fraction == 1.0 { showRatingSheet = true }
    }

    /// Episode writes only. The library transition is the caller's job.
    private func writeSeason(_ season: Int, watched on: Bool, userId: String) async {
        let episodes = episodesBySeason[season] ?? []
        for ep in episodes {
            if on { watched.insert(ep.id) } else { watched.remove(ep.id) }
        }
        let showTitle = showTitleForWrite
        await withTaskGroup(of: Void.self) { group in
            for ep in episodes {
                group.addTask {
                    let episode = Episode(id: ep.id, showId: tmdbId, tmdbId: ep.id,
                                        seasonNumber: season, episodeNumber: ep.episodeNumber,
                                        name: ep.name, overview: ep.overview ?? "",
                                        airDate: ep.airDate, userId: userId,
                                        watched: on, watchedAt: on ? ISO8601DateFormatter().string(from: Date()) : nil,
                                        showTitle: showTitle)
                    try? await supabase.insertEpisode(episode: episode)
                }
            }
        }
    }
}

// MARK: - Season sheet
// One list, one checkbox per season, one save. Replaces CompleteSeasonModal
// for Binge screens.

struct BingeSeasonSheet: View {
    let seasons: [Int]
    let episodesBySeason: [Int: [EpisodeDetail]]
    let watched: Set<Int>
    var onSave: ([Int], [Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<Int> = []
    @State private var started: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Seasons").bingeDisplay(30).textCase(.uppercase)
                Spacer(minLength: 12)
                Button { dismiss() } label: {
                    Text("Cancel").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 20).padding(.bottom, 12)
            BingeRule(strong: true)

            Text("Tick a season to mark every episode in it watched. Untick to undo.")
                .bingeBody(13).foregroundStyle(BingeTheme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
            BingeRule()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(seasons, id: \.self) { s in
                        Button { toggle(s) } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Rectangle()
                                        .fill(checked.contains(s) ? BingeTheme.ink : Color.clear)
                                        .overlay(Rectangle().stroke(checked.contains(s)
                                                                    ? BingeTheme.ink : BingeTheme.hairline,
                                                                    lineWidth: 2))
                                        .frame(width: 22, height: 22)
                                    if checked.contains(s) {
                                        Text("✓").bingeLabel(11).foregroundStyle(BingeTheme.ground)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Season \(s)").bingeHeadline(16)
                                    Text(detail(s)).bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
                            .frame(minHeight: BingeTheme.minTap)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        BingeRule()
                    }
                }
            }

            Button {
                let on = checked.subtracting(started)
                let off = started.subtracting(checked)
                onSave(Array(on).sorted(), Array(off).sorted())
            } label: {
                HStack {
                    Text("Save").bingeHeadline(15).textCase(.uppercase)
                    Spacer(minLength: 12)
                    Text("→").bingeHeadline(15)
                }
                .padding(.horizontal, 18).padding(.vertical, 17)
                .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap)
                .background(BingeTheme.accent)
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 14).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .onAppear {
            let done = Set(seasons.filter { s in
                let eps = episodesBySeason[s] ?? []
                return !eps.isEmpty && eps.allSatisfy { watched.contains($0.id) }
            })
            checked = done
            started = done
        }
    }

    private func toggle(_ s: Int) {
        if checked.contains(s) { checked.remove(s) } else { checked.insert(s) }
    }

    private func detail(_ s: Int) -> String {
        let eps = episodesBySeason[s] ?? []
        let done = eps.filter { watched.contains($0.id) }.count
        if eps.isEmpty { return "No episodes listed" }
        return "\(done) of \(eps.count) watched"
    }
}
