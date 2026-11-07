//
//  KaiPermissions.swift
//  Kai OS
//
//  Everything Kai OS asks macOS for, in one place, so one screen can explain and request it.
//

import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import CoreGraphics
import EventKit
import Speech
import UserNotifications

public enum KaiPermission: String, CaseIterable, Identifiable, Sendable {
    case accessibility, mailAutomation, notesAutomation, screenRecording, microphone, speech, calendar, notifications

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .mailAutomation: return "Apple Mail"
        case .notesAutomation: return "Apple Notes"
        case .screenRecording: return "Screen Recording"
        case .microphone: return "Microphone"
        case .speech: return "Speech Recognition"
        case .calendar: return "Calendar"
        case .notifications: return "Notifications"
        }
    }

    public var reason: String {
        switch self {
        case .accessibility: return "Writes drafts into the email you're replying to, in any app. Also enables tapping right ⌘."
        case .mailAutomation: return "Reads the message you select and opens replies. Kai OS never sends mail."
        case .notesAutomation: return "Lets the assistant read your recent notes. It can't change them."
        case .screenRecording: return "Reads an email from your screen when you double tap outside Apple Mail, or when you attach your screen."
        case .microphone: return "Listens only while you hold the talk key or the mic button is on."
        case .speech: return "Turns your speech into text on this Mac."
        case .calendar: return "Reads your events, and adds new ones after you approve them."
        case .notifications: return "Delivers reminders you've approved."
        }
    }

    public var iconName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .mailAutomation: return "envelope"
        case .notesAutomation: return "note.text"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .microphone: return "mic"
        case .speech: return "waveform"
        case .calendar: return "calendar"
        case .notifications: return "bell"
        }
    }

    public var settingsURL: URL? {
        let privacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_"
        switch self {
        case .accessibility: return URL(string: privacy + "Accessibility")
        case .mailAutomation, .notesAutomation: return URL(string: privacy + "Automation")
        case .screenRecording: return URL(string: privacy + "ScreenCapture")
        case .microphone: return URL(string: privacy + "Microphone")
        case .speech: return URL(string: privacy + "SpeechRecognition")
        case .calendar: return URL(string: privacy + "Calendars")
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        }
    }

    /// These can't show an inline Allow prompt and send the user to System Settings instead,
    /// so they come after the simple prompts.
    var opensSystemSettings: Bool { self == .accessibility || self == .screenRecording }
}

public enum KaiPermissionStatus: Equatable, Sendable {
    case notRequested, denied, granted
    /// macOS applies this grant only after the app relaunches.
    case needsRestart
}

public enum KaiPermissionRowAction: Equatable, Sendable {
    case none, request, openSettings, restart
}

public enum KaiPermissionPlan {
    public static func requestsForAllowAll(statuses: [KaiPermission: KaiPermissionStatus]) -> [KaiPermission] {
        let wanted = KaiPermission.allCases.filter { statuses[$0] == .notRequested }
        return wanted.filter { !$0.opensSystemSettings } + wanted.filter(\.opensSystemSettings)
    }

    public static func rowAction(for status: KaiPermissionStatus) -> KaiPermissionRowAction {
        switch status {
        case .notRequested: return .request
        case .denied: return .openSettings
        case .granted: return .none
        case .needsRestart: return .restart
        }
    }

    public static func missingCount(statuses: [KaiPermission: KaiPermissionStatus]) -> Int {
        KaiPermission.allCases.filter { statuses[$0] != .granted }.count
    }
}

/// Abstracted so the screen can be tested without real permission prompts.
@MainActor
public protocol KaiPermissionProviding: AnyObject {
    func status(of permission: KaiPermission) async -> KaiPermissionStatus
    func request(_ permission: KaiPermission) async
}

@MainActor
public final class KaiSystemPermissionProvider: KaiPermissionProviding {
    /// True only for this launch: macOS applies a grant at the next launch, so a restart can
    /// only help within the launch that asked. Remembering it longer would hide the Allow button
    /// after the grant is reset, and only asking makes macOS list the app in System Settings.
    private var screenRequestedThisLaunch = false
    private let screenAccessGranted: () -> Bool
    private let requestScreenAccess: () -> Void
    private static let automationGrantPrefix = "kai.permissions.automationGranted."

    public init(
        screenAccessGranted: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestScreenAccess: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() }
    ) {
        self.screenAccessGranted = screenAccessGranted
        self.requestScreenAccess = requestScreenAccess
    }

    public func status(of permission: KaiPermission) async -> KaiPermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notRequested
        case .screenRecording:
            if screenAccessGranted() { return .granted }
            return screenRequestedThisLaunch ? .needsRestart : .notRequested
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notRequested
            default: return .denied
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notRequested
            default: return .denied
            }
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notRequested
            default: return .denied
            }
        case .notifications:
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral: return .granted
            case .notDetermined: return .notRequested
            default: return .denied
            }
        case .mailAutomation:
            return await automationStatus(bundleIdentifier: "com.apple.mail")
        case .notesAutomation:
            return await automationStatus(bundleIdentifier: "com.apple.Notes")
        }
    }

    public func request(_ permission: KaiPermission) async {
        switch permission {
        case .accessibility:
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        case .screenRecording:
            screenRequestedThisLaunch = true
            requestScreenAccess()
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speech:
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        case .calendar:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .mailAutomation:
            await requestAutomation(bundleIdentifier: "com.apple.mail")
        case .notesAutomation:
            await requestAutomation(bundleIdentifier: "com.apple.Notes")
        }
    }

    // macOS can only answer for an app that's running, so the last known answer covers the rest.
    private func automationStatus(bundleIdentifier: String) async -> KaiPermissionStatus {
        let key = Self.automationGrantPrefix + bundleIdentifier
        let result = await Self.determineAutomation(bundleIdentifier: bundleIdentifier, ask: false)
        switch result {
        case noErr:
            UserDefaults.standard.set(true, forKey: key)
            return .granted
        case OSStatus(errAEEventNotPermitted):
            UserDefaults.standard.set(false, forKey: key)
            return .denied
        case OSStatus(procNotFound):
            return UserDefaults.standard.bool(forKey: key) ? .granted : .notRequested
        default:
            return .notRequested
        }
    }

    private func requestAutomation(bundleIdentifier: String) async {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            try? await Task.sleep(for: .seconds(2))
        }
        _ = await Self.determineAutomation(bundleIdentifier: bundleIdentifier, ask: true)
    }

    /// Runs off the main thread, because asking blocks until the user answers the prompt.
    private nonisolated static func determineAutomation(bundleIdentifier: String, ask: Bool) async -> OSStatus {
        await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        }.value
    }
}
