//
//  KaiKnowledgeGraph.swift
//  Kai Knowledge
//
//  Connects what Kai knows into a graph you can look at: documents are dots, and a line joins two that
//  are about the same things (they share rare words, or one links to the other by name). The layout is
//  a force simulation: lines pull their ends together, every dot pushes the others away. Plain math, no
//  model, nothing leaves the Mac. Same input, same picture.
//

import Foundation

public struct KaiGraphNode: Identifiable, Equatable, Sendable {
    public let id: String          // source + "|" + sourceID
    public let index: Int
    public let title: String
    public let source: String
    public let sourceID: String
    public var degree: Int
    /// Position in the unit square, 0 to 1.
    public var x: Double
    public var y: Double
}

public struct KaiGraphEdge: Equatable, Sendable {
    public let a: Int
    public let b: Int
    /// 0 to 1: how strongly the two are related.
    public let weight: Double
}

public struct KaiKnowledgeGraph: Equatable, Sendable {
    public var nodes: [KaiGraphNode]
    public var edges: [KaiGraphEdge]

    public init(nodes: [KaiGraphNode] = [], edges: [KaiGraphEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }

    public static let maxNodes = 160
    static let stopWords: Set<String> = [
        "about", "above", "after", "again", "against", "also", "because", "been", "before", "being", "between", "both", "could", "does",
        "doing", "down", "during", "each", "from", "further", "have", "having", "here", "into", "just", "like", "more", "most", "much",
        "must", "only", "other", "over", "same", "should", "some", "such", "than", "that", "their", "them", "then", "there", "these",
        "they", "this", "those", "through", "under", "until", "very", "want", "were", "what", "when", "where", "which", "while", "will",
        "with", "would", "your", "you're", "i'll", "don't", "email", "message", "subject", "today", "tomorrow", "yesterday", "meeting",
    ]

    /// Lowercase words of four letters or more, without the filler, counted.
    public static func terms(_ text: String) -> [String: Double] {
        var counts: [String: Double] = [:]
        var word = ""
        func flush() {
            if word.count >= 4, !stopWords.contains(word), !word.allSatisfy(\.isNumber) { counts[word, default: 0] += 1 }
            word = ""
        }
        for character in text.lowercased() {
            if character.isLetter || character.isNumber || character == "'" { word.append(character) } else { flush() }
        }
        flush()
        return counts
    }

    /// Titles written as [[Title]] or as a link to another note's file name.
    static func links(in text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let open = rest.range(of: "[[") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "]]") else { break }
            found.append(String(after[..<close.lowerBound]).lowercased())
            rest = after[close.upperBound...]
        }
        return found
    }

    public static func build(documents all: [KaiKnowledgeDocument], threshold: Double = 0.16, maxPerNode: Int = 4) -> KaiKnowledgeGraph {
        let documents = Array(all.prefix(maxNodes))
        var nodes = documents.enumerated().map { index, d in
            KaiGraphNode(id: d.source + "|" + d.sourceID, index: index, title: d.title, source: d.source, sourceID: d.sourceID, degree: 0, x: 0.5, y: 0.5)
        }
        // Weight a word by how rare it is across documents, so common words do not join everything.
        let vectors = documents.map { d in terms(d.title + " " + d.title + " " + d.title + " " + String(d.text.prefix(2_500))) }
        var documentFrequency: [String: Int] = [:]
        for vector in vectors { for word in vector.keys { documentFrequency[word, default: 0] += 1 } }
        let count = Double(max(documents.count, 1))
        let weighted: [[String: Double]] = vectors.map { vector in
            var out: [String: Double] = [:]
            for (word, n) in vector {
                let df = Double(documentFrequency[word] ?? 1)
                if df > count * 0.5 && documents.count > 6 { continue }          // in most documents: says nothing
                out[word] = (1 + log(n)) * log(1 + count / df)
            }
            return out
        }
        // Sums are taken over words in alphabetical order. A dictionary hands its words out in a different order each
        // time, and adding decimals in a different order gives slightly different totals, so the picture would shift.
        let sorted: [[(word: String, value: Double)]] = weighted.map { $0.sorted { $0.key < $1.key }.map { (word: $0.key, value: $0.value) } }
        let norms = sorted.map { sqrt($0.reduce(0) { $0 + $1.value * $1.value }) }

        var candidates: [KaiGraphEdge] = []
        let byTitle = Dictionary(nodes.map { ($0.title.lowercased(), $0.index) }, uniquingKeysWith: { first, _ in first })
        for i in 0..<documents.count {
            for link in links(in: documents[i].text) {
                if let j = byTitle[link], j != i { candidates.append(KaiGraphEdge(a: min(i, j), b: max(i, j), weight: 1)) }
            }
            guard norms[i] > 0 else { continue }
            for j in (i + 1)..<max(documents.count, i + 1) where norms[j] > 0 {
                var dot = 0.0
                var x = 0, y = 0
                let (left, right) = (sorted[i], sorted[j])
                while x < left.count, y < right.count {
                    if left[x].word == right[y].word { dot += left[x].value * right[y].value; x += 1; y += 1 }
                    else if left[x].word < right[y].word { x += 1 } else { y += 1 }
                }
                let similarity = dot / (norms[i] * norms[j])
                if similarity >= threshold { candidates.append(KaiGraphEdge(a: i, b: j, weight: min(1, similarity))) }
            }
        }
        // Keep each dot's strongest lines only, so the picture stays readable.
        var kept: [KaiGraphEdge] = []
        var perNode = [Int](repeating: 0, count: documents.count)
        var seen = Set<[Int]>()
        for edge in candidates.sorted(by: { ($0.weight, -$0.a, -$0.b) > ($1.weight, -$1.a, -$1.b) }) {
            guard seen.insert([edge.a, edge.b]).inserted, perNode[edge.a] < maxPerNode, perNode[edge.b] < maxPerNode else { continue }
            perNode[edge.a] += 1; perNode[edge.b] += 1
            kept.append(edge)
        }
        for edge in kept { nodes[edge.a].degree += 1; nodes[edge.b].degree += 1 }
        var graph = KaiKnowledgeGraph(nodes: nodes, edges: kept)
        graph.layOut()
        return graph
    }

    /// Spreads the dots with a force simulation (Fruchterman and Reingold). Deterministic, and every dot ends
    /// up inside the unit square with a margin.
    public mutating func layOut(iterations: Int = 220) {
        let n = nodes.count
        guard n > 0 else { return }
        if n == 1 { nodes[0].x = 0.5; nodes[0].y = 0.5; return }
        // A fixed starting ring with a small repeatable wobble from the id.
        var px = [Double](repeating: 0, count: n), py = [Double](repeating: 0, count: n)
        for (i, node) in nodes.enumerated() {
            let wobble = Double(abs(node.id.hashValueStable % 1000)) / 1000
            let angle = 2 * Double.pi * (Double(i) + wobble * 0.5) / Double(n)
            let radius = 0.28 + 0.12 * wobble
            px[i] = 0.5 + radius * cos(angle); py[i] = 0.5 + radius * sin(angle)
        }
        let k = sqrt(1.0 / Double(n)) * 0.9
        var temperature = 0.12
        for _ in 0..<iterations {
            var dx = [Double](repeating: 0, count: n), dy = [Double](repeating: 0, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var ex = px[i] - px[j], ey = py[i] - py[j]
                    var distance = sqrt(ex * ex + ey * ey)
                    if distance < 0.0005 { ex = 0.001 * Double(i - j); ey = 0.001; distance = 0.0015 }
                    let push = (k * k) / distance
                    dx[i] += ex / distance * push; dy[i] += ey / distance * push
                    dx[j] -= ex / distance * push; dy[j] -= ey / distance * push
                }
            }
            for edge in edges {
                let ex = px[edge.a] - px[edge.b], ey = py[edge.a] - py[edge.b]
                let distance = max(sqrt(ex * ex + ey * ey), 0.0005)
                let pull = (distance * distance) / k * (0.5 + edge.weight)
                dx[edge.a] -= ex / distance * pull; dy[edge.a] -= ey / distance * pull
                dx[edge.b] += ex / distance * pull; dy[edge.b] += ey / distance * pull
            }
            for i in 0..<n {
                // A pull to the middle keeps unconnected dots from drifting off to the edge in a ring.
                let gravity = nodes[i].degree == 0 ? 0.12 : 0.03
                dx[i] += (0.5 - px[i]) * gravity; dy[i] += (0.5 - py[i]) * gravity
                let length = max(sqrt(dx[i] * dx[i] + dy[i] * dy[i]), 0.0001)
                let step = min(length, temperature)
                px[i] += dx[i] / length * step; py[i] += dy[i] / length * step
            }
            temperature = max(temperature * 0.965, 0.002)
        }
        // Stretch to fill the square, with a margin.
        let minX = px.min()!, maxX = px.max()!, minY = py.min()!, maxY = py.max()!
        let spanX = max(maxX - minX, 0.0001), spanY = max(maxY - minY, 0.0001)
        let margin = 0.06
        for i in 0..<n {
            nodes[i].x = margin + (px[i] - minX) / spanX * (1 - 2 * margin)
            nodes[i].y = margin + (py[i] - minY) / spanY * (1 - 2 * margin)
        }
    }
}

extension String {
    /// A hash that is the same on every run (Swift's own changes from run to run).
    var hashValueStable: Int {
        var h: UInt64 = 1469598103934665603
        for byte in utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return Int(truncatingIfNeeded: h >> 1)
    }
}
