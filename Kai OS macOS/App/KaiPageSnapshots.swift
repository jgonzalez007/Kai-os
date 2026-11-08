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
    static var directory: String? { ProcessInfo.processInfo.environment["KAI_PAGE_SNAPSHOT_DIR"] }

    static func runAndExit() {
        guard let dir = directory else { return }
        Task {
            let folder = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let pages: [(String, KaiSettingsView.Page)] = [
                ("sidekick", .sidekick), ("knowledge", .knowledge), ("notch", .notch), ("system", .system)
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
            exit(0)
        }
    }
}
#endif
