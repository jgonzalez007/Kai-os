//
//  KaiAppIcon.swift
//  Kai OS macOS
//
//  A Dock icon to try while the app runs. The icon of the app file itself (Finder) is not touched.
//

import AppKit
import SwiftUI

enum KaiAppIcon {
    static let defaultsKey = "kai.icon.style"

    enum Style: String, CaseIterable {
        case glass, arch, neon

        var title: String {
            switch self {
            case .glass: return "Liquid glass K"
            case .arch: return "Arch tile"
            case .neon: return "Neon tile"
            }
        }

        /// The picture for this style, or nil to use the app file's own icon.
        @MainActor var image: NSImage? {
            switch self {
            case .glass: return nil
            case .neon: return NSImage(named: "KaiIconNeon")
            case .arch: return KaiAppIcon.archTile()
            }
        }
    }

    static var current: Style {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Style.init(rawValue:)) ?? .glass
    }

    /// The asset package's icon: the arch and K on its dark navy rounded square, drawn at 512 points.
    @MainActor static func archTile() -> NSImage? {
        let tile = ZStack {
            RoundedRectangle(cornerRadius: 100, style: .continuous).fill(Color(red: 0.039, green: 0.059, blue: 0.122))
            KaiArchLogoArt(size: 512, glow: 0.7)
        }
        .frame(width: 512, height: 512)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 1
        return renderer.nsImage
    }

    /// Puts the chosen icon in the Dock. A missing picture leaves the normal icon.
    @MainActor static func apply() {
        NSApp.applicationIconImage = current.image
    }
}
