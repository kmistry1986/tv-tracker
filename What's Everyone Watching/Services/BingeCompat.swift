//  BingeCompat.swift
//  Bridges the older unprefixed API (Theme, Rule, Poster, StatRow,
//  .displayTitle, .headline …) onto the namespaced types in BingeTheme.swift.
//
//  Views written against the old names keep compiling. New code should use the
//  Binge* names directly. Delete this file once nothing references the old API.

import SwiftUI

// MARK: - Tokens

typealias Theme = BingeTheme

extension BingeTheme {
    static let ruleStrong: CGFloat = 2
    static let ruleHair: CGFloat = 1
    static let minTapTarget: CGFloat = BingeTheme.minTap
}

// MARK: - Text roles

extension View {
    func displayTitle(_ size: CGFloat = 40) -> some View { bingeDisplay(size) }
    func headline(_ size: CGFloat = 17) -> some View { bingeHeadline(size) }
    func label(_ size: CGFloat = 11) -> some View { bingeLabel(size) }
    func bodyCopy(_ size: CGFloat = 13) -> some View { bingeBody(size) }
}

// MARK: - Rules

struct Rule: View {
    var strong = false
    var onDark = false
    var body: some View { BingeRule(strong: strong, onDark: onDark) }
}

struct VRule: View {
    var onDark = false
    var body: some View { BingeVRule(onDark: onDark) }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var onDark = false
    var action: () -> Void = {}
    var body: some View { BingePrimaryButton(title: title, onDark: onDark, action: action) }
}

struct OutlineButton: View {
    let title: String
    var onDark = false
    var action: () -> Void = {}
    var body: some View { BingeOutlineButton(title: title, onDark: onDark, action: action) }
}

struct ChipButton: View {
    let title: String
    var filled = false
    var muted = false
    var action: () -> Void = {}
    var body: some View { BingeChip(title: title, filled: filled, muted: muted, action: action) }
}

// MARK: - Controls

struct RuledSegmented: View {
    let options: [String]
    @Binding var selection: Int
    var body: some View { BingeSegmented(options: options, selection: $selection) }
}

// MARK: - Stats
// StatRow.Stat keeps working via the nested alias.

extension BingeStatRow { typealias Stat = BingeStat }
typealias StatRow = BingeStatRow

// MARK: - Poster
// Accepts either a URL or a poster-path String, since callers use both.

struct Poster: View {
    private let urlString: String?
    var width: CGFloat? = 74
    var height: CGFloat = 104
    var accessibilityTitle: String? = nil

    init(url: URL?, width: CGFloat? = 74, height: CGFloat = 104, accessibilityTitle: String? = nil) {
        self.urlString = url?.absoluteString
        self.width = width; self.height = height; self.accessibilityTitle = accessibilityTitle
    }
    init(urlString: String?, width: CGFloat? = 74, height: CGFloat = 104, accessibilityTitle: String? = nil) {
        self.urlString = urlString
        self.width = width; self.height = height; self.accessibilityTitle = accessibilityTitle
    }

    var body: some View {
        BingePoster(urlString: urlString, width: width, height: height,
                    accessibilityTitle: accessibilityTitle)
    }
}

struct ThinProgress: View {
    let fraction: Double
    var onDark = false
    var body: some View { BingeProgress(fraction: fraction, onDark: onDark) }
}

// MARK: - Rows

struct FeedRow: View {
    let posterURL: URL?
    let meta: String
    let headline: String
    var quote: String? = nil
    var highlighted = false
    var actions: AnyView? = nil

    var body: some View {
        BingeFeedRow(posterURL: posterURL?.absoluteString,
                     meta: meta, headline: headline,
                     quote: quote, highlighted: highlighted) {
            if let actions { actions }
        }
    }
}

struct TitleRow: View {
    let posterURL: URL?
    let title: String
    let subtitle: String
    var progress: Double? = nil
    var trailing: AnyView? = nil

    var body: some View {
        BingeTitleRow(posterURL: posterURL?.absoluteString,
                      title: title, subtitle: subtitle, progress: progress) {
            if let trailing { trailing }
        }
    }
}

// MARK: - Blocks

struct SourceBand: View {
    let kicker: String
    let statement: String
    var body: some View { BingeSourceBand(kicker: kicker, statement: statement) }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var onDark = false
    var body: some View { BingeSectionHeader(title: title, trailing: trailing, onDark: onDark) }
}

struct ArgumentBlock: View {
    let kicker: String
    let headline: String
    let message: String
    var onDark = false
    var body: some View {
        BingeArgumentBlock(kicker: kicker, headline: headline, message: message, onDark: onDark)
    }
}
