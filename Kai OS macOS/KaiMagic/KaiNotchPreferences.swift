//
//  KaiNotchPreferences.swift
//  Kai OS macOS
//

import Foundation

enum KaiNotchPreferences {
    static let enabledKey = "kai.notch.enabled"
    static let hoverOpenKey = "kai.notch.hoverOpen"
    static let statusKey = "kai.notch.status"
    static let hideFullScreenKey = "kai.notch.hideFullScreen"
    static let menuBarKey = "kai.menubar.enabled"

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static var isEnabled: Bool { flag(enabledKey) }
    /// Hovering over the notch opens the panel after a short pause.
    static var hoverOpens: Bool { flag(hoverOpenKey) }
    /// Slim strips beside the notch show Kai's status all the time.
    static var showsStatus: Bool { flag(statusKey) }
    /// The notch steps away while another app is full screen.
    static var hidesInFullScreen: Bool { flag(hideFullScreenKey) }
    static var menuBarEnabled: Bool { flag(menuBarKey) }
}
