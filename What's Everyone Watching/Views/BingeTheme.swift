//  BingeTheme.swift
//  Design tokens + core components for the Binge design (Modernist).
//  Drop into your Xcode project. iOS 16+.
//
//  FONTS: the design uses Archivo (Google Fonts, OFL).
//  1. Download Archivo, add the .ttf files to your target.
//  2. Info.plist → "Fonts provided by application" (UIAppFonts) → one entry per file.
//  3. If you'd rather not bundle a font, swap Theme.font(...) to use
//     .system(size:weight:design: .default) — but set .kerning() as below,
//     the tight tracking is doing most of the work.

import SwiftUI

// MARK: - Tokens

enum Theme {

    // Color — four values. Do not add a fifth without a reason.
    static let ground   = Color(hex: 0xF3F2F2)   // paper
    static let ink      = Color(hex: 0x201E1D)   // text, rules, dark screens
    static let accent   = Color(hex: 0xEC3013)   // the ONE action per screen
    static let surface  = Color(hex: 0xEAE9E9)   // tinted row / highlighted card

    // Derived greys (all sampled from the ink ramp — don't invent new ones)
    static let inkMuted    = Color(hex: 0x605D5D)  // secondary text on ground
    static let inkFaint    = Color(hex: 0xBAB6B6)  // poster placeholder, disabled
    static let hairline    = Color(hex: 0xD7D3D3)  // 1px row divider
    static let onDarkMuted = Color(hex: 0x8B8787)  // secondary text on ink
    static let onDarkRule  = Color(hex: 0x3D3A39)  // divider on ink
    static let accentTint  = Color(hex: 0xFF9783)  // accent on dark ground (contrast-safe)

    // Radius — zero, everywhere. This is not negotiable in Modernist.
    static let radius: CGFloat = 0

    // Rules
    static let ruleStrong: CGFloat = 2   // section + frame edges
    static let ruleHair: CGFloat = 1     // between rows

    // Spacing — 4pt base
    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        static let lg: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 28
    }
    static let gutter: CGFloat = 20      // screen horizontal inset

    // Type. Archivo only, five roles.
    static func display(_ size: CGFloat) -> Font { .custom("Archivo-Black", size: size) }
    static func heavy(_ size: CGFloat)   -> Font { .custom("Archivo-ExtraBold", size: size) }
    static func semi(_ size: CGFloat)    -> Font { .custom("Archivo-SemiBold", size: size) }
    static func body(_ size: CGFloat)    -> Font { .custom("Archivo-Regular", size: size) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255)
    }
}

// MARK: - Text roles
// Tracking is the whole system. Display type is tight; labels are wide.

extension View {
    /// 40–56pt screen titles: PAST LIVES, MY LIBRARY, BINGE
    func displayTitle(_ size: CGFloat = 40) -> some View {
        self.font(Theme.display(size))
            .tracking(size * -0.035)
            .lineSpacing(-2)
    }
    /// 16–22pt row and card headlines
    func headline(_ size: CGFloat = 17) -> some View {
        self.font(Theme.heavy(size)).tracking(size * -0.02)
    }
    /// 10–11pt uppercase section labels and tab titles
    func label(_ size: CGFloat = 11) -> some View {
        self.font(Theme.semi(size))
            .tracking(size * 0.16)
            .textCase(.uppercase)
    }
    /// 12–15pt reading copy
    func bodyCopy(_ size: CGFloat = 13) -> some View {
        self.font(Theme.body(size)).lineSpacing(size * 0.45)
    }
}

// MARK: - Rules

struct Rule: View {
    var strong = false
    var onDark = false
    var body: some View {
        Rectangle()
            .fill(onDark ? Theme.onDarkRule : (strong ? Theme.ink : Theme.hairline))
            .frame(height: strong ? Theme.ruleStrong : Theme.ruleHair)
    }
}

// MARK: - Buttons
// One filled button per screen, max. Everything else is outlined or plain.

struct PrimaryButton: View {
    let title: String
    var onDark = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.heavy(15)).tracking(0.5).textCase(.uppercase)
                Spacer()
                Text("→").font(Theme.heavy(15))
            }
            .padding(.horizontal, 18).padding(.vertical, 17)
            .frame(maxWidth: .infinity)
            .background(onDark ? Theme.ground : Theme.accent)
            .foregroundStyle(onDark ? Theme.ink : .white)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct OutlineButton: View {
    let title: String
    var onDark = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.semi(12)).tracking(0.7).textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)  // flush left, always
                .padding(.horizontal, 16).padding(.vertical, 14)
                .foregroundStyle(onDark ? Theme.inkFaint : Theme.ink)
                .overlay(Rectangle().stroke(onDark ? Theme.onDarkMuted : Theme.ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented control (the All / Shows / Films row)

struct RuledSegmented: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Text(options[i])
                        .font(Theme.semi(11)).tracking(0.9).textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .foregroundStyle(selection == i ? Theme.ground : Theme.inkMuted)
                        .background(selection == i ? Theme.ink : .clear)
                }
                .buttonStyle(.plain)
                if i < options.count - 1 { Rule().frame(width: 1).frame(maxHeight: .infinity) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
    }
}

// MARK: - Stat row (37 FINISHED / 9 SAVED / 6 YOU STARTED)

struct StatRow: View {
    struct Stat: Identifiable { let id = UUID(); let value: String; let label: String; var accent = false }
    let stats: [Stat]
    var onDark = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(stats.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats[i].value)
                        .font(Theme.display(28)).tracking(-0.9)
                        .foregroundStyle(stats[i].accent ? (onDark ? Theme.accentTint : Theme.accent)
                                                         : (onDark ? Theme.ground : Theme.ink))
                    Text(stats[i].label)
                        .label(10)
                        .foregroundStyle(onDark ? Theme.onDarkMuted : Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter).padding(.vertical, 14)
                if i < stats.count - 1 { Rule(onDark: onDark).frame(width: 1).frame(maxHeight: .infinity) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Poster
// AsyncImage with a flat placeholder. NEVER round the corners, never tint the art.

struct Poster: View {
    let url: URL?
    var width: CGFloat = 74
    var height: CGFloat = 104

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: Theme.inkFaint
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

// MARK: - Feed row

struct FeedRow: View {
    let posterURL: URL?
    let meta: String        // "Maya · 2h ago · Hulu"
    let headline: String    // "Finished The Bear S3 in one sitting"
    var quote: String? = nil
    var highlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Poster(url: posterURL)
            VStack(alignment: .leading, spacing: 6) {
                Text(meta).label(11).foregroundStyle(Theme.inkMuted)
                Text(headline).headline(18).fixedSize(horizontal: false, vertical: true)
                if let quote {
                    Text(quote).bodyCopy(13).foregroundStyle(Theme.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 18)
        .background(highlighted ? Theme.surface : Theme.ground)
    }
}

// MARK: - Tonight's source band (the red statement)

struct SourceBand: View {
    let kicker: String      // "WHY YOU, WHY TONIGHT"
    let statement: String   // "Maya, Dev and four others finished it..."

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker).label(11).foregroundStyle(.white.opacity(0.85))
            Text(statement).font(Theme.heavy(22)).tracking(-0.44)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.gutter)
        .background(Theme.accent)
        .foregroundStyle(.white)
    }
}

// MARK: - Tab bar
// Native TabView won't give you flush-left uppercase labels with no icons.
// This is the custom bar. Keep it pinned with .safeAreaInset, never in a ScrollView.

enum Tab: String, CaseIterable { case tonight = "Tonight", friends = "Friends", you = "You" }

struct RuledTabBar: View {
    @Binding var selection: Tab
    var onDark = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(onDark ? Theme.onDarkRule : Theme.ink)
                .frame(height: onDark ? 1 : 2)
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button { selection = tab } label: {
                        Text(tab.rawValue)
                            .font(Theme.semi(10)).tracking(1.2).textCase(.uppercase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(selection == tab
                                             ? (onDark ? Theme.accentTint : Theme.accent)
                                             : (onDark ? Theme.onDarkMuted : Theme.inkMuted))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, Theme.gutter)
            .padding(.top, 14)
            .padding(.bottom, 8)   // home indicator handled by safeAreaInset
        }
        .background(onDark ? Theme.ink : Theme.ground)
    }
}
