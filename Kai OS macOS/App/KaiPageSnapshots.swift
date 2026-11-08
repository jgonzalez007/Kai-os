//
//  KaiPageSnapshots.swift
//  Kai OS macOS
//
//  Debug-only: saves pictures of a few pages, then quits. Changes nothing on disk.
//    KAI_PAGE_SNAPSHOT_DIR=/some/folder "Kai OS.app/Contents/MacOS/Kai OS"
//

#if DEBUG
import AppKit
import Foundation

@MainActor
enum KaiPageSnapshots {
    private static var started = false

    static func runIfRequested(appState: AppState) {
        guard !started, let dir = ProcessInfo.processInfo.environment["KAI_PAGE_SNAPSHOT_DIR"] else { return }
        started = true
        Task {
            let directory = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(2))
            NSApp.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { exit(1) }
            window.setContentSize(NSSize(width: 1280, height: 860))
            let shots: [(String, String, KaiSettingsView.Page)] = [
                ("Welcome", "welcome", .ai),
                ("Settings", "settings-ai", .ai),
                ("Settings", "settings-knowledge", .knowledge),
                ("Settings", "settings-notch", .notch),
                ("Settings", "settings-overnight", .overnight),
                ("Settings", "settings-system", .system),
                ("Chat", "chat", .ai)
            ]
            for (sidebar, name, page) in shots {
                KaiSettingsView.startPage = page
                appState.activeSidebar = "Chat"
                try? await Task.sleep(for: .milliseconds(400))
                appState.activeSidebar = sidebar
                try? await Task.sleep(for: .milliseconds(1200))
                KaiChatSelfTest.snapshot(window, to: directory.appendingPathComponent("\(name).png"), background: .black)
            }
            exit(0)
        }
    }
}
#endif
