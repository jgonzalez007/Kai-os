//
//  KaiKnowledge.swift
//  Kai OS macOS
//
//  The knowledge base: what Kai has read, searchable on this Mac. The store and indexers
//  are in KaiKnowledge and covered by KaiChecksTests.
//

import AppKit
import Foundation
import KaiKnowledge
import KaiShared

extension AppState {
    static let knowledgeSourceNames = ["files": "Files", "notes": "Notes", "calendar": "Calendar", "mail": "Mail", "slack": "Slack"]

    var knowledgeFolder: URL { KaiKnowledgeIndexer.defaultFolder() }

    var knowledgeDocumentCount: Int { knowledgeCounts.values.reduce(0, +) }

    /// The store opens on first use. A failure to open is shown, not hidden.
    func openKnowledgeStore() -> KaiKnowledgeStore? {
        if let knowledge { return knowledge }
        do {
            let store = try KaiKnowledgeStore(url: KaiKnowledgeStore.defaultURL())
            knowledge = store
            return store
        } catch {
            knowledgeState = .failed("Couldn't open the knowledge base: \(error.localizedDescription)")
            return nil
        }
    }

    func refreshKnowledgeCounts() {
        guard let store = openKnowledgeStore() else { return }
        knowledgeCounts = (try? store.counts()) ?? [:]
    }

    func openKnowledgeFolder() {
        try? FileManager.default.createDirectory(at: knowledgeFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(knowledgeFolder)
    }

    /// Reads the Markdown folder and every connected source. One source failing does not stop the others.
    func indexKnowledge() {
        guard !isIndexingKnowledge else { return }
        Task { _ = await indexKnowledgeNow() }
    }

    /// The awaitable form, used by the button and by Night Shift. Returns what was read and what failed.
    func indexKnowledgeNow(folder: URL? = nil, sources chosen: Set<KaiNightShiftSource>? = nil) async -> (report: KaiIndexReport, failures: [String]) {
        guard !isIndexingKnowledge, let store = openKnowledgeStore() else { return (KaiIndexReport(), []) }
        isIndexingKnowledge = true
        knowledgeState = .loading
        let folder = folder ?? knowledgeFolder
        let chosen = chosen ?? nightShift.sources
        let window = nightShift.mailWindow
        let sources = (files: chosen.contains(.files), calendar: calendarConnected && chosen.contains(.calendar),
                       notes: notesConnected && chosen.contains(.notes), mail: mailConnected && chosen.contains(.mail),
                       slack: slackClient != nil && chosen.contains(.slack))
        var failures: [String] = []
        var report = KaiIndexReport()
        func attempt(_ name: String, _ work: () async throws -> KaiIndexReport) async {
            do { report.merge(try await work()) } catch { failures.append("\(name): \(error.localizedDescription)") }
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if sources.files { await attempt("Files") { try KaiKnowledgeIndexer.indexFolder(folder, into: store) } }
        if sources.calendar { await attempt("Calendar") { try KaiKnowledgeIndexer.indexCalendar(into: store) } }
        if sources.notes { await attempt("Notes") { try await KaiKnowledgeIndexer.indexNotes(into: store) } }
        if sources.mail { await attempt("Mail") { try await KaiKnowledgeIndexer.indexMail(into: store, since: window.since()) } }
        if sources.slack { await attempt("Slack") { try await indexSlack(into: store) } }
        refreshKnowledgeCounts()
        isIndexingKnowledge = false
        knowledgeState = failures.isEmpty ? .connected : .failed(failures.joined(separator: "\n"))
        return (report, failures)
    }

    /// The assistant's view of a search: untrusted text, labelled by where it came from.
    func knowledgeTool(query: String?) -> String {
        guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return "Give a few words to search for." }
        guard let store = openKnowledgeStore() else { return "The knowledge base could not be opened." }
        guard ((try? store.count()) ?? 0) > 0 else {
            return "The knowledge base is empty. Tell the user to click Index now under Knowledge base in Settings."
        }
        guard let hits = try? store.search(query, limit: 8), !hits.isEmpty else { return "Nothing in the knowledge base matched." }
        return hits.map { hit in
            let source = Self.knowledgeSourceNames[hit.source] ?? hit.source
            let date = hit.modified.map { " (\($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
            return "[\(source)] \(hit.title)\(date)\n\(hit.snippet)"
        }.joined(separator: "\n\n")
    }
}
