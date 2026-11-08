//
//  KaiDeskController.swift
//  Kai OS macOS
//
//  Owns the Desk features in the notch: clipboard history, the Shelf, and the Claude Code bridge.
//  The pure logic lives in KaiDesk. This class only watches the pasteboard, runs the local socket
//  and keeps the published state the views draw.
//

import AppKit
import ApplicationServices
import KaiDesk
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class KaiDeskController: ObservableObject {
    static let shared = KaiDeskController()

    enum Tab: String, CaseIterable, Identifiable {
        case chat, shelf, clipboard, claude
        var id: String { rawValue }
        var title: String {
            switch self {
            case .chat: return "Chat"
            case .shelf: return "Shelf"
            case .clipboard: return "Clipboard"
            case .claude: return "Claude Code"
            }
        }
        var symbol: String {
            switch self {
            case .chat: return "bubble.left"
            case .shelf: return "tray"
            case .clipboard: return "doc.on.clipboard"
            case .claude: return "terminal"
            }
        }
    }

    struct Approval: Identifiable {
        let id = UUID()
        let event: KaiHookEvent
        let received: Date
        fileprivate let reply: @Sendable (KaiHookDecision?) -> Void
    }

    // MARK: Published state

    @Published var tab = Tab.chat
    @Published private(set) var clipboard = KaiClipboardHistory()
    @Published private(set) var shelf = KaiShelf()
    @Published private(set) var showUndo = false
    @Published private(set) var approvals: [Approval] = [] { didSet { updateKeyMonitor() } }
    @Published private(set) var clones: [KaiHookClone] = []
    @Published private(set) var recentDone: [KaiHookDone] = []
    @Published private(set) var hooksMessage = "Off"

    // MARK: Settings (UserDefaults)

    private static let defaults = UserDefaults.standard

    @Published var clipboardEnabled: Bool = KaiDeskController.defaults.bool(forKey: "kai.desk.clipboard") {
        didSet { Self.defaults.set(clipboardEnabled, forKey: "kai.desk.clipboard"); applyClipboardSetting() }
    }
    @Published var clipboardIgnoreTerminals: Bool = KaiDeskController.defaults.object(forKey: "kai.desk.clipboard.terminals") as? Bool ?? true {
        didSet { Self.defaults.set(clipboardIgnoreTerminals, forKey: "kai.desk.clipboard.terminals") }
    }
    @Published var clipboardKeepAfterQuit: Bool = KaiDeskController.defaults.bool(forKey: "kai.desk.clipboard.keep") {
        didSet {
            Self.defaults.set(clipboardKeepAfterQuit, forKey: "kai.desk.clipboard.keep")
            if clipboardKeepAfterQuit { saveClipboard() } else { try? FileManager.default.removeItem(at: Self.clipboardFile) }
        }
    }
    @Published var shelfRemoveOnDragOut: Bool = KaiDeskController.defaults.object(forKey: "kai.desk.shelf.remove") as? Bool ?? true {
        didSet { Self.defaults.set(shelfRemoveOnDragOut, forKey: "kai.desk.shelf.remove") }
    }
    @Published var hooksEnabled: Bool = KaiDeskController.defaults.bool(forKey: "kai.desk.hooks") {
        didSet { Self.defaults.set(hooksEnabled, forKey: "kai.desk.hooks"); applyHooksSetting() }
    }

    /// Set by the notch controller: something needs attention, so show the panel.
    var onApproval: (() -> Void)?
    var onDone: ((KaiHookDone) -> Void)?

    // MARK: Private state

    private static var clipboardFile: URL { KaiDeskFile.supportFolder.appendingPathComponent("clipboard.json") }
    private static var shelfFile: URL { KaiDeskFile.supportFolder.appendingPathComponent("shelf.json") }

    private var pasteboardTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var tracker = KaiHookTracker()
    private var server: KaiHookServer?
    private var maintenanceTimer: Timer?
    private var keyMonitor: Any?
    private var undoTask: Task<Void, Never>?
    private var started = false

    private init() {
        if let saved = KaiDeskFile.load(KaiShelf.self, from: Self.shelfFile) { shelf = saved }
        if Self.defaults.bool(forKey: "kai.desk.clipboard.keep"),
           let saved = KaiDeskFile.load(KaiClipboardHistory.self, from: Self.clipboardFile) {
            clipboard = saved
        }
    }

    /// Called once the app has launched. Nothing runs until the person turns a feature on.
    func start() {
        guard !started else { return }
        started = true
        applyClipboardSetting()
        applyHooksSetting()
    }

    // MARK: Clipboard history

    private func applyClipboardSetting() {
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
        guard clipboardEnabled else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPasteboard() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        pasteboardTimer = timer
    }

    private func pollPasteboard() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        let types = (board.types ?? []).map(\.rawValue)
        // Files copied in Finder are not text copies.
        if types.contains(UTType.fileURL.identifier) { return }
        guard let text = board.string(forType: .string) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let policy = KaiClipboardPolicy(ignoreTerminals: clipboardIgnoreTerminals)
        if clipboard.record(text, from: source, pasteboardTypes: types, policy: policy) { saveClipboard() }
        objectWillChange.send()
    }

    /// Copies an entry back to the pasteboard. Kai does not record its own write.
    func copyBack(_ entry: KaiClipboardEntry) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(entry.text, forType: .string)
        lastChangeCount = board.changeCount
        clipboard.bump(entry.id)
        saveClipboard()
    }

    func togglePin(_ entry: KaiClipboardEntry) { clipboard.togglePin(entry.id); saveClipboard() }
    func remove(_ entry: KaiClipboardEntry) { clipboard.remove(entry.id); saveClipboard() }
    func clearClipboard() { clipboard.clear(); saveClipboard() }

    private func saveClipboard() {
        guard clipboardKeepAfterQuit else { return }
        try? KaiDeskFile.save(clipboard, to: Self.clipboardFile)
    }

    // MARK: Shelf

    /// Accepts dropped files, links and text. Returns true when something was taken.
    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        var taken = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                taken = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    Task { @MainActor in self?.addToShelf(url: url) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                taken = true
                _ = provider.loadObject(ofClass: String.self) { [weak self] text, _ in
                    guard let text else { return }
                    Task { @MainActor in self?.shelf.addString(text); self?.saveShelf() }
                }
            }
        }
        return taken
    }

    func addToShelf(url: URL) {
        if url.isFileURL {
            shelf.addFile(url)
        } else {
            shelf.addString(url.absoluteString)
        }
        saveShelf()
    }

    func provider(for item: KaiShelfItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            if let url = item.fileURL, let provider = NSItemProvider(contentsOf: url) { return provider }
            return NSItemProvider(object: item.value as NSString)
        case .link:
            if let url = URL(string: item.value) { return NSItemProvider(object: url as NSURL) }
            return NSItemProvider(object: item.value as NSString)
        case .text:
            return NSItemProvider(object: item.value as NSString)
        }
    }

    /// A drag started. When the mouse button is released the item leaves the shelf (unless pinned),
    /// and Undo shows for five seconds. Waiting for the release keeps the drag alive.
    func dragStarted(_ item: KaiShelfItem) -> NSItemProvider {
        if shelfRemoveOnDragOut, !item.pinned {
            let id = item.id
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(100)) }
                self?.finishDragOut(id)
            }
        }
        return provider(for: item)
    }

    private func finishDragOut(_ id: UUID) {
        guard shelf.takeOut(id) else { return }
        saveShelf()
        showUndo = true
        undoTask?.cancel()
        undoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(KaiShelf.undoWindow + 0.2))
            guard !Task.isCancelled else { return }
            self?.shelf.expireUndo()
            self?.showUndo = false
        }
    }

    var undoTitle: String? { shelf.lastRemoved?.item.title }

    func undoDragOut() {
        if shelf.undo() { saveShelf() }
        showUndo = false
        undoTask?.cancel()
    }

    func togglePin(_ item: KaiShelfItem) { shelf.togglePin(item.id); saveShelf() }
    func remove(_ item: KaiShelfItem) { shelf.remove(item.id); saveShelf() }
    func clearShelf() { shelf.clear(); saveShelf() }

    func open(_ item: KaiShelfItem) {
        switch item.kind {
        case .file: if let url = item.fileURL { NSWorkspace.shared.open(url) }
        case .link: if let url = URL(string: item.value) { NSWorkspace.shared.open(url) }
        case .text:
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(item.value, forType: .string)
            lastChangeCount = board.changeCount
        }
    }

    private func saveShelf() {
        try? KaiDeskFile.save(shelf, to: Self.shelfFile)
    }

    // MARK: Claude Code bridge

    var helperPath: String {
        (Bundle.main.executableURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: "/"))
            .appendingPathComponent("kai-hook").path
    }

    var helperExists: Bool { FileManager.default.isExecutableFile(atPath: helperPath) }

    var setupSnippet: String { KaiHookSetup.settingsSnippet(helperPath: helperPath) }

    func copySetupSnippet() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(setupSnippet, forType: .string)
        lastChangeCount = board.changeCount
    }

    private func applyHooksSetting() {
        server?.stop()
        server = nil
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
        // Anything still waiting is released with no decision, so Claude Code asks in the terminal.
        for approval in approvals { approval.reply(nil) }
        approvals = []
        tracker.reset()
        clones = []
        guard hooksEnabled else { hooksMessage = "Off"; return }

        let server = KaiHookServer { [weak self] event, reply in
            Task { @MainActor in self?.receive(event, reply: reply) }
        }
        do {
            try server.start()
            self.server = server
            hooksMessage = "Listening"
        } catch {
            hooksMessage = "Could not start: \(error.localizedDescription)"
            return
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tracker.expire()
                self.clones = self.tracker.clones
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer
    }

    private func receive(_ event: KaiHookEvent, reply: @escaping @Sendable (KaiHookDecision?) -> Void) {
        guard hooksEnabled else { reply(nil); return }
        if let done = tracker.apply(event) {
            recentDone.insert(done, at: 0)
            if recentDone.count > 5 { recentDone.removeLast() }
            onDone?(done)
        }
        clones = tracker.clones
        guard event.name == .permissionRequest else { return }
        let approval = Approval(event: event, received: Date(), reply: reply)
        approvals.append(approval)
        tab = .claude
        onApproval?()
        // The server stops waiting at 56 seconds, so the card goes then too.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(KaiHookServer.permissionTimeout))
            self?.dropApproval(approval.id, decision: nil)
        }
    }

    func decide(_ approval: Approval, _ decision: KaiHookDecision) {
        dropApproval(approval.id, decision: decision)
    }

    private func dropApproval(_ id: UUID, decision: KaiHookDecision?) {
        guard let index = approvals.firstIndex(where: { $0.id == id }) else { return }
        let approval = approvals.remove(at: index)
        approval.reply(decision)
        tracker.setWaiting(agentID: approval.event.agentID, false)
        clones = tracker.clones
    }

    /// Control-Option-Y allows and Control-Option-N denies the oldest request. Needs Accessibility,
    /// which Kai OS already asks for the Sidekick. Active only while a request is waiting.
    private func updateKeyMonitor() {
        if approvals.isEmpty {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            return
        }
        guard keyMonitor == nil, AXIsProcessTrusted() else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.control, .option] else { return }
            let keyCode = event.keyCode
            MainActor.assumeIsolated {
                guard let self, let first = self.approvals.first else { return }
                if keyCode == 16 { self.decide(first, .allow) }
                if keyCode == 45 { self.decide(first, .deny) }
            }
        }
    }

    var keyboardShortcutsWork: Bool { AXIsProcessTrusted() }
}
