//  BingeLogo.swift
//  The mark (11b "The Converge") + wordmark + launch screen.
//  Three people, three arrows, one recipient rule. Pure shapes — no assets,
//  so it scales from a 16pt header glyph to a 200pt splash without artwork.
//
//  Name note: the wordmark reads WORD. File/type prefixes stay `Binge`
//  until the bundle rename pass.

import SwiftUI

// MARK: - Arrowhead

private struct BingeArrowHead: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Mark

/// Three people → three arrows → you.
/// `height` is the height of the recipient rule; everything else scales off it.
struct BingeMark: View {
    var height: CGFloat = 28
    var onDark = false
    /// Knocked out of a solid tile (app icon, tab bar) rather than sitting on the ground.
    var knockout = false

    private var u: CGFloat { height / 62 }
    private var personFill: Color {
        knockout ? BingeTheme.ground : (onDark ? BingeTheme.ground : BingeTheme.ink)
    }
    private var arrowFill: Color {
        // accentTint exists so small accent TEXT stays legible on ink. The mark
        // is large solid shapes — it should carry the true signal red, or the
        // app icon comes out salmon.
        BingeTheme.accent
    }

    var body: some View {
        HStack(spacing: 6 * u) {
            VStack(spacing: 7 * u) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 4 * u) {
                        Rectangle().fill(personFill)
                            .frame(width: 14 * u, height: 14 * u)
                        Rectangle().fill(arrowFill)
                            .frame(width: 14 * u, height: 5 * u)
                        BingeArrowHead().fill(arrowFill)
                            .frame(width: 8 * u, height: 12 * u)
                    }
                }
            }
            Rectangle().fill(arrowFill)
                .frame(width: 15 * u, height: 62 * u)
        }
        .frame(height: 62 * u)
        .accessibilityHidden(true)
    }
}

// MARK: - Wordmark

struct BingeWordmark: View {
    var size: CGFloat = 34
    var onDark = false
    var showsMark = true

    var body: some View {
        HStack(spacing: size * 0.30) {
            if showsMark { BingeMark(height: size * 1.35, onDark: onDark) }
            Text("WORD")
                .bingeDisplay(size)
                .foregroundStyle(onDark ? BingeTheme.ground : BingeTheme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Word")
    }
}

// MARK: - Launch / splash

struct BingeLaunchView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            BingeMark(height: 118)
                .padding(.bottom, 30)
            Text("WORD")
                .bingeDisplay(64)
                .foregroundStyle(BingeTheme.ink)
            Spacer()
            BingeRule(strong: true)
                .padding(.bottom, 14)
            Text("Straight from your people")
                .bingeLabel(11)
                .foregroundStyle(BingeTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BingeTheme.gutter)
        .padding(.bottom, 44)
        .background(BingeTheme.ground.ignoresSafeArea())
    }
}

// MARK: - App icon artwork (export at 1024 for the asset catalog)

struct BingeIconArtwork: View {
    var side: CGFloat = 1024
    var body: some View {
        ZStack {
            BingeTheme.ink
            BingeMark(height: side * 0.56, knockout: true)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - Icon export helper (temporary)

struct IconExportHelper: View {
    @State private var status = "Ready"

    var body: some View {
        VStack(spacing: 20) {
            BingeIconArtwork(side: 240)
                .frame(width: 240, height: 240)
            Button(action: exportIcon) {
                Text(status)
                    .bingeLabel(12)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(BingeTheme.accent)
                    .foregroundStyle(.white)
            }
        }
        .padding()
    }

    func exportIcon() {
        let artwork = BingeIconArtwork(side: 1024)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1

        if let image = renderer.uiImage {
            if let pngData = image.pngData() {
                let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
                let filePath = (documentsPath as NSString).appendingPathComponent("AppIcon-1024.png")
                do {
                    try pngData.write(to: URL(fileURLWithPath: filePath))
                    status = "✓ Saved to Documents"
                    print("Icon saved: \(filePath)")
                    print("Copy this file to your asset catalog as AppIcon 1024pt slot")
                } catch {
                    status = "✗ Failed to save"
                }
            }
        }
    }
}

#Preview("Launch") { BingeLaunchView() }
#Preview("Icon") { BingeIconArtwork(side: 240) }
#Preview("Export Icon") { IconExportHelper() }
