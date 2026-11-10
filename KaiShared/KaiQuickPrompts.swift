//
//  KaiQuickPrompts.swift
//  Kai Shared
//
//  Prompts the person saved to run on text they select: "Make it concise", "Translate to Spanish". Each is a name
//  and one instruction. They appear under Rewrite in the notch, and run on the selected text with the answer shown
//  as a suggestion that only replaces the original after approval.
//

import Foundation

public struct KaiQuickPrompt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var instruction: String

    public init(id: String = UUID().uuidString, name: String, instruction: String) {
        self.id = id
        self.name = name
        self.instruction = instruction
    }
}

public enum KaiQuickPrompts {
    public static let defaultsKey = "kai.quickPrompts"
    public static let maxPrompts = 12
    public static let maxName = 30
    public static let maxInstruction = 600

    public static let starters: [KaiQuickPrompt] = [
        KaiQuickPrompt(id: "starter-concise", name: "Make it concise", instruction: "Rewrite the text so it says the same thing in about half the words. Keep every fact, name, date and number."),
        KaiQuickPrompt(id: "starter-simple", name: "Explain simply", instruction: "Rewrite the text in plain, simple words a smart newcomer would follow. Keep every fact."),
        KaiQuickPrompt(id: "starter-bullets", name: "Turn into bullets", instruction: "Turn the text into short bullet points, one idea each, keeping every fact, name, date and number."),
        KaiQuickPrompt(id: "starter-spanish", name: "Translate to Spanish", instruction: "Translate the text into natural Spanish. Keep names, numbers and links as they are."),
    ]

    /// One line, no control characters, cut to length. Nil when nothing is left.
    public static func clean(_ text: String, limit: Int) -> String? {
        let scalars = text.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0) }
        let tidy = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return tidy.isEmpty ? nil : String(tidy.prefix(limit))
    }

    public static func make(name: String, instruction: String) -> KaiQuickPrompt? {
        guard let n = clean(name.replacingOccurrences(of: "\n", with: " "), limit: maxName), let i = clean(instruction, limit: maxInstruction) else { return nil }
        return KaiQuickPrompt(name: n, instruction: i)
    }

    /// The saved list, or the starters when the person has not saved any yet.
    public static func stored(_ defaults: UserDefaults = .standard) -> [KaiQuickPrompt] {
        guard let data = defaults.data(forKey: defaultsKey), let list = try? JSONDecoder().decode([KaiQuickPrompt].self, from: data) else { return starters }
        return list
    }

    public static func save(_ list: [KaiQuickPrompt], _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(Array(list.prefix(maxPrompts))), forKey: defaultsKey)
    }
}
