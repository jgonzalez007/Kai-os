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
import AVFoundation
import Foundation
import Speech
import KaiCapture
import KaiLocalAI
import KaiLocalData

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

        report("the chat field has focus at launch", window.firstResponder is NSTextView, "\(String(describing: window.firstResponder.map { Swift.type(of: $0) }))")
        let recognizer = SFSpeechRecognizer()
        log.append("INFO  on-device speech: \(recognizer?.supportsOnDeviceRecognition == true), locale \(recognizer?.locale.identifier ?? "none"), speech permission \(SFSpeechRecognizer.authorizationStatus().rawValue), mic permission \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
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

        // Assistant tools, against real Spotlight and the real model.
        if !appState.mailConnected {
            let mail = await appState.runTool(KaiOllamaToolCall(name: "list_recent_mail", arguments: [:]))
            report("an unconnected source says so instead of prompting", mail.contains("not connected"), mail)
        }
        let unknown = await appState.runTool(KaiOllamaToolCall(name: "delete_everything", arguments: [:]))
        report("an unknown tool is refused", unknown.hasPrefix("Unknown tool"), unknown)

        let marker = "kaiprobe\(UUID().uuidString.prefix(8).lowercased())"
        let probe = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("\(marker).txt")
        try? "Kai OS Spotlight probe".write(to: probe, atomically: true, encoding: .utf8)
        let importer = Process()
        importer.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
        importer.arguments = [probe.path]
        try? importer.run()
        importer.waitUntilExit()
        var found = false
        for _ in 0..<20 where !found {
            try? await Task.sleep(for: .seconds(1))
            found = (try? await KaiSpotlightSource.search(marker))?.contains { $0.path == probe.path } == true
        }
        report("Spotlight finds a new file", found, marker)

        let toolRunsBefore = appState.toolRunCount
        appState.sendMessage(text: "Use the search_files tool to find the file named \(marker). Reply with its full path.")
        await waitForReply(appState: appState, seconds: 180)
        let toolReply = appState.messages.last?.text ?? ""
        report("the model calls a tool", appState.toolRunCount > toolRunsBefore, "\(appState.toolRunCount - toolRunsBefore) call(s)")
        report("the reply uses the tool's result", toolReply.contains(probe.path), toolReply)
        snapshot(window, to: directory.appendingPathComponent("2b-tool.png"))

        // Vision, with a generated image: capturing the real screen needs a permission prompt.
        appState.pendingScreenshot = wordImage("KIWI")
        report("a screenshot waits for the next message", appState.pendingScreenshot != nil)
        appState.sendMessage(text: "What single word is written in this image? Reply with only that word.")
        report("sending consumes the attachment", appState.pendingScreenshot == nil)
        report("the message keeps its image", appState.messages.last { $0.isUser }?.imageData != nil)
        await waitForReply(appState: appState, seconds: 180)
        let visionReply = appState.messages.last?.text ?? ""
        report("the model reads the attached image", visionReply.uppercased().contains("KIWI"), visionReply)
        snapshot(window, to: directory.appendingPathComponent("2c-vision.png"))
        appState.sendMessage(text: "Reply with only the word ready.")
        await waitForReply(appState: appState, seconds: 120)
        report("a later message still works after an image", appState.messages.last?.kind == .chat, appState.messages.last?.text ?? "")

        if !KaiScreenGrabber.hasPermission {
            let result: String
            do {
                _ = try await KaiScreenGrabber.capture(displayID: nil, excludingBundleIdentifier: nil)
                result = "captured"
            } catch {
                result = error.localizedDescription
            }
            report("capture without permission explains itself", result == KaiScreenCaptureError.needsPermission.localizedDescription, result)
        } else {
            // Only the size is checked, and the image is discarded, so nothing on screen is kept.
            appState.attachScreen()
            await waitUntil(seconds: 20) { !appState.isCapturingScreen }
            let size = appState.pendingScreenshot?.count ?? 0
            let longEdge = appState.pendingScreenshot.flatMap { NSImage(data: $0)?.representations.first }.map { max($0.pixelsWide, $0.pixelsHigh) } ?? 0
            report("a real screen capture attaches a resized image", size > 0 && longEdge == KaiScreenImage.defaultMaxLongEdge, "\(size) bytes, long edge \(longEdge)")
            appState.pendingScreenshot = nil
        }

        appState.activeSidebar = "Mail"
        try? await Task.sleep(for: .milliseconds(500))
        snapshot(window, to: directory.appendingPathComponent("3-mail.png"))
        appState.activeSidebar = "Chat"
        try? await Task.sleep(for: .milliseconds(500))
        snapshot(window, to: directory.appendingPathComponent("4-chat-after-navigation.png"))
        report("the chat field has focus after navigating back", window.firstResponder is NSTextView)
        report("the transcript survives navigation", appState.messages.contains { $0.text == first })

        try? FileManager.default.removeItem(at: probe)
        finish(log: log, failures: failures, directory: directory)
    }

    private static func wordImage(_ word: String) -> Data? {
        let image = NSImage(size: NSSize(width: 600, height: 240), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 120),
                .foregroundColor: NSColor.black,
            ]
            (word as NSString).draw(at: NSPoint(x: 60, y: 50), withAttributes: attributes)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [:])
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
