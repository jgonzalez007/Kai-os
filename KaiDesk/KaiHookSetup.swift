//
//  KaiHookSetup.swift
//  Kai Desk
//
//  The text a person pastes into ~/.claude/settings.json to connect Claude Code. Kai OS never
//  edits that file: it only shows this text and lets you copy it.
//

import Foundation

public enum KaiHookSetup {
    /// Event name, matcher (nil for none) and timeout in seconds.
    static let entries: [(event: String, matcher: String?, timeout: Int)] = [
        ("PermissionRequest", "*", 75),
        ("Stop", nil, 10),
        ("UserPromptSubmit", nil, 10),
        ("SubagentStart", nil, 10),
        ("SubagentStop", nil, 10),
        ("StopFailure", nil, 10),
        ("SessionEnd", nil, 10)
    ]

    /// The path wrapped in single quotes, safe for a shell command even with spaces ("Kai OS.app").
    public static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A complete `{"hooks": {...}}` block, pretty printed.
    public static func settingsSnippet(helperPath: String) -> String {
        var hooks: [String: Any] = [:]
        for entry in entries {
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": shellQuoted(helperPath), "timeout": entry.timeout] as [String: Any]]
            ]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            hooks[entry.event] = [group]
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\\/", with: "/") ?? "{}"
    }

    public static let events: [String] = entries.map(\.event)
}
