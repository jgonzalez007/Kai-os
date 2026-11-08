//
//  KaiHookEvent.swift
//  Kai Desk
//
//  What Kai reads from a Claude Code hook. Only a few fields are kept: the event, the project folder,
//  the tool and a short summary of what it will do. File contents and tool output are never read.
//

import Foundation

public enum KaiHookEventName: String, Sendable {
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case userPromptSubmit = "UserPromptSubmit"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case sessionEnd = "SessionEnd"
    case stopFailure = "StopFailure"
}

public struct KaiHookEvent: Equatable, Sendable {
    public static let maxSummary = 2_000

    public let name: KaiHookEventName
    public let sessionID: String
    public let cwd: String
    public let toolName: String?
    /// The command line, file path or a short list of fields. Capped at `maxSummary` characters.
    public let toolSummary: String?
    public let agentID: String?
    public let agentType: String?

    public init(name: KaiHookEventName, sessionID: String = "", cwd: String = "", toolName: String? = nil,
                toolSummary: String? = nil, agentID: String? = nil, agentType: String? = nil) {
        self.name = name
        self.sessionID = sessionID
        self.cwd = cwd
        self.toolName = toolName
        self.toolSummary = toolSummary
        self.agentID = agentID
        self.agentType = agentType
    }

    /// The folder name of the project, for the card title.
    public var project: String {
        let last = URL(fileURLWithPath: cwd).lastPathComponent
        return last.isEmpty || last == "/" ? "Claude Code" : last
    }

    /// Reads a hook payload. Returns nil for an unknown event or invalid JSON.
    public static func parse(_ data: Data) -> KaiHookEvent? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rawName = object["hook_event_name"] as? String,
              let name = KaiHookEventName(rawValue: rawName) else { return nil }
        let tool = object["tool_name"] as? String
        let input = object["tool_input"] as? [String: Any]
        return KaiHookEvent(
            name: name,
            sessionID: object["session_id"] as? String ?? "",
            cwd: object["cwd"] as? String ?? "",
            toolName: tool,
            toolSummary: name == .permissionRequest ? summary(tool: tool, input: input) : nil,
            agentID: object["agent_id"] as? String,
            agentType: object["agent_type"] as? String
        )
    }

    /// Picks the fields a person needs to judge the request. Contents of files being written are left out.
    static func summary(tool: String?, input: [String: Any]?) -> String? {
        guard let input else { return nil }
        func text(_ key: String) -> String? { (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let picked: String?
        switch tool {
        case "Bash": picked = text("command")
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit": picked = text("file_path") ?? text("notebook_path")
        case "WebFetch": picked = text("url")
        case "WebSearch": picked = text("query")
        case "Glob", "Grep": picked = text("pattern")
        case "Task", "Agent": picked = text("description") ?? text("prompt")
        default:
            let lines = input.keys.sorted().compactMap { key -> String? in
                guard let value = input[key] as? String else { return nil }
                let flat = value.count > 300 ? String(value.prefix(300)) + "…" : value
                return "\(key): \(flat)"
            }
            picked = lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        guard let picked else { return nil }
        return picked.count > maxSummary ? String(picked.prefix(maxSummary)) + "…" : picked
    }
}

public enum KaiHookDecision: Equatable, Sendable {
    case allow
    case deny

    /// The JSON Claude Code expects. Allow carries no changed input and no new permission rules.
    public var outputJSON: Data {
        let decision: [String: Any]
        switch self {
        case .allow: decision = ["behavior": "allow"]
        case .deny: decision = ["behavior": "deny", "message": "Denied by the user from Kai OS."]
        }
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}
