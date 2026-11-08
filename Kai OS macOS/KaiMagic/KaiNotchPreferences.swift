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
    static let peeksKey = "kai.notch.peeks"
    static let clickKey = "kai.notch.click"

    private static func flag(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    static var isEnabled: Bool { flag(enabledKey) }
    /// Hovering over the notch opens the panel after a short pause.
    static var hoverOpens: Bool { flag(hoverOpenKey, default: false) }
    /// Slim strips beside the notch show Kai's status all the time.
    static var showsStatus: Bool { flag(statusKey, default: false) }
    /// Wings beside the notch for hover, activity and events. Off keeps the notch exactly its own size
    /// until it is expanded. A waiting Claude Code permission request still opens the panel.
    static var showsPeeks: Bool { flag(peeksKey, default: false) }
    /// The notch steps away while another app is full screen.
    static var hidesInFullScreen: Bool { flag(hideFullScreenKey) }
    /// Clicking (or hovering over) the notch opens Kai. Off leaves the notch to other apps; the shared key still works.
    static var clickOpens: Bool { flag(clickKey) }
    static var menuBarEnabled: Bool { flag(menuBarKey) }
}
