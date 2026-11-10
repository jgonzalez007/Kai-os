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
    static let knowledgeSourceNames = ["files": "Files", "folder": "Folders", "notes": "Notes", "calendar": "Calendar", "mail": "Mail", "slack": "Slack"]

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

    // MARK: Folders and files the person gives Kai

    private func saveKnowledgeFolders() {
        do { try KaiKnowledgeFolderList.standard.save(knowledgeFolders) } catch {
            knowledgeAddMessage = "Couldn't save the folder list: \(error.localizedDescription)"
        }
    }

    /// Adds a folder to read, then reads it. Returns why it can't be added, or nil.
    @discardableResult
    func addKnowledgeFolder(_ url: URL) -> String? {
        if let problem = KaiKnowledgeFolders.problem(adding: url, to: knowledgeFolders) { return problem }
        knowledgeFolders.append(KaiKnowledgeFolder(path: url.resolvingSymlinksInPath().standardizedFileURL.path))
        saveKnowledgeFolders()
        indexKnowledge()
        return nil
    }

    func removeKnowledgeFolder(_ id: String) {
        knowledgeFolders.removeAll { $0.id == id }
        knowledgeFolderResults[id] = nil
        saveKnowledgeFolders()
        indexKnowledge()
    }

    func setKnowledgeFolder(_ id: String, enabled: Bool) {
        guard let index = knowledgeFolders.firstIndex(where: { $0.id == id }) else { return }
        knowledgeFolders[index].enabled = enabled
        saveKnowledgeFolders()
        indexKnowledge()
    }

    /// Files and folders dropped on Kai or picked in a dialog. A folder joins the list; a file is copied into Uploads.
    func addKnowledgeItems(_ urls: [URL]) {
        var files: [URL] = []
        var lines: [String] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if let problem = addKnowledgeFolder(url) { lines.append("\(url.lastPathComponent): \(problem)") } else { lines.append("Added the folder “\(url.lastPathComponent)”.") }
            } else {
                files.append(url)
            }
        }
        if !files.isEmpty {
            let result = KaiKnowledgeFolders.upload(files, into: knowledgeFolder)
            if !result.copied.isEmpty { lines.append("Added \(result.copied.count) file\(result.copied.count == 1 ? "" : "s"): \(result.copied.prefix(3).joined(separator: ", "))\(result.copied.count > 3 ? "…" : "").") }
            lines += result.rejected
            if !result.copied.isEmpty { Task { _ = await indexKnowledgeNow(sources: [.files]) } }
        }
        knowledgeAddMessage = lines.joined(separator: "\n")
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

    /// Saves something the person typed as a Markdown file in the knowledge folder, then indexes it so Kai can find it.
    /// Returns a line to show, and whether it worked.
    func addManualKnowledge(title: String, text: String) async -> (message: String, ok: Bool) {
        do {
            let file = try KaiManualNote.write(title: title, text: text, in: knowledgeFolder)
            _ = await indexKnowledgeNow(sources: [.files])
            return ("Added “\(file.deletingPathExtension().lastPathComponent)”. Kai can find it now.", true)
        } catch {
            return (error.localizedDescription, false)
        }
    }

    /// The awaitable form, used by the button and by Night Shift. Returns what was read and what failed.
    func indexKnowledgeNow(folder: URL? = nil, sources chosen: Set<KaiNightShiftSource>? = nil) async -> (report: KaiIndexReport, failures: [String], sourceResults: [KaiNightShiftRecord.SourceResult]) {
        guard !isIndexingKnowledge, let store = openKnowledgeStore() else { return (KaiIndexReport(), [], []) }
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
        if sources.files {
            let folders = knowledgeFolders
            var results: [String: KaiFolderResult] = [:]
            await attempt("Files") {
                // Reading PDFs and pictures takes a while, so it never runs on the main thread.
                let outcome = try await Task.detached(priority: .utility) { () -> (KaiIndexReport, [String: KaiFolderResult]) in
                    var report = try KaiKnowledgeIndexer.indexFolder(folder, into: store)
                    let extra = try KaiKnowledgeIndexer.indexFolders(folders, into: store)
                    report.merge(extra.report)
                    return (report, extra.results)
                }.value
                results = outcome.1
                return outcome.0
            }
            knowledgeFolderResults = results
        }
        if sources.calendar { await attempt("Calendar") { try KaiKnowledgeIndexer.indexCalendar(into: store) } }
        if sources.notes { await attempt("Notes") { try await KaiKnowledgeIndexer.indexNotes(into: store) } }
        if sources.mail { await attempt("Mail") { try await KaiKnowledgeIndexer.indexMail(into: store, since: window.since()) } }
        if sources.slack { await attempt("Slack") { try await indexSlack(into: store) } }
        refreshKnowledgeCounts()
        isIndexingKnowledge = false
        knowledgeState = failures.isEmpty ? .connected : .failed(failures.joined(separator: "\n"))

        // What each source gave, and why not when it gave nothing, so a quiet source is never mistaken for a working one.
        let counts = (try? store.counts()) ?? [:]
        func result(_ source: KaiNightShiftSource, name: String, key: String, connected: Bool, none: String) -> KaiNightShiftRecord.SourceResult? {
            guard chosen.contains(source) else { return nil }
            let count = (counts[key] ?? 0) + (key == "files" ? (counts["folder"] ?? 0) : 0)
            if !connected { return .init(name: name, count: count, note: "Not connected. Allow it on the Permissions page, or connect it in Preferences.") }
            if let failure = failures.first(where: { $0.hasPrefix(name + ":") }) { return .init(name: name, count: count, note: String(failure.dropFirst(name.count + 2))) }
            return .init(name: name, count: count, note: count == 0 ? none : nil)
        }
        let results = [
            result(.files, name: "Files", key: "files", connected: true, none: "No readable files in your knowledge folder or your added folders yet."),
            result(.calendar, name: "Calendar", key: "calendar", connected: sources.calendar || !calendarWanted(chosen), none: "No events in the last 30 or next 90 days."),
            result(.notes, name: "Notes", key: "notes", connected: sources.notes || !notesConnectedWanted(chosen), none: "Apple Notes has no notes on this Mac."),
            result(.mail, name: "Mail", key: "mail", connected: sources.mail || !mailConnectedWanted(chosen), none: "No mail in the chosen time window."),
            result(.slack, name: "Slack", key: "slack", connected: sources.slack || !slackWanted(chosen), none: "No Slack messages found."),
        ].compactMap { $0 }
        return (report, failures, results)
    }

    // A source that was chosen but isn't connected has to be said so; these read the connection, not the choice.
    private func calendarWanted(_ chosen: Set<KaiNightShiftSource>) -> Bool { chosen.contains(.calendar) && !calendarConnected }
    private func notesConnectedWanted(_ chosen: Set<KaiNightShiftSource>) -> Bool { chosen.contains(.notes) && !notesConnected }
    private func mailConnectedWanted(_ chosen: Set<KaiNightShiftSource>) -> Bool { chosen.contains(.mail) && !mailConnected }
    private func slackWanted(_ chosen: Set<KaiNightShiftSource>) -> Bool { chosen.contains(.slack) && slackClient == nil }

    /// The assistant's view of a search: untrusted text, labelled by where it came from.
    func knowledgeTool(query: String?) -> String {
        guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return "Give a few words to search for." }
        guard let store = openKnowledgeStore() else { return "The knowledge base could not be opened." }
        guard ((try? store.count()) ?? 0) > 0 else {
            return "The knowledge base is empty. Tell the user to click Index now under Knowledge base in Settings."
        }
        guard let hits = try? store.search(query, limit: 8), !hits.isEmpty else {
            return "Nothing in the knowledge base matched. Say that you could not find it in the user's files and notes. Do not guess or make it up."
        }
        let folders = knowledgeFolders
        let found = hits.map { hit in
            let source = Self.knowledgeSourceNames[hit.source] ?? hit.source
            let date = hit.modified.map { " (\($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
            let place = KaiKnowledgeCitation.label(source: hit.source, sourceID: hit.sourceID, folders: folders)
            return "[\(source)] \(hit.title)\(date)" + (place.isEmpty ? "" : "\nFile: \(place)") + "\n\(hit.snippet)"
        }.joined(separator: "\n\n")
        return found + "\n\nWhen you use any of this, say which source it came from (its title or file). If it does not answer the question, say you could not find it instead of guessing."
    }
}
