//
//  KaiAppIcon.swift
//  Kai OS macOS
//
//  A Dock icon to try while the app runs. The icon of the app file itself (Finder) is not touched.
//

import AppKit

enum KaiAppIcon {
    static let defaultsKey = "kai.icon.style"

    enum Style: String, CaseIterable {
        case glass, neon

        var title: String { self == .glass ? "Liquid glass K" : "Neon tile" }

        /// The picture for this style, or nil to use the app file's own icon.
        var image: NSImage? { self == .neon ? NSImage(named: "KaiIconNeon") : nil }
    }

    static var current: Style {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Style.init(rawValue:)) ?? .glass
    }

    /// Puts the chosen icon in the Dock. A missing picture leaves the normal icon.
    @MainActor static func apply() {
        NSApp.applicationIconImage = current.image
    }
}
