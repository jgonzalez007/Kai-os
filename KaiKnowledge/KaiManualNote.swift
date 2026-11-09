//
//  KaiManualNote.swift
//  Kai Knowledge
//
//  Something the person types in to tell Kai: saved as a plain Markdown file in the knowledge folder, so
//  it stays theirs to read, edit or delete, and found by the same search as everything else.
//

import Foundation

public enum KaiManualNote {
    public static let folderName = "Added by me"
    public static let maxLength = 20_000
    public static let maxTitle = 80

    public enum Failure: LocalizedError, Equatable {
        case empty
        public var errorDescription: String? { "Type something to add first." }
    }

    /// Control characters removed (new lines and tabs stay), trimmed, cut to the limit.
    public static func clean(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength).description
    }

    /// The given title, or the first line of the text, cut short.
    public static func title(_ given: String, text: String) -> String {
        let candidate = clean(given).replacingOccurrences(of: "\n", with: " ")
        let fallback = clean(text).split(separator: "\n").first.map(String.init) ?? "Note"
        let chosen = candidate.isEmpty ? fallback : candidate
        return chosen.count > maxTitle ? String(chosen.prefix(maxTitle)) + "…" : chosen
    }

    /// 2026-11-09-0912-trip-ideas.md: letters and digits only in the name, so nothing can point outside the folder.
    public static func fileName(title: String, date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d-%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        var slug = ""
        var lastWasDash = true
        for scalar in title.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar); lastWasDash = false
            } else if !lastWasDash {
                slug += "-"; lastWasDash = true
            }
        }
        slug = String(slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(stamp)-\(slug.isEmpty ? "note" : slug).md"
    }

    public static func markdown(title: String, text: String) -> String {
        "# \(title)\n\n\(text)\n"
    }

    /// Writes the note into `<knowledge folder>/Added by me/` and returns the file. Never overwrites a file.
    @discardableResult
    public static func write(title given: String, text rawText: String, in knowledgeFolder: URL, date: Date = Date()) throws -> URL {
        let text = clean(rawText)
        guard !text.isEmpty else { throw Failure.empty }
        let title = title(given, text: text)
        let folder = knowledgeFolder.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = fileName(title: title, date: date)
        var url = folder.appendingPathComponent(base)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(base.replacingOccurrences(of: ".md", with: "-\(counter).md"))
            counter += 1
        }
        try markdown(title: title, text: text).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
