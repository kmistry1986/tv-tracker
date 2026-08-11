//  ImportManagementView.swift
//  The redesigned import sheet: start → preview → running → result → fill gaps → log.
//
//  Five things this fixes beyond the styling, all found in the previous version:
//  · `unmatchedEpisodes` was never persisted — there was a saveFailedImports()
//    with no counterpart, so the larger of the two logs died on every relaunch.
//    Both kinds are now one `ImportIssue` row in Supabase.
//  · The history screen stacked two `List`s in a VStack — two independently
//    scrolling lists in one sheet, the second unreachable on a short screen.
//    It's one list with two sections now.
//  · `processedCount += entries.count` appeared TWICE in a row in two places,
//    so progress ran past 100% and "23 / 12" was reachable. Counted once, and
//    counted in shows rather than rows, which is what the loop actually does.
//  · The outcome was a four-line emoji alert — the only place the numbers were
//    ever stated, and gone the moment you tapped OK. It's a screen.
//  · Prime Video took 50% of a segmented control to say "Coming Soon".
//
//  Gap filling: when an episode can't be named but sits in a hole bounded by
//  watched episodes, and the unplaced CSV rows for that season account for the
//  hole, it's offered as a batch proposal. See `proposeGapFills`.
//
//  REQUIRES: three new SupabaseService methods and one table — see the comment
//  at the foot of this file.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

/// One row in the import log. Both failure kinds live in one table because
/// they're one list on screen — and because keeping them apart is what let the
/// unmatched half go unpersisted for so long.
struct ImportIssue: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        /// TMDB has no show under that name. You can act on this.
        case notFound = "not_found"
        /// Show matched; the episode line didn't. Informational.
        case unplaced = "unplaced"
    }

    var id: Int?
    var kind: Kind
    /// For `.notFound` this is the title we searched. For `.unplaced` it's the
    /// raw CSV line, kept verbatim so you can see WHY it failed.
    var title: String
    var showName: String?
    var source: String
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case showName = "show_name"
        case source
        case createdAt = "created_at"
    }
}

/// A run of episodes we'd mark watched, with the evidence for it.
struct GapProposal: Identifiable {
    let id = UUID()
    let tmdbShowId: Int
    let showName: String
    let season: Int
    let episodes: [Int]
    let unplacedCount: Int
    /// The date to record — taken from the unplaced rows it accounts for.
    let watchedDate: String
    /// For gaps at season start: (season, episodeNumber) of last ep in previous season
    let prevSeasonBoundary: (Int, Int)?

    var range: String {
        guard let first = episodes.first, let last = episodes.last else { return "" }
        return first == last ? "E\(first)" : "E\(first)–E\(last)"
    }

    var evidence: String {
        guard let first = episodes.first, let last = episodes.last else { return "" }
        let rows = unplacedCount == 1 ? "1 unplaced row" : "\(unplacedCount) unplaced rows"

        if let (prevSeason, prevEp) = prevSeasonBoundary {
            return "S\(prevSeason)E\(prevEp) and S\(season)E\(last + 1) are watched · \(rows) for S\(season)E\(first)–E\(last)"
        }
        return "E\(first - 1) and E\(last + 1) are watched · \(rows) for S\(season)"
    }
}

/// A show as the importer actually processes it — one lookup per show, not per
/// CSV row. 862 rows is unreadable as checkboxes; 41 shows is a decision.
struct ImportShowGroup: Identifiable {
    let id = UUID()
    let showName: String
    let entries: [NetflixCSVParser.ParsedEntry]

    var isFilm: Bool { entries.allSatisfy { !$0.isShow } }

    var meta: String {
        if isFilm {
            return "Film · watched \(entries.first?.date ?? "")"
        }
        let seasons = Set(entries.compactMap(\.seasonNumber)).sorted()
        let count = entries.count
        let episodes = "\(count) episode\(count == 1 ? "" : "s")"
        guard let low = seasons.first, let high = seasons.last else {
            return "Series · \(episodes)"
        }
        let span = low == high ? "S\(low)" : "S\(low)–S\(high)"
        return "Series · \(episodes) · \(span)"
    }
}

// MARK: - View

struct ImportManagementView: View {
    /// Optional: lets a "not found" row hand the title to the Search tab. With
    /// no handler the title goes to the clipboard instead — useful, never broken.
    var onSearch: ((String) -> Void)? = nil
    var onComplete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var tmdb = TMDBService.shared

    private enum Phase { case start, preview, running, result, gaps, log }
    @State private var phase: Phase = .start

    @State private var showsPicker = false
    @State private var groups: [ImportShowGroup] = []
    @State private var selected = Set<UUID>()

    @State private var doneShows = 0
    @State private var currentShow = ""
    @State private var matched = 0
    @State private var unplaced = 0
    @State private var notFound = 0
    @State private var filmsAdded = 0
    @State private var showsTouched = 0
    @State private var stopRequested = false

    @State private var proposals: [GapProposal] = []
    @State private var acceptedProposals = Set<UUID>()
    @State private var issues: [ImportIssue] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                BingeRule(strong: true)

                switch phase {
                case .start:   start
                case .preview: preview
                case .running: running
                case .result:  result
                case .gaps:    gaps
                case .log:     log
                }
            }
            .background(BingeTheme.ground)
            .foregroundStyle(BingeTheme.ink)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(isPresented: $showsPicker,
                      allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                      onCompletion: handleFile)
        .alert("Couldn't read that", isPresented: .constant(error != nil), presenting: error) { _ in
            Button("OK") { error = nil }
        } message: { Text($0) }
        .task { await loadIssues() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(headerTitle).bingeDisplay(30)
            Spacer(minLength: 12)
            if phase == .log && !issues.isEmpty {
                Button { Task { await clearIssues() } } label: {
                    Text("Clear").bingeLabel(13).foregroundStyle(BingeTheme.inkMuted)
                }
                .buttonStyle(.plain)
            } else if phase != .running {
                Button { dismiss() } label: {
                    Text("Close").bingeLabel(13).foregroundStyle(BingeTheme.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, BingeTheme.gutter)
        .padding(.top, 18).padding(.bottom, 14)
    }

    private var headerTitle: String {
        switch phase {
        case .running: return "Importing"
        case .result:  return "Imported"
        case .gaps:    return "Fill the gaps?"
        case .log:     return "Import log"
        default:       return "Import"
        }
    }

    // MARK: Start

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Netflix").bingeLabel(13).foregroundStyle(BingeTheme.accent)
                    Text("Bring everything you've already watched.")
                        .bingeHeadline(19)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Netflix gives you a CSV of your viewing activity. Hand it over and we'll match it against every show and episode.")
                        .bingeBody(14).foregroundStyle(BingeTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 20)

                primaryButton("Choose CSV file") { showsPicker = true }
                    .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 20)

                #if DEBUG
                Button { loadTestData() } label: {
                    Text("Load test data").bingeLabel(13).foregroundStyle(BingeTheme.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap, alignment: .leading)
                        .padding(.horizontal, 18)
                        .overlay(Rectangle().stroke(BingeTheme.hairline, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 20)
                #endif

                BingeRule()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Where to get it").bingeLabel(13)
                        .foregroundStyle(BingeTheme.inkMuted)
                        .padding(.bottom, 12)
                    step(1, "Open netflix.com/viewingactivity")
                    step(2, "Download all — it arrives as a CSV")
                    step(3, "Come back here and pick the file")
                    BingeRule()
                }
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 18)

                BingeRule()

                Button { phase = .log } label: {
                    HStack {
                        Text("Past imports").bingeBody(14)
                        Spacer()
                        if !issues.isEmpty {
                            Text("\(issues.count)").bingeLabel(13)
                                .foregroundStyle(BingeTheme.ground)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(BingeTheme.ink)
                        }
                        Text("View").bingeLabel(13).foregroundStyle(BingeTheme.accent)
                    }
                    .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                BingeRule()
                // One honest line. It used to be half a segmented control
                // advertising an absence every time the sheet opened.
                Text("Prime Video history upload support coming soon")
                    .bingeBody(13).foregroundStyle(BingeTheme.inkFaint)
                    .padding(.horizontal, BingeTheme.gutter)
                    .padding(.top, 15).padding(.bottom, 24)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").bingeLabel(13).foregroundStyle(BingeTheme.accent).frame(width: 16, alignment: .leading)
            Text(text).bingeBody(14).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { BingeRule() }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(groups.reduce(0) { $0 + $1.entries.count }) rows · \(groups.count) shows")
                    .bingeBody(14)
                Spacer()
                Button { selected = [] } label: {
                    Text("None").bingeLabel(13).foregroundStyle(BingeTheme.inkMuted)
                }
                .buttonStyle(.plain)
                Button { selected = Set(groups.map(\.id)) } label: {
                    Text("All").bingeLabel(13).foregroundStyle(BingeTheme.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
            BingeRule(strong: true)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        Button {
                            if selected.contains(group.id) { selected.remove(group.id) }
                            else { selected.insert(group.id) }
                        } label: {
                            HStack(spacing: 13) {
                                checkbox(selected.contains(group.id))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.showName).bingeHeadline(16).lineLimit(1)
                                        .foregroundStyle(selected.contains(group.id) ? BingeTheme.ink : BingeTheme.inkMuted)
                                    Text(group.meta).bingeLabel(13).foregroundStyle(BingeTheme.inkMuted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 15)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        BingeRule()
                    }
                }
            }

            BingeRule(strong: true)
            primaryButton(selected.count == 1 ? "Import 1 show" : "Import \(selected.count) shows") {
                Task { await runImport() }
            }
            .opacity(selected.isEmpty ? 0.45 : 1)
            .allowsHitTesting(!selected.isEmpty)
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 16).padding(.bottom, 22)
        }
    }

    private func checkbox(_ on: Bool) -> some View {
        Group {
            if on {
                Text("✓").bingeLabel(13).foregroundStyle(BingeTheme.ground)
                    .frame(width: 20, height: 20).background(BingeTheme.ink)
            } else {
                Rectangle().fill(Color.clear).frame(width: 20, height: 20)
                    .overlay(Rectangle().stroke(BingeTheme.hairline, lineWidth: 1))
            }
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(doneShows)").bingeDisplay(52)
                    Text("of \(selected.count) shows").bingeHeadline(19)
                        .foregroundStyle(BingeTheme.inkMuted)
                }
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(BingeTheme.accent)
                            .frame(width: max(0, geo.size.width * progress))
                        Rectangle().fill(BingeTheme.hairline)
                    }
                }
                .frame(height: 8)
                .padding(.top, 18)

                if !currentShow.isEmpty {
                    Text("Matching episodes for \(currentShow)")
                        .bingeBody(14).foregroundStyle(BingeTheme.inkMuted)
                        .lineLimit(1)
                        .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 24)

            BingeRule()
            HStack(spacing: 0) {
                tally("\(matched)", "Matched")
                BingeVRule()
                tally("\(unplaced)", "Skipped")
                BingeVRule()
                tally("\(notFound)", "Not found", accent: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            BingeRule()

            Spacer(minLength: 0)

            // 800 rows is minutes of work and hundreds of calls. It used to be
            // uninterruptible, and closing the sheet orphaned the task.
            Button { stopRequested = true } label: {
                Text(stopRequested ? "Stopping…" : "Stop after this show")
                    .bingeLabel(14)
                    .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap, alignment: .leading)
                    .padding(.horizontal, 18)
                    .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(stopRequested)
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 16).padding(.bottom, 22)
        }
    }

    private var progress: Double {
        guard !selected.isEmpty else { return 0 }
        return min(1, Double(doneShows) / Double(selected.count))
    }

    private func tally(_ value: String, _ label: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).bingeHeadline(26).foregroundStyle(accent ? BingeTheme.accent : BingeTheme.ink)
            Text(label).bingeLabel(13).foregroundStyle(BingeTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 16)
    }

    // MARK: Result

    private var result: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Import complete").bingeLabel(13).foregroundStyle(BingeTheme.accentTint)
                Text(resultHeadline)
                    .bingeDisplay(34)
                    .foregroundStyle(BingeTheme.ground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text("Across \(showsTouched) show\(showsTouched == 1 ? "" : "s"). Your library just got real.")
                    .bingeBody(14).foregroundStyle(BingeTheme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 22).padding(.bottom, 18)
            .background(BingeTheme.ink)

            if notFound > 0 || unplaced > 0 {
                Text("What didn't land").bingeLabel(13)
                    .foregroundStyle(BingeTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BingeTheme.gutter)
                    .padding(.top, 18).padding(.bottom, 6)

                if notFound > 0 {
                    didntLand("\(notFound)", "Shows we couldn't find",
                              "Not in TMDB under that name. You can search for these by hand.",
                              accent: true)
                }
                if unplaced > 0 {
                    let gapFillableCount = proposals.reduce(0) { $0 + $1.episodes.count }
                    let unplacedNotInGaps = unplaced - gapFillableCount
                    if unplacedNotInGaps > 0 {
                        didntLand("\(unplacedNotInGaps)", "Episodes we couldn't place",
                                  "Show matched, but Netflix's episode name didn't. The show is in your library.")
                    }
                }
            }

            Spacer(minLength: 0)
            BingeRule(strong: true)

            VStack(alignment: .leading, spacing: 10) {
                if !proposals.isEmpty {
                    primaryButton("Fill \(proposals.count) gap\(proposals.count == 1 ? "" : "s")") {
                        phase = .gaps
                    }
                } else if notFound > 0 || unplaced > 0 {
                    primaryButton("See the \(notFound + unplaced) issues") { phase = .log }
                }
                Button {
                    onComplete?()
                    dismiss()
                } label: {
                    Text("Done").bingeLabel(14).foregroundStyle(BingeTheme.inkMuted)
                        .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 16).padding(.bottom, 22)
        }
    }

    private var resultHeadline: String {
        var parts: [String] = []
        if matched > 0 { parts.append("\(matched) episode\(matched == 1 ? "" : "s")") }
        if filmsAdded > 0 { parts.append("\(filmsAdded) film\(filmsAdded == 1 ? "" : "s")") }
        if parts.isEmpty { return "Nothing new." }
        return parts.joined(separator: "\nand ") + "."
    }

    private func didntLand(_ count: String, _ title: String, _ body: String, accent: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(count).bingeHeadline(24)
                .foregroundStyle(accent ? BingeTheme.accent : BingeTheme.ink)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).bingeHeadline(15)
                Text(body).bingeBody(13).foregroundStyle(BingeTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
        .overlay(alignment: .top) { BingeRule() }
    }

    // MARK: Gaps

    private var gaps: some View {
        VStack(spacing: 0) {
            Text("\(proposals.reduce(0) { $0 + $1.episodes.count }) episodes we couldn't name sit between episodes you've watched. They're almost certainly the rows Netflix wrote differently.")
                .bingeBody(14).foregroundStyle(BingeTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
            BingeRule()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(proposals) { p in
                        Button {
                            if acceptedProposals.contains(p.id) { acceptedProposals.remove(p.id) }
                            else { acceptedProposals.insert(p.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 13) {
                                checkbox(acceptedProposals.contains(p.id)).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.showName).bingeHeadline(16).lineLimit(1)
                                    Text("Mark S\(p.season) \(p.range) watched").bingeBody(15)
                                    Text(p.evidence).bingeBody(13).foregroundStyle(BingeTheme.inkFaint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(acceptedProposals.contains(p.id) ? BingeTheme.ink : BingeTheme.inkMuted)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 15)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        BingeRule()
                    }
                }
            }

            BingeRule(strong: true)
            VStack(alignment: .leading, spacing: 10) {
                primaryButton("Mark \(acceptedEpisodeCount) episode\(acceptedEpisodeCount == 1 ? "" : "s")") {
                    Task { await applyGapFills() }
                }
                .opacity(acceptedProposals.isEmpty ? 0.45 : 1)
                .allowsHitTesting(!acceptedProposals.isEmpty)
                Button { phase = .log } label: {
                    Text("Skip all").bingeLabel(14).foregroundStyle(BingeTheme.inkMuted)
                        .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 16).padding(.bottom, 22)
        }
    }

    private var acceptedEpisodeCount: Int {
        proposals.filter { acceptedProposals.contains($0.id) }.reduce(0) { $0 + $1.episodes.count }
    }

    // MARK: Log

    private var log: some View {
        Group {
            if issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing logged").bingeLabel(13).foregroundStyle(BingeTheme.inkMuted)
                    Text("Every title from your last import found a home.")
                        .bingeBody(14).foregroundStyle(BingeTheme.inkMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 18)
            } else {
                // ONE list, two sections — actionable first. Two Lists in a
                // VStack was the old bug: the second was unreachable.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let missing = issues.filter { $0.kind == .notFound }
                        let unplacedRows = issues.filter { $0.kind == .unplaced }

                        if !missing.isEmpty {
                            sectionHead("Not found · \(missing.count)", accent: true, hint: "Tap to search")
                            ForEach(missing) { issue in
                                Button { search(issue.title) } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(issue.title).bingeHeadline(16).lineLimit(1)
                                            Text(sourceLine(issue)).bingeLabel(13)
                                                .foregroundStyle(BingeTheme.inkMuted)
                                        }
                                        Spacer(minLength: 0)
                                        Text("↗").bingeHeadline(16).foregroundStyle(BingeTheme.accent)
                                    }
                                    .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 15)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                BingeRule()
                            }
                        }

                        if !unplacedRows.isEmpty {
                            sectionHead("Couldn't place · \(unplacedRows.count)")
                            ForEach(unplacedRows) { issue in
                                VStack(alignment: .leading, spacing: 5) {
                                    if let show = issue.showName {
                                        Text(show).bingeLabel(13).foregroundStyle(BingeTheme.inkMuted)
                                    }
                                    // The raw CSV line, so you can see WHY.
                                    Text(issue.title).bingeBody(15)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("No episode by that name").bingeBody(13)
                                        .foregroundStyle(BingeTheme.inkFaint)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 15)
                                BingeRule()
                            }
                        }
                    }
                    .padding(.bottom, 22)
                }
            }
        }
    }

    private func sectionHead(_ title: String, accent: Bool = false, hint: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text(title).bingeLabel(13)
                .foregroundStyle(accent ? BingeTheme.accent : BingeTheme.inkMuted)
            Rectangle().fill(BingeTheme.hairline).frame(height: 1)
            if let hint {
                Text(hint).bingeBody(13).foregroundStyle(BingeTheme.inkMuted)
            }
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 13)
        .background(BingeTheme.ink.opacity(0.045))
        .overlay(alignment: .top) { BingeRule(strong: true) }
    }

    private func sourceLine(_ issue: ImportIssue) -> String {
        issue.source.capitalized
    }

    private func search(_ title: String) {
        if let onSearch {
            dismiss()
            onSearch(title)
        } else {
            UIPasteboard.general.string = title
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).bingeLabel(14)
                Spacer()
                Text("→").bingeHeadline(16)
            }
            .foregroundStyle(BingeTheme.ground)
            .padding(.horizontal, 18).padding(.vertical, 17)
            .frame(maxWidth: .infinity)
            .background(BingeTheme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: File

    private func handleFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                error = "Unable to access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let entries = try NetflixCSVParser.shared.parseCSV(content: content)
                guard !entries.isEmpty else {
                    error = "No valid entries found. Make sure it's the Netflix viewing-activity CSV."
                    return
                }
                group(entries)
            } catch {
                self.error = "Couldn't parse that CSV: \(error.localizedDescription)"
            }
        case .failure(let err):
            error = "Couldn't read that file: \(err.localizedDescription)"
        }
    }

    private func group(_ entries: [NetflixCSVParser.ParsedEntry]) {
        var byShow: [String: [NetflixCSVParser.ParsedEntry]] = [:]
        for entry in entries { byShow[entry.showName, default: []].append(entry) }
        groups = byShow
            .map { ImportShowGroup(showName: $0.key, entries: $0.value) }
            .sorted { $0.entries.count > $1.entries.count }
        selected = Set(groups.map(\.id))
        phase = .preview
    }

    private func loadTestData() {
        let csv = """
        Title,Date Watched
        Dynasty: Season 4: Equal Justice for the Rich,8/4/26
        Ozark: Season 4: A Hard Way to Go,4/25/26
        Breaking Bad: Season 1: Pilot,2024-01-15
        Hit & Run: Part & Parcel,8/4/26
        """
        do {
            group(try NetflixCSVParser.shared.parseCSV(content: csv))
        } catch {
            self.error = "Couldn't parse the test data: \(error.localizedDescription)"
        }
    }

    // MARK: Import

    private func runImport() async {
        guard let userId = supabase.currentUser?.id else {
            error = "You're not signed in."
            return
        }
        phase = .running
        doneShows = 0; matched = 0; unplaced = 0; notFound = 0
        filmsAdded = 0; showsTouched = 0; stopRequested = false
        proposals = []; acceptedProposals = []

        var newIssues: [ImportIssue] = []
        let chosen = groups.filter { selected.contains($0.id) }

        for group in chosen {
            if stopRequested { break }
            currentShow = group.showName
            let entry = group.entries[0]

            do {
                var results = try await tmdb.searchTV(query: group.showName)
                if results.isEmpty, let first = group.showName.split(separator: " ").first {
                    results = try await tmdb.searchTV(query: String(first))
                }
                if results.isEmpty {
                    results = try await fuzzySearchTV(showName: group.showName,
                                                      episodeTitle: extractEpisodeTitle(from: entry.title))
                }

                var chosenResult = results.first
                if results.count > 1, let episodeTitle = extractEpisodeTitle(from: entry.title) {
                    chosenResult = await findShowByEpisodeName(shows: results,
                                                               episodeTitle: episodeTitle,
                                                               seasonNumber: entry.seasonNumber) ?? results.first
                }

                if let show = chosenResult {
                    let issues = try await importShow(show, group: group, userId: userId)
                    newIssues.append(contentsOf: issues)
                    showsTouched += 1
                } else if !entry.isShow {
                    if try await importFilm(group: group, userId: userId) {
                        filmsAdded += 1
                    } else {
                        newIssues.append(notFoundIssue(group.showName))
                        notFound += 1
                    }
                } else {
                    newIssues.append(notFoundIssue(group.showName))
                    notFound += 1
                }
            } catch {
                newIssues.append(notFoundIssue(group.showName))
                notFound += 1
            }

            // Counted ONCE, and in shows — the old code incremented twice in a
            // row here, so the bar overshot.
            doneShows += 1
        }

        currentShow = ""
        if !newIssues.isEmpty {
            do {
                try await supabase.insertImportIssues(userId: userId, issues: newIssues)
            } catch {
                print("❌ Failed to save import issues: \(error)")
            }
        }
        await loadIssues()
        phase = .result
    }

    /// Returns the issues this show produced, and accumulates a gap proposal if
    /// the unplaced rows account for a bounded hole.
    private func importShow(_ show: TVSearchResult,
                            group: ImportShowGroup,
                            userId: String) async throws -> [ImportIssue] {
        let detail = try await tmdb.getTVShow(id: show.id)

        let existing = (try? await supabase.fetchUserShows(userId: userId)) ?? []
        if !existing.contains(where: { $0.showId == show.id }) {
            try await supabase.insertUserShow(userId: userId,
                                              showId: show.id,
                                              watchedDate: group.entries[0].date)
        }

        let tvShow = TVShow(id: detail.id, tmdbId: detail.id, title: detail.name,
                            overview: detail.overview, posterUrl: detail.imageUrl,
                            firstAirDate: detail.firstAirDate,
                            numberOfSeasons: detail.numberOfSeasons,
                            numberOfEpisodes: detail.numberOfEpisodes,
                            platforms: nil, runtime: nil)
        try? await supabase.insertShow(show: tvShow)

        guard detail.numberOfSeasons > 0 else { return [] }

        var matchedTitles = Set<String>()
        /// season → episode numbers we marked watched, for gap detection.
        var watchedBySeason: [Int: Set<Int>] = [:]

        var tasks: [Task<SeasonDetail, Error>] = []
        for season in 1...detail.numberOfSeasons {
            tasks.append(Task { try await self.tmdb.getTVSeason(showId: show.id, seasonNumber: season) })
        }

        for task in tasks {
            guard let seasonDetail = try? await task.value else { continue }
            for episodeDetail in seasonDetail.episodes {
                for csvEntry in group.entries {
                    var isWatched = false

                    if let season = csvEntry.seasonNumber, let number = csvEntry.episodeNumber {
                        isWatched = (season == episodeDetail.seasonNumber && number == episodeDetail.episodeNumber)
                    }
                    if !isWatched, let episodeTitle = extractEpisodeTitle(from: csvEntry.title) {
                        let seasonMatches = csvEntry.seasonNumber == nil
                            || csvEntry.seasonNumber == episodeDetail.seasonNumber
                        if seasonMatches {
                            let a = normalizeEpisodeTitle(episodeDetail.name)
                            let b = normalizeEpisodeTitle(episodeTitle)
                            isWatched = a.contains(b) || b.contains(a)
                        }
                    }
                    guard isWatched else { continue }

                    matchedTitles.insert(csvEntry.title)
                    watchedBySeason[episodeDetail.seasonNumber, default: []].insert(episodeDetail.episodeNumber)

                    let episode = Episode(id: nil, showId: show.id, tmdbId: episodeDetail.id,
                                          seasonNumber: episodeDetail.seasonNumber,
                                          episodeNumber: episodeDetail.episodeNumber,
                                          name: episodeDetail.name,
                                          overview: episodeDetail.overview ?? "",
                                          airDate: episodeDetail.airDate,
                                          userId: userId, watched: true,
                                          watchedAt: csvEntry.date, showTitle: detail.name)
                    if (try? await supabase.insertEpisode(episode: episode)) != nil {
                        matched += 1
                    }
                }
            }
        }

        let leftovers = group.entries.filter { !matchedTitles.contains($0.title) }

        let newProposals = proposeGapFills(showId: show.id,
                                          showName: group.showName,
                                          watchedBySeason: watchedBySeason,
                                          leftovers: leftovers)
        proposals.append(contentsOf: newProposals)

        let gapFillableTitles = Set(newProposals.flatMap { proposal in
            leftovers.filter { entry in
                let seasonMatches = entry.seasonNumber == nil || entry.seasonNumber == proposal.season
                let episodeMatches = entry.episodeNumber == nil || proposal.episodes.contains(entry.episodeNumber ?? 0)
                return seasonMatches && episodeMatches
            }.map { $0.title }
        })

        let unloggedLeftovers = leftovers.filter { !gapFillableTitles.contains($0.title) }
        unplaced += unloggedLeftovers.count

        return unloggedLeftovers.map {
            ImportIssue(id: nil, kind: .unplaced, title: $0.title,
                        showName: group.showName, source: "netflix", createdAt: nil)
        }
    }

    private func importFilm(group: ImportShowGroup, userId: String) async throws -> Bool {
        var results = try await tmdb.searchMovie(query: group.showName)
        if results.isEmpty, let first = group.showName.split(separator: " ").first {
            results = try await tmdb.searchMovie(query: String(first))
        }
        if results.isEmpty {
            results = try await fuzzySearchMovie(movieName: group.showName)
        }
        guard let found = results.first else { return false }

        let movie = Movie(id: found.id, tmdbId: found.id, title: found.title,
                          overview: found.overview ?? "", posterUrl: found.imageUrl,
                          releaseDate: found.releaseDate, runtime: nil, platforms: nil)
        try? await supabase.insertMovie(movie: movie)

        let existing = (try? await supabase.fetchUserMovies(userId: userId)) ?? []
        if !existing.contains(where: { $0.movieId == found.id }) {
            try await supabase.insertUserMovie(userId: userId, movieId: found.id,
                                               watchedDate: group.entries[0].date)
        }
        return true
    }

    private func notFoundIssue(_ title: String) -> ImportIssue {
        ImportIssue(id: nil, kind: .notFound, title: title,
                    showName: nil, source: "netflix", createdAt: nil)
    }

    // MARK: Gap filling

    /// The rule, all five conditions required:
    /// · the hole is inside ONE season — never across a boundary, where a real
    ///   break is ordinary;
    /// · it's bounded on both sides by watched episodes — a trailing hole is
    ///   just where you stopped;
    /// · it's `maxGap` episodes or fewer;
    /// · the unplaced CSV rows for that season ACCOUNT for it. This is the
    ///   load-bearing condition: no unplaced rows means you genuinely skipped
    ///   the episode, and a gap on its own is not evidence of anything;
    /// · nothing is applied silently — this only ever builds a proposal.
    private static let maxGap = 3

    private func proposeGapFills(showId: Int,
                                 showName: String,
                                 watchedBySeason: [Int: Set<Int>],
                                 leftovers: [NetflixCSVParser.ParsedEntry]) -> [GapProposal] {
        var out: [GapProposal] = []

        for (season, watched) in watchedBySeason {
            guard !watched.isEmpty else { continue }
            let sorted = watched.sorted()

            // Rows Netflix gave us for this season that we couldn't place. A row
            // with no season stated could belong anywhere, so it counts too.
            let seasonLeftovers = leftovers.filter { $0.seasonNumber == season || $0.seasonNumber == nil }
            guard !seasonLeftovers.isEmpty else { continue }
            var budget = seasonLeftovers.count
            let date = seasonLeftovers[0].date

            // Gap at the beginning: if S5E3 is first watched, propose E1-E2
            if let firstWatched = sorted.first, firstWatched > 1 {
                let gap = firstWatched - 1
                if gap > 0, gap <= Self.maxGap, gap <= budget {
                    budget -= gap
                    // Reference last ep of previous season if available
                    let prevBoundary: (Int, Int)? = {
                        if season > 1, let prevWatched = watchedBySeason[season - 1]?.sorted().last {
                            return (season - 1, prevWatched)
                        }
                        return nil
                    }()
                    out.append(GapProposal(tmdbShowId: showId,
                                           showName: showName,
                                           season: season,
                                           episodes: Array(1...(firstWatched - 1)),
                                           unplacedCount: gap,
                                           watchedDate: date,
                                           prevSeasonBoundary: prevBoundary))
                }
            }

            // Gaps between consecutive watched episodes
            for (index, low) in sorted.enumerated() where index + 1 < sorted.count {
                let high = sorted[index + 1]
                let gap = high - low - 1
                guard gap > 0, gap <= Self.maxGap, gap <= budget else { continue }
                budget -= gap
                out.append(GapProposal(tmdbShowId: showId,
                                       showName: showName,
                                       season: season,
                                       episodes: Array((low + 1)...(high - 1)),
                                       unplacedCount: gap,
                                       watchedDate: date,
                                       prevSeasonBoundary: nil))
            }
        }

        return out.sorted { ($0.season, $0.episodes.first ?? 0) < ($1.season, $1.episodes.first ?? 0) }
    }

    private func applyGapFills() async {
        guard let userId = supabase.currentUser?.id else { return }
        let accepted = proposals.filter { acceptedProposals.contains($0.id) }

        for proposal in accepted {
            guard let seasonDetail = try? await tmdb.getTVSeason(showId: proposal.tmdbShowId,
                                                                 seasonNumber: proposal.season)
            else { continue }
            for episodeDetail in seasonDetail.episodes where proposal.episodes.contains(episodeDetail.episodeNumber) {
                let episode = Episode(id: nil, showId: proposal.tmdbShowId, tmdbId: episodeDetail.id,
                                      seasonNumber: episodeDetail.seasonNumber,
                                      episodeNumber: episodeDetail.episodeNumber,
                                      name: episodeDetail.name,
                                      overview: episodeDetail.overview ?? "",
                                      airDate: episodeDetail.airDate,
                                      userId: userId, watched: true,
                                      watchedAt: proposal.watchedDate,
                                      showTitle: proposal.showName)
                try? await supabase.insertEpisode(episode: episode)
                matched += 1
            }
        }
        phase = .log
    }

    // MARK: Log storage

    private func loadIssues() async {
        guard let userId = supabase.currentUser?.id else { return }
        issues = (try? await supabase.fetchImportIssues(userId: userId)) ?? []
    }

    private func clearIssues() async {
        guard let userId = supabase.currentUser?.id else { return }
        try? await supabase.clearImportIssues(userId: userId)
        issues = []
    }

    // MARK: Matching helpers (unchanged)

    private func fuzzySearchTV(showName: String, episodeTitle: String?) async throws -> [TVSearchResult] {
        if let episodeTitle, !episodeTitle.isEmpty {
            let results = try await tmdb.searchTV(query: "\(showName) \(episodeTitle)")
            if !results.isEmpty { return results }
        }
        let cleaned = showName.lowercased()
            .replacingOccurrences(of: #"[&-:,!?]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !cleaned.isEmpty && cleaned != showName.lowercased() {
            let results = try await tmdb.searchTV(query: cleaned)
            if !results.isEmpty { return results }
        }
        let noNumbers = cleaned
            .replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !noNumbers.isEmpty && noNumbers != cleaned {
            return try await tmdb.searchTV(query: noNumbers)
        }
        return []
    }

    private func fuzzySearchMovie(movieName: String) async throws -> [MovieSearchResult] {
        let cleaned = movieName.lowercased()
            .replacingOccurrences(of: #"[&-:,!?]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !cleaned.isEmpty && cleaned != movieName.lowercased() {
            let results = try await tmdb.searchMovie(query: cleaned)
            if !results.isEmpty { return results }
        }
        let noNumbers = cleaned
            .replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !noNumbers.isEmpty && noNumbers != cleaned {
            return try await tmdb.searchMovie(query: noNumbers)
        }
        return []
    }

    private func findShowByEpisodeName(shows: [TVSearchResult],
                                       episodeTitle: String,
                                       seasonNumber: Int?) async -> TVSearchResult? {
        for show in shows {
            guard let detail = try? await tmdb.getTVShow(id: show.id) else { continue }
            let seasons = seasonNumber.map { [$0] } ?? Array(1...min(max(detail.numberOfSeasons, 1), 5))
            for season in seasons where season <= detail.numberOfSeasons {
                guard let seasonDetail = try? await tmdb.getTVSeason(showId: show.id, seasonNumber: season)
                else { continue }
                for episode in seasonDetail.episodes {
                    let a = normalizeEpisodeTitle(episode.name)
                    let b = normalizeEpisodeTitle(episodeTitle)
                    if a.contains(b) || b.contains(a) { return show }
                }
            }
        }
        return nil
    }

    private func normalizeEpisodeTitle(_ title: String) -> String {
        var result = title.lowercased()
        // Normalize hyphens to spaces for compound numbers
        result = result.replacingOccurrences(of: "-", with: " ")

        let numberWords = [
            "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
            "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
            "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
            "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
            "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
            "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
            "eighty": "80", "ninety": "90"
        ]

        // Replace compound numbers: "twenty five" → "25", "thirty two" → "32", etc.
        let tens = ["twenty": "2", "thirty": "3", "forty": "4", "fifty": "5",
                    "sixty": "6", "seventy": "7", "eighty": "8", "ninety": "9"]
        let ones = ["one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
                    "six": "6", "seven": "7", "eight": "8", "nine": "9"]

        for (tenWord, tenDigit) in tens {
            for (oneWord, oneDigit) in ones {
                result = result.replacingOccurrences(of: "\(tenWord) \(oneWord)", with: "\(tenDigit)\(oneDigit)")
            }
        }

        // Replace standalone written numbers
        for (written, digit) in numberWords {
            result = result.replacingOccurrences(of: written, with: digit)
        }

        return result
    }

    private func extractEpisodeTitle(from title: String) -> String? {
        let parts = title.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return String(parts.last ?? "").trimmingCharacters(in: .whitespaces)
    }
}

//  ─────────────────────────────────────────────────────────────────────────
//  BACKEND — one table and three methods.
//
//  create table import_issues (
//    id         bigint generated by default as identity primary key,
//    user_id    uuid not null references auth.users(id) on delete cascade,
//    kind       text not null check (kind in ('not_found','unplaced')),
//    title      text not null,
//    show_name  text,
//    source     text not null default 'netflix',
//    created_at timestamptz not null default now()
//  );
//  alter table import_issues enable row level security;
//  create policy "own rows" on import_issues for all
//    using (auth.uid() = user_id) with check (auth.uid() = user_id);
//  create index import_issues_user_idx on import_issues (user_id, created_at desc);
//
//  Then, in SupabaseService — the same insert/fetch/delete shapes the file
//  already uses everywhere else:
//
//    func insertImportIssues(userId: String, issues: [ImportIssue]) async throws
//      → POST /rest/v1/import_issues with the array, user_id stamped on each.
//        One request, not one per row: an import can produce hundreds.
//
//    func fetchImportIssues(userId: String) async throws -> [ImportIssue]
//      → GET /rest/v1/import_issues?user_id=eq.\(userId)&order=created_at.desc
//
//    func clearImportIssues(userId: String) async throws
//      → deleteRequest(endpoint: ".../import_issues?user_id=eq.\(userId)")
//  ─────────────────────────────────────────────────────────────────────────

#Preview {
    ImportManagementView()
}
