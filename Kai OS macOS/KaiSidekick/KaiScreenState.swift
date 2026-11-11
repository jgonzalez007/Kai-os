//
//  KaiScreenState.swift
//  Kai OS macOS
//
//  What is on the Mac besides the picture: which app is in front, which window, which apps are open with no window
//  on screen. A screenshot alone can't say that an app opened behind another or has no window, and a small model
//  that can't tell keeps pressing "Open Safari". Read-only: window titles and app names only, never what is in them.
//

import AppKit

enum KaiScreenState {
    /// On-screen windows of ordinary size, per process, with the title of the first one that has a name.
    private static func windows() -> [pid_t: (count: Int, title: String?)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var result: [pid_t: (count: Int, title: String?)] = [:]
        for window in list where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32 else { continue }
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat], (bounds["Width"] ?? 0) < 80 || (bounds["Height"] ?? 0) < 60 { continue }
            var entry = result[pid] ?? (0, nil)
            entry.count += 1
            if entry.title == nil, let name = window[kCGWindowName as String] as? String, !name.isEmpty { entry.title = name }
            result[pid] = entry
        }
        return result
    }

    static func windowCount(pid: pid_t) -> Int { windows()[pid]?.count ?? 0 }

    /// Waits until the app is the front one, asking it to come forward again now and then. False if it never does.
    static func waitUntilFront(_ app: NSRunningApplication, seconds: Double = 4) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        var asked = 0
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return true }
            if asked < 3 { app.activate(); asked += 1 }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// Waits for the app to have a window on screen. False if none appears.
    static func waitForWindow(of app: NSRunningApplication, seconds: Double = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if windowCount(pid: app.processIdentifier) > 0 { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return windowCount(pid: app.processIdentifier) > 0
    }

    /// One or two lines: the app in front and its window, then the other apps that matter.
    static func note(ownBundleIdentifier: String? = Bundle.main.bundleIdentifier) -> String? {
        let all = windows()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        var lines: [String] = []
        if let front = NSWorkspace.shared.frontmostApplication {
            let name = front.localizedName ?? "an app"
            if front.bundleIdentifier == ownBundleIdentifier {
                lines.append("Front app: Kai OS itself. Kai won't act while its own window is in front.")
            } else if let entry = all[front.processIdentifier] {
                let title = entry.title.map { ", window “\(KaiAgentTextCleaner.line($0))”" } ?? ""
                lines.append("Front app: \(name)\(title)\(entry.count > 1 ? " (\(entry.count) windows)" : "").")
            } else {
                lines.append("Front app: \(name), but it has no window on screen.")
            }
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let others = apps.filter { $0.processIdentifier != frontPID && $0.bundleIdentifier != ownBundleIdentifier }
        let showing = others.filter { all[$0.processIdentifier] != nil }.compactMap(\.localizedName).prefix(6)
        // Finder is always running with no window, which says nothing.
        let hidden = others.filter { all[$0.processIdentifier] == nil && $0.bundleIdentifier != "com.apple.finder" }.compactMap(\.localizedName).prefix(6)
        if !showing.isEmpty { lines.append("Other apps with a window on screen: \(showing.joined(separator: ", ")).") }
        if !hidden.isEmpty { lines.append("Open but with no window on screen (hidden, minimized or on another desktop): \(hidden.joined(separator: ", ")).") }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}

/// Window titles come from other apps: one short line, nothing that looks like a new instruction block.
enum KaiAgentTextCleaner {
    static func line(_ text: String, limit: Int = 70) -> String {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ").replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
