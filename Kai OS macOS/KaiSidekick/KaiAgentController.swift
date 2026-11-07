//
//  KaiAgentController.swift
//  Kai OS macOS
//
//  Starts and stops the computer-use agent and carries the person's answers to it.
//  Approve and Stop are buttons only a person can press: the agent can't see Kai's panel
//  (it is left out of screenshots) and can't click inside it (those clicks are refused).
//

import AppKit
import ApplicationServices
import Combine
import KaiAgent
import KaiCapture
import KaiLocalAI
import KaiShared
import SwiftUI

@MainActor
final class KaiAgentController: ObservableObject {
    enum LineKind { case thought, proposed, performed, problem, outcome }

    struct Line: Identifiable {
        let id = UUID()
        let kind: LineKind
        let text: String
    }

    @Published var task = ""
    @Published var mode: KaiAgentMode = .askEach
    @Published private(set) var isRunning = false
    @Published private(set) var lines: [Line] = []
    @Published private(set) var pending: KaiApprovalRequest?
    @Published private(set) var outcome: KaiAgentOutcome?
    @Published var message: String?

    private var stopSwitch = KaiAgentStopSwitch()
    private var approval: CheckedContinuation<Bool, Never>?
    private let input = KaiSystemInput()
    private var overlay: KaiAgentOverlay?

    var statusLine: String { lines.last { $0.kind != .thought }?.text ?? "Starting…" }

    // MARK: Start and stop

    func start(appState: AppState) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, !trimmed.isEmpty else { return }
        message = nil
        guard AXIsProcessTrusted() else {
            message = "Sidekick needs Accessibility permission to use the mouse and keyboard. Turn it on in System Settings → Privacy & Security → Accessibility, then try again."
            return
        }
        guard KaiScreenGrabber.hasPermission else {
            message = "Sidekick needs Screen Recording permission to see the screen. Turn it on in System Settings → Privacy & Security → Screen Recording, then reopen Kai OS."
            return
        }
        isRunning = true
        lines = []
        outcome = nil
        Task {
            guard let model = await chooseModel(appState: appState) else {
                isRunning = false
                message = "Sidekick needs a local Ollama model that can read images. Start Ollama and run: ollama pull gemma4:e4b"
                return
            }
            begin(task: trimmed, model: model)
        }
    }

    private func begin(task: String, model: String) {
        stopSwitch = KaiAgentStopSwitch()
        let overlay = KaiAgentOverlay(controller: self)
        self.overlay = overlay
        input.onEscape = { [weak self] in Task { @MainActor in self?.stop() } }
        input.protectedFrames = { await MainActor.run { overlay.protectedFramesInDisplayCoordinates() } }
        input.startMonitoring()
        overlay.show()

        let runner = KaiAgentRunner(
            screen: KaiSystemScreen(),
            input: input,
            brain: KaiOllamaAgentBrain(client: KaiOllamaClient(), model: model),
            approver: KaiControllerApprover(controller: self),
            observer: KaiCombinedObserver(observers: [KaiControllerObserver(controller: self), KaiAgentAuditLog()]),
            policy: KaiAgentPolicy(mode: mode, ownBundleIdentifier: Bundle.main.bundleIdentifier),
            stop: stopSwitch
        )
        Task {
            // Step aside so the app you were using is in front: the agent never acts while Kai is.
            NSApp.hide(nil)
            try? await Task.sleep(for: .milliseconds(900))
            let result = await runner.run(task: task)
            finish(result)
        }
    }

    func stop() {
        guard isRunning else { return }
        stopSwitch.stop()
        resolve(false)
        message = "Stopping…"
    }

    private func finish(_ result: KaiAgentOutcome) {
        isRunning = false
        outcome = result
        message = nil
        lines.append(Line(kind: .outcome, text: result.summary))
        input.stopMonitoring()
        overlay?.hide()
        overlay = nil
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A local model that reads images: the one chosen in Kai if it is local, else the first that can.
    private func chooseModel(appState: AppState) async -> String? {
        if appState.modelInfo.isEmpty { try? await appState.refreshChatModels() }
        let chosen = KaiModelTag.name(from: appState.selectedModel)
        if appState.selectedModel.hasPrefix("ollama: "), appState.modelInfo.first(where: { $0.name == chosen })?.supportsVision == true {
            return chosen
        }
        return appState.modelInfo.first { $0.supportsVision }?.name
    }

    // MARK: From the runner

    func requestApproval(_ request: KaiApprovalRequest) async -> Bool {
        guard !stopSwitch.isStopped else { return false }
        pending = request
        overlay?.refreshSize()
        return await withCheckedContinuation { approval = $0 }
    }

    /// Only the Approve and Decline buttons call this.
    func resolve(_ approved: Bool) {
        pending = nil
        approval?.resume(returning: approved)
        approval = nil
        overlay?.refreshSize()
    }

    func handle(_ event: KaiAgentEvent) {
        switch event {
        case .thought(_, let text): lines.append(Line(kind: .thought, text: text))
        case .proposed(_, let summary): lines.append(Line(kind: .proposed, text: summary))
        case .performed(_, let summary, let point):
            lines.append(Line(kind: .performed, text: "Did: \(summary)"))
            if let point { overlay?.showTarget(point) }
        case .blocked(_, let summary, let reason): lines.append(Line(kind: .problem, text: "Blocked: \(summary). \(reason)"))
        case .declined(_, let summary): lines.append(Line(kind: .problem, text: "You declined: \(summary)"))
        case .approved, .started, .finished: break
        }
    }
}

private struct KaiControllerApprover: KaiAgentApprover {
    let controller: KaiAgentController
    func approve(_ request: KaiApprovalRequest) async -> Bool { await controller.requestApproval(request) }
}

private struct KaiControllerObserver: KaiAgentObserver {
    let controller: KaiAgentController
    func event(_ event: KaiAgentEvent) { Task { @MainActor in controller.handle(event) } }
}

private struct KaiCombinedObserver: KaiAgentObserver {
    let observers: [KaiAgentObserver]
    func event(_ event: KaiAgentEvent) { observers.forEach { $0.event(event) } }
}
