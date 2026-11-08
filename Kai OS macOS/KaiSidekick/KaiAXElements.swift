//
//  KaiAXElements.swift
//  Kai OS macOS
//
//  Reads the clickable items of the front app's window through Accessibility, so the agent can be told
//  exactly where to click. It reads names and positions only: never the contents of a text field, and
//  never a password field. Apps the agent may not operate are skipped entirely.
//

import AppKit
import ApplicationServices
import KaiAgent

enum KaiAXElements {
    private static let clickable: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea", "AXComboBox", "AXPopUpButton",
        "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXLink", "AXTabGroup", "AXSlider", "AXDisclosureTriangle",
    ]
    private static let maxNodes = 350
    private static let maxDepth = 8
    private static let timeBudget: TimeInterval = 0.8

    static func collect(bounds: CGRect, pixelWidth: Int, pixelHeight: Int, ownBundleIdentifier: String?) -> [KaiAgentElement] {
        guard AXIsProcessTrusted(), bounds.width > 0, bounds.height > 0,
              let front = NSWorkspace.shared.frontmostApplication,
              let identifier = front.bundleIdentifier,
              identifier != ownBundleIdentifier,
              !KaiAgentPolicy.blockedBundleIdentifiers.contains(identifier) else { return [] }

        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let deadline = Date().addingTimeInterval(timeBudget)
        let scaleX = Double(pixelWidth) / bounds.width
        let scaleY = Double(pixelHeight) / bounds.height

        var roots: [AXUIElement] = []
        if let window = elementValue(app, kAXFocusedWindowAttribute) ?? elementValue(app, kAXMainWindowAttribute) { roots.append(window) }
        if let menuBar = elementValue(app, kAXMenuBarAttribute) { roots.append(menuBar) }

        var found: [KaiAgentElement] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard visited < maxNodes, depth <= maxDepth, Date() < deadline else { return }
            visited += 1
            let role = stringValue(element, kAXRoleAttribute) ?? ""
            let subrole = stringValue(element, kAXSubroleAttribute) ?? ""
            if subrole == "AXSecureTextField" || role == "AXSecureTextField" { return }
            if clickable.contains(role), let center = center(of: element) {
                let x = Int(((center.x - bounds.minX) * scaleX).rounded())
                let y = Int(((center.y - bounds.minY) * scaleY).rounded())
                if x >= 0, y >= 0, x < pixelWidth, y < pixelHeight {
                    found.append(KaiAgentElement(label: label(of: element), role: friendly(role), x: x, y: y))
                }
            }
            // A menu's items are only worth listing while it is open, so menus are not opened to read them.
            if role == "AXMenuBarItem" { return }
            for child in children(of: element) { walk(child, depth: depth + 1) }
        }
        for root in roots { walk(root, depth: 0) }
        return found
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
