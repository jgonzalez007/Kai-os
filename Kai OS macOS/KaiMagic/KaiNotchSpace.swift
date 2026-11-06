//
//  KaiNotchSpace.swift
//  Kai OS macOS
//
//  Chooses the screen for the notch panel and describes it to KaiNotchLayout.
//

import AppKit
import KaiNotchCore

enum KaiNotchSpace {
    /// Prefers the built-in display with a hardware notch, even when another display is main.
    static func currentLayout() -> KaiNotchLayout? {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first else {
            return nil
        }
        return KaiNotchLayout(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }
}
