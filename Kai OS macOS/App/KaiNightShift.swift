//
//  KaiNightShift.swift
//  Kai OS macOS
//
//  Night Shift: an unattended run that indexes the knowledge base and prepares the morning
//  briefing. It only prepares cards, so nothing is sent, created or changed. The schedule,
//  power rules and launchd job are in KaiShared (KaiNightShift.swift) and covered by KaiChecksTests.
//

import AppKit
import Foundation
import KaiShared
import KaiActions
import KaiKnowledge

@MainActor
enum KaiNightShiftRunner {
    /// launchd starts the app with this flag.
    static var isRequested: Bool { CommandLine.arguments.contains(KaiNightShiftAgent.launchArgument) }

    /// A test run keeps everything in this folder and reads no personal source.
    static var testDirectory: URL? {
        ProcessInfo.processInfo.environment["KAI_NIGHT_SHIFT_TEST_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Runs once from launchd: hidden, then quits.
    static func runUnattended(appState: AppState) async {
        func hideWindows() { NSApp.windows.forEach { $0.orderOut(nil) } }
        hideWindows()
        Task { try? await Task.sleep(for: .seconds(1)); hideWindows() }
        let store = testDirectory.map { KaiNightShiftStore(directory: $0) } ?? KaiNightShiftStore()
        _ = await run(appState: appState, store: store, power: KaiPowerState.current())
        NSApp.terminate(nil)
    }

    /// Does the work and records the outcome. Used by launchd and by "Run now".
    static func run(appState: AppState, store: KaiNightShiftStore, power: KaiPowerState) async -> KaiNightShiftRecord {
        let record = await perform(appState: appState, power: power)
        try? store.save(record)
        return record
    }

    private static func perform(appState: AppState, power: KaiPowerState) async -> KaiNightShiftRecord {
        let now = Date()
        if let reason = KaiNightShiftPolicy.skipReason(power) {
            return KaiNightShiftRecord(ranAt: now, outcome: .skipped(reason))
        }

        if let directory = testDirectory {
            guard let store = try? KaiKnowledgeStore(url: directory.appendingPathComponent("knowledge.sqlite")) else {
                return KaiNightShiftRecord(ranAt: now, outcome: .failed("Couldn't open the test knowledge base."))
            }
            appState.knowledge = store
            let result = await appState.indexKnowledgeNow(folder: directory.appendingPathComponent("folder"), sources: [.files])
            return KaiNightShiftRecord(ranAt: now, outcome: result.failures.isEmpty ? .completed : .failed(result.failures.joined(separator: " ")),
                                       documentsIndexed: appState.knowledgeDocumentCount, cardsPrepared: 0)
        }

        let chosen = appState.nightShift.sources
        if chosen.contains(.calendar) { appState.refreshCalendar() }
        let result = await appState.indexKnowledgeNow(sources: chosen)
        let indexed = appState.knowledgeDocumentCount

        // New items are read into summaries and the linked notes updated, both with the local model. If there is none
        // running, this is skipped and the rest of the night goes on.
        await appState.summarizeKnowledgeNow(limit: 150)
        await appState.buildLinkedNotesNow()

        // The portrait comes before the briefing, so today's cards are about what matters to this person.
        // If it can't be built (no local model running, say), the briefing is made without it.
        await appState.rebuildProfileNow()

        // A briefing already made today is kept, so a run at noon doesn't replace cards you've acted on.
        let briefing = appState.morningCards
        briefing.loadStoredCards()
        let today = KaiBriefingSchedule.dayKey(for: now)
        if chosen.contains(.briefing), briefing.hasSources, briefing.lastRunDay != today {
            briefing.generate()
            let deadline = Date().addingTimeInterval(15 * 60)
            while briefing.isGenerating, Date() < deadline { try? await Task.sleep(for: .milliseconds(500)) }
            if let message = briefing.errorMessage {
                return KaiNightShiftRecord(ranAt: now, outcome: .failed(message), documentsIndexed: indexed, cardsPrepared: 0, sources: result.sourceResults)
            }
        }
        if !result.failures.isEmpty, result.report.total == 0 {
            return KaiNightShiftRecord(ranAt: now, outcome: .failed(result.failures.joined(separator: " ")), documentsIndexed: indexed, cardsPrepared: 0, sources: result.sourceResults)
        }
        return KaiNightShiftRecord(ranAt: now, outcome: .completed, documentsIndexed: indexed, cardsPrepared: briefing.activeCards.count, sources: result.sourceResults)
    }
}

extension AppState {
    /// Saves the choice and adds or removes the launchd job to match.
    func updateNightShift(_ settings: KaiNightShiftSettings) {
        nightShift = settings
        nightShiftMessage = nil
        do {
            try KaiNightShiftStore().save(settings)
            let agent = KaiNightShiftAgent()
            if settings.enabled {
                guard let executable = Bundle.main.executablePath, executable.contains(".app/Contents/MacOS/") else {
                    nightShift.enabled = false
                    try? KaiNightShiftStore().save(nightShift)
                    nightShiftMessage = "Night Shift needs the installed app. Run scripts/install-app.sh, then turn it on from that copy."
                    return
                }
                guard try agent.install(executable: executable, hour: settings.hour, minute: settings.minute) else {
                    nightShift.enabled = false
                    try? KaiNightShiftStore().save(nightShift)
                    nightShiftMessage = "macOS wouldn't load the Night Shift job. Nothing was scheduled."
                    return
                }
            } else {
                try agent.uninstall()
            }
        } catch {
            nightShiftMessage = "Couldn't update Night Shift: \(error.localizedDescription)"
        }
    }

    func runNightShiftNow() {
        guard !isRunningNightShift else { return }
        isRunningNightShift = true
        nightShiftMessage = nil
        Task {
            let record = await KaiNightShiftRunner.run(appState: self, store: KaiNightShiftStore(), power: KaiPowerState.current())
            nightShiftRecord = record
            isRunningNightShift = false
        }
    }
}
