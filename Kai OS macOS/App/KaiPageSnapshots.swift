//
//  KaiPageSnapshots.swift
//  Kai OS macOS
//
//  Debug-only: draws a few Preferences pages into its own window, saves pictures, and quits before
//  anything else starts (no notch, no hotkeys, no menu bar item). Changes nothing on disk.
//    KAI_PAGE_SNAPSHOT_DIR=/some/folder "Kai OS.app/Contents/MacOS/Kai OS"
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum KaiPageSnapshots {
    static var directory: String? {
        ProcessInfo.processInfo.environment["KAI_PAGE_SNAPSHOT_DIR"] ?? ProcessInfo.processInfo.environment["KAI_ICON_DIR"]
    }

    /// Draws the app icon (the K on a dark glass tile) at 1024 points.
    private static func renderIcon(to folder: URL) {
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.07, green: 0.06, blue: 0.13), KaiColor.windowBg], startPoint: .top, endPoint: .bottom))
            Circle().fill(RadialGradient(colors: [KaiColor.violet.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 360))
                .frame(width: 720, height: 720).offset(x: -150, y: -160)
            Circle().fill(RadialGradient(colors: [KaiColor.cyan.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 300))
                .frame(width: 600, height: 600).offset(x: 200, y: 120)
            Circle().fill(RadialGradient(colors: [KaiColor.magenta.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 280))
                .frame(width: 560, height: 560).offset(x: -60, y: 260)
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 6)
            KaiLogoMark(size: 900)
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 230, style: .continuous))
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("icon_1024.png"))
        }
    }

    static func runAndExit() {
        guard let dir = directory else { return }
        Task {
            let folder = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if ProcessInfo.processInfo.environment["KAI_ICON_DIR"] != nil {
                renderIcon(to: folder)
                exit(0)
            }
            let pages: [(String, KaiSettingsView.Page)] = [
                ("ai", .ai), ("sidekick", .sidekick), ("knowledge", .knowledge), ("notch", .notch), ("system", .system)
            ]
            for (name, page) in pages {
                KaiSettingsView.startPage = page
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = NSHostingView(rootView: KaiSettingsView().environmentObject(AppState.shared))
                window.orderFrontRegardless()
                try? await Task.sleep(for: .milliseconds(1500))
                if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
                }
                window.orderOut(nil)
            }
            // Health and Permissions, as full pages.
            let others: [(String, AnyView)] = [
                ("health", AnyView(KaiHealthView(briefing: AppState.shared.morningCards).environmentObject(AppState.shared))),
                ("permissions", AnyView(KaiPermissionsView(permissions: .shared).environmentObject(AppState.shared)))
            ]
            for (name, view) in others {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
                window.orderFrontRegardless()
                try? await Task.sleep(for: .milliseconds(1500))
                if let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
                }
                window.orderOut(nil)
            }
            // The menu bar window, at its real width.
            let hud = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            hud.contentView = NSHostingView(rootView: KaiMenuBarContent(appState: AppState.shared))
            hud.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(1500))
            if let view = hud.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("hud.png"))
            }
            exit(0)
        }
    }
}
#endif
