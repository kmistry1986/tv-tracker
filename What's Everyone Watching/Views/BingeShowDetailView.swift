//  BingeShowDetailView.swift
//  The show screen: what it is, how far you are, and every episode you can
//  tick off — plus "finish the show" and "finish whole seasons" in one place.
//
//  Replaces ShowDetailView for anything opened from a Binge screen. Same data
//  paths as the original (TMDB for details/episodes, Supabase for watched
//  state), restyled to the system and with the 1–5 rating sheet attached.
//
//  `tmdbId` drives TMDB and the episodes table (as the original did).
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

    @Environment(\.dismiss) private var dismiss

    private var allEpisodes: [EpisodeDetail] { episodesBySeason.values.flatMap { $0 } }
    private var totalCount: Int { max(allEpisodes.count, details?.numberOfEpisodes ?? 0) }
    private var watchedCount: Int { watched.count }
    private var fraction: Double {
        totalCount == 0 ? 0 : min(1, Double(watchedCount) / Double(totalCount))
    }
    private var seasonEpisodes: [EpisodeDetail] { episodesBySeason[selectedSeason] ?? [] }
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
                        if isInLibrary {
                            actions
                            BingeRule(strong: true)
                        }
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
        .task { await load() }
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
                Text("By season").bingeLabel(12)
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
                }
            }
        }
        .background(BingeTheme.ground)
    }

    private var seasonHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Season \(selectedSeason) · \(seasonEpisodes.count) episodes")
                .bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
            Spacer()
            if isInLibrary && !seasonEpisodes.isEmpty {
                Button { Task { await setSeason(selectedSeason, watched: !seasonDone) } } label: {
                    Text(seasonDone ? "Unmark season" : "Mark season")
                        .bingeLabel(11).foregroundStyle(BingeTheme.accent)
                        .padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

            // Insert episode record if marking as watched
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

            if turningOn && wasEmpty {
                try await supabase.moveWatchlistToLibrary(userId: userId, showId: dbShowId ?? tmdbId)
            } else if !turningOn && watched.isEmpty {
                try await supabase.removeFromLibraryIfNoWatchedEpisodes(userId: userId, showId: dbShowId ?? tmdbId)
            }

            if isNowComplete && !wasComplete {
                showRatingSheet = true
            }
        } catch {
            if turningOn { watched.remove(ep.id) } else { watched.insert(ep.id) }
        }
    }

    private func setSeason(_ season: Int, watched on: Bool) async {
        isWorking = true
        guard let userId = supabase.currentUser?.id else { isWorking = false; return }

        for ep in episodesBySeason[season] ?? [] {
            let episode = Episode(id: ep.id, showId: tmdbId, tmdbId: ep.id,
                                seasonNumber: season, episodeNumber: ep.episodeNumber,
                                name: ep.name, overview: ep.overview ?? "",
                                airDate: ep.airDate, userId: userId,
                                watched: on, watchedAt: on ? ISO8601DateFormatter().string(from: Date()) : nil,
                                showTitle: details?.name)
            try? await supabase.insertEpisode(episode: episode)
            if on { watched.insert(ep.id) } else { watched.remove(ep.id) }
        }
        isWorking = false
    }

    private func finishShow(thenRate: Bool) async {
        guard let userId = supabase.currentUser?.id else { return }
        isWorking = true

        let wasEmpty = watched.isEmpty
        for s in seasons { await setSeason(s, watched: true) }

        if wasEmpty && !isInLibrary {
            try? await supabase.moveWatchlistToLibrary(userId: userId, showId: dbShowId ?? tmdbId)
            isInLibrary = true
        }

        let rows = (try? await supabase.fetchEpisodes(showId: tmdbId, userId: userId)) ?? []
        watched = Set(rows.filter { $0.watched }.map { $0.id })

        isWorking = false
        if thenRate || rating == nil { showRatingSheet = true }
    }

    private func applySeasons(on: [Int], off: [Int]) async {
        showSeasonSheet = false
        for s in on { await setSeason(s, watched: true) }
        for s in off { await setSeason(s, watched: false) }

        guard let userId = supabase.currentUser?.id else { return }
        let rows = (try? await supabase.fetchEpisodes(showId: tmdbId, userId: userId)) ?? []
        watched = Set(rows.filter { $0.watched }.map { $0.id })

        if rating == nil && !on.isEmpty { showRatingSheet = true }
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
