//
//  KaiNotchSelfTest.swift
//  Kai OS macOS
//
//  Debug-only end-to-end test of the notch panel inside the app bundle.
//
//  Run with:
//    KAI_NOTCH_SELFTEST_DIR=/tmp/kai-notch "$HOME/Applications/Kai OS.app/Contents/MacOS/Kai OS"
//  Keep the cursor away from the notch while it runs, because hover follows the real cursor.
//  Results go to <dir>/result.txt and snapshots to <dir>/*.png. The exit code is 0 on success.
//

#if DEBUG
import AppKit
import Foundation
import KaiNotchCore

@MainActor
enum KaiNotchSelfTest {
    private static var started = false

    static func runIfRequested(appState: AppState) {
        guard !started, let dir = ProcessInfo.processInfo.environment["KAI_NOTCH_SELFTEST_DIR"] else { return }
        started = true
        Task { await run(appState: appState, directory: URL(fileURLWithPath: dir)) }
    }

    private static func run(appState: AppState, directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var log: [String] = []
        var failures = 0
        func report(_ name: String, _ passed: Bool, _ detail: String = "") {
            log.append("\(passed ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            if !passed { failures += 1 }
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(700)) }

        try? await Task.sleep(for: .seconds(2))
        let controller = KaiNotchWindowController.shared
        let model = controller.model
        guard let panel = controller.panel, let layout = model.layout else {
            log.append("FAIL  the notch panel was not created")
            finish(log: log, failures: 1, directory: directory)
        }
        let gray = NSColor(white: 0.45, alpha: 1)

        report("the panel is visible", panel.isVisible)
        report("the hardware notch is detected", layout.hasHardwareNotch, "\(layout.notch)")
        report("closed, the panel covers exactly the notch", panel.frame == layout.frame(for: .closed), "\(panel.frame)")
        report("the panel sits above the menu bar", panel.level.rawValue > NSWindow.Level.mainMenu.rawValue)
        report("the Control-Option-Space hotkey registered", KaiSidekickHotkeyMonitor.shared.isHotKeyRegistered)

        model.isHovering = true
        await settle()
        report("hover grows the wings", panel.frame == layout.frame(for: .peek), "\(panel.frame)")
        KaiChatSelfTest.snapshot(panel, to: directory.appendingPathComponent("1-peek.png"), background: gray)
        model.isHovering = false
        await settle()
        report("leaving returns to the closed frame", panel.frame == layout.frame(for: .closed), "\(panel.frame)")

        controller.toggle()
        await settle()
        report("the toggle expands the panel", model.isExpanded && panel.frame == layout.frame(for: .expanded), "\(panel.frame)")
        report("the expanded panel takes keyboard focus", panel.isKeyWindow)
        report("the text field has focus", panel.firstResponder is NSTextView)

        let prompt = "Reply with only the word mango."
        for character in prompt {
            KaiChatSelfTest.sendKey(characters: String(character), keyCode: 0, window: panel)
        }
        try? await Task.sleep(for: .milliseconds(300))
        report("typed text reaches the notch field", model.draft == prompt, "draft=\"\(model.draft)\"")
        KaiChatSelfTest.sendKey(characters: "\r", keyCode: 36, window: panel)
        try? await Task.sleep(for: .milliseconds(200))
        report("Return sends from the notch", appState.messages.contains { $0.isUser && $0.text == prompt })
        report("activity shows running", model.activity == .running)

        controller.collapse()
        await settle()
        if appState.isProcessing {
            report("collapsed while running, the wings stay out", panel.frame == layout.frame(for: .peek), "\(panel.frame)")
            KaiChatSelfTest.snapshot(panel, to: directory.appendingPathComponent("2-running.png"), background: gray)
        }
        report("collapsing releases keyboard focus", !panel.isKeyWindow)

        var waited = 0
        while appState.isProcessing && waited < 1200 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        let reply = appState.messages.last
        report("the reply arrived", reply?.text.lowercased().contains("mango") == true, reply?.text ?? "nil")
        report("activity shows done", model.activity == .done)
        report("the conversation is shared with the main window", appState.messages.contains { $0.text == prompt })
        try? await Task.sleep(for: .seconds(2))
        report("the done state clears", model.activity == .idle)

        controller.expand()
        await settle()
        KaiChatSelfTest.snapshot(panel, to: directory.appendingPathComponent("3-expanded.png"), background: gray)
        KaiChatSelfTest.sendKey(characters: "\u{1b}", keyCode: 53, window: panel)
        await settle()
        report("Esc closes the panel", !model.isExpanded && panel.frame == layout.frame(for: .closed), "\(panel.frame)")

        // Failure state, driven through the same signals a failed reply produces.
        appState.isProcessing = true
        appState.messages.append(Message(text: "Simulated failure", kind: .error))
        appState.isProcessing = false
        await settle()
        report("a failed reply shows the failed state", model.activity == .failed && panel.frame == layout.frame(for: .peek))
        KaiChatSelfTest.snapshot(panel, to: directory.appendingPathComponent("4-failed.png"), background: gray)

        UserDefaults.standard.set(false, forKey: KaiNotchPreferences.enabledKey)
        controller.applyEnabledPreference()
        report("the Settings switch hides the panel", !panel.isVisible)
        UserDefaults.standard.removeObject(forKey: KaiNotchPreferences.enabledKey)
        controller.applyEnabledPreference()
        report("the Settings switch restores the panel", panel.isVisible)

        finish(log: log, failures: failures, directory: directory)
    }

    private static func finish(log: [String], failures: Int, directory: URL) -> Never {
        let summary = log.joined(separator: "\n") + "\n\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")\n"
        try? summary.write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
