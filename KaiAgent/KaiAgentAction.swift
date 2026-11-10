import Foundation
import KaiShared

/// One thing the agent can do. Coordinates are pixels in the screenshot the model saw.
public enum KaiAgentAction: Equatable, Sendable {
    case click(x: Int, y: Int, double: Bool, right: Bool)
    /// A click on a numbered item of the latest screenshot. The runner turns it into a point.
    case clickElement(number: Int, double: Bool, right: Bool)
    case type(String)
    case key(KaiKeyCombo)
    case scroll(x: Int, y: Int, dx: Int, dy: Int)
    case wait(seconds: Double)
    case openApp(String)
    /// A direct tool: it does the job without the screen (make a note, add an event, look something up).
    case tool(name: String, arguments: [String: String])
    case finish(String)

    public var summary: String {
        switch self {
        case .click(let x, let y, let double, let right):
            return "\(right ? "Right-click" : double ? "Double-click" : "Click") at (\(x), \(y))"
        case .clickElement(let number, let double, let right):
            return "\(right ? "Right-click" : double ? "Double-click" : "Click") item \(number)"
        case .type(let text):
            let shown = text.count > 60 ? String(text.prefix(60)) + "…" : text
            return "Type “\(shown.replacingOccurrences(of: "\n", with: "⏎"))”"
        case .key(let combo): return "Press \(combo.display)"
        case .scroll(_, _, let dx, let dy): return "Scroll \(dy != 0 ? (dy > 0 ? "down" : "up") : (dx > 0 ? "right" : "left"))"
        case .wait(let seconds): return "Wait \(seconds.formatted()) s"
        case .openApp(let name): return "Open \(name)"
        case .tool(let name, let arguments): return KaiAgentTools.summary(name: name, arguments: arguments)
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

    /// Tools that only read, so they run without asking. The rest make something, so each one asks first.
    public static let readOnlyTools: Set<String> = ["read_calendar", "search_files"]
    public static let directToolNames = ["open_url", "create_note", "add_calendar_event", "compose_mail_draft", "read_calendar", "search_files"]
    public static let names = ["computer_click", "computer_type", "computer_key", "computer_scroll", "computer_wait", "computer_open_app", "computer_new_tab", "computer_new_window", "computer_address_bar"] + directToolNames + ["task_complete"]

    /// The text of a note as HTML for Apple Notes, with the title as its heading. Characters that mean something in HTML
    /// are escaped, so a title or body can't add markup of its own.
    public static func noteHTML(title: String, body: String) -> String {
        func html(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let lines = body.components(separatedBy: .newlines).map { $0.isEmpty ? "<div><br></div>" : "<div>\(html($0))</div>" }
        return "<div><h1>\(html(title))</h1></div>" + lines.joined()
    }

    static func short(_ text: String?, _ limit: Int = 50) -> String {
        let one = (text ?? "").components(separatedBy: .newlines).joined(separator: " ")
        return one.count > limit ? String(one.prefix(limit)) + "…" : one
    }

    public static func summary(name: String, arguments a: [String: String]) -> String {
        switch name {
        case "open_url": return "Open \(short(a["url"], 80)) in the browser"
        case "create_note": return "Make a note called “\(short(a["title"]))” in Notes"
        case "add_calendar_event": return "Add “\(short(a["title"]))” to Calendar at \(short(a["start"]))"
        case "compose_mail_draft": return "Open a mail draft to \(short(a["to"])) about “\(short(a["subject"]))”"
        case "read_calendar": return "Read your calendar for the next \(a["days"] ?? "3") days"
        case "search_files": return "Search your files for “\(short(a["query"]))”"
        default: return name
        }
    }

    public static let definitions: [KaiOllamaTool] = [
        KaiOllamaTool(name: "computer_click", description: "Click a numbered item from the list under the screenshot (give element), or a point on the screenshot (give x and y).",
                      parameters: [
                        .init(name: "element", type: "integer", description: "The number of the item to click, as listed and drawn on the screenshot", required: false),
                        .init(name: "x", type: "integer", description: "Pixels from the left edge of the screenshot, when there is no element number", required: false),
                        .init(name: "y", type: "integer", description: "Pixels from the top edge of the screenshot, when there is no element number", required: false),
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
        KaiOllamaTool(name: "computer_new_tab", description: "Open a new tab in the front browser (⌘T), so the page that was open is left alone.", parameters: []),
        KaiOllamaTool(name: "computer_new_window", description: "Open a new window in the front app (⌘N).", parameters: []),
        KaiOllamaTool(name: "computer_address_bar", description: "Move the cursor to the browser's address bar (⌘L). Then type an address and press return.", parameters: []),
        KaiOllamaTool(name: "open_url", description: "Open a web address in the browser. Use it instead of typing into the address bar.",
                      parameters: [.init(name: "url", type: "string", description: "A full http or https address", required: true)]),
        KaiOllamaTool(name: "create_note", description: "Make a new note in Apple Notes without opening the app. Much faster than clicking.",
                      parameters: [
                        .init(name: "title", type: "string", description: "The note's title", required: true),
                        .init(name: "body", type: "string", description: "The note's text", required: false)]),
        KaiOllamaTool(name: "add_calendar_event", description: "Add an event to Apple Calendar without opening the app.",
                      parameters: [
                        .init(name: "title", type: "string", description: "The event's title", required: true),
                        .init(name: "start", type: "string", description: "When it starts, as local time like 2026-11-12T15:00:00", required: true),
                        .init(name: "minutes", type: "integer", description: "How long it lasts. Defaults to 60.", required: false),
                        .init(name: "location", type: "string", description: "Where it is", required: false)]),
        KaiOllamaTool(name: "compose_mail_draft", description: "Open a new mail draft in Apple Mail with the recipient, subject and text filled in. It is never sent: the user reads it and sends it themselves.",
                      parameters: [
                        .init(name: "to", type: "string", description: "Email addresses, separated by commas", required: true),
                        .init(name: "subject", type: "string", description: "The subject", required: true),
                        .init(name: "body", type: "string", description: "The message text", required: false)]),
        KaiOllamaTool(name: "read_calendar", description: "Read the user's calendar events for the next few days. Use it to learn what is scheduled instead of opening Calendar.",
                      parameters: [.init(name: "days", type: "integer", description: "How many days, 1 to 14. Defaults to 3.", required: false)]),
        KaiOllamaTool(name: "search_files", description: "Find files on this Mac by name or content, using Spotlight. Returns names and paths.",
                      parameters: [.init(name: "query", type: "string", description: "Words to look for", required: true)]),
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
        case "computer_new_tab": return .success(.key(KaiKeyCombo(modifiers: [.command], key: "t")))
        case "computer_new_window": return .success(.key(KaiKeyCombo(modifiers: [.command], key: "n")))
        case "computer_address_bar": return .success(.key(KaiKeyCombo(modifiers: [.command], key: "l")))
        case "computer_click":
            if let number = int("element") {
                guard number >= 1, number <= KaiAgentElements.maxCount else { return .failure(.invalid("Item numbers go from 1 to \(KaiAgentElements.maxCount), as listed under the screenshot.")) }
                return .success(.clickElement(number: number, double: bool("double"), right: bool("right")))
            }
            guard let x = int("x"), let y = int("y") else { return .failure(.missing("an element number, or x and y")) }
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
        case "open_url":
            guard let url = string("url")?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { return .failure(.missing("url")) }
            guard url.count <= 2_000, let scheme = URL(string: url)?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return .failure(.invalid("Give a full http or https address."))
            }
            return .success(.tool(name: call.name, arguments: ["url": url]))
        case "create_note":
            guard let title = string("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return .failure(.missing("title")) }
            let body = string("body") ?? ""
            guard title.count <= 200, body.count <= 5_000 else { return .failure(.invalid("Keep the title under 200 characters and the text under 5,000.")) }
            return .success(.tool(name: call.name, arguments: ["title": title, "body": body]))
        case "add_calendar_event":
            guard let title = string("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return .failure(.missing("title")) }
            guard let start = string("start")?.trimmingCharacters(in: .whitespacesAndNewlines), !start.isEmpty else { return .failure(.missing("start")) }
            guard title.count <= 200, (string("location") ?? "").count <= 200 else { return .failure(.invalid("Keep the title and location under 200 characters.")) }
            var arguments = ["title": title, "start": start, "location": string("location") ?? ""]
            if let minutes = int("minutes") { arguments["minutes"] = String(minutes) }
            return .success(.tool(name: call.name, arguments: arguments))
        case "compose_mail_draft":
            guard let to = string("to")?.trimmingCharacters(in: .whitespacesAndNewlines), !to.isEmpty else { return .failure(.missing("to")) }
            guard let subject = string("subject")?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty else { return .failure(.missing("subject")) }
            let body = string("body") ?? ""
            guard subject.count <= 300, body.count <= 10_000, to.count <= 500 else { return .failure(.invalid("That draft is too long.")) }
            return .success(.tool(name: call.name, arguments: ["to": to, "subject": subject, "body": body]))
        case "read_calendar":
            return .success(.tool(name: call.name, arguments: ["days": String(min(max(int("days") ?? 3, 1), 14))]))
        case "search_files":
            guard let query = string("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return .failure(.missing("query")) }
            guard query.count <= 200 else { return .failure(.invalid("Keep the search under 200 characters.")) }
            return .success(.tool(name: call.name, arguments: ["query": query]))
        case "task_complete":
            return .success(.finish(string("summary") ?? "Done."))
        default:
            return .failure(.unknownTool(call.name))
        }
    }
}
