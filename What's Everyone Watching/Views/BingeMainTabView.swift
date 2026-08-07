//  BingeMainTabView.swift
//  Three tabs instead of seven. Nothing is deleted — Library, Watchlist,
//  Activity, Import and Profile all still exist, they're nested one level down.
//
//  TO SWITCH THE APP OVER, change ONE line in ContentView.swift:
//      MainTabView()        →  BingeMainTabView()
//  Change it back any time. Your original MainTabView is untouched.

import SwiftUI

struct BingeMainTabView: View {
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var searchEngine = BingeSearchEngine()
    @StateObject private var youEngine = BingeYouEngine()
    @State private var tab: BingeTab = .tonight
    /// Carried WITH the presentation. A plain @State array read by a
    /// .sheet(isPresented:) closure can be captured while it's still empty,
    /// which is what rendered "Rate these" over nothing.
    @State private var ratingPrompt: RatingPromptPayload?

    var body: some View {
        Group {
            switch tab {
            case .tonight:
                NavigationStack { BingeTonightView(tab: $tab) }
            case .friends:
                NavigationStack { BingeFriendsTab(tab: $tab) }
            case .search:
                NavigationStack { BingeSearchView(engine: searchEngine, tab: $tab) }
            case .you:
                NavigationStack { BingeYouView(tab: $tab, engine: youEngine) }
            }
        }
        .environmentObject(supabase)
        .tint(BingeTheme.accent)
        .sheet(item: $ratingPrompt) { payload in
            DailyRatingPrompt(items: payload.items) {
                ratingPrompt = nil
                UserDefaults.standard.set(Date(), forKey: "lastRatingPromptDate")
            }
            .environmentObject(supabase)
        }
        .task {
            await checkAndShowRatingPrompt()
            // Preload You tab data in background
            Task { await youEngine.load() }
        }
    }

    private func checkAndShowRatingPrompt() async {
        let lastPromptDate = UserDefaults.standard.object(forKey: "lastRatingPromptDate") as? Date ?? Date(timeIntervalSince1970: 0)
        let hoursSinceLastPrompt = Date().timeIntervalSince(lastPromptDate) / 3600

        guard hoursSinceLastPrompt >= 24, let userId = supabase.currentUser?.id else { return }
        guard let items = try? await loadWatchingItems(userId: userId) else { return }

        let unrated = items.filter { $0.rating == nil && $0.isWatching }
        guard !unrated.isEmpty else { return }

        // Building the payload IS the trigger, so the sheet can never open empty.
        ratingPrompt = RatingPromptPayload(items: Array(unrated.prefix(3)))
    }

    private func loadWatchingItems(userId: String) async throws -> [BingeLibraryItem] {
        let episodes = (try? await supabase.fetchUserEpisodes(userId: userId)) ?? []
        var counts: [Int: Int] = [:]
        for ep in episodes where ep.watched {
            counts[ep.showId, default: 0] += 1
        }

        let shows = (try? await supabase.fetchUserShows(userId: userId)) ?? []
        var built: [BingeLibraryItem] = []
        for row in shows {
            guard let show = try? await supabase.fetchShowById(id: row.showId) else { continue }
            built.append(BingeLibraryItem(id: row.id, show: show, rating: row.rating,
                                          watchedDate: row.watchedDate, isWatchlist: false,
                                          watchedEpisodes: counts[row.showId] ?? 0))
        }

        return built.sorted { $0.progress > $1.progress }
    }
}

// MARK: - Friends tab
// Your ActivityFeedView and FriendsView, behind one segmented control.

struct BingeFriendsTab: View {
    @Binding var tab: BingeTab
    @State private var showPeople = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Friends").bingeDisplay(34).textCase(.uppercase)
                Spacer(minLength: 12)
                Button { showPeople = true } label: {
                    Text("Invite").bingeLabel(11)
                        .foregroundStyle(BingeTheme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 8).padding(.bottom, 12)
            BingeRule(strong: true)

            BingeFriendsFeed(tab: $tab, onFindPeople: { showPeople = true })
        }
        .sheet(isPresented: $showPeople) {
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("People").bingeDisplay(30).textCase(.uppercase)
                        Spacer(minLength: 12)
                        Button { showPeople = false } label: {
                            Text("Done").bingeLabel(11).foregroundStyle(BingeTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, BingeTheme.gutter).padding(.top, 18).padding(.bottom, 12)
                    BingeRule(strong: true)
                    BingePeopleTab()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(BingeTheme.ground)
                .foregroundStyle(BingeTheme.ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { BingeTabBar(selection: $tab) }
    }
}

// MARK: - You tab
// Library + Watchlist + Import + Profile, folded into one screen.

struct BingeYouTab: View {
    @EnvironmentObject private var supabase: SupabaseService
    @Binding var tab: BingeTab
    @State private var section = 0
    @State private var showSettings = false
    @State private var showImport = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 12) {
                    Text(initials).bingeHeadline(14)
                        .frame(width: 44, height: 44)
                        .background(BingeTheme.ink).foregroundStyle(BingeTheme.ground)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(supabase.currentUser?.name ?? "You").bingeHeadline(18)
                        Text(supabase.currentUser?.email ?? "")
                            .bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                    }
                }
                Spacer()
                Button { showSettings = true } label: {
                    Text("Settings").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 8).padding(.bottom, 14)
            BingeRule(strong: true)

            BingeSegmented(options: ["Library", "Watchlist"], selection: $section)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
            BingeRule(strong: true)

            Group {
                if section == 0 { LibraryView() } else { WatchlistView() }
            }
            .toolbar(.hidden, for: .navigationBar)

            BingeRule(strong: true)
            HStack(spacing: 8) {
                BingeChip(title: "Import") { showImport = true }
                BingeChip(title: "Platforms", muted: true) { showSettings = true }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { BingeTabBar(selection: $tab) }
        .sheet(isPresented: $showSettings) { BingeSettingsView() }
        .sheet(isPresented: $showImport) { ImportManagementView() }
    }

    private var initials: String {
        let name = supabase.currentUser?.name ?? "You"
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

// MARK: - Daily Rating Prompt

struct RatingPromptPayload: Identifiable {
    let id = UUID()
    let items: [BingeLibraryItem]
}

struct DailyRatingPrompt: View {
    @EnvironmentObject private var supabase: SupabaseService
    let items: [BingeLibraryItem]
    let onDismiss: () -> Void
    @State private var ratingTarget: BingeLibraryItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Rate these").bingeDisplay(28)
                    Spacer()
                    Button { onDismiss() } label: {
                        Text("Skip").bingeLabel(11).foregroundStyle(BingeTheme.accent)
                            .padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, BingeTheme.gutter).padding(.top, 12).padding(.bottom, 10)
                BingeRule(strong: true)

                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing to rate").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                        Text("You're caught up on everything you're watching.")
                            .bingeBody(14).foregroundStyle(BingeTheme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 18)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            Button { ratingTarget = item } label: {
                                HStack(spacing: 14) {
                                    BingePoster(urlString: item.show.posterUrl, width: 48, height: 68)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.show.title).bingeHeadline(15).lineLimit(2)
                                        Text("Tap to rate").bingeLabel(10).foregroundStyle(BingeTheme.inkMuted)
                                    }
                                    Spacer()
                                    Text("★").bingeHeadline(16).foregroundStyle(BingeTheme.accentTint)
                                }
                                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(BingeTheme.ink)
                            BingeRule()
                        }
                    }
                }

                VStack(spacing: 9) {
                    BingePrimaryButton(title: "Later") { onDismiss() }
                }
                .padding(.horizontal, BingeTheme.gutter).padding(.top, 12).padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(BingeTheme.ground)
            .foregroundStyle(BingeTheme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $ratingTarget) { item in
                BingeRatingSheet(title: item.show.title,
                                 posterUrl: item.show.posterUrl,
                                 itemId: item.show.id,
                                 isMovie: false,
                                 existingRating: item.rating) { _, _ in
                    ratingTarget = nil
                }
            }
        }
    }
}
