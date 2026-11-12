//
//  KaiVaultIndex.swift
//  Kai Knowledge
//
//  Reading the linked notes: the graph drawn from their [[links]], a search over their text, and reading one by
//  title. Everything resolves a note by its name from the folder's own list, never from a path someone typed, so
//  nothing outside the folder can be reached.
//

import Foundation

public struct KaiNoteHit: Equatable, Sendable {
    public let title: String
    public let path: String
    public let snippet: String
}

public enum KaiVaultIndex {
    public static let maxReadCharacters = 6_000

    /// The text of every note, by path. Notes are small, so the folder is read whole.
    static func contents(of vault: URL) -> [(path: String, title: String, text: String)] {
        let base = vault.resolvingSymlinksInPath()
        return KaiVault.notes(in: vault).compactMap { note in
            guard let text = try? String(contentsOf: base.appendingPathComponent(note.path), encoding: .utf8) else { return nil }
            return (note.path, note.title, text)
        }
    }

    /// The links in a note, as the titles they point at (alias and heading dropped).
    public static func links(in text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let open = rest.range(of: "[[") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "]]") else { break }
            let inner = String(after[..<close.lowerBound])
            let target = inner.split(separator: "|", maxSplits: 1).first.map(String.init) ?? inner
            let page = target.split(separator: "#", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? target
            if !page.isEmpty { out.append(page) }
            rest = after[close.upperBound...]
        }
        return out
    }

    /// The notes as a graph: a dot for each note, a line for each link between two notes.
    public static func graph(vault: URL) -> KaiKnowledgeGraph {
        let notes = contents(of: vault).filter { $0.path != KaiVault.overviewName }.prefix(KaiKnowledgeGraph.maxNodes)
        var nodes = notes.enumerated().map { index, note in
            KaiGraphNode(id: "vault|" + note.path, index: index, title: note.title,
                         source: "vault-" + (note.path.split(separator: "/").count > 1 ? String(note.path.split(separator: "/")[0]).lowercased() : "other"),
                         sourceID: note.path, degree: 0, x: 0.5, y: 0.5)
        }
        var byTitle: [String: Int] = [:]
        for node in nodes { byTitle[KaiVault.normalized(node.title)] = node.index }
        var seen = Set<[Int]>()
        var edges: [KaiGraphEdge] = []
        for (index, note) in notes.enumerated() {
            for target in links(in: note.text) {
                guard let other = byTitle[KaiVault.normalized(target)], other != index, seen.insert([min(index, other), max(index, other)]).inserted else { continue }
                edges.append(KaiGraphEdge(a: min(index, other), b: max(index, other), weight: 1))
            }
        }
        for edge in edges { nodes[edge.a].degree += 1; nodes[edge.b].degree += 1 }
        var graph = KaiKnowledgeGraph(nodes: nodes, edges: edges)
        graph.layOut()
        return graph
    }

    /// Notes that match every word of the query, best first: a word in the title counts more than one in the text.
    public static func search(vault: URL, query: String, limit: Int = 6) -> [KaiNoteHit] {
        let words = KaiSearchQuery.words(query)
        guard !words.isEmpty else { return [] }
        var scored: [(Int, KaiNoteHit)] = []
        for note in contents(of: vault) where note.path != KaiVault.overviewName {
            let lowerText = note.text.lowercased(), lowerTitle = note.title.lowercased()
            guard words.allSatisfy({ lowerText.contains($0) || lowerTitle.contains($0) }) else { continue }
            let score = words.reduce(0) { $0 + (lowerTitle.contains($1) ? 5 : 0) + min(lowerText.components(separatedBy: $1).count - 1, 4) }
            let body = note.text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst().joined(separator: " ")
            let first = words.first.flatMap { body.lowercased().range(of: $0) }
            let start = first.map { body.index($0.lowerBound, offsetBy: -60, limitedBy: body.startIndex) ?? body.startIndex } ?? body.startIndex
            scored.append((score, KaiNoteHit(title: note.title, path: note.path, snippet: String(body[start...].prefix(220)))))
        }
        return scored.sorted { ($0.0, $1.1.title) > ($1.0, $0.1.title) }.prefix(limit).map(\.1)
    }

    /// One note by its title, cut to a size a model can read. Nil when there is no note of that name.
    public static func read(vault: URL, title: String) -> String? {
        let key = KaiVault.normalized(title.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: ""))
        guard !key.isEmpty, let note = contents(of: vault).first(where: { KaiVault.normalized($0.title) == key }) else { return nil }
        return String(note.text.prefix(maxReadCharacters))
    }
}
