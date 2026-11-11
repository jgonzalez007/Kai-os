//
//  KaiNotchGlow.swift
//  Kai OS macOS
//
//  The notch's edge glow and its ring logo: a slowly turning spectrum, seen only along the visible
//  edge. The mask lives outside the TimelineView so the glow follows the shape's morph in step.
//

import SwiftUI

enum KaiSpectrum {
    /// Cyan, liquid blue, violet and magenta from the brand palette, looping back to cyan.
    static var colors: [Color] {
        // Cobalt Plasma has no violet or magenta: the ring runs from cyan through cobalt and electric blue and back.
        KaiTheme.isCobalt
            ? [KaiCobalt.plasmaCyan, KaiCobalt.primary, KaiCobalt.electricBlue, KaiCobalt.plasmaCyan, KaiCobalt.primary, KaiCobalt.plasmaCyan]
            : [KaiColor.cyan, KaiColor.liquidBlue, KaiColor.violet, KaiColor.magenta, KaiColor.violet, KaiColor.cyan]
    }
}

struct KaiNotchGlow: View {
    let size: CGSize
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    var intensity: Double = 1

    private static let bleed: CGFloat = 36

    var body: some View {
        // Three passes: a wide soft halo, a denser one, and a crisp rim.
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                ZStack {
                    layer(width: 16, blur: 14, opacity: 0.45)
                    layer(width: 6, blur: 5, opacity: 0.75)
                    layer(width: 1.6, blur: 0, opacity: 0.95)
                }
                .frame(width: size.width + 2 * Self.bleed, height: size.height + 2 * Self.bleed)
                .opacity(intensity)
            }
            .allowsHitTesting(false)
    }

    private func layer(width: CGFloat, blur: CGFloat, opacity: Double) -> some View {
        spectrum
            .mask {
                KaiNotchSkirtShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    .padding(Self.bleed)
                    .blur(radius: blur)
            }
            .opacity(opacity)
    }

    private var spectrum: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: 7) / 7) * 360
            AngularGradient(colors: KaiSpectrum.colors, center: .center, angle: .degrees(angle))
        }
    }
}

/// A thin spectrum ring with a white dot, the Kai mark in the notch.
struct KaiSpectrumLogo: View {
    var spinning: Bool
    var diameter: CGFloat = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period: Double = spinning ? 2 : 13
            let angle = (t.truncatingRemainder(dividingBy: period) / period) * 360
            ZStack {
                Circle()
                    .strokeBorder(AngularGradient(colors: KaiSpectrum.colors, center: .center, angle: .degrees(angle)), lineWidth: diameter * 0.2)
                Circle().fill(Color.white).frame(width: diameter * 0.26, height: diameter * 0.26)
            }
            .frame(width: diameter, height: diameter)
        }
        .transaction { $0.animation = nil }
    }
}
