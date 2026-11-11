//
//  KaiAXElements.swift
//  Kai OS macOS
//
//  Reads the clickable items of the front app's window through Accessibility, so the agent can be told
//  exactly where to click, and the text the window shows (headings, labels, prices, messages) so it can read
//  the page as a person does. It never reads what is typed into a text field, and never a password field.
//  Apps the agent may not operate are skipped entirely.
//

import AppKit
import ApplicationServices
import KaiAgent

enum KaiAXElements {
    private static let clickable: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea", "AXComboBox", "AXPopUpButton",
        "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXLink", "AXTabGroup", "AXSlider", "AXDisclosureTriangle",
    ]
    private static let maxNodes = 600
    private static let maxDepth = 12
    private static let timeBudget: TimeInterval = 1.0
    /// Shown text, never typed text: static labels and headings only.
    private static let readable: Set<String> = ["AXStaticText", "AXHeading"]

    static func collect(bounds: CGRect, pixelWidth: Int, pixelHeight: Int, ownBundleIdentifier: String?) -> (elements: [KaiAgentElement], texts: [String]) {
        guard AXIsProcessTrusted(), bounds.width > 0, bounds.height > 0,
              let front = NSWorkspace.shared.frontmostApplication,
              let identifier = front.bundleIdentifier,
              identifier != ownBundleIdentifier,
              !KaiAgentPolicy.blockedBundleIdentifiers.contains(identifier) else { return ([], []) }

        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let deadline = Date().addingTimeInterval(timeBudget)
        let scaleX = Double(pixelWidth) / bounds.width
        let scaleY = Double(pixelHeight) / bounds.height

        // The window comes first, so its items are numbered before the menu bar's. Only the window's text is read.
        var roots: [(element: AXUIElement, isWindow: Bool)] = []
        if let window = elementValue(app, kAXFocusedWindowAttribute) ?? elementValue(app, kAXMainWindowAttribute) { roots.append((window, true)) }
        if let menuBar = elementValue(app, kAXMenuBarAttribute) { roots.append((menuBar, false)) }

        var found: [KaiAgentElement] = []
        var shown: [(y: Int, x: Int, text: String)] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int, inWindow: Bool) {
            guard visited < maxNodes, depth <= maxDepth, Date() < deadline else { return }
            visited += 1
            let role = stringValue(element, kAXRoleAttribute) ?? ""
            let subrole = stringValue(element, kAXSubroleAttribute) ?? ""
            if subrole == "AXSecureTextField" || role == "AXSecureTextField" { return }
            if inWindow, readable.contains(role), let center = center(of: element), shown.count < 120 {
                let x = Int(((center.x - bounds.minX) * scaleX).rounded())
                let y = Int(((center.y - bounds.minY) * scaleY).rounded())
                if x >= 0, y >= 0, x < pixelWidth, y < pixelHeight, let text = stringValue(element, kAXValueAttribute) ?? stringValue(element, kAXTitleAttribute) {
                    shown.append((y, x, text))
                }
            }
            if clickable.contains(role), let center = center(of: element) {
                let x = Int(((center.x - bounds.minX) * scaleX).rounded())
                let y = Int(((center.y - bounds.minY) * scaleY).rounded())
                if x >= 0, y >= 0, x < pixelWidth, y < pixelHeight {
                    found.append(KaiAgentElement(label: label(of: element), role: friendly(role), x: x, y: y))
                }
            }
            // A menu's items are only worth listing while it is open, so menus are not opened to read them.
            if role == "AXMenuBarItem" { return }
            for child in children(of: element) { walk(child, depth: depth + 1, inWindow: inWindow) }
        }
        for root in roots { walk(root.element, depth: 0, inWindow: root.isWindow) }
        let texts = shown.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map(\.text)
        return (found, texts)
    }

    private static func friendly(_ role: String) -> String {
        switch role {
        case "AXButton": return "button"
        case "AXCheckBox": return "checkbox"
        case "AXRadioButton": return "tab or option"
        case "AXTextField", "AXTextArea", "AXComboBox": return "text field"
        case "AXPopUpButton", "AXMenuButton": return "menu button"
        case "AXMenuItem", "AXMenuBarItem": return "menu"
        case "AXLink": return "link"
        case "AXSlider": return "slider"
        default: return "item"
        }
    }

    /// The visible name of an item. Only names and descriptions: a field's typed contents are never read.
    private static func label(of element: AXUIElement) -> String {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXHelpAttribute] {
            if let text = stringValue(element, attribute), !text.isEmpty { return text }
        }
        return ""
    }

    private static func center(of element: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size), size.width > 1, size.height > 1 else { return nil }
        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let list = ref as? [AXUIElement] else { return [] }
        return list
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func elementValue(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success, let ref else { return nil }
        return (ref as! AXUIElement)
    }
}
