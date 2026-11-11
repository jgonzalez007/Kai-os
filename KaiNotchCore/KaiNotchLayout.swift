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
    /// The closed notch swelling a little when the cursor is over it, like a button.
    case hover
    /// A little wider and taller than the notch, with the time beside it, while Kai sleeps.
    case clock
    /// Slim strips beside the notch that always show Kai's status.
    case status
    /// Black wings beside the notch that show activity.
    case peek
    /// A slim input bar hanging just below the notch, for when there is no conversation yet.
    case bar
    /// The full panel hanging below the notch.
    case expanded
}

public struct KaiNotchLayout: Equatable, Sendable {
    public static let wingWidth: CGFloat = 72
    public static let statusWingWidth: CGFloat = 26
    /// The sleeping notch with the time: this much wider on each side, and this much taller.
    public static let clockWingWidth: CGFloat = 44
    public static let clockExtraHeight: CGFloat = 4
    /// How much the notch swells while hovered.
    public static let hoverGrow = CGSize(width: 22, height: 3)
    /// Room around the biggest shape so spring overshoot and the glow are never clipped.
    public static let canvasSlack = CGSize(width: 140, height: 90)
    public static let expandedSize = CGSize(width: 560, height: 480)
    /// The slim bar: this wide, and this much taller than the notch itself.
    public static let barWidth: CGFloat = 540
    public static let barExtraHeight: CGFloat = 82
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

    /// The one window Kai draws in: big enough for the biggest shape plus slack, centered on the notch
    /// and flush with the top of the screen. It never changes size while the notch morphs, so the
    /// notch cannot come loose from the bezel mid-animation.
    public var canvas: CGRect {
        let width = min(Self.expandedSize.width + Self.canvasSlack.width, screenFrame.width)
        let height = min(Self.expandedSize.height + Self.canvasSlack.height, screenFrame.height)
        let centeredX = (notch.midX - width / 2).rounded(.down)
        let x = max(screenFrame.minX, min(centeredX, screenFrame.maxX - width))
        return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// `barExtra` replaces the bar's default extra height, for a bar that grows to show a reply.
    /// `clock` says the sleeping notch shows the time, so hover swells that shape and not the bare notch.
    public func frame(for surface: KaiNotchSurface, barExtra: CGFloat? = nil, clock: Bool = false) -> CGRect {
        switch surface {
        case .hover:
            let base = clock ? frame(for: .clock) : notch
            let w = base.width + Self.hoverGrow.width, h = base.height + Self.hoverGrow.height
            return CGRect(x: notch.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
        case .closed:
            return notch
        case .clock:
            let w = notch.width + Self.clockWingWidth * 2, h = notch.height + Self.clockExtraHeight
            return CGRect(x: notch.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
        case .status:
            return notch.insetBy(dx: -Self.statusWingWidth, dy: 0)
        case .peek:
            return notch.insetBy(dx: -Self.wingWidth, dy: 0)
        case .bar:
            let width = min(Self.barWidth, screenFrame.width)
            let height = notch.height + (barExtra ?? Self.barExtraHeight)
            let centeredX = (notch.midX - width / 2).rounded(.down)
            let x = max(screenFrame.minX, min(centeredX, screenFrame.maxX - width))
            return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
        case .expanded:
            let width = min(Self.expandedSize.width, screenFrame.width)
            let height = min(Self.expandedSize.height, screenFrame.height)
            // Whole points, because macOS places a window on whole points. Half a point off would make the
            // layout disagree with where the panel really is.
            let centeredX = (notch.midX - width / 2).rounded(.down)
            let x = max(screenFrame.minX, min(centeredX, screenFrame.maxX - width))
            return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
        }
    }
}
