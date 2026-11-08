import Foundation
import KaiShared

/// One thing the agent can do. Coordinates are pixels in the screenshot the model saw.
public enum KaiAgentAction: Equatable, Sendable {
    case click(x: Int, y: Int, double: Bool, right: Bool)
    case type(String)
    case key(KaiKeyCombo)
    case scroll(x: Int, y: Int, dx: Int, dy: Int)
    case wait(seconds: Double)
    case openApp(String)
    case finish(String)

    public var summary: String {
        switch self {
        case .click(let x, let y, let double, let right):
            return "\(right ? "Right-click" : double ? "Double-click" : "Click") at (\(x), \(y))"
        case .type(let text):
            let shown = text.count > 60 ? String(text.prefix(60)) + "…" : text
            return "Type “\(shown.replacingOccurrences(of: "\n", with: "⏎"))”"
        case .key(let combo): return "Press \(combo.display)"
        case .scroll(_, _, let dx, let dy): return "Scroll \(dy != 0 ? (dy > 0 ? "down" : "up") : (dx > 0 ? "right" : "left"))"
        case .wait(let seconds): return "Wait \(seconds.formatted()) s"
        case .openApp(let name): return "Open \(name)"
        case .finish(let text): return "Finish: \(text)"
        }
    }
}

public struct KaiKeyCombo: Equatable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable { case command, option, control, shift }

    public let modifiers: Set<Modifier>
    public let key: String

    public init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Keys the agent may press, besides single letters and digits.
    public static let namedKeys: Set<String> = [
        "return", "tab", "space", "escape", "delete", "forwarddelete", "up", "down", "left", "right",
        "home", "end", "pageup", "pagedown",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    ]

    /// "cmd+shift+4", "return", "option+left". Nil when anything in it is unknown.
    public static func parse(_ text: String) -> KaiKeyCombo? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, !key.isEmpty else { return nil }
        var modifiers = Set<Modifier>()
        for name in parts.dropLast() {
            switch name {
            case "cmd", "command", "super", "meta": modifiers.insert(.command)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        let normalized = ["enter": "return", "esc": "escape", "backspace": "delete", "del": "forwarddelete"][key] ?? key
        guard namedKeys.contains(normalized) || (normalized.count == 1 && normalized.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else {
            return nil
        }
        return KaiKeyCombo(modifiers: modifiers, key: normalized)
    }

    public var display: String {
        let symbols: [(Modifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key
    }
}

public enum KaiAgentParseError: Error, Equatable, Sendable {
    case unknownTool(String)
    case missing(String)
    case invalid(String)

    public var message: String {
        switch self {
        case .unknownTool(let name): return "There is no action called \(name)."
        case .missing(let field): return "The action needs \(field)."
        case .invalid(let why): return why
        }
    }
}

public enum KaiAgentTools {
    public static let maxTextLength = 500
    public static let maxWaitSeconds = 10.0

    public static let names = ["computer_click", "computer_type", "computer_key", "computer_scroll", "computer_wait", "computer_open_app", "task_complete"]

    public static let definitions: [KaiOllamaTool] = [
        KaiOllamaTool(name: "computer_click", description: "Click at a point on the screenshot. x and y are pixels in the latest screenshot.",
                      parameters: [
                        .init(name: "x", type: "integer", description: "Pixels from the left edge of the screenshot", required: true),
                        .init(name: "y", type: "integer", description: "Pixels from the top edge of the screenshot", required: true),
                        .init(name: "double", type: "boolean", description: "True to double-click", required: false),
                        .init(name: "right", type: "boolean", description: "True to right-click", required: false)]),
        KaiOllamaTool(name: "computer_type", description: "Type text into the focused field. Click the field first.",
                      parameters: [.init(name: "text", type: "string", description: "The text to type", required: true)]),
        KaiOllamaTool(name: "computer_key", description: "Press a key or shortcut, such as return, tab, escape, cmd+c or cmd+shift+4.",
                      parameters: [.init(name: "keys", type: "string", description: "Modifiers joined with +, then the key", required: true)]),
        KaiOllamaTool(name: "computer_scroll", description: "Scroll the page or list under a point.",
                      parameters: [
                        .init(name: "x", type: "integer", description: "Pixels from the left edge of the screenshot", required: true),
                        .init(name: "y", type: "integer", description: "Pixels from the top edge of the screenshot", required: true),
                        .init(name: "direction", type: "string", description: "up, down, left or right", required: true),
                        .init(name: "amount", type: "integer", description: "How far, from 1 to 10. Defaults to 3.", required: false)]),
        KaiOllamaTool(name: "computer_wait", description: "Wait for something to load, up to 10 seconds.",
                      parameters: [.init(name: "seconds", type: "number", description: "Seconds to wait", required: true)]),
        KaiOllamaTool(name: "computer_open_app", description: "Open or switch to an app by name, such as Notes, Safari or Mail. Use this instead of hunting for an app icon.",
                      parameters: [.init(name: "name", type: "string", description: "The app's name", required: true)]),
        KaiOllamaTool(name: "task_complete", description: "Call this when the task is done, or when you cannot continue. Say what happened.",
                      parameters: [.init(name: "summary", type: "string", description: "What was done, or why you stopped", required: true)]),
    ]

    public static func parse(_ call: KaiOllamaToolCall) -> Result<KaiAgentAction, KaiAgentParseError> {
        func int(_ name: String) -> Int? { call.arguments[name]?.intValue }
        func string(_ name: String) -> String? { call.arguments[name]?.stringValue }
        func number(_ name: String) -> Double? {
            switch call.arguments[name] {
            case .number(let value): return value
            case .string(let text): return Double(text)
            default: return nil
            }
        }
        func bool(_ name: String) -> Bool {
            switch call.arguments[name] {
            case .bool(let value): return value
            case .string(let text): return text.lowercased() == "true"
            case .number(let value): return value != 0
            default: return false
            }
        }
        switch call.name {
        case "computer_click":
            guard let x = int("x"), let y = int("y") else { return .failure(.missing("x and y")) }
            guard x >= 0, y >= 0 else { return .failure(.invalid("x and y must be inside the screenshot.")) }
            return .success(.click(x: x, y: y, double: bool("double"), right: bool("right")))
        case "computer_type":
            guard let text = string("text"), !text.isEmpty else { return .failure(.missing("text")) }
            guard text.count <= maxTextLength else { return .failure(.invalid("Type at most \(maxTextLength) characters at a time.")) }
            return .success(.type(text))
        case "computer_key":
            guard let keys = string("keys") else { return .failure(.missing("keys")) }
            guard let combo = KaiKeyCombo.parse(keys) else { return .failure(.invalid("“\(keys)” is not a key I can press.")) }
            return .success(.key(combo))
        case "computer_scroll":
            guard let x = int("x"), let y = int("y"), let direction = string("direction")?.lowercased() else {
                return .failure(.missing("x, y and direction"))
            }
            guard x >= 0, y >= 0 else { return .failure(.invalid("x and y must be inside the screenshot.")) }
            let amount = min(max(int("amount") ?? 3, 1), 10)
            switch direction {
            case "down": return .success(.scroll(x: x, y: y, dx: 0, dy: amount))
            case "up": return .success(.scroll(x: x, y: y, dx: 0, dy: -amount))
            case "right": return .success(.scroll(x: x, y: y, dx: amount, dy: 0))
            case "left": return .success(.scroll(x: x, y: y, dx: -amount, dy: 0))
            default: return .failure(.invalid("direction must be up, down, left or right."))
            }
        case "computer_wait":
            guard let seconds = number("seconds") else { return .failure(.missing("seconds")) }
            return .success(.wait(seconds: min(max(seconds, 0), maxWaitSeconds)))
        case "computer_open_app":
            guard let name = string("name")?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return .failure(.missing("name")) }
            guard name.count <= 60, !name.contains("/"), !name.contains("\n") else { return .failure(.invalid("Give just the app's name.")) }
            return .success(.openApp(name))
        case "task_complete":
            return .success(.finish(string("summary") ?? "Done."))
        default:
            return .failure(.unknownTool(call.name))
        }
    }
}
