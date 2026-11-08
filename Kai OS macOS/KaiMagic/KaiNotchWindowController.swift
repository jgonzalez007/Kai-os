//
//  KaiNotchWindowController.swift
//  Kai OS macOS
//
//  Owns the always-on-top panel at the notch. The panel never activates the app, so the
//  user's current app stays frontmost while they talk to Kai.
//

import AppKit
import Combine
import KaiCapture
import KaiDesk
import KaiLocalData
import KaiNotchCore
import SwiftUI

@MainActor
final class KaiNotchModel: ObservableObject {
    enum Activity: Equatable {
        case idle, running, done, failed
    }

    enum VoicePhase: Equatable {
        case idle, listening, transcribing
    }

    enum PanelMode: Equatable {
        case chat, reply
    }

    @Published var voicePhase = VoicePhase.idle
    @Published var panelMode = PanelMode.chat

    @Published var isExpanded = false { didSet { onSurfaceChange?() } }
    /// The cursor is over the notch (idle: it swells; open: it keeps a reply on screen).
    @Published var isHovering = false { didSet { onSurfaceChange?() } }
    @Published var activity = Activity.idle { didSet { onSurfaceChange?() } }
    @Published var layout: KaiNotchLayout?
    @Published var draft = ""
    /// True while the open notch is the slim bar: there is no tab, request or email reply to show,
    /// and the person has not asked for the full conversation.
    @Published var compact = true { didSet { onSurfaceChange?() } }
    /// The person asked for the full conversation panel.
    @Published var fullRequested = false
    /// A finished reply shown in the bar for a moment, so a quick question never needs the full panel.
    @Published var readBack: String?
    /// Extra bar height below the notch. Taller while a reply is shown.
    @Published var barExtra = KaiNotchLayout.barExtraHeight { didSet { onSurfaceChange?() } }
    @Published var peekText: String? { didSet { onSurfaceChange?() } }
    /// Another app is full screen, so the notch steps away.
    @Published var hiddenForFullScreen = false
    /// Slim status strips stay beside the notch.
    @Published var showsStatus = KaiNotchPreferences.showsStatus { didSet { onSurfaceChange?() } }
    @Published var showsPeeks = KaiNotchPreferences.showsPeeks { didSet { onSurfaceChange?() } }

    var onSurfaceChange: (() -> Void)?

    var surface: KaiNotchSurface {
        if isExpanded { return compact ? .bar : .expanded }
        if showsPeeks && (activity != .idle || peekText != nil) { return .peek }
        if isHovering && !hiddenForFullScreen { return .hover }
        return showsStatus && !hiddenForFullScreen ? .status : .closed
    }

    /// Where the shape is on screen right now (AppKit coordinates).
    var shapeFrame: CGRect? { layout?.frame(for: surface, barExtra: barExtra) }
}

final class KaiNotchPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Uses an always-active tracking area, because hover must work while another app is frontmost.
final class KaiNotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }
}

@MainActor
final class KaiNotchWindowController: NSObject, NSWindowDelegate {
    static let shared = KaiNotchWindowController()

    private static let doneFlourish: Duration = .milliseconds(1500)
    private static let failedFlourish: Duration = .seconds(5)

    let model = KaiNotchModel()
    /// Replaced by the self-test, which has no microphone permission to rely on.
    var voiceEngine: any KaiVoiceEngine = KaiSpeechTranscriber()
    private(set) var panel: KaiNotchPanel?
    private(set) var doubleTap: KaiDoubleTapController?

    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var hoverEntry = NSRect.null
    private var dragNearNotch = false
    private var mouseMonitors: [Any] = []
    private var lingerTask: Task<Void, Never>?
    private var flourishTask: Task<Void, Never>?
    private var started = false
    private var autoOpened = false
    private var hoverNeedsReentry = false
    private var hoverTask: Task<Void, Never>?
    private var lastCardCount: Int?
    private var fullScreenObservers: [NSObjectProtocol] = []

    func start(appState: AppState) {
        guard !started else { return }
        started = true
        self.appState = appState
        doubleTap = KaiDoubleTapController(appState: appState)
        doubleTap?.onReplyOpened = { [weak self] in self?.collapse() }
        doubleTap?.onReleaseFocus = { [weak self] in self?.releaseKeyboardFocus() }
        model.onSurfaceChange = { [weak self] in self?.applySurface() }
        appState.$isProcessing
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isProcessing in self?.processingChanged(isProcessing) }
            .store(in: &cancellables)
        // The open notch is a slim bar until there is something to show: a message, another tab,
        // a permission request or an email reply.
        Publishers.MergeMany([
            appState.$messages.map { _ in () }.eraseToAnyPublisher(),
            appState.$isProcessing.map { _ in () }.eraseToAnyPublisher(),
            KaiDeskController.shared.$tab.map { _ in () }.eraseToAnyPublisher(),
            KaiDeskController.shared.$approvals.map { _ in () }.eraseToAnyPublisher(),
            model.$panelMode.map { _ in () }.eraseToAnyPublisher()
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.updateCompact() }
        .store(in: &cancellables)
        model.$isHovering.removeDuplicates().dropFirst()
            .sink { [weak self] hovering in self?.hoverChanged(hovering) }
            .store(in: &cancellables)
        // A new For You card gets a short peek.
        appState.morningCards.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkNewCards() }
            .store(in: &cancellables)
        observeFullScreen()
        let desk = KaiDeskController.shared
        desk.onApproval = { [weak self] in self?.showForApproval() }
        desk.onDone = { [weak self] done in self?.showClaudeDone(done) }
        desk.start()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLayout() }
        }
        // Clicks in other apps close the panel. Mouse monitors need no permission.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissForOutsideInteraction() }
        }
        KaiSidekickHotkeyMonitor.shared.start { [weak self] action in
            switch action {
            case .none, .awaitSecondTap: break
            case .toggle: self?.toggle()
            case .doubleTap: self?.startReply()
            case .beginHold: self?.beginVoice()
            case .endHold: self?.endVoice()
            case .cancelHold: self?.cancelVoice()
            }
        }
        applyEnabledPreference()
        updateFullScreen()
        updateCompact()
        // A mouse monitor registered while the app is still starting can wedge event routing.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.installMouseMonitors()
        }
    }

    func applyEnabledPreference() {
        if KaiNotchPreferences.isEnabled {
            if panel == nil { makePanel() }
            refreshLayout()
            panel?.orderFrontRegardless()
        } else {
            collapse()
            panel?.orderOut(nil)
        }
    }

    func toggle() {
        guard KaiNotchPreferences.isEnabled else { return }
        if model.isExpanded { collapse() } else { expand() }
    }

    func expand() {
        guard let panel, !model.isExpanded else { return }
        autoOpened = false
        model.isExpanded = true
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func collapse() {
        guard let panel, model.isExpanded else { return }
        cancelVoice()
        autoOpened = false
        // The cursor may still rest on the notch, so hover must leave and come back before it opens again.
        hoverNeedsReentry = model.isHovering
        lingerTask?.cancel()
        model.readBack = nil
        model.fullRequested = false
        model.barExtra = KaiNotchLayout.barExtraHeight
        model.isExpanded = false
        model.panelMode = .chat
        doubleTap?.cancel()
        // Reordering hands keyboard focus back to the frontmost app without flicker.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        // The poll sees where the cursor is and lets go of the mouse once the notch has closed.
        startPolling()
    }

    // MARK: Hover, full screen, events

    /// The open notch is the slim bar unless there is something that needs room: another tab, a
    /// permission request, an email reply, or the person asked for the whole conversation.
    private func updateCompact() {
        let compact = model.panelMode == .chat && KaiDeskController.shared.tab == .chat
            && KaiDeskController.shared.approvals.isEmpty && !model.fullRequested
        if model.compact != compact { model.compact = compact }
    }

    /// Asks for the full conversation panel, or goes back to the bar.
    func setFullConversation(_ full: Bool) {
        lingerTask?.cancel()
        model.fullRequested = full
        if full { KaiDeskController.shared.tab = .chat } else { model.readBack = nil }
        updateCompact()
    }

    /// Shows a finished reply in the bar, then retracts after a moment unless the cursor is on it.
    private func showReadBack(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let width = KaiNotchLayout.barWidth - 36
        let height = KaiNotchReadBack.height(of: clean, width: width)
        model.barExtra = KaiNotchReadBack.barExtra(textHeight: height)
        model.readBack = clean
        lingerTask?.cancel()
        let lines = max(1, Int((height / KaiNotchReadBack.lineHeight).rounded()))
        let seconds = min(9.0, 4.0 + Double(lines) * 0.5)
        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            while let self, !Task.isCancelled, self.model.isHovering { try? await Task.sleep(for: .milliseconds(400)) }
            guard let self, !Task.isCancelled, self.model.readBack != nil, self.model.compact else { return }
            self.collapse()
        }
    }

    /// Back from a reply to the input line.
    func replyAgain() {
        lingerTask?.cancel()
        model.readBack = nil
        model.barExtra = KaiNotchLayout.barExtraHeight
    }

    /// Hover opens the panel after a short pause, and closes it again after the mouse leaves,
    /// but only when the hover opened it and nothing is in progress.
    private func hoverChanged(_ hovering: Bool) {
        // The scripted self-test drives hover by hand.
        if ProcessInfo.processInfo.environment["KAI_NOTCH_SELFTEST_DIR"] != nil { return }
        hoverTask?.cancel()
        if !hovering { hoverNeedsReentry = false }
        guard KaiNotchPreferences.hoverOpens else { return }
        if hovering {
            guard !model.isExpanded, !hoverNeedsReentry, !model.hiddenForFullScreen else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, !Task.isCancelled, self.model.isHovering, !self.model.isExpanded else { return }
                self.autoOpened = true
                self.showWithoutFocus()
            }
        } else if model.isExpanded, autoOpened {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled, !self.model.isHovering, self.autoOpened, self.canAutoClose else { return }
                self.collapse()
            }
        }
    }

    /// Never closes on its own while the person is typing, talking, replying to an email,
    /// or has a permission request to answer.
    private var canAutoClose: Bool {
        model.panelMode == .chat && model.draft.isEmpty && model.voicePhase == .idle
            && KaiDeskController.shared.approvals.isEmpty
    }

    private func showWithoutFocus() {
        guard KaiNotchPreferences.isEnabled, let panel, !model.isExpanded else { return }
        model.isExpanded = true
        panel.orderFrontRegardless()
    }

    private func observeFullScreen() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // A space change finishes animating a moment after the notification.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.updateFullScreen()
                }
            }
            fullScreenObservers.append(token)
        }
    }

    func updateFullScreen() {
        let full = KaiNotchPreferences.hidesInFullScreen && NSApp.currentSystemPresentationOptions.contains(.fullScreen)
        guard full != model.hiddenForFullScreen else { return }
        model.hiddenForFullScreen = full
        guard let panel, KaiNotchPreferences.isEnabled else { return }
        if full {
            // A waiting permission request still needs an answer.
            if KaiDeskController.shared.approvals.isEmpty {
                collapse()
                panel.orderOut(nil)
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Applies a changed preference without a restart.
    func preferencesChanged() {
        model.showsStatus = KaiNotchPreferences.showsStatus
        model.showsPeeks = KaiNotchPreferences.showsPeeks
        updateFullScreen()
    }

    private func checkNewCards() {
        guard let appState else { return }
        let count = appState.morningCards.activeCards.count
        defer { lastCardCount = count }
        guard let last = lastCardCount, count > last else { return }
        showPeek(count - last == 1 ? "New card" : "\(count - last) new cards")
    }

    /// A short note in the right wing, then back to normal.
    func showPeek(_ text: String, seconds: Double = 4) {
        guard KaiNotchPreferences.isEnabled, !model.hiddenForFullScreen, !model.isExpanded else { return }
        flourishTask?.cancel()
        model.peekText = text
        flourishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.model.peekText = nil
        }
    }

    // MARK: Claude Code

    /// Opens the panel for a permission request without taking keyboard focus from the terminal.
    private func showForApproval() {
        guard KaiNotchPreferences.isEnabled, let panel else { return }
        autoOpened = false
        model.panelMode = .chat
        model.isExpanded = true
        panel.orderFrontRegardless()
    }

    private func showClaudeDone(_ done: KaiHookDone) {
        guard KaiNotchPreferences.isEnabled else { return }
        flourishTask?.cancel()
        model.peekText = done.failed ? "Claude failed" : "Claude done"
        model.activity = done.failed ? .failed : .done
        flourishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.model.peekText = nil
            self?.model.activity = .idle
        }
    }

    // MARK: Double tap

    func startReply() {
        guard KaiNotchPreferences.isEnabled else { return }
        cancelVoice()
        doubleTap?.start()
        model.panelMode = .reply
        expand()
    }

    /// Starts a reply from a morning card.
    func startReply(to mail: KaiBriefingMail) {
        guard KaiNotchPreferences.isEnabled else { return }
        cancelVoice()
        doubleTap?.start(provider: KaiReferencedMailProvider(reference: mail.reference))
        model.panelMode = .reply
        expand()
    }

    /// Hands keyboard focus back to the frontmost app while the panel stays on screen.
    func releaseKeyboardFocus() {
        guard let panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Voice

    func toggleVoice() {
        if model.voicePhase == .listening { endVoice() } else { beginVoice() }
    }

    func beginVoice() {
        guard KaiNotchPreferences.isEnabled, model.voicePhase == .idle, let appState else { return }
        expand()
        guard voiceEngine.isAuthorized else {
            Task {
                // The prompts take longer than a key hold, so the user talks on the next try.
                if await voiceEngine.requestAuthorization() {
                    appState.postError("Microphone is ready. Hold the talk key again and speak.")
                } else {
                    appState.postError("Kai OS needs Microphone and Speech Recognition permission. Turn them on in System Settings → Privacy & Security.")
                }
            }
            return
        }
        do {
            let isReply = model.panelMode == .reply
            if !isReply { model.draft = "" }
            model.voicePhase = .listening
            try voiceEngine.start { [weak self] text in
                if isReply {
                    self?.doubleTap?.instruction = text
                } else {
                    self?.model.draft = text
                }
            }
        } catch {
            model.voicePhase = .idle
            appState.postError(error.localizedDescription)
        }
    }

    /// Sends what was heard. If a reply is still running, the text waits in the field instead.
    func endVoice() {
        guard model.voicePhase == .listening, let appState else { return }
        model.voicePhase = .transcribing
        Task {
            let text = await voiceEngine.finish().trimmingCharacters(in: .whitespacesAndNewlines)
            model.voicePhase = .idle
            if model.panelMode == .reply {
                // Speech in reply mode is an instruction for the draft, never a chat message.
                if !text.isEmpty {
                    doubleTap?.instruction = text
                    doubleTap?.regenerate()
                }
            } else if text.isEmpty {
                model.draft = ""
                appState.postError("I didn't catch that. Hold the talk key and try again.")
            } else if appState.isProcessing {
                model.draft = text
            } else {
                model.draft = ""
                appState.sendMessage(text: text)
            }
        }
    }

    func cancelVoice() {
        guard model.voicePhase == .listening else { return }
        voiceEngine.cancel()
        model.voicePhase = .idle
        if model.panelMode == .chat { model.draft = "" }
    }

    func openMainWindow() {
        collapse()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Reopening the running app makes SwiftUI create a new window.
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        dismissForOutsideInteraction()
    }

    /// A draft in progress survives clicks elsewhere, so the user can reread the email or answer
    /// a permission prompt. The chat panel holds nothing that would be lost, so it closes.
    func dismissForOutsideInteraction() {
        guard model.panelMode == .chat else { return }
        // A permission request waits for an answer, so a click elsewhere must not hide it.
        guard KaiDeskController.shared.approvals.isEmpty else { return }
        collapse()
    }

    private func makePanel() {
        guard let appState else { return }
        let panel = KaiNotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above the menu bar and above other apps that draw at the notch, such as Sentient.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.collapse() }

        let hosting = KaiNotchHostingView(
            rootView: KaiNotchView(model: model, appState: appState, controller: self)
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.ignoresMouseEvents = true
        self.panel = panel
    }

    private func refreshLayout() {
        model.layout = KaiNotchSpace.currentLayout()
        guard let panel, let layout = model.layout else { return }
        // One fixed canvas: the shape animates inside it, so the window is never resized mid-morph.
        panel.setFrame(layout.canvas, display: true)
        refreshHoverEntry()
    }

    // MARK: Click-through, hover and the cursor poll

    /// The notch's own cutout, in screen coordinates, plus 2 points above the screen's top edge: a
    /// cursor pushed against the top reports exactly that edge, and a half-open rect would miss it.
    private func refreshHoverEntry() {
        guard let layout = model.layout else { hoverEntry = .null; return }
        var rect = layout.notch
        rect.size.height += 2
        hoverEntry = rect
    }

    /// The window only receives the mouse while the cursor is over the notch shape (or a file is being
    /// dragged toward it). Everywhere else every click passes straight through to the app underneath,
    /// including the empty parts of the canvas and the glow.
    private func applySurface() {
        if model.isExpanded || model.isHovering { startPolling() }
    }

    private func startPolling() {
        pollTick()
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTick() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        panel?.ignoresMouseEvents = true
    }

    private func pollTick() {
        guard let panel, model.layout != nil else { return }
        let p = NSEvent.mouseLocation
        var box = model.shapeFrame ?? .null
        box.size.height += 2
        let over = box.contains(p)
        if model.isExpanded {
            let hold = box.insetBy(dx: -4, dy: -4).contains(p)
            if model.isHovering != hold { model.isHovering = hold }
        } else {
            // Entry is the tight cutout, leaving is the swollen box plus a margin: no flicker at the edge.
            let hovering = model.isHovering ? box.insetBy(dx: -4, dy: -4).contains(p) : hoverEntry.contains(p)
            if hovering != model.isHovering { setHover(hovering) }
        }
        var near = box.insetBy(dx: -30, dy: -30)
        near.size.height += 2
        let receive = over || (dragNearNotch && near.contains(p))
        if panel.ignoresMouseEvents == receive { panel.ignoresMouseEvents = !receive }
        if !model.isExpanded && !model.isHovering && !dragNearNotch { stopPolling() }
    }

    private func setHover(_ hovering: Bool) {
        guard KaiNotchPreferences.isEnabled, KaiNotchPreferences.clickOpens || !hovering, !model.hiddenForFullScreen || !hovering else { return }
        model.isHovering = hovering
        if hovering {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            startPolling()
        }
    }

    /// `.mouseMoved` monitors only BEGIN a hover (one cached rect test per move). Leaving, and the
    /// click-through, are the poll's job. Mouse monitors need no permission. Installed a moment after
    /// launch, never during app start.
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                guard let self, !self.model.isExpanded, !self.model.isHovering,
                      self.hoverEntry.contains(location) else { return }
                self.setHover(true)
            }
        }) { mouseMonitors.append(moved) }
        // A file or link dragged toward the notch makes the window listen, so it can be dropped on the Shelf.
        if let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                guard let self, let canvas = self.model.layout?.canvas else { return }
                let near = canvas.contains(location)
                if near != self.dragNearNotch {
                    self.dragNearNotch = near
                    if near { self.startPolling() }
                }
            }
        }) { mouseMonitors.append(dragged) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dragNearNotch = false }
        }) { mouseMonitors.append(up) }
    }

    private func processingChanged(_ isProcessing: Bool) {
        flourishTask?.cancel()
        model.peekText = nil
        if isProcessing {
            lingerTask?.cancel()
            model.readBack = nil
            model.barExtra = KaiNotchLayout.barExtraHeight
            model.activity = .running
            return
        }
        guard let last = appState?.messages.last, !last.isUser else {
            model.activity = .idle
            return
        }
        model.activity = last.kind == .error ? .failed : .done
        // A question asked from the bar is answered in the bar.
        if model.isExpanded && model.compact && model.panelMode == .chat {
            if last.actionCard != nil {
                // An action card needs the person's decision, which has room in the full panel.
                setFullConversation(true)
            } else {
                showReadBack(last.kind == .error ? "⚠︎ " + last.text : last.text)
            }
        }
        let duration = last.kind == .error ? Self.failedFlourish : Self.doneFlourish
        flourishTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.model.activity = .idle
        }
    }
}
