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
import KaiKnowledge
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
                ("ai", .ai), ("overnight", .overnight), ("sidekick", .sidekick), ("knowledge", .knowledge), ("notch", .notch), ("permissions-page", .permissions), ("appearance", .appearance), ("updates", .updates)
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
            // A made-up portrait, in memory only, so the About you face can be seen.
            AppState.shared.profile = KaiProfile(markdown: """
            ## Who you are
            - Jose Gonzalez, runs the platform team at SailPoint.
            - Builds Kai OS, a personal AI for the Mac, in the evenings.

            ## What matters to you
            - Shipping Kai OS so regular people can install it.
            - Keeping your data on your own Mac.

            ## In flight
            - Contract review for the Austin trip, waiting on Ana.
            - Kai OS update 1.2 due this week.

            ## Not sure yet
            - Which projects at work come first this quarter?
            """, updatedAt: Date(), documentCount: 42, edited: true)
            AppState.shared.calendarConnected = true
            AppState.shared.mailConnected = true
            AppState.shared.mailMessages = KaiMailView.sampleMessages()
            // Health and Permissions, as full pages.
            let others: [(String, AnyView)] = [
                ("home", AnyView(KaiMainViewForSnapshot())),
                ("knowledge-page", AnyView(KaiMainViewForSnapshot(page: "Knowledge"))),
                ("knowledge-graph", AnyView(KaiMainViewForSnapshot(page: "Knowledge", graph: true))),
                ("mail-page", AnyView(KaiMainViewForSnapshot(page: "Mail"))),
                ("calendar-page", AnyView(KaiMainViewForSnapshot(page: "Calendar"))),
                ("sidekick-page", AnyView(KaiMainViewForSnapshot(page: "Sidekick"))),
                ("health", AnyView(KaiHealthView(briefing: AppState.shared.morningCards).environmentObject(AppState.shared))),
                ("permissions", AnyView(KaiPermissionsView(permissions: .shared).environmentObject(AppState.shared)))
            ]
            for (name, view) in others {
                let narrow = false
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled], backing: .buffered, defer: false)
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

/// The main window's content, without Preferences, for the snapshot.
private struct KaiMainViewForSnapshot: View {
    var page = "Chat"
    var graph = false
    var body: some View {
        KaiMainView().environmentObject(AppState.shared).onAppear {
            KaiKnowledgeView.startInGraph = graph
            AppState.shared.activeSidebar = page
        }
    }
}
