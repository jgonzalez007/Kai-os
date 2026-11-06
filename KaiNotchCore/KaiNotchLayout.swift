//
//  KaiNotchLayout.swift
//  Kai OS
//
//  Pure geometry for the notch panel, in AppKit screen coordinates (origin at bottom left).
//

import CoreGraphics

public enum KaiNotchSurface: Equatable, Sendable {
    /// Exactly covers the notch, so it is invisible on a display with a hardware notch.
    case closed
    /// Black wings beside the notch that show activity.
    case peek
    /// The full panel hanging below the notch.
    case expanded
}

public struct KaiNotchLayout: Equatable, Sendable {
    public static let wingWidth: CGFloat = 72
    public static let expandedSize = CGSize(width: 560, height: 480)
    private static let pillWidth: CGFloat = 120
    private static let fallbackHeight: CGFloat = 24

    public let screenFrame: CGRect
    public let notch: CGRect
    public let hasHardwareNotch: Bool

    /// Pass the screen's `safeAreaInsets.top` and the widths of its auxiliary top areas.
    /// A screen without a hardware notch gets a centered pill in the menu bar instead.
    public init(screenFrame: CGRect, safeAreaTop: CGFloat, leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?, menuBarHeight: CGFloat) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = leftAreaWidth, let right = rightAreaWidth, screenFrame.width - left - right > 0 {
            hasHardwareNotch = true
            // A notch can sit on a half point, but AppKit rounds window frames to whole points.
            // Snapping outward keeps the panel centered and still covers the whole notch.
            notch = CGRect(
                x: screenFrame.minX + left,
                y: screenFrame.maxY - safeAreaTop,
                width: screenFrame.width - left - right,
                height: safeAreaTop
            ).integral
        } else {
            hasHardwareNotch = false
            let height = menuBarHeight > 0 ? menuBarHeight : Self.fallbackHeight
            notch = CGRect(
                x: screenFrame.midX - Self.pillWidth / 2,
                y: screenFrame.maxY - height,
                width: Self.pillWidth,
                height: height
            )
        }
    }

    public func frame(for surface: KaiNotchSurface) -> CGRect {
        switch surface {
        case .closed:
            return notch
        case .peek:
            return notch.insetBy(dx: -Self.wingWidth, dy: 0)
        case .expanded:
            let width = min(Self.expandedSize.width, screenFrame.width)
            let height = min(Self.expandedSize.height, screenFrame.height)
            let centeredX = notch.midX - width / 2
            let x = max(screenFrame.minX, min(centeredX, screenFrame.maxX - width))
            return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
        }
    }
}
