//  BingeTheme.swift
//  Design tokens + components for the Binge redesign.
//  Every type is prefixed `Binge` so nothing collides with your existing views.
//  iOS 16+.
//
//  FONTS: Archivo (Google Fonts, OFL).
//  1. Add the .ttf files to the target.
//  2. Info.plist → "Fonts provided by application" → one row per file.
//  3. If text still renders as SF, call BingeTheme.debugPrintFontNames().

import SwiftUI

// MARK: - Tokens

enum BingeTheme {

    // No Color(hex:) extension — you may already have one. Local helper instead.
    private static func c(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red:   Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8)  & 0xFF) / 255,
              blue:  Double( hex        & 0xFF) / 255,
              opacity: 1)
    }

    // Four values. Don't add a fifth without a reason.
    static let ground  = c(0xF3F2F2)
    static let ink     = c(0x201E1D)
    static let accent  = c(0xEC3013)
    static let surface = c(0xEAE9E9)

    // Derived greys, sampled from the ink ramp.
    static let inkMuted    = c(0x605D5D)
    static let inkFaint    = c(0xBAB6B6)
    static let hairline    = c(0xD7D3D3)
    static let onDarkMuted = c(0x8B8787)
    static let onDarkRule  = c(0x3D3A39)
    static let accentTint  = c(0xFF9783)   // accent on ink — contrast-safe
    static let accentDeep  = c(0xAE1800)   // pressed state on ground

    static let radius: CGFloat = 0         // zero everywhere
    static let gutter: CGFloat = 20
    static let minTap: CGFloat = 44

    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        static let lg: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 28
    }

    static func display(_ s: CGFloat) -> Font { .custom("Archivo-Black", size: s, relativeTo: .largeTitle) }
    static func heavy(_ s: CGFloat)   -> Font { .custom("Archivo-ExtraBold", size: s, relativeTo: .headline) }
    static func semi(_ s: CGFloat)    -> Font { .custom("Archivo-SemiBold", size: s, relativeTo: .caption) }
    static func body(_ s: CGFloat)    -> Font { .custom("Archivo-Regular", size: s, relativeTo: .body) }

    static func debugPrintFontNames() {
        for f in UIFont.familyNames.sorted() { print(f, UIFont.fontNames(forFamilyName: f)) }
    }
}

// MARK: - Text roles (Dynamic Type aware, with per-role growth caps)

private struct BingeDisplayMod: ViewModifier {
    let size: CGFloat
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    func body(content: Content) -> some View {
        let s = min(size * scale, size * 1.35)
        content.font(BingeTheme.display(s)).tracking(s * -0.035)
    }
}
private struct BingeHeadlineMod: ViewModifier {
    let size: CGFloat
    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1
    func body(content: Content) -> some View {
        let s = min(size * scale, size * 1.6)
        content.font(BingeTheme.heavy(s)).tracking(s * -0.02)
    }
}
private struct BingeLabelMod: ViewModifier {
    let size: CGFloat
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1
    func body(content: Content) -> some View {
        let s = min(size * scale, size * 1.8)
        content.font(BingeTheme.semi(s)).tracking(s * 0.16).textCase(.uppercase)
    }
}
private struct BingeBodyMod: ViewModifier {
    let size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    func body(content: Content) -> some View {
        let s = size * scale
        content.font(BingeTheme.body(s)).lineSpacing(s * 0.45)
    }
}

extension View {
    /// 28–52pt screen titles
    func bingeDisplay(_ size: CGFloat = 40) -> some View { modifier(BingeDisplayMod(size: size)) }
    /// 14–22pt row and card headlines
    func bingeHeadline(_ size: CGFloat = 17) -> some View { modifier(BingeHeadlineMod(size: size)) }
    /// 10–12pt uppercase labels
    func bingeLabel(_ size: CGFloat = 11) -> some View { modifier(BingeLabelMod(size: size)) }
    /// 12–15pt reading copy
    func bingeBody(_ size: CGFloat = 13) -> some View { modifier(BingeBodyMod(size: size)) }
}

// MARK: - Rules

struct BingeRule: View {
    var strong = false
    var onDark = false
    var body: some View {
        Rectangle()
            .fill(onDark ? BingeTheme.onDarkRule : (strong ? BingeTheme.ink : BingeTheme.hairline))
            .frame(height: strong ? 2 : 1)
            .accessibilityHidden(true)
    }
}

struct BingeVRule: View {
    var onDark = false
    var body: some View {
        Rectangle()
            .fill(onDark ? BingeTheme.onDarkRule : BingeTheme.hairline)
            .frame(width: 1).frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

private struct BingeButtonStyle: ButtonStyle {
    var filled: Bool
    var onDark: Bool
    func makeBody(configuration: Configuration) -> some View {
        let pressed: Color = filled
            ? (onDark ? BingeTheme.inkFaint : BingeTheme.accentDeep)
            : (onDark ? Color.white.opacity(0.12) : BingeTheme.surface)
        let normal: Color = filled ? (onDark ? BingeTheme.ground : BingeTheme.accent) : .clear
        configuration.label
            .background(configuration.isPressed ? pressed : normal)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BingePrimaryButton: View {
    let title: String
    var onDark = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).bingeHeadline(15).textCase(.uppercase)
                Spacer(minLength: 12)
                Text("→").bingeHeadline(15).accessibilityHidden(true)
            }
            .padding(.horizontal, 18).padding(.vertical, 17)
            .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap)
            .foregroundStyle(onDark ? BingeTheme.ink : Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(BingeButtonStyle(filled: true, onDark: onDark))
    }
}

struct BingeOutlineButton: View {
    let title: String
    var onDark = false
    var labelSize: CGFloat = 12
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .bingeLabel(labelSize)
                .frame(maxWidth: .infinity, alignment: .leading)   // flush left, always
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(minHeight: BingeTheme.minTap)
                .foregroundStyle(onDark ? BingeTheme.inkFaint : BingeTheme.ink)
                .overlay(Rectangle().stroke(onDark ? BingeTheme.onDarkMuted : BingeTheme.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(BingeButtonStyle(filled: false, onDark: onDark))
    }
}

struct BingeChip: View {
    let title: String
    var filled = false
    var muted = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .bingeLabel(11)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(minHeight: 34)
                .foregroundStyle(filled ? Color.white : (muted ? BingeTheme.inkMuted : BingeTheme.ink))
                .background(filled ? BingeTheme.accent : Color.clear)
                .overlay(Rectangle().stroke(filled ? Color.clear : (muted ? BingeTheme.hairline : BingeTheme.ink), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)      // invisible padding to reach a 44pt target
    }
}

// MARK: - Segmented control

struct BingeSegmented: View {
    let options: [String]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Text(options[i])
                        .bingeLabel(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .frame(minHeight: BingeTheme.minTap)
                        .foregroundStyle(selection == i ? BingeTheme.ground : BingeTheme.inkMuted)
                        .background(selection == i ? BingeTheme.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == i ? [.isButton, .isSelected] : .isButton)
                if i < options.count - 1 { BingeVRule() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))
    }
}

// MARK: - Stat row

struct BingeStat: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    var accent = false
    var spoken: String? = nil       // "✓" reads badly otherwise
}

struct BingeStatRow: View {
    let stats: [BingeStat]
    var onDark = false
    var body: some View {
        HStack(spacing: 0) {
            ForEach(stats.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats[i].value)
                        .bingeDisplay(28)
                        .foregroundStyle(stats[i].accent
                                         ? (onDark ? BingeTheme.accentTint : BingeTheme.accent)
                                         : (onDark ? BingeTheme.ground : BingeTheme.ink))
                    Text(stats[i].label)
                        .bingeLabel(10)
                        .foregroundStyle(onDark ? BingeTheme.onDarkMuted : BingeTheme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, i == 0 ? BingeTheme.gutter : 16)
                .padding(.trailing, 10)
                .padding(.vertical, 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(stats[i].spoken ?? stats[i].value) \(stats[i].label)")
                if i < stats.count - 1 { BingeVRule(onDark: onDark) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Poster
// Takes your TMDB poster_url string directly. Never rounded, never tinted.

struct BingePoster: View {
    let urlString: String?
    var width: CGFloat? = 74
    var height: CGFloat? = 104
    var cropAnchor: Alignment = .center
    var accessibilityTitle: String? = nil

    private var url: URL? {
        guard let s = urlString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: BingeTheme.inkFaint
            }
        }
        .frame(width: width, height: height, alignment: cropAnchor)
        .frame(maxWidth: width == nil ? .infinity : nil,
               maxHeight: height == nil ? .infinity : nil,
               alignment: cropAnchor)
        .clipped()
        .accessibilityHidden(accessibilityTitle == nil)
        .accessibilityLabel(accessibilityTitle ?? "")
    }
}

// MARK: - Progress

struct BingeProgress: View {
    let fraction: Double
    var onDark = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(onDark ? BingeTheme.onDarkRule : BingeTheme.hairline)
                Rectangle().fill(onDark ? BingeTheme.accentTint : BingeTheme.ink)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

struct BingeFeedRow<Actions: View>: View {
    let posterURL: String?
    let meta: String
    let headline: String
    var quote: String? = nil
    var highlighted = false
    var metaAccent = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BingePoster(urlString: posterURL)
            VStack(alignment: .leading, spacing: 6) {
                Text(meta).bingeLabel(11)
                    .foregroundStyle(metaAccent ? BingeTheme.accent : BingeTheme.inkMuted)
                Text(headline).bingeHeadline(18).fixedSize(horizontal: false, vertical: true)
                if let quote {
                    Text(quote).bingeBody(13).foregroundStyle(BingeTheme.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) { actions() }.padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 18)
        .background(highlighted ? BingeTheme.surface : BingeTheme.ground)
    }
}

struct BingeTitleRow<Trailing: View>: View {
    let posterURL: String?
    let title: String
    let subtitle: String
    var progress: Double? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            BingePoster(urlString: posterURL, width: 56, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).bingeHeadline(16)
                Text(subtitle).bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                if let progress { BingeProgress(fraction: progress) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

// MARK: - Tonight's red source band

struct BingeSourceBand: View {
    let kicker: String
    let statement: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker).bingeLabel(9).foregroundStyle(.white.opacity(0.85))
            Text(statement).bingeHeadline(14).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17).padding(.vertical, 12)
        .background(BingeTheme.accent)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section header

struct BingeSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var onDark = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).bingeLabel(11)
                .foregroundStyle(onDark ? BingeTheme.onDarkMuted : BingeTheme.inkMuted)
            Spacer()
            if let trailing {
                Text(trailing).bingeLabel(11)
                    .foregroundStyle(onDark ? BingeTheme.accentTint : BingeTheme.accent)
            }
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.top, 2).padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Empty state
// Binge empty states argue for the product. They never shrug.

struct BingeArgumentBlock: View {
    let kicker: String
    let headline: String
    let message: String
    var onDark = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kicker).bingeLabel(11)
                .foregroundStyle(onDark ? BingeTheme.accentTint : BingeTheme.accent)
            Text(headline).bingeDisplay(28)
                .foregroundStyle(onDark ? BingeTheme.ground : BingeTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message).bingeBody(13)
                .foregroundStyle(onDark ? BingeTheme.inkFaint : BingeTheme.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 26)
    }
}

// MARK: - Tab bar
// Named BingeTab, not Tab — SwiftUI added its own `Tab` type in iOS 18.

enum BingeTab: String, CaseIterable {
    case tonight = "Tonight", friends = "Friends", search = "Search", you = "You"
}

struct BingeTabBar: View {
    @Binding var selection: BingeTab
    var onDark = false
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(onDark ? BingeTheme.onDarkRule : BingeTheme.ink)
                .frame(height: 2)
            HStack(spacing: 0) {
                ForEach(BingeTab.allCases, id: \.self) { tab in
                    Button { selection = tab } label: {
                        Text(tab.rawValue)
                            .bingeLabel(15)
                            .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap, alignment: .leading)
                            .foregroundStyle(selection == tab
                                             ? (onDark ? BingeTheme.accentTint : BingeTheme.accent)
                                             : (onDark ? BingeTheme.onDarkMuted : BingeTheme.inkMuted))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.leading, BingeTheme.gutter).padding(.top, 6)
            .frame(height: BingeTheme.minTap + 6)
        }
        .background((onDark ? BingeTheme.ink : BingeTheme.ground).ignoresSafeArea(edges: .bottom))
    }
}
