//
//  KaiChatSelfTest.swift
//  Kai OS macOS
//
//  Debug-only end-to-end chat test. It types into the real text field with key events,
//  so it covers focus, Return handling, streaming, history and Stop inside the app bundle.
//
//  Run with:
//    KAI_UI_SELFTEST_DIR=/tmp/kai-selftest "$HOME/Applications/Kai OS.app/Contents/MacOS/Kai OS"
//  Results go to <dir>/result.txt and window snapshots to <dir>/*.png. The exit code is 0 on success.
//

#if DEBUG
import AppKit
import Foundation

@MainActor
enum KaiChatSelfTest {
    private static var started = false

    static func runIfRequested(appState: AppState) {
        guard !started, let dir = ProcessInfo.processInfo.environment["KAI_UI_SELFTEST_DIR"] else { return }
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

        try? await Task.sleep(for: .seconds(2))
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
            log.append("FAIL  no visible main window")
            finish(log: log, failures: 1, directory: directory)
        }
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1))
        snapshot(window, to: directory.appendingPathComponent("1-launch.png"))

        report("a local chat model was discovered", !appState.selectedModel.isEmpty, appState.selectedModel)

        // Typing and Return through the real text field.
        let first = "Remember the word pineapple. Reply with only OK."
        type(first, into: window)
        try? await Task.sleep(for: .milliseconds(300))
        report("typed text reaches the input field", appState.chatDraft == first, "draft=\"\(appState.chatDraft)\"")
        pressReturn(in: window)
        try? await Task.sleep(for: .milliseconds(300))
        report("Return sends the message", appState.messages.contains { $0.isUser && $0.text == first })
        report("Return clears the input field", appState.chatDraft.isEmpty)
        await waitForReply(appState: appState, seconds: 180)
        let firstReply = appState.messages.last
        report("the model replied", firstReply?.kind == .chat && firstReply?.isUser == false && firstReply?.text.isEmpty == false, firstReply?.text ?? "nil")

        // Conversation history reaches the model.
        type("Which word did I ask you to remember? Reply with just that word.", into: window)
        try? await Task.sleep(for: .milliseconds(300))
        pressReturn(in: window)
        await waitForReply(appState: appState, seconds: 120)
        let recall = appState.messages.last?.text ?? ""
        report("a follow-up sees earlier turns", recall.lowercased().contains("pineapple"), recall)
        snapshot(window, to: directory.appendingPathComponent("2-conversation.png"))

        // Stop keeps the partial reply and leaves the chat usable.
        appState.sendMessage(text: "Count from 1 to 500, one number per line.")
        await waitUntil(seconds: 60) { appState.messages.last?.text.isEmpty == false }
        appState.cancelReply()
        await waitUntil(seconds: 5) { !appState.isProcessing }
        report("Stop ends the reply", !appState.isProcessing)
        let partial = appState.messages.last?.text ?? ""
        report("Stop keeps the partial text", !partial.isEmpty && !partial.contains("500"), "\(partial.count) characters")

        appState.activeSidebar = "Mail"
        try? await Task.sleep(for: .milliseconds(500))
        snapshot(window, to: directory.appendingPathComponent("3-mail.png"))
        appState.activeSidebar = "Chat"
        try? await Task.sleep(for: .milliseconds(500))
        snapshot(window, to: directory.appendingPathComponent("4-chat-after-navigation.png"))
        report("the transcript survives navigation", appState.messages.contains { $0.text == first })

        finish(log: log, failures: failures, directory: directory)
    }

    private static func waitForReply(appState: AppState, seconds: Double) async {
        await waitUntil(seconds: seconds) { !appState.isProcessing }
    }

    private static func waitUntil(seconds: Double, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func type(_ text: String, into window: NSWindow) {
        for character in text {
            sendKey(characters: String(character), keyCode: 0, window: window)
        }
    }

    private static func pressReturn(in window: NSWindow) {
        sendKey(characters: "\r", keyCode: 36, window: window)
    }

    static func sendKey(characters: String, keyCode: UInt16, window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ) else { continue }
            window.sendEvent(event)
        }
    }

    static func snapshot(_ window: NSWindow, to url: URL, background: NSColor = .windowBackgroundColor) {
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // The window background belongs to the frame view, so it is composited in by hand.
        // Without it, light text in dark mode lands on transparency and looks missing.
        let flattened = NSImage(size: view.bounds.size)
        flattened.lockFocus()
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            background.setFill()
            view.bounds.fill()
        }
        bitmap.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        flattened.unlockFocus()
        guard let tiff = flattened.tiffRepresentation, let output = NSBitmapImageRep(data: tiff) else { return }
        try? output.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func finish(log: [String], failures: Int, directory: URL) -> Never {
        let summary = log.joined(separator: "\n") + "\n\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")\n"
        try? summary.write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
