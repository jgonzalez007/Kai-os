//
//  KaiPermissionTester.swift
//  Kai OS macOS
//
//  "Test this" for each permission. The switch in System Settings can say On while macOS still refuses (it happens
//  after an app is rebuilt or re-signed), so each test does the smallest real thing that needs the permission and
//  says what happened. Every test only reads: it changes nothing and sends nothing.
//

import AppKit
import ApplicationServices
import Foundation
import KaiCapture
import KaiLocalData

struct KaiPermissionTestResult: Equatable {
    let ok: Bool
    let message: String
}

@MainActor
enum KaiPermissionTester {
    static func test(_ permission: KaiPermission) async -> KaiPermissionTestResult {
        switch permission {
        case .accessibility: return accessibility()
        case .screenRecording: return await screen()
        case .mailAutomation: return await app("Mail", "count of accounts", noun: "account")
        case .notesAutomation: return await app("Notes", "count of notes", noun: "note")
        case .calendar: return calendar()
        case .microphone, .speech, .notifications:
            let status = await KaiSystemPermissionProvider().status(of: permission)
            return status == .granted
                ? .init(ok: true, message: "macOS says \(permission.title) is allowed. Kai uses it only when you ask.")
                : .init(ok: false, message: "\(permission.title) is not allowed yet. Use Allow, or turn it on in System Settings.")
        }
    }

    private static let resetHint = "If it is on in System Settings but fails here, press Reset next to it, then restart Kai OS and allow it again."

    private static func accessibility() -> KaiPermissionTestResult {
        guard AXIsProcessTrusted() else { return .init(ok: false, message: "macOS has not given Kai OS Accessibility. " + resetHint) }
        // Trusted on paper. Ask for the front app's focused window: a refused app gets an error here.
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .init(ok: true, message: "Accessibility is on. Switch to another app and test again to see Kai read it.")
        }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, &value)
        switch result {
        case .success, .noValue, .attributeUnsupported:
            return .init(ok: true, message: "Works. Kai can see \(app.localizedName ?? "the front app").")
        default:
            return .init(ok: false, message: "Accessibility is on, but macOS refused to let Kai read \(app.localizedName ?? "the front app"). " + resetHint)
        }
    }

    private static func screen() async -> KaiPermissionTestResult {
        guard KaiScreenGrabber.hasPermission else { return .init(ok: false, message: "macOS has not given Kai OS Screen Recording. " + resetHint) }
        do {
            let data = try await KaiScreenGrabber.capture(displayID: nil, excludingBundleIdentifier: Bundle.main.bundleIdentifier, maxLongEdge: 240)
            return .init(ok: true, message: "Works. Kai took a small test picture of the screen (\(data.count / 1024) KB) and threw it away.")
        } catch {
            return .init(ok: false, message: "Screen Recording is on, but the test picture failed: \(error.localizedDescription) " + resetHint)
        }
    }

    /// Asks Apple Mail or Notes one harmless question. Kai does not start the app for a test.
    private static func app(_ name: String, _ question: String, noun: String) async -> KaiPermissionTestResult {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == name }) else {
            return .init(ok: false, message: "Open \(name) first. Kai doesn't start it for a test.")
        }
        let script = "tell application \"\(name)\" to return (\(question)) as string"
        guard let output = try? await KaiProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script], timeout: 30) else {
            return .init(ok: false, message: "\(name) did not answer in 30 seconds.")
        }
        if output.exitCode == 0 {
            let n = Int(output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return .init(ok: true, message: "Works. \(name) answered: \(n) \(noun)\(n == 1 ? "" : "s").")
        }
        let error = output.standardError
        if error.contains("-1743") || error.lowercased().contains("not authorized") {
            return .init(ok: false, message: "macOS refused Kai OS control of \(name). " + resetHint)
        }
        return .init(ok: false, message: "\(name) gave an error. Try again with \(name) open and not busy.")
    }

    private static func calendar() -> KaiPermissionTestResult {
        guard KaiCalendarSource.access == .granted else { return .init(ok: false, message: "Calendar access is not granted. Use Allow. " + resetHint) }
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let count = KaiCalendarSource.events(from: Date(), to: end).count
        return .init(ok: true, message: "Works. Kai found \(count) event\(count == 1 ? "" : "s") in the next 7 days.")
    }
}
