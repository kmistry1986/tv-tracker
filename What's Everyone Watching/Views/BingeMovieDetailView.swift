//  BingeMovieDetailView.swift
//  Unified movie detail view: what it is and whether you've watched it.
//
//  Used from all Binge screens (Tonight, You, Search, Friends).
//  Same data paths as the original (TMDB for details, Supabase for watched
//  state), restyled to the system and with the 1–5 rating sheet attached.
//
//  `tmdbId` drives TMDB. `dbMovieId` is the movies row id for ratings.

import SwiftUI

struct BingeMovieDetailView: View {
    let tmdbId: Int
    var dbMovieId: Int? = nil
    let title: String

    @StateObject private var tmdb = TMDBService.shared
    @StateObject private var supabase = SupabaseService.shared

    @State private var details: MovieDetail?
    @State private var rating: Int?
    @State private var review: String?
    @State private var isInLibrary = false
    /// On your watchlist. Same as the show page: without this the screen can't
    /// say which of your lists it's in.
    @State private var isSaved = false
    /// watchlist_movies row id — that table only deletes by row id.
    @State private var savedRowId: Int? = nil
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var showAbout = false
    @State private var showRatingSheet = false
    @State private var justFinished = false
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var youEngine: BingeYouEngine

    @Environment(\.dismiss) private var dismiss

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
                    LazyVStack(spacing: 0) {
                        subject
                        BingeRule(strong: true)
                        actions
                        BingeRule(strong: true)
                        if let overview = details?.overview, !overview.isEmpty {
                            about(overview)
                            BingeRule(strong: true)
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
        .sheet(isPresented: $showRatingSheet) {
            BingeRatingSheet(title: details?.title ?? title,
                             posterUrl: details?.imageUrl,
                             itemId: dbMovieId ?? tmdbId,
                             isMovie: true,
                             existingRating: rating,
                             existingReview: review) { newRating, newReview in
                rating = newRating
                review = newReview
            }
        }
        .onChange(of: showRatingSheet) { _, newValue in
            // After rating sheet closes and we just finished the movie, dismiss back to previous screen
            if !newValue && justFinished {
                dismiss()
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
            Text(details?.title ?? title).bingeLabel(11)
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
                Text((details?.title ?? title).uppercased())
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
            if let release = d.releaseDate, release.count >= 4 {
                parts.append(String(release.prefix(4)))
            }
            if let runtime = d.runtime, runtime > 0 {
                parts.append("\(runtime) min")
            }
        }
        return parts.isEmpty ? "Movie" : parts.joined(separator: " · ")
    }

    /// The show page's Save → Watching → Watched, minus the middle: a film has
    /// no midpoint to be at. Two cells, same geometry, same rules — so the two
    /// detail pages read as one design rather than two.
    private var actions: some View {
        HStack(spacing: 0) {
            stateCell("Save", on: isSaved) { Task { await setState(saved: true) } }
            stateCell("Watched", on: isInLibrary, accent: true) { Task { await setState(saved: false) } }
        }
        .opacity(isWorking ? 0.5 : 1)
        .allowsHitTesting(!isWorking)
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
    }

    private func stateCell(_ title: String,
                           on: Bool,
                           accent: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).bingeLabel(12)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap, alignment: .leading)
                .padding(.horizontal, 12)
                .foregroundStyle(on ? BingeTheme.ground : BingeTheme.inkMuted)
                .background(on ? (accent ? BingeTheme.accent : BingeTheme.ink) : Color.clear)
                .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// One entry point for both cells, so the lists can never disagree.
    /// `removeMovieFromLibrary` is safe to use here — unlike the show version it
    /// deletes no episode history, because a film has none.
    private func setState(saved: Bool) async {
        guard let userId = supabase.currentUser?.id else { return }
        let id = dbMovieId ?? tmdbId
        isWorking = true
        defer { isWorking = false }

        if saved {
            if isSaved {                                   // tap Save again to unsave
                if let rowId = savedRowId {
                    try? await supabase.removeFromWatchlistMovie(id: rowId)
                }
                isSaved = false; savedRowId = nil
                return
            }
            if isInLibrary {
                try? await supabase.removeMovieFromLibrary(userId: userId, movieId: id)
                isInLibrary = false
                youEngine.library.removeAll { $0.show.id == id }
            }
            try? await supabase.addToWatchlistMovie(userId: userId, movieId: id, priority: "high")
            isSaved = true
            await refreshSavedRow(userId: userId, movieId: id)
        } else {
            if isInLibrary {                               // tap Watched again to undo
                try? await supabase.removeMovieFromLibrary(userId: userId, movieId: id)
                isInLibrary = false
                youEngine.library.removeAll { $0.show.id == id }
                return
            }
            if isSaved, let rowId = savedRowId {
                try? await supabase.removeFromWatchlistMovie(id: rowId)
                isSaved = false; savedRowId = nil
            }
            await markWatched()
        }
    }

    private func refreshSavedRow(userId: String, movieId: Int) async {
        guard let rows = try? await supabase.fetchWatchlistMovies(userId: userId) else { return }
        savedRowId = rows.first { $0.movieId == movieId }?.id
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

    // MARK: Data

    private func load() async {
        guard let userId = supabase.currentUser?.id else { isLoading = false; return }
        do {
            let d = try await tmdb.getMovie(id: tmdbId)
            details = d

            // Refresh watch providers from TMDB
            _ = try? await tmdb.getMovieWatchProviders(movieId: tmdbId)

            let userMovies = (try? await supabase.fetchUserMovies(userId: userId)) ?? []
            if let userMovie = userMovies.first(where: { $0.movieId == (dbMovieId ?? tmdbId) }) {
                rating = userMovie.rating
                review = userMovie.review
                isInLibrary = true
            }

            if let saved = try? await supabase.fetchWatchlistMovies(userId: userId),
               let row = saved.first(where: { $0.movieId == (dbMovieId ?? tmdbId) }) {
                isSaved = true
                savedRowId = row.id
            }
        } catch {
            print("BingeMovieDetailView load failed: \(error)")
        }
        isLoading = false
    }

    private func markWatched() async {
        guard let userId = supabase.currentUser?.id else { return }

        do {
            let today = ISO8601DateFormatter().string(from: Date())
            try await supabase.insertUserMovie(userId: userId, movieId: dbMovieId ?? tmdbId, watchedDate: today)
            isInLibrary = true
            notificationManager.show("Marked as watched")
            youEngine.library.removeAll { $0.show.id == (dbMovieId ?? tmdbId) }
            justFinished = true
            showRatingSheet = true
        } catch {
            print("Failed to mark movie as watched: \(error)")
        }
    }
}
