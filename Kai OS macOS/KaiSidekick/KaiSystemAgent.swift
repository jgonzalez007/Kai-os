//
//  KaiSystemAgent.swift
//  Kai OS macOS
//
//  The real screen, mouse, keyboard and model behind the computer-use agent. The rules and the
//  loop are in KaiAgent and covered by KaiChecksTests. This file only does what they ask.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import KaiAgent
import KaiCapture
import KaiLocalAI
import KaiShared

// MARK: - Screen

/// One screenshot of the main display, without Kai's own windows. It stays on this Mac:
/// the agent only talks to a local model.
struct KaiSystemScreen: KaiAgentScreen {
    func capture() async throws -> KaiAgentFrame {
        let display = CGMainDisplayID()
        let data = try await KaiScreenGrabber.capture(displayID: display, excludingBundleIdentifier: Bundle.main.bundleIdentifier)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw KaiScreenCaptureError.encodingFailed }
        let bounds = CGDisplayBounds(display)
        // The clickable items of the front window, found through Accessibility. If that fails or the app is
        // off limits, the model simply gets the picture alone.
        let elements = await Task.detached(priority: .userInitiated) {
            KaiAXElements.collect(bounds: bounds, pixelWidth: width, pixelHeight: height, ownBundleIdentifier: Bundle.main.bundleIdentifier)
        }.value
        return KaiAgentFrame(jpeg: data, pixelWidth: width, pixelHeight: height, screenWidth: bounds.width, screenHeight: bounds.height, elements: elements)
    }
}

// MARK: - Model

/// Asks a local Ollama model for the next action. Screenshots are never sent to a cloud provider.
struct KaiOllamaAgentBrain: KaiAgentBrain, @unchecked Sendable {
    let client: KaiOllamaClient
    let model: String

    func next(messages: [KaiOllamaMessage]) async throws -> (text: String, calls: [KaiOllamaToolCall]) {
        var text = ""
        var calls: [KaiOllamaToolCall] = []
        for try await event in client.stream(model: model, messages: messages, tools: KaiAgentTools.definitions, temperature: 0.2) {
            switch event {
            case .text(let delta): text += delta
            case .toolCalls(let found): calls += found
            }
        }
        return (text, calls)
    }
}

// MARK: - Mouse and keyboard

enum KaiInputError: LocalizedError {
    case needsAccessibility
    case ownControls
    case couldNotPost

    var errorDescription: String? {
        switch self {
        case .needsAccessibility: return "Kai OS needs Accessibility permission to use the mouse and keyboard. Turn it on in System Settings → Privacy & Security → Accessibility."
        case .ownControls: return "The agent tried to click Kai's own controls, so it was stopped."
        case .couldNotPost: return "macOS didn't accept the input event."
        }
    }
}

/// Posts real mouse and keyboard events. Every event carries a tag, so the person's own input
/// can be told apart from the agent's and stops it.
final class KaiSystemInput: KaiAgentInput, @unchecked Sendable {
    static let tag: Int64 = 0x4B41495F

    private let lock = NSLock()
    private var userInput = false
    private var monitors: [Any] = []
    var onEscape: (@Sendable () -> Void)?
    /// Where Kai's own controls are, in display coordinates. Clicks there are refused.
    var protectedFrames: @Sendable () async -> [CGRect] = { [] }

    @MainActor
    func startMonitoring() {
        stopMonitoring()
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.observe(event) }) {
            monitors.append(monitor)
        }
        clearUserInput()
    }

    @MainActor
    func stopMonitoring() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func observe(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.tag { return }
        if event.type == .keyDown, event.keyCode == 53 { onEscape?() }
        lock.lock(); userInput = true; lock.unlock()
    }

    private func clearUserInput() { lock.lock(); userInput = false; lock.unlock() }

    func userInterrupted() async -> Bool { lock.lock(); defer { lock.unlock() }; return userInput }
    func clearInterruption() async { clearUserInput() }

    func frontmostBundleIdentifier() async -> String? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    }

    func perform(_ action: KaiPlacedAction) async throws {
        guard AXIsProcessTrusted() else { throw KaiInputError.needsAccessibility }
        let source = CGEventSource(stateID: .hidSystemState)
        switch action {
        case .click(let x, let y, let double, let right):
            try await refuseOwnControls(CGPoint(x: x, y: y))
            try post(mouse: right ? .rightMouseDown : .leftMouseDown, at: CGPoint(x: x, y: y), source: source, button: right ? .right : .left, clickState: 1, move: true)
            try post(mouse: right ? .rightMouseUp : .leftMouseUp, at: CGPoint(x: x, y: y), source: source, button: right ? .right : .left, clickState: 1)
            if double {
                try await Task.sleep(for: .milliseconds(60))
                try post(mouse: .leftMouseDown, at: CGPoint(x: x, y: y), source: source, button: .left, clickState: 2)
                try post(mouse: .leftMouseUp, at: CGPoint(x: x, y: y), source: source, button: .left, clickState: 2)
            }
        case .scroll(let x, let y, let dx, let dy):
            try await refuseOwnControls(CGPoint(x: x, y: y))
            try post(mouse: .mouseMoved, at: CGPoint(x: x, y: y), source: source, button: .left, clickState: 0)
            guard let event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: Int32(-dy), wheel2: Int32(-dx), wheel3: 0) else {
                throw KaiInputError.couldNotPost
            }
            event.setIntegerValueField(.eventSourceUserData, value: Self.tag)
            event.post(tap: .cghidEventTap)
        case .key(let combo):
            guard let code = KaiKeyCodes.code(for: combo.key) else { throw KaiInputError.couldNotPost }
            try postKey(code, flags: KaiKeyCodes.flags(combo.modifiers), source: source)
        case .type(let text):
            try await type(text, source: source)
        case .openApp(let name):
            try await openApplication(named: name)
        }
    }

    /// Opens an app by name from the usual folders. The app it resolves to is checked again against the
    /// blocked list, so a different name for a blocked app does not get around it.
    private func openApplication(named name: String) async throws {
        guard let url = Self.applicationURL(named: name) else {
            throw KaiAgentActionProblem("There is no app called \(name). Use an app that is installed, or call task_complete.")
        }
        let identifier = Bundle(url: url)?.bundleIdentifier
        if let identifier, KaiAgentPolicy.blockedBundleIdentifiers.contains(identifier) || identifier == Bundle.main.bundleIdentifier {
            throw KaiAgentActionProblem("Kai never operates \(name).")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        try await Task.sleep(for: .milliseconds(700))
    }

    static func applicationURL(named name: String) -> URL? {
        var wanted = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if wanted.hasSuffix(".app") { wanted.removeLast(4) }
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            if let match = names.first(where: { $0.lowercased() == wanted + ".app" }) {
                return URL(fileURLWithPath: folder).appendingPathComponent(match)
            }
        }
        return nil
    }

    private func refuseOwnControls(_ point: CGPoint) async throws {
        for frame in await protectedFrames() where frame.insetBy(dx: -8, dy: -8).contains(point) { throw KaiInputError.ownControls }
    }

    private func post(mouse type: CGEventType, at point: CGPoint, source: CGEventSource?, button: CGMouseButton, clickState: Int64, move: Bool = false) throws {
        if move, let moved = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            moved.setIntegerValueField(.eventSourceUserData, value: Self.tag)
            moved.post(tap: .cghidEventTap)
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { throw KaiInputError.couldNotPost }
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.setIntegerValueField(.eventSourceUserData, value: Self.tag)
        event.post(tap: .cghidEventTap)
    }

    private func postKey(_ code: CGKeyCode, flags: CGEventFlags, source: CGEventSource?) throws {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { throw KaiInputError.couldNotPost }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.tag)
            event.post(tap: .cghidEventTap)
        }
    }

    private func type(_ text: String, source: CGEventSource?) async throws {
        for character in text {
            if character == "\n" || character == "\r" {
                try postKey(36, flags: [], source: source)
            } else {
                let units = Array(String(character).utf16)
                for down in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { throw KaiInputError.couldNotPost }
                    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                    event.setIntegerValueField(.eventSourceUserData, value: Self.tag)
                    event.post(tap: .cghidEventTap)
                }
            }
            try await Task.sleep(for: .milliseconds(12))
        }
    }
}
