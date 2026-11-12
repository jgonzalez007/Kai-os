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

/// A permission rule Claude Code offers with a request ("always allow this"), kept exactly as sent so
/// that it can be handed back unchanged. Only plain "allow these tools" rules are ever kept.
public struct KaiHookRule: Equatable, Sendable {
    /// One permission update, as JSON, exactly as Claude Code offered it.
    public let json: Data
    /// What it would allow, for the button: `Bash(npm test:*)`.
    public let summary: String
    /// Where Claude Code would save it: this session, or a settings file.
    public let destination: String

    static let destinations: Set<String> = ["session", "localSettings", "projectSettings", "userSettings"]

    /// Picks the first suggestion that only adds allow rules. A Bash rule without a command pattern would
    /// allow every command, so it is never offered; neither are mode changes.
    static func pick(from suggestions: [[String: Any]]?) -> KaiHookRule? {
        for item in suggestions ?? [] {
            guard item["type"] as? String == "addRules",
                  item["behavior"] as? String == "allow",
                  let destination = item["destination"] as? String, destinations.contains(destination),
                  let rules = item["rules"] as? [[String: Any]], !rules.isEmpty, rules.count <= 5 else { continue }
            var names: [String] = []
            var ok = true
            for rule in rules {
                guard let tool = rule["toolName"] as? String, !tool.isEmpty else { ok = false; break }
                let content = (rule["ruleContent"] as? String) ?? ""
                if tool == "Bash" && content.isEmpty { ok = false; break }
                names.append(content.isEmpty ? tool : "\(tool)(\(content))")
            }
            guard ok, let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]) else { continue }
            let text = names.joined(separator: ", ")
            return KaiHookRule(json: data, summary: text.count > 160 ? String(text.prefix(160)) + "…" : text, destination: destination)
        }
        return nil
    }
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
    /// The "always allow" rule Claude Code offered with this request, if it is a safe one.
    public let rule: KaiHookRule?

    public init(name: KaiHookEventName, sessionID: String = "", cwd: String = "", toolName: String? = nil,
                toolSummary: String? = nil, agentID: String? = nil, agentType: String? = nil, rule: KaiHookRule? = nil) {
        self.rule = rule
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
            agentType: object["agent_type"] as? String,
            rule: name == .permissionRequest ? KaiHookRule.pick(from: object["permission_suggestions"] as? [[String: Any]]) : nil
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
    /// Allow, and also save the rule Claude Code offered so it does not ask again.
    case alwaysAllow(KaiHookRule)
    case deny

    /// The JSON Claude Code expects. Plain allow carries no changed input and no new permission rules;
    /// only `alwaysAllow` adds the one rule Claude Code itself offered.
    public var outputJSON: Data {
        let decision: [String: Any]
        switch self {
        case .allow: decision = ["behavior": "allow"]
        case .alwaysAllow(let rule):
            var update: Any = [String: Any]()
            if let parsed = try? JSONSerialization.jsonObject(with: rule.json) { update = parsed }
            decision = ["behavior": "allow", "updatedPermissions": [update]]
        case .deny: decision = ["behavior": "deny", "message": "Denied by the user from Kai OS."]
        }
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}
