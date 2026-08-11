//  BingeMainTabView.swift
//  Three tabs instead of seven. Nothing is deleted — Library, Watchlist,
//  Activity, Import and Profile all still exist, they're nested one level down.
//
//  TO SWITCH THE APP OVER, change ONE line in ContentView.swift:
//      MainTabView()        →  BingeMainTabView()
//  Change it back any time. Your original MainTabView is untouched.

import SwiftUI
import UIKit

struct BingeMainTabView: View {
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var searchEngine = BingeSearchEngine()
    @StateObject private var youEngine = BingeYouEngine()
    @StateObject private var notificationManager = NotificationManager()
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
                NavigationStack { BingeYouView(engine: youEngine, tab: $tab) }
            }
        }
        .environmentObject(supabase)
        .environmentObject(notificationManager)
        .environmentObject(youEngine)
        .environmentObject(searchEngine)
        .tint(BingeTheme.accent)
        .onAppear {
            // Temporary: .custom() falls back to San Francisco SILENTLY when a
            // font isn't in the target, so a missing Archivo looks like a design
            // problem rather than a build one. Check the console for "Archivo".
            #if DEBUG
            print("— Archivo loaded:", UIFont.fontNames(forFamilyName: "Archivo"))
            let ttf = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil)?
                .map { $0.lastPathComponent }.sorted() ?? []
            let otf = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil)?
                .map { $0.lastPathComponent }.sorted() ?? []
            print("— Font files in bundle:", ttf + otf)
            print("— UIAppFonts declared:", Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") ?? "MISSING")
            #endif
        }
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

        // Finished-but-unrated, not mid-watch: "how was it" is a question you
        // can only answer about something you've actually finished.
        let unrated = items.filter { $0.rating == nil && $0.isFinished }
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
    @StateObject private var engine = UsersEngine()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Friends").bingeDisplay(34).textCase(.uppercase)
                Spacer(minLength: 12)
                if engine.incomingRequests.count > 0 {
                    Button { showPeople = true } label: {
                        VStack(spacing: 2) {
                            Text("Invite").bingeLabel(11)
                                .foregroundStyle(BingeTheme.accent)
                            Text("\(engine.incomingRequests.count)")
                                .bingeLabel(9)
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { showPeople = true } label: {
                        Text("Invite").bingeLabel(11)
                            .foregroundStyle(BingeTheme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 8).padding(.bottom, 12)
            BingeRule(strong: true)

            UsersFeed(engine: engine, tab: $tab, onFindPeople: { showPeople = true })
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
                    BingePeopleTab(engine: engine)
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
        .task(id: tab) { if tab == .friends { await engine.load() } }
    }
}


// MARK: - Daily Rating Prompt

struct RatingPromptPayload: Identifiable {
    let id = UUID()
    let items: [BingeLibraryItem]
}

/// 19a: the whole ask, visible at once, rated in place. A daily prompt has to
/// be cheaper than the thing it's nudging you toward — so the stars live in the
/// row and one tap is the entire interaction. No second sheet.
struct DailyRatingPrompt: View {
    @EnvironmentObject private var supabase: SupabaseService
    let items: [BingeLibraryItem]
    let onDismiss: () -> Void

    /// show id → score, held locally so a tap lands instantly and the write
    /// happens behind it.
    @State private var scores: [Int: Int] = [:]

    private var ratedCount: Int {
        var n = 0
        for value in scores.values where value > 0 { n += 1 }
        return n
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Rate these").bingeDisplay(28)
                Spacer(minLength: 12)
                // One way out, and it isn't the loudest thing on screen.
                Button { onDismiss() } label: {
                    Text("Not now").bingeLabel(11)
                        .foregroundStyle(BingeTheme.inkMuted)
                        .padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 14)

            Text("You finished these. One tap each and Tonight gets sharper.")
                .bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BingeTheme.gutter)
                .padding(.top, 6).padding(.bottom, 12)

            BingeRule(strong: true)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        promptRow(item)
                        BingeRule()
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Text("\(ratedCount) of \(items.count) rated").bingeLabel(11)
                    .foregroundStyle(BingeTheme.inkMuted)
                HStack(spacing: 3) {
                    ForEach(0..<items.count, id: \.self) { index in
                        Rectangle()
                            .fill(index < ratedCount ? BingeTheme.accent : BingeTheme.hairline)
                            .frame(height: 5)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 16).padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
    }

    private func promptRow(_ item: BingeLibraryItem) -> some View {
        let score = scores[item.show.id] ?? 0
        return HStack(spacing: 14) {
            BingePoster(urlString: item.show.posterUrl, width: 48, height: 68)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.show.title).bingeHeadline(15).lineLimit(1)
                    Text(item.kindLine).bingeLabel(10).foregroundStyle(BingeTheme.inkMuted)
                }
                // 30pt targets — on this screen, hitting the right star is the
                // entire job, so they're twice the size they are in the library.
                HStack(spacing: 7) {
                    ForEach(1...5, id: \.self) { star in
                        Button { set(star, on: item) } label: {
                            Image(systemName: star <= score ? "star.fill" : "star")
                                .font(.system(size: 21))
                                .foregroundStyle(star <= score ? BingeTheme.ink : BingeTheme.inkFaint)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                    }
                }
            }

            Spacer(minLength: 0)

            // Status only — nothing here until it's been answered.
            if score > 0 {
                Text("Saved").bingeLabel(10).foregroundStyle(BingeTheme.inkMuted)
            }
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
    }

    private func set(_ score: Int, on item: BingeLibraryItem) {
        scores[item.show.id] = score
        let done = ratedCount == items.count
        Task {
            guard let userId = supabase.currentUser?.id else { return }
            try? await supabase.updateRating(userId: userId,
                                             itemId: item.show.id,
                                             rating: score,
                                             review: nil,
                                             isMovie: item.isMovie)
            // Got what it came for — don't make them dismiss it too.
            if done {
                try? await Task.sleep(nanoseconds: 450_000_000)
                onDismiss()
            }
        }
    }
}
