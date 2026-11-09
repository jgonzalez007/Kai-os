import Foundation

public enum KaiAgentMode: String, Codable, CaseIterable, Sendable {
    /// Every action that touches the Mac waits for the user's Approve.
    case askEach
    /// Clicks, typing and scrolling run on their own. Risky ones still ask.
    case auto
}

public enum KaiAgentDecision: Equatable, Sendable {
    case allow
    case needsApproval(String)
    case deny(String)
}

/// The rules that decide what runs. Nothing the model says, and nothing on the screen, can change them.
public struct KaiAgentPolicy: Sendable {
    /// Apps the agent never operates: terminals, password managers, system settings and scripting tools.
    public static let blockedBundleIdentifiers: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        "com.apple.systempreferences", "com.apple.Passwords", "com.apple.keychainaccess",
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal",
        "com.apple.ScriptEditor2", "com.apple.Automator", "com.apple.ActivityMonitor", "com.apple.Console",
    ]

    public let mode: KaiAgentMode
    /// Kai OS itself. The agent must never click its own Approve or Stop buttons.
    public let ownBundleIdentifier: String?

    public init(mode: KaiAgentMode, ownBundleIdentifier: String?) {
        self.mode = mode
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    /// Names of the apps in `blockedBundleIdentifiers`, as a person or a model would say them.
    static let blockedAppNames: Set<String> = [
        "terminal", "iterm", "iterm2", "warp", "ghostty", "kitty", "alacritty", "wezterm", "hyper",
        "system settings", "system preferences", "passwords", "keychain access", "1password", "1password 7", "bitwarden",
        "lastpass", "dashlane", "script editor", "automator", "activity monitor", "console",
    ]

    /// True for an app the agent must never open, by the name it was given.
    public static func isBlockedAppName(_ name: String) -> Bool {
        var n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasSuffix(".app") { n.removeLast(4) }
        return blockedAppNames.contains(n)
    }

    static let riskyKeys: Set<String> = ["return", "delete", "forwarddelete"]

    public func decide(_ action: KaiAgentAction, frontmostBundleIdentifier: String?) -> KaiAgentDecision {
        switch action {
        case .finish, .wait:
            return .allow
        default: break
        }

        // A direct tool doesn't touch the screen, so it doesn't depend on what is in front. Reading is allowed;
        // anything that makes something waits for the person, in both modes.
        if case .tool(let name, _) = action {
            return KaiAgentTools.readOnlyTools.contains(name) ? .allow : .needsApproval(action.summary)
        }

        // Opening an app does not depend on what is in front. It can never open one of the blocked apps.
        if case .openApp(let name) = action {
            if Self.isBlockedAppName(name) { return .deny("Kai never operates \(name).") }
            return mode == .askEach ? .needsApproval(action.summary) : .allow
        }

        guard let app = frontmostBundleIdentifier else { return .deny("Kai can't tell which app is in front, so it won't act.") }
        if Self.blockedBundleIdentifiers.contains(app) { return .deny("Kai never operates this app (\(app)).") }
        if app == ownBundleIdentifier { return .deny("Kai won't act while its own window is in front.") }

        switch action {
        case .scroll:
            return .allow
        case .click, .type, .key:
            if mode == .askEach { return .needsApproval(action.summary) }
            if let reason = riskReason(action) { return .needsApproval(reason) }
            return .allow
        default:
            return .allow
        }
    }

    /// Why an action needs a person even in automatic mode, or nil.
    func riskReason(_ action: KaiAgentAction) -> String? {
        switch action {
        case .type(let text):
            if text.contains("\n") || text.contains("\r") { return "This text includes a new line, which can send or submit." }
            return nil
        case .key(let combo):
            let command = combo.modifiers.contains(.command)
            let control = combo.modifiers.contains(.control)
            let option = combo.modifiers.contains(.option)
            if Self.riskyKeys.contains(combo.key) {
                return combo.key == "return" ? "Return can send or submit." : "Delete can remove things."
            }
            if command, ["q", "w", "space"].contains(combo.key) { return "\(combo.display) closes or launches things." }
            if command, control, combo.key == "q" { return "This locks the screen." }
            if command, option, combo.key == "escape" { return "This opens Force Quit." }
            if command, combo.key == "return" { return "⌘Return often sends." }
            return nil
        default:
            return nil
        }
    }
}
