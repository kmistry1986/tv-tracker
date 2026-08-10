//  UsersView.swift
//  The 3a Friends feed, wired to SupabaseService.
//
//  Builds the feed from friends' rated shows (getFriendRatings) rather than
//  activity_feed rows — activity rows carry only episode/movie ids, so they
//  can't produce a poster or a title without an extra lookup per row.
//
//  REQUIRES `fetchShowById(id:)` on SupabaseService (same one Tonight uses).

import SwiftUI
import Combine

struct BingeFeedEntry: Identifiable {
    let id = UUID()
    let friend: User
    let show: TVShow
    let rating: Int?
    let review: String?
    let watchedDate: String

    var meta: String {
        let first = friend.name.split(separator: " ").first.map(String.init) ?? friend.name
        return "\(first) · \(relativeDate)"
    }

    var headline: String {
        if let rating { return "Rated \(show.title) \(rating).0" }
        return "Finished \(show.title)"
    }

    private var relativeDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: watchedDate)
            ?? ISO8601DateFormatter().date(from: watchedDate)
        guard let date else { return "recently" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

@MainActor
final class UsersEngine: ObservableObject {
    @Published var friends: [User] = []
    @Published var entries: [BingeFeedEntry] = []
    @Published var suggestions: [UserProfile] = []
    @Published var incomingRequests: [(friendship: Friendship, profile: UserProfile?)] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var addingFriendId: String? = nil
    @Published var acceptingFriendId: Int? = nil
    @Published var error: String? = nil
    @Published var successMessage: String? = nil

    private let supabase = SupabaseService.shared

    /// Shows two or more friends are on — the highlighted row in the design.
    @Published var sharedShow: (show: TVShow, who: [User])?

    /// friend id → the show they're currently watching, for the people strip.
    @Published var nowWatching: [String: TVShow] = [:]

    /// Every show each friend has going. The strip is one card per SHOW, not
    /// per person — someone watching three things is three cards, because a
    /// card that stood for a person could only ever name one of them.
    @Published var nowWatchingAll: [String: [TVShow]] = [:]

    /// TMDB ids already on your watchlist. Held here so a card can show its own
    /// state — a save control that doesn't know it's already saved is worse than
    /// none, since the only way to check would be to leave the page.
    @Published var savedShowIds: Set<Int> = []
    @Published var savingShowId: Int? = nil
    /// show id → watchlist ROW id. Removal is keyed on the row, not the show.
    private var savedRowIds: [Int: Int] = [:]

    /// `show_id` in this codebase IS the TMDB id — addToWatchlistShow passes it
    /// straight to TMDBService.getTVShow(id:), so nothing here translates.
    func toggleSave(_ show: TVShow) async {
        guard let userId = supabase.currentUser?.id else { return }
        let id = show.tmdbId
        savingShowId = id
        do {
            if savedShowIds.contains(id) {
                if let rowId = savedRowIds[id] {
                    try await supabase.removeFromWatchlistShow(id: rowId)
                }
                savedShowIds.remove(id)
                savedRowIds[id] = nil
            } else {
                try await supabase.addToWatchlistShow(userId: userId, showId: id, priority: "high")
                savedShowIds.insert(id)
                // Re-read so we hold the new row's id and a second tap can undo it.
                if let rows = try? await supabase.fetchWatchlistShows(userId: userId) {
                    savedRowIds = Dictionary(rows.map { ($0.showId, $0.id) },
                                             uniquingKeysWith: { first, _ in first })
                }
                successMessage = "Saved \(show.title)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.successMessage = nil
                }
            }
        } catch {
            self.error = "Couldn't update your list. Try again."
        }
        savingShowId = nil
    }

    func load() async {
        guard let userId = supabase.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        var allFriends = (try? await supabase.fetchFriends(userId: userId)) ?? []
        print("👥 fetchFriends returned \(allFriends.count) total friend entries")
        // Deduplicate friends by ID (keep first occurrence)
        var seenIds = Set<String>()
        friends = allFriends.filter { f in
            if seenIds.contains(f.id) {
                print("  → Filtering duplicate: \(f.id) (\(f.name))")
                return false
            }
            seenIds.insert(f.id)
            print("  → Keeping: \(f.id) (\(f.name))")
            return true
        }
        print("👥 After dedup: \(friends.count) unique friends for user \(userId)")
        
        let requests = (try? await supabase.fetchFriendRequests(userId: userId)) ?? []
        var requestsWithProfiles: [(Friendship, UserProfile?)] = []
        for req in requests {
            let profile = try? await supabase.getUserProfile(userId: req.userId)
            requestsWithProfiles.append((req, profile))
        }
        incomingRequests = requestsWithProfiles

        var built: [BingeFeedEntry] = []
        var byShow: [Int: (TVShow, [User])] = [:]
        var seenShowPerFriend = Set<String>()  // Track "friendId:showId" to deduplicate globally

        for friend in friends {
            // Show completed shows in feed (rated or all episodes watched)
            let userShows = (try? await supabase.getFriendRatings(friendId: friend.id)) ?? []

            // Get episode counts for this friend
            let episodes = (try? await supabase.fetchUserEpisodes(userId: friend.id)) ?? []
            var watchedCounts: [Int: Int] = [:]
            for ep in episodes where ep.watched {
                watchedCounts[ep.showId, default: 0] += 1
            }

            var finished: [UserShow] = []
            for row in userShows {
                if row.rating != nil {
                    finished.append(row)
                } else {
                    // Check if all episodes are watched
                    guard let show = try? await supabase.fetchShowById(id: row.showId) else { continue }
                    let watchedCount = watchedCounts[row.showId] ?? 0
                    if show.numberOfEpisodes > 0 && watchedCount >= show.numberOfEpisodes {
                        finished.append(row)
                    }
                }
            }

            let sorted = finished.sorted { $0.watchedDate > $1.watchedDate }

            for row in sorted.prefix(10) {
                let key = "\(friend.id):\(row.showId)"
                guard !seenShowPerFriend.contains(key) else { continue }
                seenShowPerFriend.insert(key)

                guard let show = try? await supabase.fetchShowById(id: row.showId) else { continue }
                built.append(BingeFeedEntry(friend: friend, show: show,
                                            rating: nil, review: nil,
                                            watchedDate: row.watchedDate))
                var entry = byShow[row.showId] ?? (show, [])
                entry.1.append(friend)
                byShow[row.showId] = entry
            }
        }

        entries = built.sorted { $0.watchedDate > $1.watchedDate }

        // Build "Watching right now" from currently-watching shows, not from completed feed
        var latest: [String: TVShow] = [:]
        var all: [String: [TVShow]] = [:]
        let currentUserId = supabase.currentUser?.id ?? ""
        for friend in friends where friend.id != currentUserId {
            let currentlyWatching = (try? await supabase.getFriendCurrentlyWatching(friendId: friend.id)) ?? []
            if let show = currentlyWatching.first {
                latest[friend.id] = show
            }
            // Capped at three per person so one heavy watcher can't own the strip.
            if !currentlyWatching.isEmpty {
                all[friend.id] = Array(currentlyWatching.prefix(3))
            }
        }
        nowWatching = latest
        nowWatchingAll = all
        if let userId = supabase.currentUser?.id,
           let saved = try? await supabase.fetchWatchlistShows(userId: userId) {
            savedShowIds = Set(saved.map(\.showId))
            savedRowIds = Dictionary(saved.map { ($0.showId, $0.id) },
                                     uniquingKeysWith: { first, _ in first })
        }
        sharedShow = byShow.values.first(where: { $0.1.count >= 2 }).map { ($0.0, $0.1) }
    }

    func search() async {
        guard searchText.count >= 2 else { suggestions = []; return }
        let results = (try? await supabase.searchUsers(query: searchText)) ?? []
        // Filter out people already in your friends list
        let friendIds = Set(friends.map { $0.id })
        suggestions = results.filter { !friendIds.contains($0.userId) }
    }

    func add(_ profile: UserProfile) async {
        guard let userId = supabase.currentUser?.id else { return }
        addingFriendId = profile.userId
        error = nil
        
        do {
            try await supabase.sendFriendRequest(userId: userId, friendId: profile.userId)
            suggestions.removeAll { $0.id == profile.id }
            successMessage = "Friend request sent to \(profile.displayName)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.successMessage = nil
            }
        } catch {
            self.error = "Failed to send friend request. Please try again."
            print("Friend request error: \(error.localizedDescription)")
        }
        
        addingFriendId = nil
    }
    
    func accept(_ friendship: Friendship) async {
        guard let userId = supabase.currentUser?.id else { return }
        acceptingFriendId = friendship.id
        error = nil
        
        do {
            print("👥 Accepting friend request: \(friendship.id) from \(friendship.userId)")
            try await supabase.acceptFriendRequest(requestId: friendship.id, userId: userId, friendId: friendship.userId)
            print("👥 Friend request accepted successfully!")
            incomingRequests.removeAll { $0.friendship.id == friendship.id }
            await load()
            successMessage = "Friend request accepted"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.successMessage = nil
            }
        } catch {
            self.error = "Failed to accept request. Please try again."
            print("❌ Accept request error: \(error.localizedDescription)")
        }
        
        acceptingFriendId = nil
    }
    
    func reject(_ friendship: Friendship) async {
        acceptingFriendId = friendship.id
        error = nil
        
        do {
            try await supabase.rejectFriendRequest(requestId: friendship.id)
            incomingRequests.removeAll { $0.friendship.id == friendship.id }
            successMessage = "Friend request declined"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.successMessage = nil
            }
        } catch {
            self.error = "Failed to decline request. Please try again."
            print("Reject request error: \(error.localizedDescription)")
        }
        
        acceptingFriendId = nil
    }
}

// MARK: - Feed

struct UsersFeed: View {
    @ObservedObject var engine: UsersEngine
    @Binding var tab: BingeTab
    var onFindPeople: () -> Void = {}

    var body: some View {
        Group {
            if engine.isLoading && engine.entries.isEmpty {
                loading
            } else if engine.friends.isEmpty {
                empty
            } else {
                feed
            }
        }
    }

    private var loading: some View {
        VStack {
            Spacer()
            ProgressView().tint(BingeTheme.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Empty, but the same page. 3a's architecture is strip → strong rule →
    /// stacked rows, and that shape should be legible before a single friend
    /// exists — so the strip is present with its slots drawn empty, and the
    /// rows below are outlined rather than filled with invented people. The
    /// one thing this must never do is fake a social graph.
    private var empty: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Watching right now").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                    HStack(spacing: 10) {
                        Button { onFindPeople() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("+")
                                    .bingeHeadline(20)
                                    .foregroundStyle(BingeTheme.accent)
                                    .frame(width: 50, height: 50)
                                    .overlay(Rectangle().stroke(BingeTheme.accent, lineWidth: 1))
                                Text("Add").bingeBody(10)
                                    .foregroundStyle(BingeTheme.accent)
                                    .frame(width: 50, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 5) {
                                Rectangle().fill(Color.clear)
                                    .frame(width: 50, height: 50)
                                    .overlay(Rectangle().stroke(BingeTheme.hairline, lineWidth: 1))
                                Rectangle().fill(BingeTheme.hairline)
                                    .frame(width: 34, height: 6)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
                BingeRule(strong: true)

                BingeArgumentBlock(
                    kicker: "Nobody here yet",
                    headline: "BINGE IS EMPTY\nWITHOUT THEM.",
                    message: "Every recommendation comes from someone you know. Add three people and Tonight starts working.")
                BingePrimaryButton(title: "Find people") { onFindPeople() }
                    .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 18)
                BingeRule(strong: true)

                // The feed's own row, drawn hollow — this is the shape your
                // people will arrive in, not a placeholder for a person.
                ghostRow(lines: 3)
                BingeRule()
                ghostRow(lines: 2)
                BingeRule()

                VStack(alignment: .leading, spacing: 6) {
                    Text("What lands here").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                    Text("Ratings, finished shows and the title two or more of your people are on — newest first.")
                        .bingeBody(13).foregroundStyle(BingeTheme.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
                BingeRule()
            }
        }
        .refreshable { await engine.load() }
    }

    private func ghostRow(lines: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle().fill(Color.clear)
                .frame(width: 74, height: 104)
                .overlay(Rectangle().stroke(BingeTheme.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 9) {
                Rectangle().fill(BingeTheme.hairline).frame(width: 118, height: 6)
                Rectangle().fill(BingeTheme.hairline).frame(height: 10)
                if lines > 2 {
                    Rectangle().fill(BingeTheme.hairline).frame(height: 10).frame(maxWidth: 180)
                }
                Rectangle().fill(Color.clear)
                    .frame(width: 66, height: 24)
                    .overlay(Rectangle().stroke(BingeTheme.hairline, lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 18)
        .opacity(0.9)
        .accessibilityHidden(true)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !nowCards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Watching right now").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(nowCards.enumerated()), id: \.offset) { _, item in
                                    NavigationLink {
                                        BingeShowDetailView(tmdbId: item.show.tmdbId,
                                                            dbShowId: item.show.id,
                                                            title: item.show.title)
                                    } label: {
                                        nowCard(item.friend, show: item.show)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, BingeTheme.gutter)
                        }
                        .padding(.horizontal, -BingeTheme.gutter)
                    }
                    .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
                    BingeRule(strong: true)
                }

                if let shared = engine.sharedShow {
                    NavigationLink {
                        BingeShowDetailView(tmdbId: shared.show.tmdbId,
                                            dbShowId: shared.show.id,
                                            title: shared.show.title)
                    } label: {
                        BingeFeedRow(posterURL: shared.show.posterUrl,
                                     meta: "\(shared.who.count) friends · watching",
                                     headline: "Everyone's on \(shared.show.title)",
                                     quote: "Catch up and you're in the conversation.",
                                     highlighted: true,
                                     metaAccent: true) {
                            saveChip(shared.show, filled: true)
                        }
                    }
                    .buttonStyle(.plain)
                    BingeRule()
                }

                ForEach(engine.entries) { entry in
                    NavigationLink {
                        BingeShowDetailView(tmdbId: entry.show.tmdbId,
                                            dbShowId: entry.show.id,
                                            title: entry.show.title)
                    } label: {
                        BingeFeedRow(posterURL: entry.show.posterUrl,
                                     meta: entry.meta,
                                     headline: entry.headline,
                                     quote: entry.review) {
                            saveChip(entry.show)
                        }
                    }
                    .buttonStyle(.plain)
                    BingeRule()
                }

                if engine.entries.isEmpty {
                    BingeArgumentBlock(
                        kicker: "Quiet so far",
                        headline: "NOBODY'S RATED\nANYTHING YET.",
                        message: "Your friends are here but haven't logged a show. Nudge one, or rate something yourself to get the ball rolling.")
                }
            }
        }
        .refreshable { await engine.load() }
    }

    // MARK: - Watching right now

    /// One card per SHOW, not per person — a card that stood for a person could
    /// only ever name one of the things they're watching. Someone with three
    /// shows going gets three cards.
    private var nowCards: [(friend: User, show: TVShow)] {
        engine.friends.flatMap { f in
            (engine.nowWatchingAll[f.id] ?? []).map { (friend: f, show: $0) }
        }
    }

    /// 21a. The poster is the tile and the person is the caption — the right way
    /// round, since a poster is what the eye recognises instantly and a name is
    /// the small print. 104pt gives a title two full lines, which the old 50pt
    /// column never could: "Silo" fitted and nothing else did.
    private func nowCard(_ f: User, show: TVShow) -> some View {
        let saved = engine.savedShowIds.contains(show.tmdbId)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                poster(show)
                Text(initials(f.name))
                    .bingeLabel(9)
                    .foregroundStyle(BingeTheme.ground)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(BingeTheme.ink)
            }
            .frame(width: 104, height: 148)
            .clipped()
            .overlay(alignment: .topTrailing) {
                // Save without leaving the strip. Ink on the artwork so it reads
                // as a control on the poster, accent once saved — the one place
                // colour means "this is yours now".
                Button { Task { await engine.toggleSave(show) } } label: {
                    Image(systemName: saved ? "checkmark" : "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BingeTheme.ground)
                        .frame(width: 30, height: 30)
                        .background(saved ? BingeTheme.accent : BingeTheme.ink)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(saved ? "Saved. Remove \(show.title)" : "Save \(show.title)")
            }

            // Title and name are one caption block, so they sit close and the
            // gap that separates cards stays bigger than the gap inside one.
            VStack(alignment: .leading, spacing: 1) {
                Text(show.title)
                    .bingeBody(12)
                    .foregroundStyle(BingeTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 104, height: 32, alignment: .topLeading)

                Text(f.name.split(separator: " ").first.map(String.init) ?? f.name)
                    .bingeLabel(10)
                    .foregroundStyle(BingeTheme.inkMuted)
                    .lineLimit(1)
                    .frame(width: 104, alignment: .leading)
            }
        }
        .frame(width: 104, alignment: .leading)
    }

    /// One chip, three states — the row's action has to say what it already did,
    /// or you tap it twice and can't tell whether the first one worked. Note it
    /// sits INSIDE a NavigationLink, so it takes its own tap and doesn't push.
    @ViewBuilder
    private func saveChip(_ show: TVShow, filled: Bool = false) -> some View {
        let saved = engine.savedShowIds.contains(show.tmdbId)
        if engine.savingShowId == show.tmdbId {
            ProgressView().tint(BingeTheme.accent).frame(minHeight: 34)
        } else {
            BingeChip(title: saved ? "Saved" : "Save it",
                      filled: filled && !saved,
                      muted: saved) {
                Task { await engine.toggleSave(show) }
            }
        }
    }

    /// Posters are 2:3, so this slot matches them and nothing is cropped.
    @ViewBuilder
    private func poster(_ show: TVShow) -> some View {
        if let urlString = show.posterUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 104, height: 148)
                default:
                    Rectangle().fill(BingeTheme.hairline)
                }
            }
        } else {
            Rectangle().fill(BingeTheme.hairline)
        }
    }

    /// The strip alternates weight so a row of initials reads as people rather
    /// than a barcode. Accent appears once every four, never more.
    private func tileFill(_ index: Int) -> Color {
        switch index % 4 {
        case 1:  return BingeTheme.accent
        case 2:  return BingeTheme.inkMuted
        case 3:  return BingeTheme.inkFaint
        default: return BingeTheme.ink
        }
    }

    private func tileInk(_ index: Int) -> Color {
        index % 4 == 3 ? BingeTheme.ink : BingeTheme.ground
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2)
            .map { String($0.prefix(1)).uppercased() }.joined()
    }
}

// MARK: - People

struct BingePeopleTab: View {
    @ObservedObject var engine: UsersEngine

    var body: some View {
        VStack(spacing: 0) {
            if let error = engine.error {
                HStack {
                    Text(error).bingeBody(13).foregroundStyle(Color.white)
                    Spacer()
                    Button { engine.error = nil } label: {
                        Text("×").bingeHeadline(16).foregroundStyle(Color.white)
                    }
                }
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
                .background(Color.red.opacity(0.8))
                BingeRule()
            }
            
            if let success = engine.successMessage {
                HStack {
                    Text(success).bingeBody(13).foregroundStyle(BingeTheme.ground)
                    Spacer()
                }
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
                .background(BingeTheme.accent)
                BingeRule()
            }
            
            HStack(spacing: 10) {
                TextField("Search by name", text: $engine.searchText)
                    .bingeBody(14)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await engine.search() } }
                Button { Task { await engine.search() } } label: {
                    Text("Search").bingeLabel(11).foregroundStyle(BingeTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
            BingeRule(strong: true)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !engine.incomingRequests.isEmpty {
                        BingeSectionHeader(title: "Pending requests")
                        ForEach(engine.incomingRequests, id: \.friendship.id) { item in
                            BingeRule()
                            HStack {
                                HStack(spacing: 12) {
                                    Text((item.profile?.displayName ?? "Someone").split(separator: " ").prefix(2)
                                            .map { String($0.prefix(1)).uppercased() }.joined())
                                        .bingeHeadline(12)
                                        .frame(width: 36, height: 36)
                                        .background(BingeTheme.ink).foregroundStyle(BingeTheme.ground)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.profile?.displayName ?? "Someone").bingeHeadline(14)
                                        Text("wants to be friends").bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    if engine.acceptingFriendId == item.friendship.id {
                                        ProgressView()
                                            .tint(BingeTheme.accent)
                                            .frame(height: 34)
                                    } else {
                                        Button { Task { await engine.accept(item.friendship) } } label: {
                                            Text("Accept").bingeLabel(11)
                                                .foregroundStyle(Color.white)
                                                .padding(.horizontal, 12).padding(.vertical, 7)
                                                .frame(minHeight: 34)
                                                .background(BingeTheme.accent)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button { Task { await engine.reject(item.friendship) } } label: {
                                            Text("Decline").bingeLabel(11)
                                                .foregroundStyle(BingeTheme.ink)
                                                .padding(.horizontal, 12).padding(.vertical, 7)
                                                .frame(minHeight: 34)
                                                .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 6)
                        }
                    }
                    
                    if !engine.suggestions.isEmpty {
                        BingeSectionHeader(title: "Results")
                        ForEach(engine.suggestions) { p in
                            BingeRule()
                            personRow(name: p.displayName, detail: p.bio ?? "On Binge", userId: p.userId) {
                                Task { await engine.add(p) }
                            }
                        }
                    }

                    if !engine.friends.isEmpty {
                        BingeSectionHeader(title: "Your friends")
                        ForEach(engine.friends) { f in
                            BingeRule()
                            personRow(name: f.name, detail: f.email, userId: f.id, action: nil)
                        }
                    }

                    if engine.friends.isEmpty && engine.suggestions.isEmpty && engine.incomingRequests.isEmpty {
                        BingeArgumentBlock(
                            kicker: "Start here",
                            headline: "FIND THREE\nPEOPLE.",
                            message: "Three is the number where Tonight stops guessing and starts naming names.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func personRow(name: String, detail: String, userId: String, action: (() -> Void)? = nil) -> some View {
        HStack {
            HStack(spacing: 12) {
                Text(name.split(separator: " ").prefix(2)
                        .map { String($0.prefix(1)).uppercased() }.joined())
                    .bingeHeadline(12)
                    .frame(width: 36, height: 36)
                    .background(BingeTheme.ink).foregroundStyle(BingeTheme.ground)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).bingeHeadline(14)
                    Text(detail).bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let action {
                if engine.addingFriendId == userId {
                    ProgressView()
                        .tint(BingeTheme.accent)
                        .frame(height: 34)
                } else {
                    BingeChip(title: "Add", action: action)
                }
            }
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 6)
    }
}
