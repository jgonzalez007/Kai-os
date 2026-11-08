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

    private static func note(_ dir: String, _ text: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("log.txt")
        let line = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(line); try? handle.close() }
        else { try? line.write(to: url) }
    }

    static func runIfRequested(appState: AppState) {
        guard !started, let dir = ProcessInfo.processInfo.environment["KAI_PAGE_SNAPSHOT_DIR"] else { return }
        started = true
        note(dir, "starting")
        Task {
            let directory = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(2))
            NSApp.activate(ignoringOtherApps: true)
            note(dir, "windows \(NSApp.windows.map { "\($0.isVisible) \($0.canBecomeMain)" })")
            // A window the user closed stays closed for a new copy of the app, so ask for one.
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
                try? await Task.sleep(for: .seconds(2))
            }
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { exit(1) }
            window.setContentSize(NSSize(width: 1280, height: 860))
            let shots: [(String, String, KaiSettingsView.Page)] = [
                ("Welcome", "welcome", .ai),
                ("Chat", "chat", .ai),
                ("ForYou", "foryou", .ai),
                ("Calendar", "calendar", .ai),
                ("Mail", "mail", .ai),
                ("Notes", "notes", .ai),
                ("Sidekick", "sidekick", .ai),
                ("Health", "health", .ai),
                ("Permissions", "permissions", .ai),
                ("Settings", "settings-ai", .ai),
                ("Settings", "settings-system", .system)
            ]
            for (sidebar, name, page) in shots {
                KaiSettingsView.startPage = page
                appState.activeSidebar = "Health"
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
