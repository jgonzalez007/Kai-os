//
//  KaiSidekickHotkeyMonitor.swift
//  Kai OS macOS
//
//  Two keys drive the notch: tap to toggle, hold to talk, double tap to draft an email reply.
//  Control-Option-Space uses a Carbon
//  hotkey, which needs no permission. Right Command needs Accessibility, because macOS
//  withholds global keyboard events from untrusted apps.
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

    private var onAction: ((KaiHoldGesture.Action) -> Void)?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var monitors: [Any] = []
    private var hotKeyGesture = KaiHoldGesture()
    private var rightCommandGesture = KaiHoldGesture()
    private var activationObserver: NSObjectProtocol?
    private var monitoredWhileTrusted = false

    private(set) var isHotKeyRegistered = false

    var isRightCommandAvailable: Bool { AXIsProcessTrusted() }

    private init() {}

    func start(onAction: @escaping (KaiHoldGesture.Action) -> Void) {
        self.onAction = onAction
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

    func hotKeyPressed() {
        let token = hotKeyGesture.press(at: ProcessInfo.processInfo.systemUptime)
        scheduleHoldTimer { monitor in monitor.hotKeyGesture.holdTimerFired(token: token) }
    }

    func hotKeyReleased() {
        dispatch(hotKeyGesture.release(at: ProcessInfo.processInfo.systemUptime)) { monitor, token in
            monitor.hotKeyGesture.tapTimerFired(token: token)
        }
    }

    /// A first tap only becomes a toggle if no second tap arrives in time.
    private func dispatch(_ action: KaiHoldGesture.Action, tapTimer: @escaping (KaiSidekickHotkeyMonitor, Int) -> KaiHoldGesture.Action) {
        guard case .awaitSecondTap(let token) = action else {
            onAction?(action)
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(KaiHoldGesture.doubleTapWindow))
            guard let self else { return }
            self.onAction?(tapTimer(self, token))
        }
    }

    private func scheduleHoldTimer(_ fire: @escaping (KaiSidekickHotkeyMonitor) -> KaiHoldGesture.Action) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(KaiHoldGesture.holdThreshold))
            guard let self else { return }
            self.onAction?(fire(self))
        }
    }

    private func registerHotKey() {
        guard hotKey == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                let pressed = event.map { GetEventKind($0) == UInt32(kEventHotKeyPressed) } ?? false
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let monitor = KaiSidekickHotkeyMonitor.shared
                        if pressed { monitor.hotKeyPressed() } else { monitor.hotKeyReleased() }
                    }
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
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
            onAction?(rightCommandGesture.interrupt())
            return
        }
        if event.modifierFlags.rawValue & Self.rightCommandMask != 0 {
            let token = rightCommandGesture.press(at: event.timestamp)
            scheduleHoldTimer { monitor in monitor.rightCommandGesture.holdTimerFired(token: token) }
        } else {
            dispatch(rightCommandGesture.release(at: event.timestamp)) { monitor, token in
                monitor.rightCommandGesture.tapTimerFired(token: token)
            }
        }
    }
}
