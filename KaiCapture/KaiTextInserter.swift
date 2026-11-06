//
//  KaiTextInserter.swift
//  Kai OS
//
//  Puts text at the cursor in another app by pasting it, which works in native apps and in
//  web pages alike. It only ever pastes, and the clipboard is put back afterwards.
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox

public struct KaiPasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    public init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { fields -> NSPasteboardItem in
            let item = NSPasteboardItem()
            fields.forEach { item.setData($0.1, forType: $0.0) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }

    /// Leaves the pasteboard alone if anything has changed it since `changeCount`, so a copy
    /// the user just made is never overwritten.
    public func restore(to pasteboard: NSPasteboard, ifChangeCountIs changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        restore(to: pasteboard)
    }
}

public enum KaiFocusKind: Equatable, Sendable {
    /// A multi-line text area, which is where an email body lives.
    case multiline
    /// A single-line field such as a recipient or search box.
    case singleLine
    case none
}

public enum KaiFocusProbe {
    static func isEditable(role: String?, settable: Bool) -> Bool {
        guard settable, let role else { return false }
        return ["AXTextArea", "AXTextField", "AXComboBox"].contains(role)
    }

    /// Looks at the focused element in the frontmost app. Kai's own windows count as none.
    @MainActor
    public static func currentFocus() -> KaiFocusKind {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .none }
        // Chromium browsers expose web page contents only after being asked to.
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .none }
        let element = focused as! AXUIElement

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        let roleName = role as? String
        guard isEditable(role: roleName, settable: settable.boolValue) else { return .none }
        return roleName == "AXTextArea" ? .multiline : .singleLine
    }
}

/// Abstracted so the double tap flow can be tested without touching the user's other apps.
@MainActor
public protocol KaiTextInserting: AnyObject {
    var isAvailable: Bool { get }
    func currentFocus() -> KaiFocusKind
    /// Pastes at the cursor of whichever app has keyboard focus.
    func insert(_ text: String) async throws
}

public enum KaiTextInsertError: LocalizedError, Equatable, Sendable {
    case notAllowed
    case eventFailed

    public var errorDescription: String? {
        switch self {
        case .notAllowed:
            return "To write into your email, turn on Accessibility in the Permissions section of Kai OS. Until then, use Copy."
        case .eventFailed:
            return "The text couldn't be written into that app. Use Copy instead."
        }
    }
}

@MainActor
public final class KaiPasteInserter: KaiTextInserting {
    /// Long enough for the target app to read the pasteboard before it's restored.
    private static let pasteSettleTime: Duration = .milliseconds(600)
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    public init() {}

    public var isAvailable: Bool { AXIsProcessTrusted() }

    public func currentFocus() -> KaiFocusKind { KaiFocusProbe.currentFocus() }

    public func insert(_ text: String) async throws {
        guard isAvailable else { throw KaiTextInsertError.notAllowed }
        let pasteboard = NSPasteboard.general
        let saved = KaiPasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        // Marked transient so clipboard managers don't keep the draft.
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        pasteboard.writeObjects([item])
        let draftChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            saved.restore(to: pasteboard)
            throw KaiTextInsertError.eventFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        try? await Task.sleep(for: Self.pasteSettleTime)
        saved.restore(to: pasteboard, ifChangeCountIs: draftChangeCount)
    }
}
