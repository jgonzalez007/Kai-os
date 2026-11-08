//
//  KaiNotchShape.swift
//  Kai OS macOS
//
//  Notch silhouette: concave shoulders at the top, rounded corners at the bottom.
//

import SwiftUI

struct KaiNotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}


/// The notch's visible edge as an open path: the notch silhouette above, without its closing line along
/// the top. The glow strokes this, so it bends into the top corners without lighting the line along the
/// screen's top edge. It is built from `KaiNotchShape` itself, so the two can never disagree.
struct KaiNotchSkirtShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var open = Path()
        KaiNotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect).forEach { element in
            switch element {
            case .move(let point): open.move(to: point)
            case .line(let point): open.addLine(to: point)
            case .quadCurve(let point, let control): open.addQuadCurve(to: point, control: control)
            case .curve(let point, let control1, let control2): open.addCurve(to: point, control1: control1, control2: control2)
            case .closeSubpath: break
            }
        }
        return open
    }
}
