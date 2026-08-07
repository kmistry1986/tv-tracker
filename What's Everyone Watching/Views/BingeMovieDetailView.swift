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
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var showAbout = false
    @State private var showRatingSheet = false
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
                        if isInLibrary {
                            actions
                            BingeRule(strong: true)
                        }
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
        }
        return parts.isEmpty ? "Movie" : parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { Task { await markWatched() } } label: {
                HStack {
                    Text(isWorking ? "Working…" : "Mark watched")
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

    // MARK: Data

    private func load() async {
        guard let userId = supabase.currentUser?.id else { isLoading = false; return }
        do {
            let d = try await tmdb.getMovie(id: tmdbId)
            details = d

            let userMovies = (try? await supabase.fetchUserMovies(userId: userId)) ?? []
            if let userMovie = userMovies.first(where: { $0.movieId == (dbMovieId ?? tmdbId) }) {
                rating = userMovie.rating
                review = userMovie.review
                isInLibrary = true
            }
        } catch {
            print("BingeMovieDetailView load failed: \(error)")
        }
        isLoading = false
    }

    private func markWatched() async {
        isWorking = true
        guard let userId = supabase.currentUser?.id else { isWorking = false; return }

        do {
            let today = ISO8601DateFormatter().string(from: Date())
            try await supabase.insertUserMovie(userId: userId, movieId: dbMovieId ?? tmdbId, watchedDate: today)
            isInLibrary = true
            notificationManager.show("Marked as watched")
            youEngine.library.removeAll { $0.show.id == (dbMovieId ?? tmdbId) }
            showRatingSheet = true
        } catch {
            print("Failed to mark movie as watched: \(error)")
        }
        isWorking = false
    }
}
