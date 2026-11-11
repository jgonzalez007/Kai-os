//
//  KaiFocusedText.swift
//  Kai Capture
//
//  Reads the text the user is writing in another app (the selection, or the whole field) and, only after
//  they approve a suggestion, puts the new text in its place. It first tries Accessibility, which swaps
//  the text without touching the clipboard, and falls back to a paste. If the text has changed since Kai
//  read it, nothing is replaced.
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox

public enum KaiFocusedTextError: LocalizedError, Equatable, Sendable {
    case notAllowed
    case changed
    case failed

    public var errorDescription: String? {
        switch self {
        case .notAllowed: return "To replace your text, turn on Accessibility for Kai OS in the Permissions section. Until then, use Copy."
        case .changed: return "The text changed after Kai read it, so nothing was replaced. Press Proofread again."
        case .failed: return "Kai couldn't replace the text in that app. Use Copy and paste it yourself."
        }
    }
}

@MainActor
public final class KaiFocusedText {
    public let appName: String
    public let original: String
    /// True when only the selected part was read.
    public let isSelection: Bool

    private let pid: pid_t
    /// Nil when the text came from copying a selection (web editors, Slack, Chrome), which can only be pasted back over.
    private let element: AXUIElement?

    private init(appName: String, original: String, isSelection: Bool, pid: pid_t, element: AXUIElement?) {
        self.appName = appName
        self.original = original
        self.isSelection = isSelection
        self.pid = pid
        self.element = element
    }

    // MARK: Which app the person was writing in

    private static var lastExternal: NSRunningApplication?
    private static var observer: NSObjectProtocol?

    /// Remembers the last app in front that isn't Kai. Opening Kai's notch or a menu can make Kai the front app for a
    /// moment, and the text to read or replace is in the app the person was in before that.
    public static func startTracking() {
        guard observer == nil else { return }
        remember(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { remember(app) }
        }
    }

    private static func remember(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier, app.activationPolicy == .regular else { return }
        lastExternal = app
    }

    /// The app in front, or if that is Kai, the one the person was in just before.
    private static func targetApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { return front }
        if let last = lastExternal, !last.isTerminated { return last }
        return nil
    }

    /// Reads the focused text field of the frontmost app (never Kai's own windows). Nil when there is
    /// no Accessibility permission, no text field in focus, or nothing written in it.
    public static func capture(maxLength: Int = 12_000) async -> KaiFocusedText? {
        trace("capture: front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none") target=\(targetApp()?.localizedName ?? "none") trusted=\(AXIsProcessTrusted())")
        // Kai's bar is a panel that doesn't take over the front app, but a menu or a click can still make it the key
        // window, and then a copy goes to Kai and not to the app the text is in. Hand the keyboard back first.
        trace("capture: kai active=\(NSApp.isActive) key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none")")
        if NSApp.isActive || NSApp.keyWindow != nil, let target = targetApp() {
            await handKeyboardBack(to: target)
            trace("capture: after handing back, kai active=\(NSApp.isActive) key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none")")
        }
        // Twice: right after a menu closes the app in front may not have taken the keyboard back yet.
        for attempt in 1...2 {
            if let found = captureFromField(maxLength: maxLength) { trace("capture: field ok (\(found.original.count) chars, selection=\(found.isSelection))"); return found }
            if let found = await captureBySelection(maxLength: maxLength) { trace("capture: copy ok (\(found.original.count) chars)"); return found }
            trace("capture: attempt \(attempt) found nothing")
            if attempt == 1 { try? await Task.sleep(for: .milliseconds(400)) }
        }
        return nil
    }

    /// Makes the other app the one that gets the keys. Kai's panels don't take over as the front app, but they can
    /// hold the keyboard, and then a copy or a paste would go to Kai and not to the app the text is in.
    private static func handKeyboardBack(to app: NSRunningApplication) async {
        NSApp.keyWindow?.resignKey()
        NSApp.deactivate()
        app.activate()
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// A short log of what was tried, never the text itself, so a failure can be understood. Kept private to the person.
    private static func trace(_ line: String) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true).appendingPathComponent("capture-debug.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Many apps (Chrome, Slack, Teams, Notion) don't give out the text of a field through Accessibility. If the
    /// person selected text there, it is read the way they would: copy. The clipboard is put back right after.
    private static func captureBySelection(maxLength: Int) async -> KaiFocusedText? {
        guard AXIsProcessTrusted(), let app = targetApp() else { return nil }
        // If Kai got the keyboard (a menu just closed), give it back so the copy goes to the right app.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            app.activate()
            try? await Task.sleep(for: .milliseconds(300))
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return nil }
        }
        let board = NSPasteboard.general
        let saved = KaiPasteboardSnapshot(board)
        let before = board.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: .milliseconds(220))
        // Nothing selected means nothing was copied, and the clipboard is untouched.
        guard board.changeCount != before else { trace("copy: clipboard did not change in \(app.localizedName ?? "?") (front now \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"))"); return nil }
        let copied = board.string(forType: .string)
        saved.restore(to: board)
        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, copied.count <= maxLength else { return nil }
        return KaiFocusedText(appName: app.localizedName ?? "that app", original: copied, isSelection: true, pid: app.processIdentifier, element: nil)
    }

    private static func captureFromField(maxLength: Int) -> KaiFocusedText? {
        guard AXIsProcessTrusted(), let app = targetApp() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var focused: CFTypeRef?
        var status = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        if status != .success || focused == nil {
            // Some apps only answer when asked through the system.
            status = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
        }
        guard status == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { trace("field: no focused element (AX status \(status.rawValue))"); return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        trace("field: focused role=\((role as? String) ?? "none")")
        guard let roleName = role as? String, ["AXTextArea", "AXTextField", "AXComboBox", "AXWebArea"].contains(roleName) else { return nil }
        // A password field is never read.
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if (subrole as? String) == (kAXSecureTextFieldSubrole as String) { return nil }

        let selected = string(element, kAXSelectedTextAttribute)
        let whole = string(element, kAXValueAttribute)
        let name = app.localizedName ?? "that app"
        if let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, selected.count <= maxLength {
            return KaiFocusedText(appName: name, original: selected, isSelection: true, pid: app.processIdentifier, element: element)
        }
        if let whole, !whole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, whole.count <= maxLength {
            return KaiFocusedText(appName: name, original: whole, isSelection: false, pid: app.processIdentifier, element: element)
        }
        return nil
    }

    /// Puts `text` where the original was. Throws without changing anything if the original is no longer there.
    public func replace(with text: String) async throws {
        guard AXIsProcessTrusted() else { throw KaiFocusedTextError.notAllowed }
        guard let element else {
            // Read by copying: it can only be pasted back over the selection, which the app still holds.
            try await pasteReplacing(text)
            return
        }
        guard currentOriginal() == original else { throw KaiFocusedTextError.changed }

        if isSelection {
            if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success,
               await confirm(text) { return }
        } else {
            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success,
               await confirm(text) { return }
        }
        try await pasteReplacing(text)
    }

    // MARK: Private

    private func currentOriginal() -> String? {
        guard let element else { return nil }
        return isSelection ? Self.string(element, kAXSelectedTextAttribute) : Self.string(element, kAXValueAttribute)
    }

    /// Some apps accept the Accessibility write and ignore it. Only believe it when the text reads back.
    private func confirm(_ text: String) async -> Bool {
        guard let element else { return false }
        try? await Task.sleep(for: .milliseconds(150))
        if isSelection {
            let now = Self.string(element, kAXSelectedTextAttribute)
            return now == text || (Self.string(element, kAXValueAttribute)?.contains(text) ?? false)
        }
        return Self.string(element, kAXValueAttribute) == text
    }

    /// Brings the app and field back, selects the old text if it was the whole field, and pastes over it.
    private func pasteReplacing(_ text: String) async throws {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { throw KaiFocusedTextError.failed }
        Self.trace("replace: kai active=\(NSApp.isActive) key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none") front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")")
        await Self.handKeyboardBack(to: app)
        if let element { AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
        try? await Task.sleep(for: .milliseconds(100))
        Self.trace("replace: after handing back front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none") kai key=\(NSApp.keyWindow != nil)")
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw KaiFocusedTextError.failed }
        if !isSelection {
            Self.post(key: kVK_ANSI_A)
            try? await Task.sleep(for: .milliseconds(120))
        }
        do {
            try await KaiPasteInserter().insert(text)
        } catch {
            throw KaiFocusedTextError.failed
        }
    }

    private static func post(key: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
