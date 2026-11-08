//
//  KaiUpdateController.swift
//  Kai OS macOS
//
//  Checks GitHub for a newer release, at most once a day and when asked. It only tells the
//  person and opens the release page: it never downloads or installs anything.
//

import AppKit
import KaiShared

@MainActor
final class KaiUpdateController: ObservableObject {
    static let shared = KaiUpdateController()

    private static let lastCheckKey = "kai.update.lastCheck"
    private static let autoKey = "kai.update.auto"

    @Published private(set) var available: KaiAvailableUpdate?
    @Published private(set) var status = ""
    @Published private(set) var isChecking = false
    @Published var automatic: Bool = UserDefaults.standard.object(forKey: KaiUpdateController.autoKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: Self.autoKey) }
    }

    var currentVersion: KaiVersion {
        KaiVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? KaiVersion("0")!
    }

    /// At launch: checks only if automatic checks are on and a day has passed.
    func checkIfDue() {
        guard automatic else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        guard KaiUpdates.isDue(lastCheck: last) else { return }
        Task { await check(manual: false) }
    }

    func check(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let update = try await KaiUpdates.check(current: currentVersion)
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            available = update
            if manual { status = update == nil ? "Kai OS \(currentVersion) is the latest version." : "Kai OS \(update!.version) is available." }
        } catch {
            // A quiet failure for the daily check; a manual check says what went wrong.
            if manual { status = "Could not check for updates. Are you online?" }
        }
    }

    func openReleasePage() {
        if let url = available?.pageURL { NSWorkspace.shared.open(url) }
    }

    func copyInstallCommand() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(KaiUpdates.installCommand, forType: .string)
    }
}
