//
//  KaiSidekickHotkeyMonitor.swift
//  Kai OS macOS
//
//  Two ways to toggle the notch. Control-Option-Space uses a Carbon hotkey, which needs no
//  permission. Tapping right Command needs Accessibility, because macOS withholds global
//  keyboard events from untrusted apps.
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KaiNotchCore

@MainActor
final class KaiSidekickHotkeyMonitor {
    static let shared = KaiSidekickHotkeyMonitor()

    /// The device-specific right Command bit in an event's raw modifier flags.
    private static let rightCommandMask: UInt = 0x10

    private var onToggle: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var monitors: [Any] = []
    private var gesture = KaiModifierGesture()
    private var activationObserver: NSObjectProtocol?
    private var monitoredWhileTrusted = false

    private(set) var isHotKeyRegistered = false

    var isRightCommandAvailable: Bool { AXIsProcessTrusted() }

    private init() {}

    func start(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        registerHotKey()
        installModifierMonitors()
        // Monitors installed before the permission was granted may stay silent, so they are
        // replaced the next time the app activates after the grant.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRightCommandAvailable != self.monitoredWhileTrusted else { return }
                self.installModifierMonitors()
            }
        }
    }

    func requestRightCommandPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        installModifierMonitors()
    }

    private func registerHotKey() {
        guard hotKey == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { KaiSidekickHotkeyMonitor.shared.onToggle?() }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
        let identifier = EventHotKeyID(signature: OSType(0x4B41_4948), id: 1) // "KAIH"
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        isHotKeyRegistered = installStatus == noErr && registerStatus == noErr
    }

    private func installModifierMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        monitoredWhileTrusted = isRightCommandAvailable
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged, Int(event.keyCode) == kVK_RightCommand else {
            gesture.interrupt()
            return
        }
        if event.modifierFlags.rawValue & Self.rightCommandMask != 0 {
            gesture.press(at: event.timestamp)
        } else if gesture.release(at: event.timestamp) {
            onToggle?()
        }
    }
}
