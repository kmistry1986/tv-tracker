//  BingeYouView.swift
//  The 3a You tab: library, watchlist and profile in one screen.
//  Replaces the embedded LibraryView / WatchlistView.
//
//  Movies are not listed yet — `fetchUserMovies` returns UserMovie rows whose
//  movieId is a DB id, and there's no fetchMovieById on SupabaseService.
//  Add one mirroring fetchShowById and this file can include them.

import SwiftUI
import Combine

struct BingeLibraryItem: Identifiable {
    let id: Int
    let show: TVShow
    let rating: Int?
    let watchedDate: String?
    let isWatchlist: Bool

    var subtitle: String {
        var parts: [String] = []
        if let d = show.firstAirDate, d.count >= 4 { parts.append(String(d.prefix(4))) }
        if show.numberOfEpisodes > 0 { parts.append("\(show.numberOfEpisodes) eps") }
        if let rating { parts.append("Rated \(rating)") }
        return parts.isEmpty ? "Series" : parts.joined(separator: " · ")
    }
}

@MainActor
final class BingeYouEngine: ObservableObject {
    @Published var library: [BingeLibraryItem] = []
    @Published var watchlist: [BingeLibraryItem] = []
    @Published var isLoading = false
    @Published var searchText = ""

    private let supabase = SupabaseService.shared

    var ratedCount: Int { library.filter { $0.rating != nil }.count }

    func filtered(_ items: [BingeLibraryItem]) -> [BingeLibraryItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.show.title.localizedCaseInsensitiveContains(searchText) }
    }

    func load() async {
        guard let userId = supabase.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        let shows = (try? await supabase.fetchUserShows(userId: userId)) ?? []
        var built: [BingeLibraryItem] = []
        for row in shows {
            guard let show = try? await supabase.fetchShowById(id: row.showId) else { continue }
            built.append(BingeLibraryItem(id: row.id, show: show, rating: row.rating,
                                          watchedDate: row.watchedDate, isWatchlist: false))
        }
        library = built.sorted { $0.show.title < $1.show.title }

        let list = (try? await supabase.fetchWatchlistShows(userId: userId)) ?? []
        var wl: [BingeLibraryItem] = []
        for row in list {
            guard let show = try? await supabase.fetchShowById(id: row.showId) else { continue }
            wl.append(BingeLibraryItem(id: row.id, show: show, rating: nil,
                                       watchedDate: row.addedAt, isWatchlist: true))
        }
        watchlist = wl
    }
}

struct BingeYouView: View {
    @EnvironmentObject private var supabase: SupabaseService
    @StateObject private var engine = BingeYouEngine()
    @Binding var tab: BingeTab
    @State private var section = 0
    @State private var showSettings = false
    @State private var showImport = false

    var body: some View {
        VStack(spacing: 0) {
            header
            BingeRule(strong: true)

            BingeStatRow(stats: [
                BingeStat(value: "\(engine.library.count)", label: "In library"),
                BingeStat(value: "\(engine.watchlist.count)", label: "Saved"),
                BingeStat(value: "\(engine.ratedCount)", label: "Rated", accent: true)
            ])
            BingeRule(strong: true)

            BingeSegmented(options: ["Library", "Watchlist"], selection: $section)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
            BingeRule(strong: true)

            list

            BingeRule(strong: true)
            HStack(spacing: 8) {
                BingeChip(title: "Import") { showImport = true }
                BingeChip(title: "Platforms", muted: true) { showSettings = true }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .navigationBarHidden(true)
        .padding(.top, 50)
        .safeAreaInset(edge: .bottom, spacing: 0) { BingeTabBar(selection: $tab) }
        .sheet(isPresented: $showSettings) { BingeSettingsView() }
        .sheet(isPresented: $showImport) { ImportManagementView() }
        .task { await engine.load() }
        .onChange(of: showSettings) { _, newValue in
            if !newValue {
                Task { await engine.load() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(initials)
                .bingeHeadline(14)
                .frame(width: 44, height: 44)
                .background(BingeTheme.ink).foregroundStyle(BingeTheme.ground)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName).bingeHeadline(18)
                Text(supabase.currentUser?.email ?? "")
                    .bingeBody(12).foregroundStyle(BingeTheme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { showSettings = true } label: {
                Text("Settings").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                    .padding(.vertical, 10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.top, 8).padding(.bottom, 14)
    }

    private var list: some View {
        let items = engine.filtered(section == 0 ? engine.library : engine.watchlist)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if engine.isLoading && items.isEmpty {
                    ProgressView().tint(BingeTheme.accent).padding(.vertical, 40)
                } else if items.isEmpty {
                    BingeArgumentBlock(
                        kicker: section == 0 ? "Nothing logged" : "Room for more",
                        headline: section == 0 ? "YOUR LIBRARY\nIS EMPTY." : "SAVE SOMETHING\nFOR LATER.",
                        message: section == 0
                            ? "Import your Netflix history or rate a show to start. Tonight gets sharper with every title you log."
                            : "Anything you save from Tonight or a friend's feed lands here.")
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            ShowDetailView(showId: item.show.tmdbId, showTitle: item.show.title)
                        } label: {
                            BingeTitleRow(posterURL: item.show.posterUrl,
                                          title: item.show.title,
                                          subtitle: item.subtitle) {
                                if item.rating == nil {
                                    Text("Rate it").bingeLabel(11).foregroundStyle(BingeTheme.accent)
                                } else {
                                    Text("\(item.rating ?? 0)")
                                        .bingeDisplay(20).foregroundStyle(BingeTheme.ink)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        BingeRule()
                    }
                }
            }
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
