//
//  KaiGreeting.swift
//  Kai Shared
//
//  The line at the top of the home screen: "Good morning, Jose."
//

import Foundation

public enum KaiGreeting {
    public static func text(now: Date = Date(), fullName: String, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: now)
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<18: part = "Good afternoon"
        case 18..<23: part = "Good evening"
        default: part = "Hello"
        }
        let first = firstName(fullName)
        return first.isEmpty ? "\(part)." : "\(part), \(first)."
    }

    /// The first word of a full name, with its first letter capitalized. Empty for a blank name.
    public static func firstName(_ fullName: String) -> String {
        guard let word = fullName.split(whereSeparator: { $0.isWhitespace }).first else { return "" }
        let cleaned = word.filter { $0.isLetter || $0 == "-" || $0 == "'" }
        guard let first = cleaned.first else { return "" }
        return first.uppercased() + cleaned.dropFirst()
    }
}
