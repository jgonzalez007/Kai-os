//
//  KaiLogoMark.swift
//  Kai OS macOS
//
//  The Kai liquid glass "K", drawn from the brand SVG (kai_os_liquid_glass_logo_svg): a curved stem and
//  two arms in cyan, violet and magenta, with a white specular shine, on a soft glow.
//

import SwiftUI

private enum KaiLogoPaths {
    // Coordinates are in the SVG's 512 x 512 box.
    static func stem() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 160, y: 110))
        p.addCurve(to: CGPoint(x: 195, y: 256), control1: CGPoint(x: 160, y: 110), control2: CGPoint(x: 195, y: 210))
        p.addCurve(to: CGPoint(x: 160, y: 402), control1: CGPoint(x: 195, y: 302), control2: CGPoint(x: 160, y: 402))
        p.addCurve(to: CGPoint(x: 225, y: 256), control1: CGPoint(x: 190, y: 402), control2: CGPoint(x: 225, y: 330))
        p.addCurve(to: CGPoint(x: 160, y: 110), control1: CGPoint(x: 225, y: 182), control2: CGPoint(x: 190, y: 110))
        p.closeSubpath()
        return p
    }

    static func upperArm() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 210, y: 245))
        p.addCurve(to: CGPoint(x: 370, y: 120), control1: CGPoint(x: 250, y: 200), control2: CGPoint(x: 310, y: 140))
        p.addCurve(to: CGPoint(x: 250, y: 265), control1: CGPoint(x: 340, y: 160), control2: CGPoint(x: 300, y: 220))
        p.closeSubpath()
        return p
    }

    static func lowerArm() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 220, y: 260))
        p.addCurve(to: CGPoint(x: 375, y: 392), control1: CGPoint(x: 270, y: 300), control2: CGPoint(x: 325, y: 365))
        p.addCurve(to: CGPoint(x: 220, y: 260), control1: CGPoint(x: 330, y: 385), control2: CGPoint(x: 275, y: 340))
        p.closeSubpath()
        return p
    }

    static func stemShine() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 165, y: 118))
        p.addCurve(to: CGPoint(x: 165, y: 394), control1: CGPoint(x: 190, y: 180), control2: CGPoint(x: 190, y: 320))
        p.addCurve(to: CGPoint(x: 205, y: 256), control1: CGPoint(x: 175, y: 394), control2: CGPoint(x: 205, y: 320))
        p.addCurve(to: CGPoint(x: 165, y: 118), control1: CGPoint(x: 205, y: 190), control2: CGPoint(x: 175, y: 118))
        p.closeSubpath()
        return p
    }

    static func armShine() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 218, y: 245))
        p.addCurve(to: CGPoint(x: 365, y: 127), control1: CGPoint(x: 258, y: 202), control2: CGPoint(x: 315, y: 145))
        p.addCurve(to: CGPoint(x: 258, y: 258), control1: CGPoint(x: 345, y: 155), control2: CGPoint(x: 308, y: 210))
        p.closeSubpath()
        return p
    }
}

private struct KaiLogoShape: Shape {
    let make: () -> Path
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 512
        return make().applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// Which artwork the app uses for its mark. The first is drawn in code from the brand SVG; the other two
/// are pictures cut from the asset sheet, to try. A picture that is missing falls back to the first.
enum KaiLogoStyle: String, CaseIterable {
    case glass, symbol, neon

    static let defaultsKey = "kai.logo.style"

    var title: String {
        switch self {
        case .glass: return "Liquid glass K"
        case .symbol: return "K with the notch ring"
        case .neon: return "Neon outline"
        }
    }

    var imageName: String? {
        switch self {
        case .glass: return nil
        case .symbol: return "KaiLogoSymbol"
        case .neon: return "KaiLogoNeon"
        }
    }

    static var current: KaiLogoStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(KaiLogoStyle.init(rawValue:)) ?? .glass
    }
}

struct KaiLogoMark: View {
    var size: CGFloat = 40
    /// A slow breathing glow, for "working".
    var pulsing = false
    @AppStorage(KaiLogoStyle.defaultsKey) private var styleName = KaiLogoStyle.glass.rawValue

    var body: some View {
        let style = KaiLogoStyle(rawValue: styleName) ?? .glass
        if let name = style.imageName, let image = NSImage(named: name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: KaiColor.violet.opacity(pulsing ? 0.7 : 0.35), radius: size * 0.12)
        } else if pulsing {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                KaiLogoArt(size: size, glow: 0.45 + 0.25 * sin(t * 3))
            }
        } else {
            KaiLogoArt(size: size, glow: 0.45)
        }
    }
}

/// The still picture of the logo. No timeline, so it also renders into an image.
struct KaiLogoArt: View {
    var size: CGFloat
    var glow: Double

    private static func unit(_ x: CGFloat, _ y: CGFloat) -> UnitPoint { UnitPoint(x: x / 512, y: y / 512) }

    var body: some View {
        ZStack {
            KaiLogoShape(make: KaiLogoPaths.stem).fill(
                LinearGradient(colors: [KaiColor.cyan, KaiColor.violet, KaiColor.magenta],
                               startPoint: Self.unit(160, 110), endPoint: Self.unit(225, 402)))
            KaiLogoShape(make: KaiLogoPaths.upperArm).fill(
                LinearGradient(stops: [.init(color: KaiColor.liquidBlue, location: 0), .init(color: KaiColor.cyan, location: 0.7), .init(color: .white, location: 1)],
                               startPoint: Self.unit(210, 265), endPoint: Self.unit(370, 120)))
            KaiLogoShape(make: KaiLogoPaths.lowerArm).fill(
                LinearGradient(colors: [KaiColor.cyan, KaiColor.violet, KaiColor.magenta],
                               startPoint: Self.unit(220, 260), endPoint: Self.unit(375, 392)))
            KaiLogoShape(make: KaiLogoPaths.stemShine).fill(
                LinearGradient(stops: [.init(color: .white.opacity(0.8), location: 0), .init(color: .white.opacity(0.1), location: 0.3),
                                       .init(color: KaiColor.cyan.opacity(0), location: 0.7), .init(color: .white.opacity(0.4), location: 1)],
                               startPoint: Self.unit(160, 110), endPoint: Self.unit(205, 394)))
            KaiLogoShape(make: KaiLogoPaths.armShine).fill(
                LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(0.6)
        }
        .frame(width: size, height: size)
        .shadow(color: KaiColor.cyan.opacity(glow), radius: size * 0.12)
        .shadow(color: KaiColor.violet.opacity(glow * 0.8), radius: size * 0.22)
    }
}
