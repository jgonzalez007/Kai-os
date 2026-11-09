//
//  KaiSidekickHotkeyMonitor.swift
//  Kai OS macOS
//
//  Two keys drive the notch: tap to toggle, hold to talk, double tap to draft an email reply.
//  Control-Option-Space uses a Carbon
//  hotkey, which needs no permission. Right Command is read from modifier changes only (never a global
//  keyDown monitor, which macOS withholds from apps it doesn't trust), the same way Sentient does it.
//  A check every second and a half puts the monitors back if they went quiet, for example after the
//  Accessibility permission was reset and granted again while Kai was running.
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
    private var healthTimer: Timer?
    private var monitoredWhileTrusted = false
    /// When the shared key went down, so a key pressed meanwhile (Right Command with C) cancels the tap.
    private var sharedKeyDownAt: TimeInterval?

    private(set) var isHotKeyRegistered = false

    var isRightCommandAvailable: Bool { AXIsProcessTrusted() }

    private init() {}

    func start(onAction: @escaping (KaiHoldGesture.Action) -> Void) {
        self.onAction = onAction
        registerHotKey()
        installModifierMonitors()
        // Monitors installed before the permission was granted may stay silent, so they are
        // replaced as soon as the permission state changes, and when the app becomes active.
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.monitors.isEmpty || self.isRightCommandAvailable != self.monitoredWhileTrusted { self.installModifierMonitors() }
            }
        }
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
        // Modifier changes only: a global keyDown monitor is withheld from an app macOS doesn't trust, and it
        // can leave this one silent too. Other keys are noticed when the shared key is let go.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        let key = KaiSharedKey.stored()
        guard event.type == .flagsChanged, Int(event.keyCode) == key.keyCode else {
            onAction?(rightCommandGesture.interrupt())
            return
        }
        if event.modifierFlags.rawValue & key.deviceMask != 0 {
            sharedKeyDownAt = event.timestamp
            let token = rightCommandGesture.press(at: event.timestamp)
            scheduleHoldTimer { monitor in monitor.rightCommandGesture.holdTimerFired(token: token) }
        } else {
            // Another key was pressed while it was held (Right Command with C): that was a shortcut, not a tap.
            if let down = sharedKeyDownAt,
               CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < event.timestamp - down {
                sharedKeyDownAt = nil
                onAction?(rightCommandGesture.interrupt())
                return
            }
            sharedKeyDownAt = nil
            dispatch(rightCommandGesture.release(at: event.timestamp)) { monitor, token in
                monitor.rightCommandGesture.tapTimerFired(token: token)
            }
        }
    }
}
