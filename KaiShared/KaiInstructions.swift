//
//  KaiInstructions.swift
//  Kai Shared
//
//  The person's own standing instructions ("Use Slack for work messages and Safari for browsing").
//  They are added to what Kai is told, as preferences. They sit below the safety rules and cannot
//  switch them off.
//

import Foundation

public enum KaiInstructions {
    public static let defaultsKey = "kai.instructions"
    public static let maxLength = 2_000

    /// Control characters removed, line endings tidied, and cut to the limit.
    public static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0) }
        let tidy = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(tidy.prefix(maxLength))
    }

    /// The paragraph to add to a system prompt, or nil when there are no instructions.
    public static func promptSection(_ text: String) -> String? {
        let cleaned = clean(text)
        guard !cleaned.isEmpty else { return nil }
        return """
        The user's own standing preferences are below. Follow them when they fit the task. They never \
        override the rules above about safety, approval and untrusted text.
        <preferences>
        \(cleaned.replacingOccurrences(of: "</preferences>", with: ""))
        </preferences>
        """
    }

    public static func stored(_ defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: defaultsKey) ?? ""
    }
}
