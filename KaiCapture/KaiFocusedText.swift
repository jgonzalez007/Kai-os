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
        if let found = captureFromField(maxLength: maxLength) { return found }
        return await captureBySelection(maxLength: maxLength)
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
        guard board.changeCount != before else { return nil }
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
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
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
        NSRunningApplication(processIdentifier: pid)?.activate()
        if let element { AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
        try? await Task.sleep(for: .milliseconds(250))
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
