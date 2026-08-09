//  BingeFriendsView.swift
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
final class BingeFriendsEngine: ObservableObject {
    @Published var friends: [User] = []
    @Published var entries: [BingeFeedEntry] = []
    @Published var suggestions: [UserProfile] = []
    @Published var searchText = ""
    @Published var isLoading = false

    private let supabase = SupabaseService.shared

    /// Shows two or more friends are on — the highlighted row in the design.
    @Published var sharedShow: (show: TVShow, who: [User])?

    /// friend id → the title they most recently logged, for the people strip.
    @Published var nowWatching: [String: String] = [:]

    func load() async {
        guard let userId = supabase.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        friends = (try? await supabase.fetchFriends(userId: userId)) ?? []

        var built: [BingeFeedEntry] = []
        var byShow: [Int: (TVShow, [User])] = [:]

        for friend in friends {
            let rated = (try? await supabase.getFriendRatings(friendId: friend.id)) ?? []
            for row in rated.prefix(10) {
                guard let show = try? await supabase.fetchShowById(id: row.showId) else { continue }
                built.append(BingeFeedEntry(friend: friend, show: show,
                                            rating: row.rating, review: row.review,
                                            watchedDate: row.watchedDate))
                var entry = byShow[row.showId] ?? (show, [])
                entry.1.append(friend)
                byShow[row.showId] = entry
            }
        }

        entries = built.sorted { $0.watchedDate > $1.watchedDate }

        var latest: [String: String] = [:]
        for entry in entries where latest[entry.friend.id] == nil {
            latest[entry.friend.id] = entry.show.title
        }
        nowWatching = latest
        sharedShow = byShow.values.first(where: { $0.1.count >= 2 }).map { ($0.0, $0.1) }
    }

    func search() async {
        guard searchText.count >= 2 else { suggestions = []; return }
        suggestions = (try? await supabase.searchUsers(query: searchText)) ?? []
    }

    func add(_ profile: UserProfile) async {
        guard let userId = supabase.currentUser?.id else { return }
        try? await supabase.sendFriendRequest(userId: userId, friendId: profile.userId)
        suggestions.removeAll { $0.id == profile.id }
    }
}

// MARK: - Feed

struct BingeFriendsFeed: View {
    @StateObject private var engine = BingeFriendsEngine()
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
        .task { await engine.load() }
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
                if !engine.friends.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Watching right now").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(engine.friends.enumerated()), id: \.element.id) { index, f in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(initials(f.name))
                                            .bingeHeadline(12)
                                            .frame(width: 50, height: 50)
                                            .background(tileFill(index))
                                            .foregroundStyle(tileInk(index))
                                        Text(engine.nowWatching[f.id]
                                             ?? (f.name.split(separator: " ").first.map(String.init) ?? f.name))
                                            .bingeBody(10)
                                            .foregroundStyle(BingeTheme.inkMuted)
                                            .frame(width: 50, alignment: .leading)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
                    BingeRule(strong: true)
                }

                if let shared = engine.sharedShow {
                    BingeFeedRow(posterURL: shared.show.posterUrl,
                                 meta: "\(shared.who.count) friends · watching",
                                 headline: "Everyone's on \(shared.show.title)",
                                 quote: "Catch up and you're in the conversation.",
                                 highlighted: true,
                                 metaAccent: true) {
                        BingeChip(title: "Join them", filled: true)
                    }
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
                            BingeChip(title: "Save it")
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
    @StateObject private var engine = BingeFriendsEngine()

    var body: some View {
        VStack(spacing: 0) {
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
                    if !engine.suggestions.isEmpty {
                        BingeSectionHeader(title: "Results")
                        ForEach(engine.suggestions) { p in
                            BingeRule()
                            personRow(name: p.displayName, detail: p.bio ?? "On Binge") {
                                Task { await engine.add(p) }
                            }
                        }
                    }

                    if !engine.friends.isEmpty {
                        BingeSectionHeader(title: "Your friends")
                        ForEach(engine.friends) { f in
                            BingeRule()
                            personRow(name: f.name, detail: f.email, action: nil)
                        }
                    }

                    if engine.friends.isEmpty && engine.suggestions.isEmpty {
                        BingeArgumentBlock(
                            kicker: "Start here",
                            headline: "FIND THREE\nPEOPLE.",
                            message: "Three is the number where Tonight stops guessing and starts naming names.")
                    }
                }
            }
        }
        .task { await engine.load() }
    }

    @ViewBuilder
    private func personRow(name: String, detail: String, action: (() -> Void)?) -> some View {
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
            if let action { BingeChip(title: "Add", action: action) }
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 6)
    }
}
