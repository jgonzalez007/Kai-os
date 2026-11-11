//
//  KaiAgentRecipes.swift
//  Kai Agent
//
//  A recipe is a task that worked, kept under a name so it can be run again. It holds the task (with {blanks} for the
//  parts that change, such as {person}) and the steps that worked. When it runs, the steps go to the model as a guide,
//  not a script: the screen may look different next time, so each step is still checked against a fresh screenshot,
//  and every action still goes through the same safety rules and approvals. Typed text and web addresses are not
//  kept, so a recipe never carries yesterday's message or search into today's task.
//

import Foundation

public struct KaiAgentRecipe: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// What to do, in the person's words. A {blank} is filled in each time it runs.
    public var task: String
    /// The steps that worked, one line each.
    public var steps: [String]
    public var createdAt: Date
    public var lastRun: Date?
    public var runs: Int

    public init(id: String = UUID().uuidString, name: String, task: String, steps: [String], createdAt: Date = Date(), lastRun: Date? = nil, runs: Int = 0) {
        self.id = id
        self.name = name
        self.task = task
        self.steps = steps
        self.createdAt = createdAt
        self.lastRun = lastRun
        self.runs = runs
    }
}

public struct KaiAgentRecipeStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: KaiAgentRecipeStore {
        KaiAgentRecipeStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true).appendingPathComponent("sidekick-recipes.json"))
    }

    public func load() -> [KaiAgentRecipe] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([KaiAgentRecipe].self, from: data)) ?? []
    }

    public func save(_ recipes: [KaiAgentRecipe]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recipes).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum KaiAgentRecipes {
    public static let maxRecipes = 40
    public static let maxSteps = 25
    public static let maxStepLength = 140
    public static let maxNameLength = 60
    public static let maxTaskLength = 500

    // MARK: Making one from a run

    /// The steps of a run, in order: what was done, without what was typed and without web addresses.
    /// Waits, questions and the like are left out, and so is anything done twice in a row.
    public static func steps(from events: [KaiAgentEvent]) -> [String] {
        var steps: [String] = []
        for event in events {
            guard case .performed(_, let summary, _) = event, let step = generalized(summary) else { continue }
            if steps.last == step { continue }
            steps.append(step)
        }
        return Array(steps.prefix(maxSteps))
    }

    /// One step as a general instruction, or nil if it isn't worth keeping.
    static func generalized(_ summary: String) -> String? {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.hasPrefix("Wait ") || text.hasPrefix("You answered") || text.hasPrefix("Asked") || text.hasPrefix("Scroll") { return nil }
        if text.hasPrefix("Type “") { return "Type the text this task needs" }
        if text.hasPrefix("Open http") {
            let url = text.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let host = URL(string: url)?.host
            return "Open the web page this task needs" + (host.map { " on \($0)" } ?? "")
        }
        if text.hasPrefix("Click at (") || text.hasPrefix("Click item") || text.hasPrefix("Double-click at") || text.hasPrefix("Right-click at") { return nil }
        // An email address in a step (a note's title, a draft's recipient) is not kept.
        let masked = text.replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "an email address", options: .regularExpression)
        let flat = masked.components(separatedBy: .newlines).joined(separator: " ")
        return flat.count > maxStepLength ? String(flat.prefix(maxStepLength)) + "…" : flat
    }

    /// A name for the recipe, from what the person typed or, if nothing, from the start of the task.
    public static func cleanName(_ text: String, task: String) -> String {
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = task.trimmingCharacters(in: .whitespacesAndNewlines) }
        name = name.components(separatedBy: .newlines).joined(separator: " ")
        return String(name.prefix(maxNameLength))
    }

    public static func make(name: String, task: String, events: [KaiAgentEvent]) -> KaiAgentRecipe? {
        let steps = steps(from: events)
        let cleanTask = String(task.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTaskLength))
        guard !steps.isEmpty, !cleanTask.isEmpty else { return nil }
        return KaiAgentRecipe(name: cleanName(name, task: cleanTask), task: cleanTask, steps: steps)
    }

    /// Adds a recipe, or replaces the one with the same name. The newest come first, and the list is capped.
    public static func adding(_ recipe: KaiAgentRecipe, to recipes: [KaiAgentRecipe]) -> [KaiAgentRecipe] {
        var list = recipes.filter { $0.name.caseInsensitiveCompare(recipe.name) != .orderedSame }
        list.insert(recipe, at: 0)
        return Array(list.prefix(maxRecipes))
    }

    // MARK: Blanks

    /// The {blanks} in a task, in order, once each: "Send the status to {person} on {app}" → ["person", "app"].
    public static func blanks(in task: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"\{([A-Za-z][A-Za-z0-9 _-]{0,30})\}"#)
        let range = NSRange(task.startIndex..., in: task)
        var seen = Set<String>(), found: [String] = []
        for match in regex?.matches(in: task, range: range) ?? [] {
            guard let r = Range(match.range(at: 1), in: task) else { continue }
            let name = String(task[r])
            if seen.insert(name).inserted { found.append(name) }
        }
        return found
    }

    public static func filled(_ task: String, with values: [String: String]) -> String {
        var result = task
        for (name, value) in values {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).joined(separator: " ")
            result = result.replacingOccurrences(of: "{\(name)}", with: String(clean.prefix(200)))
        }
        return result
    }

    // MARK: For the model

    /// The steps that worked, as a guide below the safety rules. They can't change those rules or the approvals.
    public static func promptSection(_ recipe: KaiAgentRecipe) -> String {
        let steps = recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "A saved recipe for this kind of task, \"\(recipe.name)\", worked before. These are the steps that worked, in order. Use them as a guide, not a script: the screen may look different today, so check every screenshot, skip a step that is already done, and change any step that doesn't fit today's task. It never lets you do something the user did not ask for.\n\(steps)"
    }
}
