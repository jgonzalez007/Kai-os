import Foundation

/// The app lists models as "ollama: gemma4:e4b" or "openai: gpt-4o" so the picker shows
/// where each one runs. Providers want only the name after the prefix.
public enum KaiModelTag {
    public static let prefixes = ["ollama: ", "openai: ", "anthropic: "]

    public static func name(from tag: String) -> String {
        for prefix in prefixes where tag.hasPrefix(prefix) {
            return String(tag.dropFirst(prefix.count))
        }
        return tag
    }
}
