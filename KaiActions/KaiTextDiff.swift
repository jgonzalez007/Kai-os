//
//  KaiTextDiff.swift
//  Kai Actions
//
//  Shows what a suggested rewrite changed, one change at a time, so the person can keep some and skip others.
//  The text is cut into words and spaces, the words that stayed the same are found, and everything between them
//  is a change: what the original had, and what the suggestion has instead.
//

import Foundation

public struct KaiTextDiff: Equatable, Sendable {
    public enum Piece: Equatable, Sendable {
        case same(String)
        /// `old` may be empty (an addition) and so may `new` (a deletion). `index` counts the changes from 0.
        case change(index: Int, old: String, new: String)
    }

    public let pieces: [Piece]

    public var changeCount: Int { pieces.reduce(0) { if case .change = $1 { return $0 + 1 } else { return $0 } } }

    /// Longest text compared word by word; beyond this the whole text counts as one change.
    static let maxTokens = 2_500

    public init(original: String, suggestion: String) {
        let a = Self.tokens(original), b = Self.tokens(suggestion)
        guard a.count <= Self.maxTokens, b.count <= Self.maxTokens else {
            pieces = original == suggestion ? [.same(original)] : [.change(index: 0, old: original, new: suggestion)]
            return
        }
        // Longest common subsequence of tokens.
        var table = [[Int32]](repeating: [Int32](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        enum Op { case equal(String), delete(String), insert(String) }
        var ops: [Op] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] { ops.append(.equal(a[i])); i += 1; j += 1 }
            else if j < b.count, i == a.count || table[i][j + 1] >= table[i + 1][j] { ops.append(.insert(b[j])); j += 1 }
            else { ops.append(.delete(a[i])); i += 1 }
        }
        // Group runs of deletes and inserts into changes. A single space between two changes joins them: "teh  cat" and "a  dog" read as one.
        var groups: [(same: String?, old: String, new: String)] = []
        var old = "", new = "", inChange = false
        func flush() { if inChange { groups.append((nil, old, new)); old = ""; new = ""; inChange = false } }
        for op in ops {
            switch op {
            case .equal(let token):
                flush()
                if let last = groups.last, last.same != nil { groups[groups.count - 1].same = last.same! + token } else { groups.append((token, "", "")) }
            case .delete(let token): old += token; inChange = true
            case .insert(let token): new += token; inChange = true
            }
        }
        flush()
        var merged: [(same: String?, old: String, new: String)] = []
        var position = 0
        while position < groups.count {
            var group = groups[position]
            if group.same == nil {
                while position + 2 < groups.count, let gap = groups[position + 1].same, gap.count <= 1, gap.allSatisfy(\.isWhitespace), groups[position + 2].same == nil {
                    group.old += gap + groups[position + 2].old
                    group.new += gap + groups[position + 2].new
                    position += 2
                }
            }
            merged.append(group)
            position += 1
        }
        var index = 0
        pieces = merged.map { group in
            if let same = group.same { return .same(same) }
            defer { index += 1 }
            return .change(index: index, old: group.old, new: group.new)
        }
    }

    /// The text with every change in `accepted` taken from the suggestion, and every other change left as the original.
    public func text(accepting accepted: Set<Int>) -> String {
        pieces.map { piece in
            switch piece {
            case .same(let text): return text
            case .change(let index, let old, let new): return accepted.contains(index) ? new : old
            }
        }.joined()
    }

    /// Words and the spaces between them, each its own token, so joining the tokens gives the text back.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSpace: Bool?
        for character in text {
            let space = character.isWhitespace
            if inSpace != nil, inSpace != space { result.append(current); current = "" }
            current.append(character)
            inSpace = space
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
